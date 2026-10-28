import 'palette.dart';
import 'pixel.dart';

/// Small props that float next to a character. Positions are the top-left of
/// the prop's outline in scene pixels; [frame] is tick % 4.

/// Thought cloud, 12x7, bobbing one pixel every two frames.
void drawCloud(Px px, int x, int y, int frame) {
  const body = <(int, int)>[
    (3, 0), (4, 0), (5, 0), (6, 0), //
    (1, 1), (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1), //
    (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (7, 2), (8, 2),
    (9, 2), //
    (0, 3), (1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3), (8, 3),
    (9, 3), //
    (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4), //
  ];
  final bob = frame ~/ 2 == 1 ? -1 : 0;
  px.blob(body, ScenePalette.cream, x: x + 1, y: y + 1 + bob);
  px.fill(x + 1, y + 8 + bob, 1, 1, ScenePalette.outline);
}

/// "..." speech bubble, 12x9 including the tail; shows 1-3 dots by frame.
void drawDots(Px px, int x, int y, int frame) {
  px.roundBox(x, y, 12, 7, ScenePalette.cream);
  final visible = frame % 3 + 1;
  for (var i = 0; i < visible; i++) {
    px.fill(x + 2 + i * 3, y + 3, 2, 1, ScenePalette.outline);
  }
  px.fill(x + 2, y + 6, 1, 1, ScenePalette.cream);
  px.fill(x + 1, y + 7, 1, 1, ScenePalette.outline);
  px.fill(x + 2, y + 7, 1, 1, ScenePalette.cream);
  px.fill(x + 3, y + 7, 1, 1, ScenePalette.outline);
  px.fill(x + 2, y + 8, 1, 1, ScenePalette.outline);
}

/// A 5x6 sheet of paper with two lines.
void drawSheet(Px px, int x, int y) {
  px.box(x, y, 5, 6, ScenePalette.paper);
  px.fill(x + 1, y + 2, 3, 1, ScenePalette.paperLine);
  px.fill(x + 1, y + 4, 2, 1, ScenePalette.paperLine);
}

/// Paper tray on a desk, 10x3.
void drawTray(Px px, int x, int y) {
  px.box(x, y, 10, 3, ScenePalette.steel);
}

/// Sheet flying from (fromX, fromY) to the tray at (toX, toY) in four frames.
void drawFlyingSheet(Px px, int fromX, int fromY, int toX, int toY, int frame) {
  const arc = [0, -2, -2, 0];
  final f = frame % 4;
  final x = fromX + ((toX - fromX) * f / 3).round();
  final y = fromY + ((toY - fromY) * f / 3).round() + arc[f];
  drawSheet(px, x, y);
}

/// Green check mark, 10x8 with outline.
void drawCheck(Px px, int x, int y) {
  const body = <(int, int)>[
    (0, 3), (1, 3), (1, 4), (2, 4), (2, 5), (3, 4), (3, 5), (4, 3), (4, 4),
    (5, 2), (5, 3), (6, 1), (6, 2), (7, 0), (7, 1), //
  ];
  px.blob(body, ScenePalette.green, x: x + 1, y: y + 1);
}

/// Sweat drop, 5x6, falling one pixel every two frames.
void drawSweat(Px px, int x, int y, int frame) {
  const body = <(int, int)>[
    (1, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2), (1, 3), //
  ];
  final drop = frame ~/ 2 == 1 ? 1 : 0;
  px.blob(body, ScenePalette.water, x: x + 1, y: y + 1 + drop);
}

/// Three rising sleep dots (no lettering), about 9x10.
void drawZzz(Px px, int x, int y) {
  px.blob(const [(0, 0)], ScenePalette.cream, x: x + 1, y: y + 8);
  px.blob(const [(0, 0)], ScenePalette.cream, x: x + 3, y: y + 5);
  px.blob(
    const [(0, 0), (1, 0), (0, 1), (1, 1)],
    ScenePalette.cream,
    x: x + 5,
    y: y + 1,
  );
}

/// Yellow pen held diagonally, 7x7, bobbing one pixel every two frames.
void drawPen(Px px, int x, int y, int frame) {
  const body = <(int, int)>[
    (1, 3), (2, 2), (3, 1), (2, 3), (3, 2), (4, 1), (4, 0), //
  ];
  final bob = frame ~/ 2 == 1 ? -1 : 0;
  px.blob(body, ScenePalette.yellow, x: x + 1, y: y + 1 + bob);
  px.fill(x + 1, y + 5 + bob, 1, 1, ScenePalette.outline);
}
