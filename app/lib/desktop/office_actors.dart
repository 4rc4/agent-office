import 'dart:math' as math;

import 'package:office_core/office_core.dart';

import '../state/seat_state.dart';
import 'stations.dart';

/// What an actor does once it stands at its spot; the walk there is
/// [Actor.walking].
enum ActorMood {
  stand,
  sleep,
  think,
  work,
  read,
  wait,
  coffee,
  celebrate,
  fail;

  /// Whether the pose changes from frame to frame (needs the clock).
  bool get animates => switch (this) {
    ActorMood.stand || ActorMood.sleep || ActorMood.wait => false,
    _ => true,
  };
}

/// One character on the floor line.
class Actor {
  Actor(this.seat, {required this.x});

  final Seat seat;

  /// Feet centre in logical pixels.
  double x;

  bool facingLeft = false;
  SeatVisual visual = SeatVisual.idle;
  ActorMood mood = ActorMood.stand;

  /// Where it walks to; null when standing.
  double? target;

  /// The station it uses or heads for; null on a free spot.
  StationKind? station;

  /// Ticks since [mood] started.
  int moodTicks = 0;

  /// Advances once per tick while walking (legs).
  int walkFrame = 0;

  /// When the next idle decision (wander, nap, wake) is due.
  DateTime? idleAt;

  ActorMood _pendingMood = ActorMood.stand;

  bool get walking => target != null;
}

/// Moves the characters along the floor line and picks their poses from
/// the office snapshot.
///
/// [apply] turns each seat's visual into a destination (a station slot, the
/// user spot, or "stay") and a mood on arrival; [step] walks them at
/// [speed] and counts animation ticks; [needsTicks] says whether the clock
/// must run. Idle characters wander or nap on a slow schedule ([nextWake],
/// [wake]) so nothing ticks while everyone stands still.
class Choreographer {
  Choreographer({
    required StationLayout layout,
    DateTime Function()? clock,
    math.Random? random,
    this.speed = 90,
  }) : _layout = layout,
       _clock = clock ?? DateTime.now,
       _random = random ?? math.Random() {
    for (final seat in const [Seat.claude, Seat.gpt]) {
      final desk = StationKind.deskOf(seat)!;
      actors[seat] = Actor(seat, x: layout.slotX(desk))
        ..station = desk
        ..idleAt = _clock().add(_seconds(6, 15));
    }
  }

  /// Logical pixels per second.
  final double speed;

  /// Ticks a celebration lasts (two jumps).
  static const int celebrateTicks = 12;

  final Map<Seat, Actor> actors = {};
  final DateTime Function() _clock;
  final math.Random _random;
  StationLayout _layout;

  StationLayout get layout => _layout;

  /// Whether any actor walks or animates right now.
  bool get needsTicks => actors.values.any((a) => a.walking || a.mood.animates);

  /// The earliest pending idle decision; null when none is scheduled.
  DateTime? get nextWake {
    DateTime? earliest;
    for (final a in actors.values) {
      final at = a.idleAt;
      if (at != null && (earliest == null || at.isBefore(earliest))) {
        earliest = at;
      }
    }
    return earliest;
  }

  /// Takes new seat visuals from [snapshot]; unchanged visuals keep the
  /// actor where it is.
  void apply(OfficeSnapshot snapshot) {
    for (final actor in actors.values) {
      final visual = snapshot.seat(actor.seat).visual;
      if (visual == actor.visual) continue;
      actor.visual = visual;
      _retarget(actor);
    }
  }

  /// Stations moved (a drag): actors using one walk to its new slot.
  void relayout(StationLayout layout) {
    _layout = layout;
    for (final actor in actors.values) {
      final station = actor.station;
      if (station == null) continue;
      _goTo(actor, station, actor.walking ? actor._pendingMood : actor.mood);
    }
  }

  /// Advances the world by [dt]. Returns [needsTicks] afterwards.
  bool step(Duration dt) {
    final distance = speed * dt.inMicroseconds / Duration.microsecondsPerSecond;
    for (final actor in actors.values) {
      final target = actor.target;
      if (target != null) {
        final remaining = target - actor.x;
        actor.facingLeft = remaining < 0;
        if (remaining.abs() <= distance) {
          _arrive(actor);
        } else {
          actor.x += remaining.sign * distance;
          actor.walkFrame++;
        }
        continue;
      }
      if (!actor.mood.animates) continue;
      actor.moodTicks++;
      if (actor.mood == ActorMood.celebrate &&
          actor.moodTicks >= celebrateTicks) {
        _goTo(actor, StationKind.mailbox, ActorMood.stand);
      }
    }
    return needsTicks;
  }

