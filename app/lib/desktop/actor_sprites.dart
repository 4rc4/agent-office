import '../scene/objects.dart';
import '../scene/palette.dart';
import '../scene/pixel.dart';
import '../scene/sprites.dart';
import '../state/seat_state.dart';
import 'office_actors.dart';
import 'stations.dart';

/// Sprite box rows above which the ears and badges extend.
const int actorBoxHeight = spriteHeight;

/// Draws [actor] with its feet centred on column [cx] and standing on row
/// [floor] (the first row below the shoes). [frame] is the clock's `tick %
/// 4`; [bob] lifts the whole sprite (hover).
///
/// Walking swaps the legs for a 4-frame stride and mirrors the sprite when
/// heading left. Each mood is one of the room's poses plus a prop over the
/// head: thought cloud, typing dots, "?" and "!" badges, a clock for the
/// break, z's for a nap and a sweat drop for a failure.
void drawActor(
  PixelBuffer b,
  Actor actor,
  int cx,
  int floor,
  int frame, {
  int bob = 0,
}) {
  final x = cx - spriteWidth ~/ 2;
  final y = floor - spriteHeight;
  final palette = CharacterPalette.of(actor.seat);
  final style = styleFor(actor.seat);
  paintFloorShadow(b, cx, floor, 8);

  final pose = actor.walking
      ? const CharacterPose(stance: Stance.standing)
      : _poseFor(actor, frame);
  var rows = buildCharacterRows(pose, style);
  if (actor.walking) rows = _withWalkingLegs(rows, actor.walkFrame % 4);
  if (actor.walking && actor.facingLeft) {
    rows = [for (final row in rows) row.split('').reversed.join()];
  }
  final dy = pose.dy + bob;
  b.sprite(x, y + dy - spriteEarRows, rows, characterLegend(palette));
  if (!actor.walking) _drawMoodProp(b, actor, x, y + dy, frame);
}

/// Where typing hands go when the actor works at a desk: the painter draws
/// them on the keyboard after the desk (see `paintStation`).
bool actorTypesOnKeyboard(Actor actor) =>
    !actor.walking && actor.mood == ActorMood.work;

CharacterPose _poseFor(Actor actor, int frame) {
  final breath = frame ~/ 2 == 1 ? 1 : 0;
  return switch (actor.mood) {
    ActorMood.stand => const CharacterPose(stance: Stance.standing),
    ActorMood.sleep => const CharacterPose(
      stance: Stance.standing,
      eyes: Eyes.closed,
      headDy: 1,
    ),
    ActorMood.think => CharacterPose(
      stance: Stance.standing,
      eyes: Eyes.up,
      headDy: breath,
    ),
    ActorMood.work => const CharacterPose(
      stance: Stance.standing,
      arms: Arms.onDesk,
    ),
    ActorMood.read => const CharacterPose(
      stance: Stance.standing,
      arms: Arms.paper,
      headDy: 1,
    ),
    ActorMood.wait => const CharacterPose(
      stance: Stance.standing,
      arms: Arms.raisedRight,
    ),
    ActorMood.watch => CharacterPose(
      stance: Stance.standing,
      arms: Arms.mug,
      frame: frame,
      headDy: breath,
    ),
    ActorMood.celebrate => CharacterPose(
      stance: Stance.standing,
      arms: Arms.armsUp,
      dy: _jump(actor.moodTicks),
    ),
    ActorMood.fail => const CharacterPose(
      stance: Stance.standing,
      arms: Arms.scratch,
      headDy: 1,
    ),
  };
}

/// Two hops over [Choreographer.celebrateTicks] ticks.
int _jump(int tick) {
  const profile = [-1, -2, -2, -1, 0, 0, -1, -2, -2, -1, 0, 0];
  return tick < profile.length ? profile[tick] : 0;
}

