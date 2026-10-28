import '../state/seat_state.dart';
import 'palette.dart';
import 'pixel.dart';

/// Sprite box: 16 columns by 24 rows, plus [spriteEarRows] above for the hood
/// ears. A standing character uses rows 0-22, a seated one rows 0-20.
const int spriteWidth = 16;
const int spriteHeight = 24;
const int spriteEarRows = 2;

/// Sprite row that rests on a desk surface when seated (waist at the edge).
const int seatedDeskRow = 16;

/// Sprite row that rests on a desk surface when standing behind it (hips).
const int standingDeskRow = 20;

enum Stance { standing, seated }

enum Arms { down, onDesk, raisedRight, armsUp, scratch, paper, mug }

enum Eyes { open, closed, up }

/// Where a seat's character is drawn.
enum Spot { chair, besideChair, coffee }

/// One drawable pose; [dy] shifts the sprite (lean forward, bounce).
class CharacterPose {
  const CharacterPose({
    required this.stance,
    this.arms = Arms.down,
    this.eyes = Eyes.open,
    this.dy = 0,
    this.frame = 0,
  });

  final Stance stance;
  final Arms arms;
  final Eyes eyes;
  final int dy;

  /// Animation frame 0-3; used by the mug steam.
  final int frame;
}

/// Pose for a seat visual, or null when nobody is at the seat.
CharacterPose? poseFor(SeatVisual visual, int frame, {required bool hasDesk}) {
  final deskArms = hasDesk ? Arms.onDesk : Arms.down;
  return switch (visual) {
    SeatVisual.empty => null,
    SeatVisual.idle => const CharacterPose(stance: Stance.seated),
    SeatVisual.sleeping => const CharacterPose(
      stance: Stance.seated,
      eyes: Eyes.closed,
    ),
    SeatVisual.arriving => const CharacterPose(stance: Stance.standing),
    SeatVisual.thinking => const CharacterPose(
      stance: Stance.seated,
      eyes: Eyes.up,
    ),
    SeatVisual.typing ||
    SeatVisual.editing ||
    SeatVisual.shell ||
    SeatVisual.browsing => CharacterPose(stance: Stance.seated, arms: deskArms),
    SeatVisual.reading => const CharacterPose(
      stance: Stance.seated,
      arms: Arms.paper,
      dy: 1,
    ),
    SeatVisual.waitingUser => const CharacterPose(
      stance: Stance.standing,
      arms: Arms.raisedRight,
    ),
    SeatVisual.onBreak => CharacterPose(
      stance: Stance.standing,
      arms: Arms.mug,
      frame: frame,
    ),
    SeatVisual.celebrating => CharacterPose(
      stance: Stance.seated,
      arms: Arms.armsUp,
      dy: frame ~/ 2 == 1 ? -1 : 0,
    ),
    SeatVisual.failed => const CharacterPose(
      stance: Stance.seated,
      arms: Arms.scratch,
    ),
  };
}

/// Where the character of a seat stands or sits for a visual.
Spot spotFor(SeatVisual visual) => switch (visual) {
  SeatVisual.arriving || SeatVisual.waitingUser => Spot.besideChair,
  SeatVisual.onBreak => Spot.coffee,
  _ => Spot.chair,
};

/// True when separate hands are drawn on the keyboard.
bool handsOnKeyboard(SeatVisual visual) => switch (visual) {
  SeatVisual.typing ||
  SeatVisual.editing ||
  SeatVisual.shell ||
  SeatVisual.browsing => true,
  _ => false,
};