  /// Puts every walking actor at its destination at once (tests, start-up).
  void settle() {
    for (final actor in actors.values) {
      if (actor.walking) _arrive(actor);
    }
  }

  /// Applies the idle decisions that are due: a napping actor wakes up, an
  /// idle one naps, wanders to a free spot or stays, each for a while.
  void wake() {
    final now = _clock();
    for (final actor in actors.values) {
      final at = actor.idleAt;
      if (at == null || at.isAfter(now)) continue;
      if (!_isIdle(actor.visual)) {
        actor.idleAt = null;
        continue;
      }
      if (actor.mood == ActorMood.sleep) {
        actor.mood = ActorMood.stand;
        actor.moodTicks = 0;
        actor.idleAt = now.add(_seconds(8, 20));
        continue;
      }
      final roll = _random.nextDouble();
      if (roll < 0.3) {
        actor.mood = ActorMood.sleep;
        actor.moodTicks = 0;
        actor.idleAt = now.add(_seconds(25, 50));
      } else if (roll < 0.75) {
        final spot = _freeSpot();
        if (spot != null) _goToX(actor, spot, null, ActorMood.stand);
        actor.idleAt = now.add(_seconds(8, 20));
      } else {
        actor.idleAt = now.add(_seconds(6, 15));
      }
    }
  }

  // ---- internals -----------------------------------------------------------

  static bool _isIdle(SeatVisual visual) =>
      visual == SeatVisual.idle ||
      visual == SeatVisual.empty ||
      visual == SeatVisual.sleeping;

  void _retarget(Actor actor) {
    final desk = StationKind.deskOf(actor.seat)!;
    switch (actor.visual) {
      case SeatVisual.idle:
      case SeatVisual.empty:
        _stay(actor, ActorMood.stand);
        actor.idleAt = _clock().add(_seconds(6, 15));
      case SeatVisual.sleeping:
        _stay(actor, ActorMood.sleep);
        actor.idleAt = null;
      case SeatVisual.arriving:
      case SeatVisual.thinking:
        _goTo(actor, StationKind.whiteboard, ActorMood.think);
      case SeatVisual.typing:
      case SeatVisual.editing:
      case SeatVisual.shell:
      case SeatVisual.browsing:
        _goTo(actor, desk, ActorMood.work);
      case SeatVisual.reading:
        _goTo(actor, desk, ActorMood.read);
      case SeatVisual.waitingUser:
        _goToX(actor, _layout.userSpotX, null, ActorMood.wait);
      case SeatVisual.onBreak:
        _goTo(actor, StationKind.coffee, ActorMood.coffee);
      case SeatVisual.celebrating:
        _goTo(actor, desk, ActorMood.celebrate);
      case SeatVisual.failed:
        _goTo(actor, desk, ActorMood.fail);
    }
  }

  /// Stops where it is (finishing a walk by teleport) with [mood].
  void _stay(Actor actor, ActorMood mood) {
    if (actor.walking) {
      actor.x = actor.target!;
      actor.target = null;
    }
    actor.mood = mood;
    actor.moodTicks = 0;
  }

  void _goTo(Actor actor, StationKind station, ActorMood mood) {
    final slot = actors.values
        .where((o) => o != actor && o.station == station)
        .length;
    _goToX(actor, _layout.slotX(station, slot: slot), station, mood);
  }

  void _goToX(Actor actor, double x, StationKind? station, ActorMood mood) {
    actor.station = station;
    actor._pendingMood = mood;
    actor.idleAt = null;
    if ((x - actor.x).abs() < 0.5) {
      actor.x = x;
      actor.target = null;
      actor.mood = mood;
      actor.moodTicks = 0;
      return;
    }
    actor.target = x;
  }

  void _arrive(Actor actor) {
    actor.x = actor.target!;
    actor.target = null;
    actor.mood = actor._pendingMood;
    actor.moodTicks = 0;
    if (actor.mood == ActorMood.stand && _isIdle(actor.visual)) {
      actor.idleAt ??= _clock().add(_seconds(6, 15));
    }
  }

  /// A random x on the floor that is not over a prop; null after a few
  /// misses (a crowded, narrow screen).
  double? _freeSpot() {
    final w = _layout.width;
    for (var i = 0; i < 8; i++) {
      final x = 48 + _random.nextDouble() * (w - 96);
      if (!_layout.overlapsStation(x)) return x;
    }
    return null;
  }

  Duration _seconds(int min, int max) =>
      Duration(seconds: min + _random.nextInt(max - min + 1));
}
