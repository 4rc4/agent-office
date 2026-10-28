import 'dart:ui';

import '../state/seat_state.dart';
import 'palette.dart';
import 'pixel.dart';

/// Sprite box: 24 columns by 32 rows, plus [spriteEarRows] above for the
/// beanie ears. A standing character uses rows 0-31, a seated one rows 0-28
/// behind a desk (the desk clips the rest) or 0-31 on the visitor chair.
const int spriteWidth = 24;
const int spriteHeight = 32;
const int spriteEarRows = 3;

/// Sprite row that rests on a desk surface when seated (waist at the edge).
const int seatedDeskRow = 22;

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
    this.breathe = false,
  });

  final Stance stance;
  final Arms arms;
  final Eyes eyes;
  final int dy;

  /// Animation frame 0-3; used by the mug steam and the breathing.
  final int frame;

  /// Two-frame breathing: the head sinks one pixel on frames 2 and 3.
  final bool breathe;
}

/// Pose for a seat visual, or null when nobody is at the seat.
CharacterPose? poseFor(SeatVisual visual, int frame, {required bool hasDesk}) {
  final deskArms = hasDesk ? Arms.onDesk : Arms.down;
  return switch (visual) {
    SeatVisual.empty => null,
    SeatVisual.idle => CharacterPose(
      stance: Stance.seated,
      frame: frame,
      breathe: true,
    ),
    SeatVisual.sleeping => CharacterPose(
      stance: Stance.seated,
      eyes: Eyes.closed,
      frame: frame,
      breathe: true,
    ),
    SeatVisual.arriving => const CharacterPose(stance: Stance.standing),
    SeatVisual.thinking => CharacterPose(
      stance: Stance.seated,
      eyes: Eyes.up,
      frame: frame,
      breathe: true,
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

// Legend: O ink outline; H/h/G/g hair base/light/shade/dark; S/s/D skin
// base/light/shade; E eye, W eye highlight, M mouth; B/b/N/n body
// base/light/shade/dark; Y beanie band; P/Q/p pants base/light/shade;
// K/k shoe base/shade; F glasses frame; A paper, L paper line; C/c mug
// base/shade; T steam.

/// Head with hair, rows 0-13. Eyes are stamped afterwards.
const List<String> _hairHead = [
  '......OOOOOOOOOOOO......',
  '.....OhhhHHHHHHHHGO.....',
  '....OhhHHHHHHHHHHGgO....',
  '....OhHHHHHHHHHHHGgO....',
  '....OHHsSSSSSSSSHGgO....',
  '....OHsSSSSSSSSSSHgO....',
  '....OHsSSSSSSSSSSDGO....',
  '....OHsSSSSSSSSSSDGO....',
  '....OSsSSSSSSSSSSDDO....',
  '.....OSSSSSSSSSSSDO.....',
  '.....OSSSSSMMSSSSDO.....',
  '......OSSSSSSSSSDO......',
  '.......OOSSSSSSOO.......',
  '.........ODDDDO.........',
];

/// Head with the cat-ear beanie; the first three rows are the ears above
/// the sprite box.
const List<String> _beanieHead = [
  '.....OO.........OO......',
  '....ObBO.......OBNO.....',
  '....ObBBO.....OBBNO.....',
  '....ObBBBOOOOOBBBBNO....',
  '....ObbBBBBBBBBBBBNO....',
  '....ObBBBBBBBBBBBBNO....',
  '....OYYYYYYYYYYYYYYO....',
  '....OYsSSSSSSSSSSYYO....',
  '....OYsSSSSSSSSSSDYO....',
  '....OYsSSSSSSSSSSDYO....',
  '....OYsSSSSSSSSSSDYO....',
  '....OSsSSSSSSSSSSDDO....',
  '.....OSSSSSSSSSSSDO.....',
  '.....OSSSSSMMSSSSDO.....',
  '......OSSSSSSSSSDO......',
  '.......OOSSSSSSOO.......',
  '.........ODDDDO.........',
];

/// Torso with the arms down, rows 14-24.
const List<String> _torso = [
  '......ObbBBBBBBBBNO.....',
  '.....ObbBBBBBBBBBBNO....',
  '....ObbBBBBBBBBBBBBNO...',
  '...ObBnBBBBBBBBBBnBNO...',
  '...ObBnBBBBBBBBBBnBNO...',
  '...ObBnBBBBBBBBBBnBNO...',
  '...ObBnBBBBBBBBBBnBNO...',
  '...OsSnBBBBBBBBBBnSDO...',
  '...OsSnBBBBBBBBBBnSDO...',
  '....OOnBBBBBBBBBBnOO....',
  '......OBBBBBBBBBBNO.....',
];

/// Standing legs and shoes, rows 25-31.
const List<String> _standingLegs = [
  '......OQPPPPOPPPPpO.....',
  '......OQPPPPOPPPPpO.....',
  '......OQPPPPOPPPPpO.....',
  '......OQPPPPOPPPPpO.....',
  '......OQPPPPOPPPPpO.....',
  '.....OKKKKKKOKKKKKkO....',
  '.....OkkkkkkOkkkkkkO....',
];

/// Seated legs: thighs coming forward, shins and shoes below, rows 25-31.
const List<String> _seatedLegs = [
  '......OQPPPPOPPPPpO.....',
  '.....OQPPPPPOPPPPPpO....',
  '.....OQPPPPPOPPPPPpO....',
  '.....OOpPPPOOOPPPpOO....',
  '......OPPPPOOPPPPpO.....',
  '.....OKKKKKOOKKKKKkO....',
  '.....OkkkkkOOkkkkkkO....',
];

/// Builds the ASCII rows of a character. Row 0 of the result is
/// [spriteEarRows] rows above the 24x32 sprite box.
List<String> buildCharacterRows(
  CharacterPose pose, {
  required bool beanie,
  required bool glasses,
}) {
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

  void stamp(List<String> rows, int top) {
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final ch = row[c];
        if (ch != '.') put(top + r, c, ch);
      }
    }
  }

  // Body first, so the head can overlap the shoulders while breathing.
  stamp(_torso, 14);
  stamp(pose.stance == Stance.standing ? _standingLegs : _seatedLegs, 25);

  // Arm variants over the arms-down torso.
  void clearRightArm() {
    for (var r = 17; r <= 23; r++) {
      put(r, 17, 'N');
      put(r, 18, 'O');
      put(r, 19, '.');
      put(r, 20, '.');
    }
  }

  void clearLeftArm() {
    for (var r = 17; r <= 23; r++) {
      put(r, 3, '.');
      put(r, 4, '.');
      put(r, 5, 'O');
      put(r, 6, 'b');
    }
  }

  void rightArmUp(int handTop) {
    // Upper arm from the shoulder, then the forearm straight up beside the
    // head, hand at [handTop].
    for (var r = handTop + 3; r <= 16; r++) {
      put(r, 19, 'O');
      put(r, 20, 'B');
      put(r, 21, 'N');
      put(r, 22, 'O');
    }
    put(16, 19, 'B');
    put(15, 19, 'B');
    put(15, 18, 'B');
    put(16, 18, 'B');
    line(handTop - 1, 19, 22, 'O');
    for (var r = handTop; r <= handTop + 2; r++) {
      put(r, 19, 'O');
      put(r, 20, 's');
      put(r, 21, 'S');
      put(r, 22, 'O');
    }
    put(handTop + 2, 21, 'D');
  }

  void leftArmUp(int handTop) {
    for (var r = handTop + 3; r <= 16; r++) {
      put(r, 1, 'O');
      put(r, 2, 'b');
      put(r, 3, 'B');
      put(r, 4, 'O');
    }
    put(16, 4, 'B');
    put(15, 4, 'B');
    put(15, 5, 'B');
    put(16, 5, 'B');
    line(handTop - 1, 1, 4, 'O');
    for (var r = handTop; r <= handTop + 2; r++) {
      put(r, 1, 'O');
      put(r, 2, 's');
      put(r, 3, 'S');
      put(r, 4, 'O');
    }
    put(handTop + 2, 3, 'D');
  }

  switch (pose.arms) {
    case Arms.down:
      break;
    case Arms.onDesk:
      // Sleeves reach forward; the hands are drawn on the keyboard.
      for (var r = 21; r <= 22; r++) {
        put(r, 4, 'b');
        put(r, 5, 'B');
        put(r, 18, 'B');
        put(r, 19, 'N');
      }
    case Arms.raisedRight:
      clearRightArm();
      rightArmUp(4);
    case Arms.armsUp:
      clearRightArm();
      clearLeftArm();
      rightArmUp(4);
      leftArmUp(4);
    case Arms.scratch:
      clearRightArm();
      // Forearm goes up beside the head, hand bent over the hair.
      for (var r = 7; r <= 16; r++) {
        put(r, 19, 'O');
        put(r, 20, 'B');
        put(r, 21, 'N');
        put(r, 22, 'O');
      }
      put(16, 19, 'B');
      put(15, 19, 'B');
      put(15, 18, 'B');
      put(16, 18, 'B');
      line(3, 17, 22, 'O');
      for (var r = 4; r <= 6; r++) {
        put(r, 17, 'O');
        line(r, 18, 20, r == 4 ? 's' : 'S');
        put(r, 21, 'D');
        put(r, 22, 'O');
      }
      line(7, 17, 19, 'O');
    case Arms.paper:
      // Sheet held in front of the chest, hands at its lower corners.
      line(15, 7, 16, 'O');
      for (var r = 16; r <= 23; r++) {
        put(r, 7, 'O');
        line(r, 8, 14, 'A');
        put(r, 15, 'L');
        put(r, 16, 'O');
      }
      line(23, 8, 15, 'L');
      line(18, 9, 13, 'L');
      line(20, 9, 12, 'L');
      line(22, 9, 13, 'L');
      for (var r = 20; r <= 21; r++) {
        put(r, 4, 'O');
        put(r, 5, 's');
        put(r, 6, 'S');
        put(r, 7, 'S');
        put(r, 8, 'D');
        put(r, 15, 'S');
        put(r, 16, 'S');
        put(r, 17, 'S');
        put(r, 18, 'D');
        put(r, 19, 'O');
      }
      for (var r = 22; r <= 23; r++) {
        put(r, 3, '.');
        put(r, 4, '.');
        put(r, 5, 'O');
        put(r, 6, 'b');
        put(r, 17, 'N');
        put(r, 18, 'O');
        put(r, 19, '.');
        put(r, 20, '.');
      }
    case Arms.mug:
      // Right forearm bent up, hand round a mug at chest height.
      for (var r = 20; r <= 23; r++) {
        put(r, 17, 'N');
        put(r, 18, 'O');
        put(r, 19, '.');
        put(r, 20, '.');
      }
      put(19, 18, 'B');
      put(19, 19, 'N');
      put(19, 20, 'O');
      line(14, 18, 22, 'O');
      for (var r = 15; r <= 18; r++) {
        put(r, 18, 'O');
        put(r, 19, 'C');
        put(r, 20, 'C');
        put(r, 21, 'c');
        put(r, 22, 'O');
      }
      put(15, 19, 'A');
      line(19, 18, 22, 'O');
      put(16, 23, 'O');
      put(17, 23, 'O');
      line(18, 19, 21, 'S');
      put(18, 18, 's');
      put(18, 22, 'D');
      final steamRow = pose.frame ~/ 2 == 0 ? 12 : 11;
      put(steamRow, 20, 'T');
      put(steamRow - 1, 21, 'T');
      put(steamRow + 1, 19, 'T');
  }

  // Head, possibly sunk one pixel while breathing.
  final headDy = pose.breathe && pose.frame ~/ 2 == 1 ? 1 : 0;
  if (beanie) {
    stamp(_beanieHead, -spriteEarRows + headDy);
  } else {
    stamp(_hairHead, headDy);
  }

  // Eyes (2x2 with a highlight) or closed lids.
  final eyeRow = switch (pose.eyes) {
    Eyes.open => 6,
    Eyes.up => 5,
    Eyes.closed => 7,
  };
  for (final c in const [8, 14]) {
    switch (pose.eyes) {
      case Eyes.open || Eyes.up:
        put(eyeRow + headDy, c, 'E');
        put(eyeRow + headDy, c + 1, 'W');
        put(eyeRow + 1 + headDy, c, 'E');
        put(eyeRow + 1 + headDy, c + 1, 'E');
      case Eyes.closed:
        line(eyeRow + headDy, c, c + 1, 'E');
    }
  }
  if (glasses) {
    final top = 5 + headDy;
    line(top, 7, 10, 'F');
    line(top, 13, 16, 'F');
    put(top + 1, 7, 'F');
    put(top + 1, 10, 'F');
    line(top + 1, 11, 12, 'F');
    put(top + 1, 13, 'F');
    put(top + 1, 16, 'F');
    put(top + 2, 7, 'F');
    put(top + 2, 10, 'F');
    put(top + 2, 13, 'F');
    put(top + 2, 16, 'F');
    line(top + 3, 7, 10, 'F');
    line(top + 3, 13, 16, 'F');
    if (pose.eyes == Eyes.closed) {
      line(top + 2, 8, 9, 'E');
      line(top + 2, 14, 15, 'E');
    }
  }

  return [for (final row in g) row.join()];
}

/// Colour legend for one palette.
Map<String, Color> characterLegend(CharacterPalette p) => {
  'O': ScenePalette.ink,
  'H': p.hair.base,
  'h': p.hair.light,
  'G': p.hair.shade,
  'g': p.hair.dark,
  'S': p.skin.base,
  's': p.skin.light,
  'D': p.skin.shade,
  'E': ScenePalette.ink,
  'W': const Color(0xFFFFFFFF),
  'M': p.skin.dark,
  'B': p.body.base,
  'b': p.body.light,
  'N': p.body.shade,
  'n': p.body.dark,
  'Y': p.body.dark,
  'P': p.pants.base,
  'Q': p.pants.light,
  'p': p.pants.shade,
  'K': p.shoe.base,
  'k': p.shoe.shade,
  'F': ScenePalette.steel.light,
  'A': ScenePalette.paper.base,
  'L': ScenePalette.paperLine,
  'C': ScenePalette.mug.base,
  'c': ScenePalette.mug.shade,
  'T': ScenePalette.steam,
};

/// Draws a character whose 24x32 sprite box starts at (x, y). The beanie
/// ears extend [spriteEarRows] above y. A soft shadow goes under standing
/// characters.
void drawCharacter(
  Px px,
  int x,
  int y,
  CharacterPose pose,
  CharacterPalette palette, {
  bool shadow = true,
}) {
  if (shadow && pose.stance == Stance.standing) {
    px.shadowEllipse(
      x + spriteWidth ~/ 2,
      y + pose.dy + spriteHeight - 1,
      9,
      2,
      ScenePalette.shadow,
    );
  }
  final rows = buildCharacterRows(
    pose,
    beanie: palette.beanie,
    glasses: palette.glasses,
  );
  px.sprite(x, y + pose.dy - spriteEarRows, rows, characterLegend(palette));
}

/// Two hands over a keyboard whose top-left is (kbX, kbY). With [animate]
/// the hands lift alternately over four frames.
void drawHands(
  Px px,
  int kbX,
  int kbY,
  CharacterPalette palette, {
  required bool animate,
  int frame = 0,
}) {
  final leftLift = animate && frame % 4 == 0 ? 1 : 0;
  final rightLift = animate && frame % 4 == 2 ? 1 : 0;
  void hand(int x, int y) {
    px.ring(x, y, 6, 4, palette.skin.dark);
    px.fill(x + 1, y + 1, 4, 2, palette.skin.base);
    px.hline(x + 1, y + 1, 3, palette.skin.light);
    px.hline(x + 1, y + 2, 4, palette.skin.shade);
    px.dot(x + 1, y + 2, palette.skin.base);
  }

  hand(kbX + 1, kbY - 2 - leftLift);
  hand(kbX + 13, kbY - 2 - rightLift);
}
