import 'package:office_core/office_core.dart';

import '../state/seat_state.dart';
import 'palette.dart';
import 'pixel.dart';

/// Sprite box: 24 columns by 32 rows, plus [spriteEarRows] above for the
/// beanie ears. A standing character uses rows 0-31, a seated one is clipped
/// by the desk.
const int spriteWidth = 24;
const int spriteHeight = 32;
const int spriteEarRows = 3;

enum Stance { standing, seated }

enum Arms { down, onDesk, raisedRight, armsUp, scratch, paper, mug }

enum Eyes { open, closed, up }

/// Where a seat's character is drawn.
enum Spot { chair, besideChair, coffee }

/// Which outfit a character wears.
enum CharacterStyle { beanie, glasses, sweater }

CharacterStyle styleFor(Seat seat) => switch (seat) {
  Seat.claude => CharacterStyle.beanie,
  Seat.gpt => CharacterStyle.glasses,
  Seat.gemini => CharacterStyle.sweater,
};

/// One drawable pose; [dy] shifts the whole sprite (bounce) and [headDy]
/// drops the head one pixel (breathing, drooping).
class CharacterPose {
  const CharacterPose({
    required this.stance,
    this.arms = Arms.down,
    this.eyes = Eyes.open,
    this.dy = 0,
    this.headDy = 0,
    this.frame = 0,
  });

  final Stance stance;
  final Arms arms;
  final Eyes eyes;
  final int dy;
  final int headDy;

  /// Animation frame 0-3; used by the mug steam.
  final int frame;
}

