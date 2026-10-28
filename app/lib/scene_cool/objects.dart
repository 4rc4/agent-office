import 'dart:ui';

import 'palette.dart';
import 'pixel.dart';

/// Small props that float next to a character. Positions are the top-left of
/// the prop's outline in scene pixels; [frame] is tick % 4.

/// Thought cloud, 14x9, bobbing one pixel every two frames.
void drawCloud(Px px, int x, int y, int frame) {
  const body = <(int, int)>[
    (4, 0), (5, 0), (6, 0), (7, 0), //
    (2, 1), (3, 1), (4, 1), (5, 1), (6, 1), (7, 1), (8, 1), (9, 1), (10, 1),
    (1, 2), (2, 2), (3, 2), (4, 2), (5, 2), (6, 2), (7, 2), (8, 2), (9, 2),
    (10, 2), (11, 2), (12, 2),
    (0, 3), (1, 3), (2, 3), (3, 3), (4, 3), (5, 3), (6, 3), (7, 3), (8, 3),
    (9, 3), (10, 3), (11, 3), (12, 3), (13, 3),
    (0, 4), (1, 4), (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), (7, 4), (8, 4),
    (9, 4), (10, 4), (11, 4), (12, 4), (13, 4),
    (2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (7, 5), (8, 5), (9, 5), (10, 5),
    (11, 5),
  ];
  final bob = frame ~/ 2 == 1 ? -1 : 0;
  final top = y + 1 + bob;
  px.blob(
    body,
    ScenePalette.paper.base,
    x: x + 1,
    y: top,
    edge: ScenePalette.paper.dark,
  );
  px.hline(x + 3, top + 5, 10, ScenePalette.paper.shade);
  px.hline(x + 5, top, 4, ScenePalette.paper.light);
  px.hline(x + 3, top + 1, 3, ScenePalette.paper.light);
  px.blob(
    const [(0, 0), (1, 0)],
    ScenePalette.paper.base,
    x: x + 3,
    y: top + 8,
    edge: ScenePalette.paper.dark,
  );
  px.blob(
    const [(0, 0)],
    ScenePalette.paper.base,
    x: x + 1,
    y: top + 11,
    edge: ScenePalette.paper.dark,
  );
}

/// "..." speech bubble, 14x8 plus the tail; shows 1-3 dots by frame.
void drawDots(Px px, int x, int y, int frame) {
  px.roundRing(x, y, 14, 8, ScenePalette.paper.dark);
  px.fill(x + 1, y + 1, 12, 6, ScenePalette.paper.base);
  px.hline(x + 1, y + 1, 12, ScenePalette.paper.light);
  px.hline(x + 1, y + 6, 12, ScenePalette.paper.shade);
  final visible = frame % 3 + 1;
  for (var i = 0; i < visible; i++) {
    px.fill(x + 3 + i * 3, y + 3, 2, 2, ScenePalette.ink);
  }
  px.fill(x + 3, y + 7, 1, 1, ScenePalette.paper.base);
  px.dot(x + 2, y + 8, ScenePalette.paper.dark);
  px.dot(x + 3, y + 8, ScenePalette.paper.base);
  px.dot(x + 4, y + 8, ScenePalette.paper.dark);
  px.dot(x + 3, y + 9, ScenePalette.paper.dark);
}

/// A 6x8 sheet of paper with lines and a folded corner.
void drawSheet(Px px, int x, int y) {
  px.ring(x, y, 6, 8, ScenePalette.paper.dark);
  px.fill(x + 1, y + 1, 4, 6, ScenePalette.paper.base);
  px.vline(x + 1, y + 1, 6, ScenePalette.paper.light);
  px.hline(x + 1, y + 6, 4, ScenePalette.paper.shade);
  px.hline(x + 2, y + 2, 3, ScenePalette.paperLine);
  px.hline(x + 2, y + 4, 2, ScenePalette.paperLine);
  px.dot(x + 4, y + 1, ScenePalette.paper.shade);
}

/// Sheet flying from (fromX, fromY) to the tray at (toX, toY) in four frames.
void drawFlyingSheet(Px px, int fromX, int fromY, int toX, int toY, int frame) {
  const arc = [0, -3, -3, 0];
  final f = frame % 4;
  final x = fromX + ((toX - fromX) * f / 3).round();
  final y = fromY + ((toY - fromY) * f / 3).round() + arc[f];
  drawSheet(px, x, y);
}

/// Green check mark, 12x10 with a dark edge and a highlight.
void drawCheck(Px px, int x, int y) {
  const body = <(int, int)>[
    (0, 4), (1, 4), (1, 5), (2, 5), (2, 6), (3, 6), (3, 7), (4, 6), (4, 7), //
    (5, 5), (5, 6), (6, 4), (6, 5), (7, 3), (7, 4), (8, 2), (8, 3), (9, 1),
    (9, 2), (10, 0), (10, 1),
  ];
  px.blob(
    body,
    ScenePalette.green,
    x: x + 1,
    y: y + 1,
    edge: ScenePalette.greenDark,
  );
  px.dot(x + 11, y + 1, Color(0xFFB4F0CC));
  px.dot(x + 1, y + 5, Color(0xFFB4F0CC));
}

/// Sweat drop, 5x7, falling one pixel every two frames.
void drawSweat(Px px, int x, int y, int frame) {
  const body = <(int, int)>[
    (1, 0), (0, 1), (1, 1), (2, 1), (0, 2), (1, 2), (2, 2), (0, 3), (1, 3),
    (2, 3), (1, 4), //
  ];
  final drop = frame ~/ 2 == 1 ? 1 : 0;
  px.blob(
    body,
    ScenePalette.water,
    x: x + 1,
    y: y + 1 + drop,
    edge: ScenePalette.waterDark,
  );
  px.dot(x + 1, y + 2 + drop, Color(0xFFD8F7FA));
  px.dot(x + 3, y + 4 + drop, ScenePalette.waterDark);
}

/// Three rising sleep squares (no lettering), about 11x12.
void drawZzz(Px px, int x, int y) {
  px.blob(
    const [(0, 0)],
    ScenePalette.paper.base,
    x: x + 1,
    y: y + 10,
    edge: ScenePalette.paper.dark,
  );
  px.blob(
    const [(0, 0), (1, 0), (0, 1), (1, 1)],
    ScenePalette.paper.base,
    x: x + 3,
    y: y + 6,
    edge: ScenePalette.paper.dark,
  );
  px.blob(
    const [
      (0, 0),
      (1, 0),
      (2, 0),
      (0, 1),
      (1, 1),
      (2, 1),
      (0, 2),
      (1, 2),
      (2, 2),
    ],
    ScenePalette.paper.base,
    x: x + 6,
    y: y + 1,
    edge: ScenePalette.paper.dark,
  );
  px.dot(x + 6, y + 1, ScenePalette.paper.light);
  px.dot(x + 8, y + 3, ScenePalette.paper.shade);
}

/// Yellow pen held diagonally, 9x9, bobbing one pixel every two frames.
void drawPen(Px px, int x, int y, int frame) {
  const body = <(int, int)>[
    (1, 5), (2, 4), (2, 5), (3, 3), (3, 4), (4, 2), (4, 3), (5, 1), (5, 2), //
    (6, 0), (6, 1), (7, 0),
  ];
  final bob = frame ~/ 2 == 1 ? -1 : 0;
  px.blob(
    body,
    ScenePalette.yellow,
    x: x + 1,
    y: y + 1 + bob,
    edge: ScenePalette.yellowDark,
  );
  px.dot(x + 7, y + 1 + bob, Color(0xFFFBE39A));
  px.dot(x + 1, y + 7 + bob, ScenePalette.ink);
  px.dot(x + 2, y + 6 + bob, ScenePalette.yellowDark);
}
