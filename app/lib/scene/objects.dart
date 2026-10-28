import 'palette.dart';
import 'pixel.dart';

/// Small props that float next to a character. Positions are the top-left of
/// the prop in scene pixels; [frame] is tick % 4.

/// Thought cloud, 16x10, bobbing one pixel every two frames, with two
/// trailing puffs toward the head.
void drawCloud(PixelBuffer b, int x, int y, int frame) {
  final bob = frame ~/ 2 == 1 ? -1 : 0;
  final body = <(int, int)>[
    for (var i = 4; i <= 9; i++) (i, 0),
    for (var i = 2; i <= 11; i++) (i, 1),
    for (var i = 1; i <= 12; i++) (i, 2),
    for (var i = 0; i <= 13; i++) (i, 3),
    for (var i = 0; i <= 13; i++) (i, 4),
    for (var i = 1; i <= 12; i++) (i, 5),
    for (var i = 3; i <= 10; i++) (i, 6),
  ];
  b.blob(body, Palette.cream, outline: Palette.creamDark, x: x + 1, y: y + 1 + bob);
  for (final (px, py) in body) {
    if (py >= 4 && px > 6) b.set(x + 1 + px, y + 1 + bob + py, Palette.creamShade);
  }
  b.hline(x + 5, y + 1 + bob, 4, Palette.creamLight);
  b.blob(
    const [(0, 0), (1, 0), (0, 1), (1, 1)],
    Palette.cream,
    outline: Palette.creamDark,
    x: x + 2,
    y: y + 9 + bob,
  );
  b.blob(
    const [(0, 0)],
    Palette.cream,
    outline: Palette.creamDark,
    x: x,
    y: y + 12 + bob,
  );
}

/// "..." speech bubble, 16x11 including the tail; shows 1-3 dots by frame.
void drawDots(PixelBuffer b, int x, int y, int frame) {
  b.shadow(x + 1, y + 1, 16, 9, feather: 1);
  b.roundFill(x, y, 16, 9, Palette.cream);
  b.roundRing(x, y, 16, 9, Palette.creamDark);
  b.hline(x + 2, y + 1, 12, Palette.creamLight);
  final visible = frame % 3 + 1;
  for (var i = 0; i < visible; i++) {
    b.fill(x + 3 + i * 4, y + 4, 2, 2, Palette.ink);
  }
  b.hline(x + 2, y + 8, 3, Palette.cream);
  b.set(x + 1, y + 9, Palette.creamDark);
  b.set(x + 2, y + 9, Palette.cream);
  b.set(x + 3, y + 9, Palette.creamDark);
  b.set(x + 2, y + 10, Palette.creamDark);
}

/// A 7x9 sheet of paper with lines.
void drawSheet(PixelBuffer b, int x, int y) {
  b.fill(x, y, 7, 9, Palette.paper);
  b.vline(x + 6, y, 9, Palette.paperShade);
  b.hline(x, y + 8, 7, Palette.paperShade);
  b.hline(x + 1, y + 2, 4, Palette.paperLine);
  b.hline(x + 1, y + 4, 3, Palette.paperLine);
  b.hline(x + 1, y + 6, 4, Palette.paperLine);
}

/// Sheet flying from (fromX, fromY) to (toX, toY) in four frames.
void drawFlyingSheet(
  PixelBuffer b,
  int fromX,
  int fromY,
  int toX,
  int toY,
  int frame,
) {
  const arc = [0, -3, -3, 0];
  final f = frame % 4;
  final x = fromX + ((toX - fromX) * f / 3).round();
  final y = fromY + ((toY - fromY) * f / 3).round() + arc[f];
  drawSheet(b, x, y);
}

/// Green check mark in a cream badge, 14x14.
void drawCheck(PixelBuffer b, int x, int y) {
  b.disc(x + 6, y + 6, 6, Palette.cream, outline: Palette.greenDark);
  for (final (dx, dy) in PixelBuffer.discPixels(6)) {
    if (dx + dy > 4) b.set(x + 6 + dx, y + 6 + dy, Palette.creamShade);
  }
  const body = <(int, int)>[
    (0, 3), (1, 3), (1, 4), (2, 4), (2, 5), (3, 4), (3, 5), (4, 3), (4, 4),
    (5, 2), (5, 3), (6, 1), (6, 2), (7, 0), (7, 1), //
  ];
  b.blob(body, Palette.green, outline: Palette.greenDark, x: x + 2, y: y + 3);
  b.set(x + 2, y + 6, PixelBuffer.lightOf(Palette.green));
  b.set(x + 9, y + 3, PixelBuffer.lightOf(Palette.green));
}

/// Sweat drop, 6x8, falling one pixel every two frames.
void drawSweat(PixelBuffer b, int x, int y, int frame) {
  const body = <(int, int)>[
    (1, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2), (0, 3), (1, 3),
    (2, 3), (1, 4), //
  ];
  final drop = frame ~/ 2 == 1 ? 1 : 0;
  b.blob(body, Palette.water, outline: Palette.waterDark, x: x + 1, y: y + 1 + drop);
  b.set(x + 1, y + 2 + drop, Palette.creamLight);
  b.set(x + 3, y + 4 + drop, Palette.waterDark);
}

/// Three rising z's, about 12x14.
void drawZzz(PixelBuffer b, int x, int y) {
  void z(int zx, int zy, int size) {
    b.hline(zx, zy, size, Palette.cream);
    b.hline(zx, zy + size - 1, size, Palette.cream);
    for (var i = 0; i < size; i++) {
      b.set(zx + size - 1 - i, zy + i, Palette.cream);
    }
    b.hline(zx, zy + size, size, Palette.creamDark);
  }

  z(x, y + 10, 3);
  z(x + 3, y + 5, 4);
  z(x + 7, y, 5);
}

/// Yellow pencil held diagonally, 9x9, bobbing one pixel every two frames.
void drawPen(PixelBuffer b, int x, int y, int frame) {
  final bob = frame ~/ 2 == 1 ? -1 : 0;
  const body = <(int, int)>[
    (1, 5), (2, 4), (2, 5), (3, 3), (3, 4), (4, 2), (4, 3), (5, 1), (5, 2),
    (6, 0), (6, 1), //
  ];
  b.blob(body, Palette.amber, outline: Palette.amberDark, x: x + 1, y: y + 1 + bob);
  b.set(x + 7, y + 1 + bob, Palette.pink);
  b.set(x + 1, y + 7 + bob, Palette.ink);
  b.set(x + 3, y + 4 + bob, Palette.amberLight);
  b.set(x + 5, y + 2 + bob, Palette.amberLight);
}
