import 'dart:math' as math;

import 'package:agent_office_app/desktop/office_actors.dart';
import 'package:agent_office_app/desktop/stations.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

OfficeSnapshot _snapshot({
  SeatVisual claude = SeatVisual.idle,
  SeatVisual gpt = SeatVisual.idle,
}) => OfficeSnapshot(
  seats: [
    SeatSnapshot(seat: Seat.claude, visual: claude),
    SeatSnapshot(seat: Seat.gpt, visual: gpt),
    const SeatSnapshot(seat: Seat.gemini, visual: SeatVisual.empty),
  ],
);

StationLayout _layout({Map<String, double> fractions = const {}}) =>
    StationLayout(width: 1280, floorY: 600, fractions: fractions);

void main() {
  group('StationLayout', () {
    test('props stand on the floor at their fractions', () {
      final layout = _layout();
      final desk = layout.rect(StationKind.deskClaude);
      expect(desk.bottom, 600);
      expect(desk.center.dx, closeTo(1280 * 0.26, 2));
      expect(desk.width, 36 * 4);
      expect(
        layout.slotX(StationKind.deskClaude),
        layout.centerX(StationKind.deskClaude) + 28,
      );
      expect(layout.userSpotX, 640);
    });

    test('settings override the defaults and round-trip', () {
      final layout = _layout(fractions: {'mailbox': 0.5, 'bogus': 0.1});
      expect(layout.centerX(StationKind.mailbox), 640);
      expect(layout.centerX(StationKind.tv), 1280 * 0.78);
      expect(layout.toSettings()['mailbox'], 0.5);
      expect(layout.toSettings().keys, StationKind.values.map((k) => k.name));
      expect(
        _layout(fractions: {'mailbox': 2.0}).fractions[StationKind.mailbox],
        StationLayout.maxFraction,
      );
    });

    test('overlapsStation covers props and their slots', () {
      final layout = _layout();
      expect(layout.overlapsStation(layout.centerX(StationKind.tv)), isTrue);
      expect(layout.overlapsStation(layout.userSpotX), isFalse);
    });
  });

  group('Choreographer', () {
    test('starts at the desks and stays put while idle', () {
      final c = Choreographer(layout: _layout());
      final claude = c.actors[Seat.claude]!;
      expect(claude.x, _layout().slotX(StationKind.deskClaude));
      expect(claude.station, StationKind.deskClaude);
      c.apply(_snapshot());
      expect(c.needsTicks, isFalse);
      expect(claude.mood, ActorMood.stand);
    });

    test('thinking walks to the whiteboard at 90 px/s, facing left', () {
      final c = Choreographer(layout: _layout());
      final claude = c.actors[Seat.claude]!;
      final start = claude.x;
      c.apply(_snapshot(claude: SeatVisual.thinking));
      expect(claude.walking, isTrue);
      expect(claude.target, _layout().slotX(StationKind.whiteboard));
      expect(c.needsTicks, isTrue);
      c.step(const Duration(milliseconds: 100));
      expect(claude.x, closeTo(start - 9, 0.001));
      expect(claude.facingLeft, isTrue);
      expect(claude.walkFrame, 1);
      c.settle();
      expect(claude.walking, isFalse);
      expect(claude.x, _layout().slotX(StationKind.whiteboard));
      expect(claude.mood, ActorMood.think);
      expect(claude.station, StationKind.whiteboard);
      // Thinking animates (the cloud bobs); standing idle does not.
      expect(c.needsTicks, isTrue);
      c.apply(_snapshot(claude: SeatVisual.idle));
      expect(claude.mood, ActorMood.stand);
      expect(c.needsTicks, isFalse);
    });

    test('a shared station gives the second actor the other slot', () {
      final c = Choreographer(layout: _layout());
      c.apply(_snapshot(claude: SeatVisual.thinking, gpt: SeatVisual.thinking));
      c.settle();
      final xs = {c.actors[Seat.claude]!.x, c.actors[Seat.gpt]!.x};
      expect(xs, {
        _layout().slotX(StationKind.whiteboard),
        _layout().slotX(StationKind.whiteboard, slot: 1),
      });
    });

    test('visuals map to stations and moods', () {
      final c = Choreographer(layout: _layout());
      final gpt = c.actors[Seat.gpt]!;
      final cases = {
        SeatVisual.shell: (StationKind.deskGpt, ActorMood.work),
        SeatVisual.reading: (StationKind.deskGpt, ActorMood.read),
        SeatVisual.onBreak: (StationKind.tv, ActorMood.watch),
        SeatVisual.failed: (StationKind.deskGpt, ActorMood.fail),
        SeatVisual.sleeping: (null, ActorMood.sleep),
      };
      for (final entry in cases.entries) {
        c.apply(_snapshot(gpt: entry.key));
        c.settle();
        expect(gpt.mood, entry.value.$2, reason: '${entry.key}');
        if (entry.value.$1 != null) {
          expect(
            gpt.x,
            _layout().slotX(entry.value.$1!),
            reason: '${entry.key}',
          );
        }
      }
      c.apply(_snapshot(gpt: SeatVisual.waitingUser));
      c.settle();
      expect(gpt.x, 640);
      expect(gpt.mood, ActorMood.wait);
      expect(gpt.station, isNull);
    });

    test('celebrating jumps at the desk, then walks to the mailbox', () {
      final c = Choreographer(layout: _layout());
      final gpt = c.actors[Seat.gpt]!;
      c.apply(_snapshot(gpt: SeatVisual.celebrating));
      expect(gpt.walking, isFalse);
      expect(gpt.mood, ActorMood.celebrate);
      for (var i = 0; i < Choreographer.celebrateTicks; i++) {
        c.step(const Duration(milliseconds: 100));
      }
      expect(gpt.walking, isTrue);
      expect(gpt.station, StationKind.mailbox);
      c.settle();
      expect(gpt.mood, ActorMood.stand);
      expect(gpt.x, _layout().slotX(StationKind.mailbox));
    });

    test('a moved station pulls the actor using it along', () {
      final c = Choreographer(layout: _layout());
      c.apply(_snapshot(claude: SeatVisual.typing));
      final moved = _layout(fractions: {'deskClaude': 0.4});
      c.relayout(moved);
      final claude = c.actors[Seat.claude]!;
      expect(claude.target, moved.slotX(StationKind.deskClaude));
      c.settle();
      expect(claude.mood, ActorMood.work);
    });

    test('idle schedule: naps, wanders or waits, never over a prop', () {
      var now = DateTime(2026, 10, 29, 9);
      final c = Choreographer(
        layout: _layout(),
        clock: () => now,
        random: math.Random(7),
      );
      c.apply(_snapshot());
      expect(c.nextWake, isNotNull);
      final seen = <ActorMood>{};
      for (var i = 0; i < 40; i++) {
        now = c.nextWake ?? now.add(const Duration(seconds: 30));
        c.wake();
        c.settle();
        for (final a in c.actors.values) {
          seen.add(a.mood);
          expect(c.layout.overlapsStation(a.x) && a.station == null, isFalse);
        }
      }
      expect(seen, containsAll([ActorMood.stand, ActorMood.sleep]));
      // Work interrupts the schedule.
      c.apply(_snapshot(claude: SeatVisual.typing, gpt: SeatVisual.typing));
      expect(c.nextWake, isNull);
    });
  });
}