/// Legs of a stride: frames 0 and 2 have the legs apart with one foot
/// lifted (right, then left), 1 and 3 stand together.
List<String> _withWalkingLegs(List<String> rows, int frame) {
  final grid = [for (final row in rows) row.split('')];
  void put(int r, int c, String s) {
    final row = r + spriteEarRows;
    for (var i = 0; i < s.length; i++) {
      final col = c + i;
      if (col >= 0 && col < spriteWidth) grid[row][col] = s[i];
    }
  }

  for (var r = 24; r <= 31; r++) {
    put(r, 0, '.' * spriteWidth);
  }
  if (frame.isOdd) {
    for (var r = 24; r <= 29; r++) {
      put(r, 7, 'QppPQQppPQ');
    }
    put(30, 6, 'QXxxxQQXxxxQ');
    put(31, 6, 'QQQQQQQQQQQQ');
  } else {
    final liftLeft = frame == 2;
    final leftLift = liftLeft ? 1 : 0;
    final rightLift = liftLeft ? 0 : 1;
    for (var r = 24; r <= 29 - leftLift; r++) {
      put(r, 5, 'QppPQ');
    }
    put(30 - leftLift, 4, 'QXxxxQ');
    put(31 - leftLift, 4, 'QQQQQQ');
    for (var r = 24; r <= 29 - rightLift; r++) {
      put(r, 13, 'QppPQ');
    }
    put(30 - rightLift, 13, 'QXxxxQ');
    put(31 - rightLift, 13, 'QQQQQQ');
  }
  return [for (final row in grid) row.join()];
}

void _drawMoodProp(PixelBuffer b, Actor actor, int x, int y, int frame) {
  switch (actor.mood) {
    case ActorMood.stand:
      break;
    case ActorMood.sleep:
      drawZzz(b, x + 17, y - 14);
    case ActorMood.think:
      drawCloud(b, x + 15, y - 15, frame);
    case ActorMood.work:
      drawDots(b, x + 17, y - 11, frame);
    case ActorMood.read:
      break;
    case ActorMood.wait:
      _badge(b, x + 18, y - 12, Palette.yellow, Palette.yellowDark, _question);
    case ActorMood.watch:
      // Watching idly needs no badge; a forced break (rate limit) shows the
      // clock.
      if (actor.visual == SeatVisual.onBreak) _clockBadge(b, x + 18, y - 12);
    case ActorMood.celebrate:
      drawCheck(b, x + 16, y - 16);
    case ActorMood.fail:
      drawSweat(b, x + 19, y + 3, frame);
      _badge(b, x + 18, y - 12, Palette.red, Palette.redDark, _bang);
  }
}

const List<(int, int)> _question = [
  (1, 0), (2, 0), (3, 0), (0, 1), (4, 1), (4, 2), (3, 3), (2, 4), (2, 6), //
];

const List<(int, int)> _bang = [(2, 0), (2, 1), (2, 2), (2, 3), (2, 6)];

/// A 9x9 round badge with a one-colour glyph, its tip toward the head.
void _badge(
  PixelBuffer b,
  int x,
  int y,
  int fill,
  int dark,
  List<(int, int)> glyph,
) {
  b.disc(x + 4, y + 4, 4, fill, outline: dark);
  b.hline(x + 2, y + 1, 3, PixelBuffer.lightOf(fill));
  b.set(x + 1, y + 9, dark);
  b.set(x, y + 10, dark);
  for (final (gx, gy) in glyph) {
    b.set(x + 2 + gx, y + 1 + gy, Palette.ink);
  }
}

/// Cream clock badge: a rim and two hands.
void _clockBadge(PixelBuffer b, int x, int y) {
  b.disc(x + 4, y + 4, 4, Palette.cream, outline: Palette.creamDark);
  b.hline(x + 2, y + 1, 3, Palette.creamLight);
  b.set(x + 4, y + 1, Palette.creamDark);
  b.set(x + 4, y + 7, Palette.creamDark);
  b.set(x + 1, y + 4, Palette.creamDark);
  b.set(x + 7, y + 4, Palette.creamDark);
  b.vline(x + 4, y + 2, 3, Palette.ink);
  b.hline(x + 4, y + 4, 3, Palette.ink);
}