/// Pose for a seat visual, or null when nobody is at the seat.
CharacterPose? poseFor(SeatVisual visual, int frame, {required bool hasDesk}) {
  final deskArms = hasDesk ? Arms.onDesk : Arms.down;
  final breath = frame ~/ 2 == 1 ? 1 : 0;
  return switch (visual) {
    SeatVisual.empty => null,
    SeatVisual.idle => CharacterPose(stance: Stance.seated, headDy: breath),
    SeatVisual.sleeping => const CharacterPose(
      stance: Stance.seated,
      eyes: Eyes.closed,
      headDy: 1,
    ),
    SeatVisual.arriving => CharacterPose(
      stance: Stance.standing,
      headDy: breath,
    ),
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
      headDy: breath,
    ),
    SeatVisual.celebrating => CharacterPose(
      stance: Stance.seated,
      arms: Arms.armsUp,
      dy: frame ~/ 2 == 1 ? -1 : 0,
    ),
    SeatVisual.failed => const CharacterPose(
      stance: Stance.seated,
      arms: Arms.scratch,
      headDy: 1,
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

/// Builds the ASCII rows of a character. Row 0 of the result is
/// [spriteEarRows] rows above the 24x32 sprite box.
///
/// Legend: O/H/h/d hair outline, light, base, dark; k/L/s/S skin outline,
/// light, base, shade; q/B/b/D body outline, light, base, dark; Q/p/P pants
/// outline, base, dark; x/X shoe, shoe light; e/E eye, eye glint; m mouth;
/// g glasses; n ear inside; c/C mug, mug shade; z steam; W/V/l paper, paper
/// shade, paper line.
List<String> buildCharacterRows(CharacterPose pose, CharacterStyle style) {
  const w = spriteWidth;
  const h = spriteHeight + spriteEarRows;
  final g = List.generate(h, (_) => List.filled(w, '.'));

  void put(int r, int c, String ch) {
    final row = r + spriteEarRows;
    if (row < 0 || row >= h || c < 0 || c >= w) return;
    g[row][c] = ch;
  }

  /// Writes a literal row; '.' leaves the pixel as it was.
  void text(int r, int c0, String s) {
    for (var i = 0; i < s.length; i++) {
      if (s[i] != '.') put(r, c0 + i, s[i]);
    }
  }

  /// Writes a literal row, '.' included (clears).
  void raw(int r, int c0, String s) {
    for (var i = 0; i < s.length; i++) {
      put(r, c0 + i, s[i]);
    }
  }

  final hd = pose.headDy;

  // ---- head (columns 6..17) ----
  const head = [
    '..OOOOOOOO..', // 0
    '.OHHHhhhhhO.', // 1
    'OHHHhhhhhhhO', // 2
    'OHHhhhhhhhhO', // 3
    'OHhhhhhhhhhO', // 4
    'OhdddsddddhO', // 5 fringe with a parting
    'khLssssssShk', // 6
    'kLssssssssSk', // 7
    'kLssssssssSk', // 8
    'ksssssssssSk', // 9
    'kssssmmssSSk', // 10
    '.kssssssSSk.', // 11
    '..kkkkkkkk..', // 12
  ];
  for (var i = 0; i < head.length; i++) {
    text(i + hd, 6, head[i]);
  }

  switch (style) {
    case CharacterStyle.beanie:
      // Beanie in the hoodie colour with a ribbed brim and cat ears.
      const beanie = [
        '.qbbbbbbbbq.',
        'qBBBbbbbbbbq',
        'qBBBbbbbbbbq',
        'qBBbbbbbbbbq',
        'qDbDbDbDbDbq',
        'qDDDDDDDDDDq',
      ];
      for (var i = 0; i < beanie.length; i++) {
        raw(i + hd, 6, beanie[i]);
      }
      text(6 + hd, 6, 'qb........bq');
      text(-3 + hd, 6, '..q......q..');
      text(-2 + hd, 6, '.qnq....qnq.');
      text(-1 + hd, 6, 'qbnnq..qnnbq');
    case CharacterStyle.glasses:
      text(6 + hd, 8, 'gggg');
      text(6 + hd, 12, 'gggg');
      for (final c in [8, 11, 12, 15]) {
        put(7 + hd, c, 'g');
        put(8 + hd, c, 'g');
      }
      text(9 + hd, 8, 'gggg');
      text(9 + hd, 12, 'gggg');
      put(7 + hd, 7, 'g');
      put(7 + hd, 16, 'g');
    case CharacterStyle.sweater:
      for (var r = 6; r <= 9; r++) {
        put(r + hd, 7, 'h');
        put(r + hd, 16, 'h');
      }
      put(10 + hd, 7, 'd');
      put(10 + hd, 16, 'd');
      put(5 + hd, 11, 'd');
      put(5 + hd, 13, 's');
  }

  // Eyes.
  switch (pose.eyes) {
    case Eyes.open:
      text(7 + hd, 9, 'Ee');
      text(7 + hd, 13, 'Ee');
      text(8 + hd, 9, 'ee');
      text(8 + hd, 13, 'ee');
    case Eyes.closed:
      text(8 + hd, 9, 'ee');
      text(8 + hd, 13, 'ee');
    case Eyes.up:
      text(6 + hd, 9, 'Ee');
      text(6 + hd, 13, 'Ee');
      text(7 + hd, 9, 'ee');
      text(7 + hd, 13, 'ee');
  }

  // ---- torso (columns 4..19) ----
  const torso = [
    '.qqqqkSSSSkqqqq.', // 13 shoulders and neck
    'qBBbbbSSSSbbDDDq', // 14
    'qBBbbbbbbbbbDDDq', // 15
    'qBBbbbbbbbbbDDDq', // 16
    'qBBbbbbbbbbbDDDq', // 17
    'qBBbbbbbbbbbDDDq', // 18
    'qBBbbbbbbbbbDDDq', // 19
    'qDDbbbbbbbbbDDDq', // 20 cuffs
    'kLsqbbbbbbbbqsSk', // 21 hands
    'kssqbbbbbbbbqSSk', // 22
    'kkkqqqqqqqqqqkkk', // 23
  ];
  for (var i = 0; i < torso.length; i++) {
    text(13 + i, 4, torso[i]);
  }
  switch (style) {
    case CharacterStyle.beanie:
      // Kangaroo pocket and drawstrings.
      text(19, 8, 'DDDDDDDD');
      put(15, 11, 'c');
      put(16, 11, 'c');
      put(17, 11, 'c');
      put(15, 12, 'c');
      put(16, 12, 'c');
    case CharacterStyle.glasses:
      // Shirt collar and a button placket.
      text(14, 8, 'cc....cc');
      put(15, 9, 'c');
      put(15, 14, 'c');
      put(17, 12, 'D');
      put(19, 12, 'D');
    case CharacterStyle.sweater:
      // Ribbed collar and a light chest stripe.
      text(14, 9, 'cccccc');
      text(17, 7, 'BBBBBBBBB');
  }

  // ---- legs ----
  if (pose.stance == Stance.standing) {
    for (var r = 24; r <= 29; r++) {
      text(r, 7, 'QppPQQppPQ');
    }
  } else {
    text(24, 5, 'QpppppppppppPPQ');
    text(25, 5, 'QpppppppppppPPQ');
    text(26, 5, 'QPPPPPPPPPPPPPQ');
    text(27, 5, 'QQQQQQQQQQQQQQQ');
    text(28, 7, 'QppPQQppPQ');
    text(29, 7, 'QppPQQppPQ');
  }
  text(30, 6, 'QXxxxQQXxxxQ');
  text(31, 6, 'QQQQQQQQQQQQ');

  // ---- arms ----
  void dropRightArm() {
    for (var r = 14; r <= 22; r++) {
      raw(r, 16, 'Dq..');
    }
    raw(23, 16, 'qq..');
  }

  void dropLeftArm() {
    for (var r = 14; r <= 22; r++) {
      raw(r, 4, '..qB');
    }
    raw(23, 4, '..qq');
  }

  void rightArmUp(int handTop, int armCol) {
    for (var r = handTop + 4; r <= 15; r++) {
      text(r, armCol, 'qbDq');
    }
    text(handTop, armCol - 1, '.kkk.');
    text(handTop + 1, armCol - 1, 'kLssk');
    text(handTop + 2, armCol - 1, 'ksSSk');
    text(handTop + 3, armCol - 1, '.kkk.');
  }

  void leftArmUp(int handTop) {
    for (var r = handTop + 4; r <= 15; r++) {
      text(r, 2, 'qBbq');
    }
    text(handTop, 1, '.kkk.');
    text(handTop + 1, 1, 'kLssk');
    text(handTop + 2, 1, 'ksSSk');
    text(handTop + 3, 1, '.kkk.');
  }

  void sleeves() {
    raw(21, 4, 'qBb');
    raw(22, 4, 'qBb');
    raw(23, 4, 'qqq');
    raw(21, 17, 'DDq');
    raw(22, 17, 'DDq');
    raw(23, 17, 'qqq');
  }

  switch (pose.arms) {
    case Arms.down:
      break;
    case Arms.onDesk:
      sleeves();
    case Arms.raisedRight:
      dropRightArm();
      rightArmUp(3, 18);
    case Arms.scratch:
      dropRightArm();
      rightArmUp(5 + hd, 18);
    case Arms.armsUp:
      dropRightArm();
      dropLeftArm();
      rightArmUp(3, 18);
      leftArmUp(3);
    case Arms.paper:
      sleeves();
      text(14, 8, 'VVVVVVVV');
      for (var r = 15; r <= 20; r++) {
        text(r, 8, 'WWWWWWWV');
      }
      text(21, 8, 'VVVVVVVV');
      text(16, 9, 'llll');
      text(18, 9, 'lllll');
      text(20, 9, 'lll');
      raw(18, 5, 'kLs');
      raw(19, 5, 'kss');
      raw(18, 16, 'sSk');
      raw(19, 16, 'sSk');
    case Arms.mug:
      raw(21, 17, 'DDq');
      raw(22, 17, 'DDq');
      raw(23, 17, 'qqq');
      raw(18, 16, 'kLs');
      raw(19, 16, 'kss');
      raw(20, 16, '.kk');
      text(16, 19, 'CCCC');
      text(17, 19, 'cccCC');
      text(18, 19, 'cccC.');
      text(19, 19, 'cccCC');
      text(20, 19, 'CCCC');
      final up = pose.frame ~/ 2 == 0;
      put(up ? 14 : 13, 20, 'z');
      put(up ? 13 : 14, 22, 'z');
  }

  return [for (final row in g) row.join()];
}

/// Draws a character whose 24x32 sprite box starts at (x, y). The ears
/// extend [spriteEarRows] above y. Rows at or below [clipBottom] are not
/// drawn (character behind a desk).
void drawCharacter(
  PixelBuffer b,
  int x,
  int y,
  CharacterPose pose,
  CharacterPalette palette,
  CharacterStyle style, {
  int clipBottom = 1 << 20,
}) {
  final rows = buildCharacterRows(pose, style);
  b.sprite(
    x,
    y + pose.dy - spriteEarRows,
    rows,
    characterLegend(palette),
    clipBottom: clipBottom,
  );
}

/// Colour of every legend character of [buildCharacterRows] for [palette].
Map<String, int> characterLegend(CharacterPalette palette) => {
  'O': palette.hairOutline,
  'H': palette.hairLight,
  'h': palette.hair,
  'd': palette.hairDark,
  'k': CharacterPalette.skinOutline,
  'L': CharacterPalette.skinLight,
  's': CharacterPalette.skin,
  'S': CharacterPalette.skinShade,
  'q': palette.bodyOutline,
  'B': palette.bodyLight,
  'b': palette.body,
  'D': palette.bodyDark,
  'Q': CharacterPalette.pantsOutline,
  'p': CharacterPalette.pants,
  'P': CharacterPalette.pantsDark,
  'x': CharacterPalette.shoe,
  'X': CharacterPalette.shoeLight,
  'e': Palette.ink,
  'E': Palette.creamLight,
  'm': CharacterPalette.skinOutline,
  'g': Palette.steelShade,
  'n': Palette.pink,
  'c': Palette.cream,
  'C': Palette.creamDark,
  'z': Palette.steam,
  'W': Palette.paper,
  'V': Palette.paperShade,
  'l': Palette.paperLine,
};

/// Two hands over a 22-wide keyboard whose top-left is (kbX, kbY). With
/// [animate] the hands alternate lifting one pixel every two frames.
void drawHands(
  PixelBuffer b,
  int kbX,
  int kbY,
  CharacterPalette palette, {
  required bool animate,
  int frame = 0,
}) {
  final phase = animate ? frame ~/ 2 : -1;
  final leftLift = phase == 0 ? 1 : 0;
  final rightLift = phase == 1 ? 1 : 0;
  const hand = ['.kkkk.', 'kLsssk', 'kssSSk', '.kkkk.'];
  const legend = {
    'k': CharacterPalette.skinOutline,
    'L': CharacterPalette.skinLight,
    's': CharacterPalette.skin,
    'S': CharacterPalette.skinShade,
  };
  b.sprite(kbX + 2, kbY - 3 - leftLift, hand, legend);
  b.sprite(kbX + 14, kbY - 3 - rightLift, hand, legend);
}