/// Builds the ASCII rows of a character. Legend: o outline, h hair, s skin,
/// b body, p pants, w paper, l paper line, c cream, d steam. Row 0 of the
/// result is [spriteEarRows] rows above the 16x24 sprite box.
List<String> buildCharacterRows(CharacterPose pose, {required bool hood}) {
  const w = spriteWidth;
  const h = spriteHeight + spriteEarRows;
  final g = List.generate(h, (_) => List.filled(w, '.'));

  void put(int r, int c, String ch) {
    final row = r + spriteEarRows;
    if (row < 0 || row >= h || c < 0 || c >= w) return;
    g[row][c] = ch;
  }

  void line(int r, int c0, int c1, String ch) {
    for (var c = c0; c <= c1; c++) {
      put(r, c, ch);
    }
  }

  final hair = hood ? 'b' : 'h';

  // Head.
  line(0, 4, 11, 'o');
  for (var r = 1; r <= 2; r++) {
    put(r, 3, 'o');
    line(r, 4, 11, hair);
    put(r, 12, 'o');
  }
  put(3, 3, 'o');
  put(3, 4, hair);
  line(3, 5, 10, 's');
  put(3, 11, hair);
  put(3, 12, 'o');
  for (var r = 4; r <= 7; r++) {
    put(r, 3, 'o');
    line(r, 4, 11, 's');
    put(r, 12, 'o');
  }
  line(8, 4, 11, 'o');
  if (hood) {
    put(-2, 4, 'o');
    put(-2, 11, 'o');
    put(-1, 3, 'o');
    put(-1, 4, 'b');
    put(-1, 5, 'o');
    put(-1, 10, 'o');
    put(-1, 11, 'b');
    put(-1, 12, 'o');
    put(0, 3, 'o');
    put(0, 4, 'b');
    put(0, 11, 'b');
    put(0, 12, 'o');
  }

  // Face.
  switch (pose.eyes) {
    case Eyes.open:
      put(5, 5, 'o');
      put(5, 10, 'o');
    case Eyes.up:
      put(4, 5, 'o');
      put(4, 10, 'o');
    case Eyes.closed:
      line(5, 4, 5, 'o');
      line(5, 10, 11, 'o');
  }
  line(7, 7, 8, 'o');

  // Torso with arms down.
  put(9, 3, 'o');
  line(9, 4, 11, 'b');
  put(9, 12, 'o');
  for (var r = 10; r <= 13; r++) {
    put(r, 2, 'o');
    line(r, 3, 12, 'b');
    put(r, 13, 'o');
  }
  for (var r = 14; r <= 15; r++) {
    put(r, 2, 'o');
    put(r, 3, 's');
    line(r, 4, 11, 'b');
    put(r, 12, 's');
    put(r, 13, 'o');
  }
  line(16, 2, 3, 'o');
  line(16, 4, 11, 'b');
  line(16, 12, 13, 'o');
  line(17, 3, 12, 'o');

  // Legs.
  final legRows = pose.stance == Stance.standing ? 4 : 2;
  for (var r = 18; r < 18 + legRows; r++) {
    put(r, 4, 'o');
    line(r, 5, 6, 'p');
    line(r, 7, 8, 'o');
    line(r, 9, 10, 'p');
    put(r, 11, 'o');
  }
  line(18 + legRows, 4, 11, 'o');

  // Arm variants.
  void rightArmUp(int handTop) {
    put(handTop - 1, 12, 'o');
    line(handTop - 1, 13, 14, 'o');
    for (var r = handTop; r <= handTop + 1; r++) {
      line(r, 13, 14, 's');
      put(r, 15, 'o');
    }
    for (var r = handTop + 2; r <= 10; r++) {
      line(r, 13, 14, 'b');
      put(r, 15, 'o');
    }
    line(11, 13, 15, 'o');
  }

  void leftArmUp(int handTop) {
    line(handTop - 1, 1, 2, 'o');
    put(handTop - 1, 3, 'o');
    for (var r = handTop; r <= handTop + 1; r++) {
      line(r, 1, 2, 's');
      put(r, 0, 'o');
    }
    for (var r = handTop + 2; r <= 10; r++) {
      line(r, 1, 2, 'b');
      put(r, 0, 'o');
    }
    line(11, 0, 2, 'o');
  }

  switch (pose.arms) {
    case Arms.down:
      break;
    case Arms.onDesk:
      for (var r = 14; r <= 15; r++) {
        put(r, 3, 'b');
        put(r, 12, 'b');
      }
    case Arms.raisedRight:
      rightArmUp(1);
    case Arms.scratch:
      rightArmUp(5);
    case Arms.armsUp:
      rightArmUp(1);
      leftArmUp(1);
    case Arms.paper:
      line(9, 5, 10, 'o');
      for (var r = 10; r <= 13; r++) {
        put(r, 4, 'o');
        line(r, 5, 10, 'w');
        put(r, 11, 'o');
      }
      line(14, 5, 10, 'o');
      line(11, 6, 9, 'l');
      line(13, 6, 9, 'l');
      for (var r = 12; r <= 13; r++) {
        put(r, 3, 's');
        put(r, 12, 's');
      }
    case Arms.mug:
      line(12, 13, 15, 'o');
      for (var r = 13; r <= 14; r++) {
        put(r, 13, 'o');
        put(r, 14, 'c');
        put(r, 15, 'o');
      }
      line(15, 13, 15, 'o');
      put(pose.frame ~/ 2 == 0 ? 10 : 9, 14, 'd');
  }

  return [for (final row in g) row.join()];
}

/// Draws a character whose 16x24 sprite box starts at (x, y). The hood ears
/// extend [spriteEarRows] above y.
void drawCharacter(
  Px px,
  int x,
  int y,
  CharacterPose pose,
  CharacterPalette palette, {
  required bool hood,
}) {
  final rows = buildCharacterRows(pose, hood: hood);
  px.sprite(x, y + pose.dy - spriteEarRows, rows, {
    'o': ScenePalette.outline,
    'h': palette.hair,
    's': palette.skin,
    'b': palette.body,
    'p': palette.pants,
    'w': ScenePalette.paper,
    'l': ScenePalette.paperLine,
    'c': ScenePalette.cream,
    'd': ScenePalette.grey,
  });
}

/// Two hands over a 14-wide keyboard whose top-left is (kbX, kbY). With
/// [animate] the hands alternate lifting one pixel every two frames.
void drawHands(
  Px px,
  int kbX,
  int kbY,
  CharacterPalette palette, {
  required bool animate,
  int frame = 0,
}) {
  final phase = animate ? frame ~/ 2 : -1;
  final leftLift = phase == 0 ? 1 : 0;
  final rightLift = phase == 1 ? 1 : 0;
  px.box(kbX + 1, kbY - 2 - leftLift, 4, 4, palette.skin);
  px.box(kbX + 9, kbY - 2 - rightLift, 4, 4, palette.skin);
}
