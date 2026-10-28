import 'dart:math' as math;
import 'dart:ui';

import 'palette.dart';
import 'pixel.dart';
import 'scene_layout.dart';

/// Static furniture of the night studio. Each painter takes scene-pixel
/// rects from [SceneLayout] so the layout file stays the single source of
/// positions. Light comes from the window on the upper left.

int _hash(int x, int y) {
  var h = x * 374761393 + y * 668265263;
  h = (h ^ (h >> 13)) * 1274126177;
  return (h ^ (h >> 16)) & 0x7fffffff;
}

/// Back wall: cool blue-grey, lighter around the window, darker toward the
/// top and the far corner, with a picture rail.
void paintWall(Px px) {
  const w = SceneLayout.width;
  const h = SceneLayout.wallBottom;
  final wall = ScenePalette.wall;
  px.fill(0, 0, w, h, wall.base);

  // Darker ceiling line and far (right) corner.
  px.fill(0, 0, w, 3, wall.shade);
  px.dither(0, 3, w, 5, null, wall.shade);
  px.dither(0, 8, w, 6, null, wall.shade, pattern: Dither.quarter);
  px.dither(380, 0, 50, h, null, wall.shade, pattern: Dither.quarter);
  px.dither(430, 0, 50, h, null, wall.shade);
  px.dither(462, 0, 18, h, null, wall.dark, pattern: Dither.quarter);

  // Ambient occlusion where the wall meets the skirting.
  px.dither(0, h - 8, w, 7, null, wall.shade, pattern: Dither.quarter);
  px.hline(0, h - 1, w, wall.shade);

  // Moonlight spill around the window.
  final win = SceneLayout.window;
  px.dither(
    win.x - 22,
    win.y - 16,
    win.w + 44,
    win.h + 34,
    null,
    wall.light,
    pattern: Dither.quarter,
  );
  px.dither(win.x - 11, win.y - 8, win.w + 22, win.h + 18, null, wall.light);
  px.fill(win.x - 4, win.y - 3, win.w + 8, win.h + 8, wall.light);
  px.dither(
    win.x - 2,
    win.y - 1,
    win.w + 4,
    win.h + 4,
    null,
    ScenePalette.wallGlow,
  );

  // Picture rail.
  px.hline(0, 15, w, wall.light);
  px.hline(0, 16, w, wall.dark);

  // Dado rail with bead-board wainscot below it.
  px.dither(0, 120, w, h - 120, null, wall.shade, pattern: Dither.quarter);
  for (var x = 4; x < w; x += 10) {
    px.vline(x, 121, h - 122, wall.shade);
    px.vline(x + 1, 121, h - 122, wall.light);
  }
  px.hline(0, 118, w, wall.light);
  px.hline(0, 119, w, wall.base);
  px.hline(0, 120, w, wall.dark);
  px.dither(0, 121, w, 2, null, wall.dark, pattern: Dither.quarter);
}

/// Skirting board between wall and floor.
void paintSkirting(Px px) {
  const w = SceneLayout.width;
  const y = SceneLayout.wallBottom;
  final s = ScenePalette.skirting;
  px.fill(0, y, w, SceneLayout.floorTop - y, s.base);
  px.hline(0, y, w, s.light);
  px.hline(0, y + 1, w, s.light);
  px.hline(0, SceneLayout.floorTop - 2, w, s.shade);
  px.hline(0, SceneLayout.floorTop - 1, w, s.dark);
}

/// Dark wooden floor: planks with grain, board gaps and staggered joints,
/// then the moonlight shaft from the window and a soft vignette.
void paintFloor(Px px) {
  const w = SceneLayout.width;
  const top = SceneLayout.floorTop;
  const bottom = SceneLayout.height;
  const plank = 12;
  final wood = ScenePalette.wood;

  for (var k = 0; top + k * plank < bottom; k++) {
    final y0 = top + k * plank;
    final h = math.min(plank, bottom - y0);
    px.fill(0, y0, w, h, wood.base);
    px.hline(0, y0, w, wood.light);
    if (h >= 11) px.hline(0, y0 + 10, w, wood.shade);
    if (h >= 12) px.hline(0, y0 + 11, w, wood.dark);
    for (var x = 0; x < w; x += 2) {
      final r = _hash(x, k);
      if (r % 9 == 0 && h >= 10) {
        final gy = y0 + 2 + r % 7;
        final len = 3 + (r >> 4) % 6;
        px.hline(x, gy, len, ScenePalette.woodGrain);
      }
      if (r % 23 == 0 && h >= 10) {
        px.hline(x, y0 + 1 + (r >> 3) % 8, 2 + (r >> 5) % 3, wood.light);
      }
    }
    final offset = (k.isEven ? 18 : 74) + (k * 29) % 40;
    for (var x = offset; x < w; x += 112) {
      px.vline(x, y0, math.min(11, h), wood.dark);
      px.vline(x + 1, y0 + 1, math.min(9, h - 2), ScenePalette.woodLit);
    }
  }

  // Ambient occlusion along the skirting.
  px.hline(0, top, w, ScenePalette.shadowSoft);
  px.dither(0, top + 1, w, 3, null, ScenePalette.shadowSoft);
  px.dither(
    0,
    top + 4,
    w,
    3,
    null,
    ScenePalette.shadowSoft,
    pattern: Dither.quarter,
  );

  // Moonlight shaft: a skewed trapezoid below the window.
  for (var y = top; y < bottom; y++) {
    final t = y - top;
    final left = 30 + (t * 0.42).round();
    final right = 128 + (t * 0.62).round();
    px.hline(left + 3, y, right - left - 6, ScenePalette.moonlight);
    for (var x = left; x < left + 3; x++) {
      if ((x + y).isEven) px.dot(x, y, ScenePalette.moonlight);
    }
    for (var x = right - 3; x < right; x++) {
      if ((x + y).isEven) px.dot(x, y, ScenePalette.moonlight);
    }
    for (var x = left - 6; x < left; x++) {
      if (x.isEven && y.isEven) px.dot(x, y, ScenePalette.moonlightSoft);
    }
    for (var x = right; x < right + 6; x++) {
      if (x.isEven && y.isEven) px.dot(x, y, ScenePalette.moonlightSoft);
    }
    // Shadow of the window's vertical mullion.
    final mid = (left + right) ~/ 2;
    px.hline(mid - 1, y, 3, ScenePalette.shadowSoft);
  }
  // Shadow of the horizontal mullion.
  for (var y = 198; y < 201; y++) {
    final t = y - top;
    final left = 30 + (t * 0.42).round();
    final right = 128 + (t * 0.62).round();
    px.hline(left, y, right - left, ScenePalette.shadowSoft);
  }

  // Vignette toward the far corner.
  px.dither(
    380,
    top,
    100,
    bottom - top,
    null,
    ScenePalette.shadowSoft,
    pattern: Dither.quarter,
  );
  px.dither(440, top, 40, bottom - top, null, ScenePalette.shadowSoft);
  px.dither(
    0,
    bottom - 14,
    w,
    14,
    null,
    ScenePalette.shadowSoft,
    pattern: Dither.quarter,
  );
}

/// Patterned rug under the main desk.
void paintRug(Px px, IRect r) {
  final rug = ScenePalette.rug;
  px.hline(r.x + 1, r.bottom, r.w - 2, ScenePalette.shadow);
  px.shadeRect(r.x, r.y, r.w, r.h, rug, outline: true, rounded: true);
  px.fill(r.x + 2, r.y + 2, r.w - 4, r.h - 4, rug.shade);
  px.fill(r.x + 4, r.y + 4, r.w - 4 - 1, r.h - 4 - 1, rug.base);
  px.hline(r.x + 4, r.y + 4, r.w - 5, rug.light);
  px.vline(r.x + 4, r.y + 4, r.h - 5, rug.light);
  px.ring(r.x + 7, r.y + 7, r.w - 14, r.h - 14, rug.shade);
  // Diamond lattice.
  for (var y = r.y + 12; y < r.bottom - 10; y += 10) {
    for (var x = r.x + 14; x < r.right - 12; x += 16) {
      final sx = x + (((y - r.y) ~/ 10).isOdd ? 8 : 0);
      px.dot(sx, y - 2, ScenePalette.rugPattern);
      px.hline(sx - 1, y - 1, 3, ScenePalette.rugPattern);
      px.hline(sx - 2, y, 5, ScenePalette.rugPattern);
      px.hline(sx - 1, y + 1, 3, rug.light);
      px.dot(sx, y + 2, rug.light);
      px.dot(sx + 8, y + 5, rug.light);
    }
  }
  // Fringe on the short sides.
  for (var y = r.y + 3; y < r.bottom - 3; y += 2) {
    px.dot(r.x - 1, y, rug.light);
    px.dot(r.right, y, rug.shade);
  }
}

/// Large window with a night sky, moon, city lights and a sill.
void paintWindow(Px px, IRect r, IRect sill) {
  final frame = ScenePalette.frame;
  // Shadow cast on the wall below the sill and the right of the frame.
  px.dither(r.right, r.y + 3, 3, r.h, null, ScenePalette.shadowSoft);
  px.dither(
    sill.x + 2,
    sill.bottom,
    sill.w - 2,
    3,
    null,
    ScenePalette.shadowSoft,
  );

  // Frame.
  px.shadeRect(r.x, r.y, r.w, r.h, frame, outline: true, bevel: 1);
  px.fill(r.x + 1, r.y + 1, r.w - 2, 1, frame.light);
  final gx = r.x + 4;
  final gy = r.y + 4;
  final gw = r.w - 8;
  final gh = r.h - 8;
  px.ring(gx - 1, gy - 1, gw + 2, gh + 2, frame.dark);

  // Sky gradient.
  final third = gh ~/ 3;
  px.fill(gx, gy, gw, gh, ScenePalette.skyMid);
  px.fill(gx, gy, gw, third, ScenePalette.skyTop);
  px.dither(gx, gy + third, gw, 5, null, ScenePalette.skyTop);
  px.fill(gx, gy + gh - third, gw, third, ScenePalette.skyLow);
  px.dither(gx, gy + gh - third - 5, gw, 5, null, ScenePalette.skyLow);

  // Stars.
  const stars = <(int, int)>[
    (6, 5), (14, 11), (22, 3), (31, 8), (40, 14), (48, 4), (57, 10), //
    (66, 6), (75, 13), (84, 3), (93, 9), (100, 16), (11, 20), (36, 22),
    (60, 19), (89, 23), (20, 28), (70, 30), (45, 33), (96, 34),
  ];
  for (var i = 0; i < stars.length; i++) {
    final (sx, sy) = stars[i];
    if (sx >= gw - 1 || sy >= gh) continue;
    px.dot(
      gx + sx,
      gy + sy,
      i % 3 == 0 ? ScenePalette.star : ScenePalette.starDim,
    );
  }

  // Moon with a halo.
  final mx = gx + gw - 24;
  final my = gy + 18;
  for (final (dx, dy) in Px.discPixels(11)) {
    if (dx * dx + dy * dy > 64 && (dx + dy).isEven) {
      px.dot(mx + dx, my + dy, ScenePalette.moonHalo);
    }
  }
  px.discFill(mx, my, 7, ScenePalette.moon);
  for (final (dx, dy) in Px.discPixels(7)) {
    if (dx + dy > 5) px.dot(mx + dx, my + dy, ScenePalette.moonShade);
  }
  px.dot(mx - 2, my - 1, ScenePalette.moonShade);
  px.fill(mx + 1, my + 2, 2, 1, ScenePalette.moonShade);
  px.dot(mx - 3, my + 3, ScenePalette.moonShade);

  // City skyline: a far layer and a near layer with lit windows.
  final ground = gy + gh;
  const far = <(int, int, int)>[
    (0, 10, 22), (9, 14, 18), (24, 11, 14), (36, 7, 26), (46, 9, 20), //
    (56, 12, 16), (64, 8, 24), (74, 13, 17), (84, 10, 21), (96, 8, 12),
  ];
  for (final (bx, bw, bh) in far) {
    px.fill(gx + bx, ground - bh, bw, bh, ScenePalette.buildingLit);
  }
  const near = <(int, int, int)>[
    (2, 9, 16), (13, 7, 12), (22, 12, 20), (37, 8, 9), (47, 10, 15), //
    (60, 6, 11), (68, 11, 18), (82, 8, 13), (92, 12, 10),
  ];
  for (final (bx, bw, bh) in near) {
    final x0 = gx + bx;
    final y0 = ground - bh;
    px.fill(x0, y0, bw, bh, ScenePalette.building);
    px.vline(x0, y0, bh, ScenePalette.buildingLit);
    for (var wy = y0 + 2; wy < ground - 1; wy += 3) {
      for (var wx = x0 + 1; wx < x0 + bw - 1; wx += 2) {
        final h = _hash(wx, wy);
        if (h % 5 < 2) {
          px.dot(
            wx,
            wy,
            h % 3 == 0 ? ScenePalette.cityTeal : ScenePalette.cityWarm,
          );
        }
      }
    }
  }
  px.vline(gx + 27, ground - 24, 4, ScenePalette.buildingLit);
  px.dot(gx + 27, ground - 25, ScenePalette.red);

  // Mullions.
  final mxBar = gx + gw ~/ 2 - 1;
  final myBar = gy + (gh * 0.45).round();
  px.fill(mxBar, gy, 3, gh, frame.base);
  px.vline(mxBar, gy, gh, frame.light);
  px.vline(mxBar + 2, gy, gh, frame.shade);
  px.fill(gx, myBar, gw, 3, frame.base);
  px.hline(gx, myBar, gw, frame.light);
  px.hline(gx, myBar + 2, gw, frame.shade);

  // Glass highlights in the upper-left pane.
  for (var i = 0; i < 10; i++) {
    px.dot(gx + 4 + i, gy + 14 - i, ScenePalette.glassHighlight);
    px.dot(gx + 10 + i, gy + 16 - i, ScenePalette.glassHighlight);
  }
  for (var i = 0; i < 6; i++) {
    px.dot(gx + 6 + i, gy + 20 - i, ScenePalette.glassHighlight);
  }

  // Sill.
  px.shadeRect(sill.x, sill.y, sill.w, sill.h, frame, outline: true);
  px.hline(sill.x + 1, sill.y + 1, sill.w - 2, frame.light);
}

/// Wire of the string lights along the top of the wall; bulbs are drawn by
/// [paintBulbs] every frame.
int bulbWireY(int x) {
  final t = (x % 60) / 60;
  return 6 + (5 * math.sin(math.pi * t)).round();
}

void paintLightWire(Px px) {
  for (var x = 0; x < SceneLayout.width; x++) {
    px.dot(x, bulbWireY(x), ScenePalette.ink);
  }
  for (var x = 0; x <= SceneLayout.width; x += 60) {
    px.fill(x - 1, 5, 2, 3, ScenePalette.steel.shade);
  }
  for (var x = 6; x < SceneLayout.width; x += 12) {
    final y = bulbWireY(x);
    px.dither(
      x - 2,
      y,
      6,
      7,
      null,
      ScenePalette.bulbGlow,
      pattern: Dither.quarter,
    );
  }
}

/// Bulbs of the string lights; one in four dims by [frame].
void paintBulbs(Px px, int frame) {
  var i = 0;
  for (var x = 6; x < SceneLayout.width; x += 12) {
    final y = bulbWireY(x);
    final warm = i.isEven;
    final dim = (i + frame) % 4 == 0;
    final color = dim
        ? (warm ? ScenePalette.lampShade : ScenePalette.starDim)
        : (warm ? ScenePalette.bulbWarm : ScenePalette.bulbCool);
    px.fill(x, y + 1, 2, 1, ScenePalette.ink);
    px.fill(x, y + 2, 2, 2, color);
    px.dot(x - 1, y + 3, color);
    px.dot(x + 2, y + 3, color);
    px.fill(x, y + 4, 2, 1, color);
    i++;
  }
}

/// Whiteboard frame with a marker tray; notes are drawn by the painter.
void paintWhiteboard(Px px, IRect r) {
  final frame = ScenePalette.frame;
  final board = ScenePalette.board;
  px.dither(r.x + 3, r.bottom, r.w, 3, null, ScenePalette.shadowSoft);
  px.dither(r.right, r.y + 3, 3, r.h, null, ScenePalette.shadowSoft);
  px.shadeRect(r.x, r.y, r.w, r.h, frame, outline: true);
  final ix = r.x + 4;
  final iy = r.y + 4;
  final iw = r.w - 8;
  final ih = r.h - 8;
  px.fill(ix, iy, iw, ih, board.base);
  px.hline(ix, iy, iw, board.shade);
  px.vline(ix, iy, ih, board.shade);
  px.ring(ix - 1, iy - 1, iw + 2, ih + 2, frame.dark);
  px.dither(
    ix + 1,
    iy + 1,
    iw ~/ 2,
    ih ~/ 2,
    null,
    board.light,
    pattern: Dither.quarter,
  );
  px.dither(
    ix + iw ~/ 2,
    iy + ih ~/ 2,
    iw ~/ 2 - 1,
    ih ~/ 2 - 1,
    null,
    board.shade,
    pattern: Dither.quarter,
  );

  // Tray with markers and an eraser.
  final tx = r.x + 12;
  final ty = r.bottom - 2;
  final tw = r.w - 24;
  px.shadeRect(tx, ty, tw, 4, ScenePalette.steel, outline: true);
  px.fill(tx + 6, ty - 2, 8, 2, ScenePalette.teal.base);
  px.fill(tx + 6, ty - 2, 2, 2, ScenePalette.teal.dark);
  px.hline(tx + 8, ty - 2, 6, ScenePalette.teal.light);
  px.fill(tx + 17, ty - 2, 8, 2, ScenePalette.red);
  px.fill(tx + 17, ty - 2, 2, 2, ScenePalette.redDark);
  px.shadeRect(tx + tw - 14, ty - 3, 9, 3, ScenePalette.slate, outline: false);
}

/// One sticky note with a bevel, a curled corner, faint lines and a pin
/// when it is a root task.
void paintStickyNote(
  Px px,
  int x,
  int y,
  int w,
  int h,
  Tones t, {
  required bool pinned,
}) {
  px.dither(x + 1, y + 1, w, h, null, ScenePalette.shadowSoft);
  px.fill(x, y, w, h, t.base);
  px.hline(x, y, w, t.light);
  px.vline(x, y, h, t.light);
  px.hline(x, y + h - 1, w, t.shade);
  px.vline(x + w - 1, y, h, t.shade);
  px.fill(x + w - 3, y + h - 3, 3, 3, t.shade);
  px.fill(x + w - 3, y + h - 3, 2, 2, t.light);
  px.dot(x + w - 1, y + h - 1, t.dark);
  for (var ly = y + 5; ly < y + h - 4; ly += 3) {
    final len = w - 8 - (ly ~/ 3) % 4;
    px.hline(x + 3, ly, len, t.shade);
  }
  if (pinned) {
    px.fill(x + w ~/ 2 - 1, y + 1, 3, 2, ScenePalette.pin);
    px.dot(x + w ~/ 2 - 1, y + 1, Color(0xFFF4A0A0));
    px.dot(x + w ~/ 2, y + 3, ScenePalette.ink);
  }
}

/// Round wall clock at a calm ten past ten.
void paintClock(Px px, IRect r) {
  final cx = r.centerX;
  final cy = r.centerY;
  final rad = r.w ~/ 2 - 1;
  px.shadowEllipse(cx + 2, cy + 2, rad, rad, ScenePalette.shadowSoft);
  px.shadeDisc(cx, cy, rad, ScenePalette.steel);
  px.discFill(cx, cy, rad - 2, ScenePalette.board.base);
  for (final (dx, dy) in Px.discPixels(rad - 2)) {
    if (dx + dy < -(rad - 3)) {
      px.dot(cx + dx, cy + dy, ScenePalette.board.light);
    }
    if (dx + dy > rad - 3) px.dot(cx + dx, cy + dy, ScenePalette.board.shade);
  }
  final t = rad - 3;
  px.dot(cx, cy - t, ScenePalette.ink);
  px.dot(cx, cy + t, ScenePalette.ink);
  px.dot(cx - t, cy, ScenePalette.ink);
  px.dot(cx + t, cy, ScenePalette.ink);
  for (final (dx, dy) in const [
    (4, -6),
    (6, -4),
    (6, 4),
    (4, 6),
    (-4, 6),
    (-6, 4),
    (-6, -4),
    (-4, -6),
  ]) {
    px.dot(cx + dx, cy + dy, ScenePalette.greyDark);
  }
  // Hour hand toward 10, minute hand toward 2.
  for (var i = 0; i < 4; i++) {
    px.dot(cx - i, cy - (i * 0.6).round(), ScenePalette.ink);
    px.dot(cx - i, cy - (i * 0.6).round() - 1, ScenePalette.ink);
  }
  for (var i = 0; i < 6; i++) {
    px.dot(cx + i, cy - (i * 0.6).round(), ScenePalette.ink);
  }
  px.vline(cx, cy - 2, 2, ScenePalette.ink);
  px.dot(cx, cy, ScenePalette.red);
  px.dot(cx + 1, cy + 3, ScenePalette.red);
  px.dot(cx + 1, cy + 4, ScenePalette.red);
}

/// Three usage meters. [levels] are 0..1 per bar and fill in the matching
/// accent colour from the bottom.
void paintGauges(Px px, IRect r, List<Color> accents, List<double> levels) {
  for (var i = 0; i < accents.length; i++) {
    final x = r.x + i * (SceneLayout.gaugeWidth + SceneLayout.gaugeGap);
    final w = SceneLayout.gaugeWidth;
    px.dither(x + 2, r.bottom, w, 2, null, ScenePalette.shadowSoft);
    px.shadeRect(x, r.y, w, r.h, ScenePalette.slate, outline: true);
    px.fill(x + 2, r.y + 2, w - 4, 3, accents[i]);
    px.hline(x + 2, r.y + 2, w - 4, ScenePalette.glassHighlight);
    px.hline(x + 2, r.y + 5, w - 4, ScenePalette.slate.dark);
    final bx = x + 3;
    final by = r.y + 7;
    final bw = w - 6;
    final bh = r.h - 10;
    px.fill(bx, by, bw, bh, ScenePalette.screenOff);
    for (var ty = by + 1; ty < by + bh; ty += 3) {
      px.dot(bx + bw - 1, ty, ScenePalette.slate.light);
    }
    final level = i < levels.length ? levels[i].clamp(0.0, 1.0) : 0.0;
    final fh = (bh * level).round();
    if (fh > 0) {
      px.fill(bx, by + bh - fh, bw - 1, fh, accents[i]);
      px.hline(bx, by + bh - fh, bw - 1, ScenePalette.glassHighlight);
    }
    px.dither(
      bx,
      by,
      2,
      bh,
      null,
      ScenePalette.glassHighlight,
      pattern: Dither.quarter,
    );
    px.dot(x + w - 4, r.bottom - 3, accents[i]);
  }
}

/// Two framed posters: a mountain night and abstract circles.
void paintPosters(Px px, IRect tall, IRect wide) {
  void frameAndShadow(IRect r) {
    px.dither(r.x + 2, r.bottom, r.w, 2, null, ScenePalette.shadowSoft);
    px.dither(r.right, r.y + 2, 2, r.h, null, ScenePalette.shadowSoft);
    px.ring(r.x, r.y, r.w, r.h, ScenePalette.frame.dark);
    px.hline(r.x + 1, r.y + 1, r.w - 2, ScenePalette.frame.light);
    px.vline(r.x + 1, r.y + 1, r.h - 2, ScenePalette.frame.light);
    px.hline(r.x + 1, r.bottom - 2, r.w - 2, ScenePalette.frame.shade);
    px.vline(r.right - 2, r.y + 1, r.h - 2, ScenePalette.frame.shade);
  }

  // Tall: moon over teal mountains.
  frameAndShadow(tall);
  var ix = tall.x + 2;
  var iy = tall.y + 2;
  var iw = tall.w - 4;
  var ih = tall.h - 4;
  px.fill(ix, iy, iw, ih, ScenePalette.skyMid);
  px.fill(ix, iy, iw, ih ~/ 2, ScenePalette.skyTop);
  px.discFill(ix + iw - 5, iy + 6, 3, ScenePalette.moon);
  for (var i = 0; i < iw; i++) {
    final peak = (i - 5).abs();
    final h2 = math.max(3, 10 - peak);
    px.vline(ix + i, iy + ih - h2, h2, ScenePalette.teal.dark);
    final peak2 = (i - 12).abs();
    final h3 = math.max(2, 8 - peak2);
    px.vline(ix + i, iy + ih - h3, h3, ScenePalette.teal.base);
  }
  px.fill(ix, iy + ih - 2, iw, 2, ScenePalette.teal.light);
  px.dot(ix + 3, iy + 3, ScenePalette.star);
  px.dot(ix + 8, iy + 5, ScenePalette.starDim);

  // Wide: three circles and lines.
  frameAndShadow(wide);
  ix = wide.x + 2;
  iy = wide.y + 2;
  iw = wide.w - 4;
  ih = wide.h - 4;
  px.fill(ix, iy, iw, ih, ScenePalette.slate.dark);
  px.discFill(ix + 8, iy + 9, 5, ScenePalette.teal.base);
  px.discFill(ix + 7, iy + 8, 3, ScenePalette.teal.light);
  px.discFill(ix + 16, iy + 15, 6, ScenePalette.slate.base);
  px.discFill(ix + 15, iy + 14, 3, ScenePalette.slate.light);
  px.discFill(ix + 7, iy + 23, 4, ScenePalette.frame.base);
  px.discFill(ix + 6, iy + 22, 2, ScenePalette.frame.light);
  for (var y = iy + 3; y < iy + ih - 2; y += 4) {
    px.hline(ix + iw - 6, y, 4, ScenePalette.slate.light);
  }
}

/// Small wall shelf with books.
void paintShelf(Px px, IRect r) {
  px.dither(r.x + 2, r.bottom, r.w - 2, 3, null, ScenePalette.shadowSoft);
  px.shadeRect(r.x, r.y, r.w, r.h, ScenePalette.deskTop, outline: true);
  px.fill(r.x + 4, r.bottom, 2, 3, ScenePalette.steel.shade);
  px.fill(r.right - 6, r.bottom, 2, 3, ScenePalette.steel.shade);
  final books = <(int, int, Tones)>[
    (5, 12, ScenePalette.teal),
    (4, 10, ScenePalette.slate),
    (6, 13, ScenePalette.steel),
    (4, 9, ScenePalette.rug),
    (5, 11, ScenePalette.cushion),
  ];
  var x = r.x + 4;
  for (final (bw, bh, t) in books) {
    px.shadeRect(x, r.y - bh, bw, bh, t, outline: true);
    px.hline(x + 1, r.y - bh + 3, bw - 2, t.light);
    x += bw + 1;
  }
  // A leaning book at the end.
  px.fill(x + 1, r.y - 8, 2, 8, ScenePalette.red);
  px.vline(x + 1, r.y - 8, 8, Color(0xFFF08A8A));
  px.fill(x + 3, r.y - 6, 2, 6, ScenePalette.redDark);
}

/// Door in the back wall with a frame, a glass pane and panels, plus a mat.
void paintDoor(Px px, IRect r, IRect mat) {
  final wood = ScenePalette.doorWood;
  px.dither(r.right, r.y + 2, 3, r.h - 2, null, ScenePalette.shadowSoft);
  // Frame.
  px.fill(r.x - 3, r.y - 3, r.w + 6, r.h + 3, wood.light);
  px.hline(r.x - 3, r.y - 3, r.w + 6, ScenePalette.frame.base);
  px.vline(r.x - 3, r.y - 3, r.h + 3, ScenePalette.frame.base);
  px.vline(r.right + 2, r.y - 2, r.h + 2, wood.dark);
  px.ring(r.x - 1, r.y - 1, r.w + 2, r.h + 1, wood.dark);
  // Leaf.
  px.shadeRect(r.x, r.y, r.w, r.h, wood, outline: false, bevel: 1);
  px.vline(r.x, r.y, r.h, wood.light);
  // Glass pane with reflection.
  final gx = r.x + 5;
  final gy = r.y + 6;
  final gw = r.w - 10;
  final gh = 26;
  px.ring(gx - 1, gy - 1, gw + 2, gh + 2, wood.dark);
  px.fill(gx, gy, gw, gh, ScenePalette.screenOff);
  px.fill(gx, gy + gh - 6, gw, 6, ScenePalette.screenOffReflect);
  for (var i = 0; i < 8; i++) {
    px.dot(gx + 3 + i, gy + 12 - i, ScenePalette.glassHighlight);
    px.dot(gx + 4 + i, gy + 12 - i, ScenePalette.glassHighlight);
    px.dot(gx + 9 + i, gy + 16 - i, ScenePalette.glassHighlight);
  }
  px.vline(gx + gw ~/ 2, gy, gh, wood.shade);
  // Two recessed panels.
  for (final py in [r.y + 40, r.y + 68]) {
    px.ring(gx - 1, py - 1, gw + 2, 24, wood.dark);
    px.fill(gx, py, gw, 22, wood.shade);
    px.hline(gx, py, gw, wood.dark);
    px.vline(gx, py, 22, wood.dark);
    px.hline(gx, py + 21, gw, wood.light);
    px.vline(gx + gw - 1, py, 22, wood.light);
    px.fill(gx + 2, py + 2, gw - 4, 18, wood.base);
  }
  // Handle.
  px.fill(r.right - 7, r.y + 50, 4, 2, ScenePalette.steel.light);
  px.fill(r.right - 7, r.y + 52, 4, 1, ScenePalette.steel.shade);
  px.dot(r.right - 5, r.y + 51, ScenePalette.steel.dark);
  // Mat.
  px.shadeRect(
    mat.x,
    mat.y,
    mat.w,
    mat.h,
    ScenePalette.cushion,
    outline: true,
    rounded: true,
  );
  for (var y = mat.y + 2; y < mat.bottom - 2; y += 2) {
    for (var x = mat.x + 2 + (y % 4 == 0 ? 0 : 1); x < mat.right - 2; x += 2) {
      px.dot(x, y, ScenePalette.cushion.light);
    }
  }
  px.hline(mat.x + 2, mat.y + 1, mat.w - 4, ScenePalette.teal.shade);
}

/// Filing cabinet with three drawers, handles and a small plant on top.
void paintCabinet(Px px, IRect r) {
  final steel = ScenePalette.steel;
  px.shadowEllipse(
    r.centerX + 2,
    r.bottom + 1,
    r.w ~/ 2 + 3,
    3,
    ScenePalette.shadow,
  );
  px.dither(r.right, r.y + 4, 3, r.h - 4, null, ScenePalette.shadowSoft);
  px.shadeRect(r.x, r.y, r.w, r.h, steel, outline: true, bevel: 1);
  px.fill(r.x + 1, r.y + 1, r.w - 2, 2, steel.light);
  px.vline(r.right - 2, r.y + 1, r.h - 2, steel.shade);
  px.vline(r.right - 3, r.y + 3, r.h - 4, steel.shade);
  final drawerH = (r.h - 5) ~/ 3;
  for (var i = 0; i < 3; i++) {
    final y = r.y + 4 + i * drawerH;
    px.hline(r.x + 2, y, r.w - 4, steel.dark);
    px.hline(r.x + 2, y + 1, r.w - 4, steel.light);
    px.hline(r.x + 2, y + drawerH - 1, r.w - 4, steel.shade);
    final hy = y + drawerH ~/ 2;
    px.fill(r.x + r.w ~/ 2 - 4, hy - 1, 8, 3, steel.dark);
    px.hline(r.x + r.w ~/ 2 - 3, hy - 1, 6, steel.light);
    px.fill(r.x + 4, y + 3, 6, 3, ScenePalette.board.base);
    px.hline(r.x + 5, y + 4, 4, ScenePalette.paperLine);
  }
  px.hline(r.x + 2, r.bottom - 2, r.w - 4, steel.dark);
  // Plant on top.
  paintSmallPlant(px, r.x + r.w - 14, r.y - 12);
}

/// Tiny potted plant, 12 wide, pot bottom at y + 12.
void paintSmallPlant(Px px, int x, int y) {
  px.shadeRect(x + 3, y + 7, 7, 5, ScenePalette.pot, outline: true);
  px.hline(x + 3, y + 7, 7, ScenePalette.pot.light);
  const back = <(int, int)>[
    (4, 1),
    (5, 1),
    (3, 2),
    (4, 2),
    (5, 2),
    (6, 2),
    (3, 3),
    (4, 3),
    (5, 3),
    (6, 3),
  ];
  const front = <(int, int)>[
    (2, 3),
    (3, 4),
    (4, 4),
    (6, 4),
    (7, 3),
    (8, 4),
    (5, 0),
  ];
  px.blob(
    back,
    ScenePalette.leaf.shade,
    x: x + 1,
    y: y,
    edge: ScenePalette.leaf.dark,
  );
  px.blob(
    front,
    ScenePalette.leaf.base,
    x: x + 1,
    y: y,
    edge: ScenePalette.leaf.dark,
  );
  px.dot(x + 5, y + 2, ScenePalette.leaf.light);
  px.dot(x + 4, y + 4, ScenePalette.leaf.light);
}

/// Coffee corner: counter with cupboards, a machine, a mug shelf and the
/// warm lamp with its glow. Steam is drawn by [paintSteam] every frame.
void paintCoffeeCorner(
  Px px,
  IRect counter,
  IRect machine,
  IRect lamp,
  IRect shelf,
) {
  // Warm glow on the wall behind the lamp.
  final lx = lamp.centerX;
  final ly = lamp.y + 8;
  for (final (dx, dy) in Px.discPixels(30)) {
    final d2 = dx * dx + dy * dy;
    final sx = lx + dx;
    final sy = ly + dy;
    if (sy >= counter.y) continue;
    if (d2 <= 14 * 14) {
      px.dot(sx, sy, ScenePalette.lampGlow);
    } else if (d2 <= 22 * 22 && (sx + sy).isEven) {
      px.dot(sx, sy, ScenePalette.lampGlow);
    } else if (sx.isEven && sy.isEven) {
      px.dot(sx, sy, ScenePalette.lampGlowSoft);
    }
  }

  // Mug shelf.
  px.dither(
    shelf.x + 2,
    shelf.bottom,
    shelf.w - 2,
    3,
    null,
    ScenePalette.shadowSoft,
  );
  px.shadeRect(
    shelf.x,
    shelf.y,
    shelf.w,
    shelf.h,
    ScenePalette.deskTop,
    outline: true,
  );
  px.fill(shelf.x + 3, shelf.bottom, 2, 3, ScenePalette.steel.shade);
  px.fill(shelf.right - 5, shelf.bottom, 2, 3, ScenePalette.steel.shade);
  paintMug(px, shelf.x + 4, shelf.y - 7, ScenePalette.mug);
  paintMug(px, shelf.x + 14, shelf.y - 7, ScenePalette.teal);
  paintMug(px, shelf.x + 24, shelf.y - 7, ScenePalette.cushion);

  // Counter: floor shadow, top band, cupboard doors, toe kick.
  px.shadowEllipse(
    counter.centerX,
    counter.bottom + 1,
    counter.w ~/ 2 + 2,
    3,
    ScenePalette.shadow,
  );
  final top = ScenePalette.deskTop;
  final front = ScenePalette.deskFront;
  px.fill(counter.x, counter.y + 7, counter.w, counter.h - 7, front.base);
  px.ring(counter.x, counter.y + 7, counter.w, counter.h - 7, front.dark);
  px.vline(counter.x + 1, counter.y + 8, counter.h - 9, front.light);
  final doorY = counter.y + 11;
  final doorH = counter.h - 17;
  final doorW = counter.w ~/ 2 - 5;
  for (final dx in [counter.x + 4, counter.x + counter.w ~/ 2 + 1]) {
    px.ring(dx, doorY, doorW, doorH, front.dark);
    px.fill(dx + 1, doorY + 1, doorW - 2, doorH - 2, front.shade);
    px.hline(dx + 1, doorY + 1, doorW - 2, front.dark);
    px.vline(dx + 1, doorY + 1, doorH - 2, front.dark);
    px.hline(dx + 1, doorY + doorH - 2, doorW - 2, front.light);
    px.vline(dx + doorW - 2, doorY + 1, doorH - 2, front.light);
    px.fill(dx + 3, doorY + 3, doorW - 6, doorH - 6, front.base);
  }
  px.fill(
    counter.x + counter.w ~/ 2 - 5,
    doorY + doorH ~/ 2 - 1,
    2,
    4,
    ScenePalette.steel.light,
  );
  px.fill(
    counter.x + counter.w ~/ 2 + 3,
    doorY + doorH ~/ 2 - 1,
    2,
    4,
    ScenePalette.steel.light,
  );
  px.fill(counter.x + 1, counter.bottom - 4, counter.w - 2, 3, front.dark);
  px.shadeRect(counter.x - 1, counter.y, counter.w + 2, 8, top, outline: true);
  px.hline(counter.x, counter.y + 1, counter.w, top.light);
  px.hline(counter.x + 4, counter.y + 4, 30, top.shade);
  px.hline(counter.x + 50, counter.y + 5, 20, top.shade);

  // Machine.
  final slate = ScenePalette.slate;
  px.shadeRect(
    machine.x,
    machine.y,
    machine.w,
    machine.h,
    slate,
    outline: true,
    rounded: true,
  );
  px.fill(
    machine.x + 1,
    machine.y + 1,
    machine.w - 2,
    3,
    ScenePalette.steel.light,
  );
  px.hline(
    machine.x + 1,
    machine.y + 4,
    machine.w - 2,
    ScenePalette.steel.shade,
  );
  px.fill(
    machine.x + 4,
    machine.y + 8,
    machine.w - 8,
    6,
    ScenePalette.screenOff,
  );
  px.hline(
    machine.x + 5,
    machine.y + 9,
    machine.w - 10,
    ScenePalette.screenOffReflect,
  );
  px.fill(machine.x + 6, machine.y + 10, 5, 2, ScenePalette.led);
  px.fill(machine.x + machine.w - 9, machine.y + 10, 3, 2, ScenePalette.red);
  px.fill(machine.x + 4, machine.y + 16, machine.w - 8, 2, slate.dark);
  px.fill(
    machine.x + machine.w ~/ 2 - 2,
    machine.y + 18,
    4,
    4,
    ScenePalette.steel.shade,
  );
  px.fill(
    machine.x + machine.w ~/ 2 - 1,
    machine.y + 22,
    2,
    2,
    ScenePalette.ink,
  );
  // Cup under the spout and the drip tray.
  paintMug(
    px,
    machine.x + machine.w ~/ 2 - 3,
    machine.y + machine.h - 9,
    ScenePalette.mug,
  );
  px.shadeRect(
    machine.x + 4,
    machine.y + machine.h - 3,
    machine.w - 8,
    3,
    ScenePalette.steel,
    outline: true,
  );
  px.fill(machine.x + 6, machine.y + 28, machine.w - 12, 1, slate.light);

  // Lamp: base, stem, shade, bulb.
  px.shadeRect(
    lamp.x + 2,
    lamp.bottom - 3,
    lamp.w - 4,
    3,
    ScenePalette.steel,
    outline: true,
  );
  px.fill(lamp.centerX - 1, lamp.y + 10, 2, lamp.h - 13, ScenePalette.lampStem);
  px.vline(
    lamp.centerX - 1,
    lamp.y + 10,
    lamp.h - 13,
    ScenePalette.steel.shade,
  );
  for (var i = 0; i < 11; i++) {
    final half = 3 + (i * 0.6).round();
    px.hline(lamp.centerX - half, lamp.y + i, half * 2, ScenePalette.lampShade);
    px.hline(
      lamp.centerX + 1,
      lamp.y + i,
      half - 1,
      ScenePalette.lampShadeShade,
    );
    px.dot(lamp.centerX - half - 1, lamp.y + i, ScenePalette.orangeDark);
    px.dot(lamp.centerX + half, lamp.y + i, ScenePalette.orangeDark);
  }
  px.hline(lamp.centerX - 10, lamp.y + 11, 20, ScenePalette.orangeDark);
  px.hline(lamp.centerX - 4, lamp.y - 1, 8, ScenePalette.orangeDark);
  px.fill(lamp.centerX - 3, lamp.y + 12, 6, 2, ScenePalette.lampBulb);
  px.hline(lamp.centerX - 2, lamp.y + 14, 4, ScenePalette.bulbWarm);
  // Glow on the counter top.
  px.dither(
    lamp.x - 10,
    counter.y + 1,
    lamp.w + 20,
    6,
    null,
    ScenePalette.lampGlow,
  );
  px.dither(
    lamp.x - 18,
    counter.y + 1,
    lamp.w + 36,
    7,
    null,
    ScenePalette.lampGlowSoft,
    pattern: Dither.quarter,
  );
}

/// A 6x6 mug with a handle on the right; (x, y) is the top-left of the cup.
void paintMug(Px px, int x, int y, Tones t) {
  px.ring(x, y, 6, 6, t.dark);
  px.fill(x + 1, y + 1, 4, 4, t.base);
  px.vline(x + 1, y + 1, 4, t.light);
  px.hline(x + 1, y + 4, 4, t.shade);
  px.hline(x + 1, y + 1, 4, ScenePalette.screenOff);
  px.vline(x + 6, y + 1, 3, t.dark);
  px.dot(x + 5, y + 1, t.dark);
  px.dot(x + 5, y + 3, t.dark);
}

/// Four-frame steam puff above the coffee machine's cup.
void paintSteam(Px px, IRect machine, int frame) {
  final cx = machine.x + machine.w ~/ 2;
  final base = machine.y + machine.h - 11;
  final f = frame % 4;
  px.dot(cx - 1 + (f == 1 || f == 2 ? 1 : 0), base - f, ScenePalette.steam);
  px.dot(cx + 1 - (f >= 2 ? 1 : 0), base - 2 - f, ScenePalette.steam);
  if (f >= 1) px.dot(cx, base - 4 - f, ScenePalette.steam);
  if (f >= 2) px.dot(cx + 1, base - 6 - f, ScenePalette.starDim);
}

/// Desk: bevelled top band and a front with an open leg space on the left
/// and a drawer pedestal on the right. Casts a shadow on the floor.
void paintDesk(Px px, IRect r, int surfaceHeight) {
  final top = ScenePalette.deskTop;
  final front = ScenePalette.deskFront;
  px.dither(r.x + 2, r.bottom, r.w - 1, 3, null, ScenePalette.shadow);
  px.dither(r.x + 4, r.bottom + 3, r.w - 2, 2, null, ScenePalette.shadowSoft);
  // Front face.
  final fy = r.y + surfaceHeight;
  final fh = r.h - surfaceHeight;
  px.fill(r.x, fy, r.w, fh, front.base);
  px.ring(r.x, fy, r.w, fh, front.dark);
  // Open leg space: dark cavity with a leg at the left end.
  final pedestalW = 40;
  px.fill(r.x + 5, fy + 1, r.w - pedestalW - 7, fh - 3, front.dark);
  px.fill(r.x + 1, fy + 1, 4, fh - 2, front.base);
  px.vline(r.x + 1, fy + 1, fh - 2, front.light);
  px.vline(r.x + 4, fy + 1, fh - 2, front.shade);
  px.hline(r.x + 5, fy + 1, r.w - pedestalW - 7, ScenePalette.ink);
  // Drawer pedestal.
  final pxl = r.right - pedestalW - 1;
  px.fill(pxl, fy + 1, pedestalW, fh - 2, front.base);
  px.vline(pxl, fy + 1, fh - 2, front.light);
  px.vline(r.right - 2, fy + 1, fh - 2, front.shade);
  final drawerH = (fh - 3) ~/ 2;
  for (var i = 0; i < 2; i++) {
    final dy = fy + 2 + i * drawerH;
    px.ring(pxl + 3, dy, pedestalW - 6, drawerH - 1, front.dark);
    px.fill(pxl + 4, dy + 1, pedestalW - 8, drawerH - 3, front.shade);
    px.hline(pxl + 4, dy + 1, pedestalW - 8, front.dark);
    px.hline(pxl + 4, dy + drawerH - 3, pedestalW - 8, front.light);
    px.fill(
      pxl + pedestalW ~/ 2 - 4,
      dy + drawerH ~/ 2 - 1,
      8,
      2,
      ScenePalette.steel.shade,
    );
    px.hline(
      pxl + pedestalW ~/ 2 - 4,
      dy + drawerH ~/ 2 - 1,
      8,
      ScenePalette.steel.light,
    );
  }
  px.hline(r.x + 1, r.bottom - 2, r.w - 2, front.dark);
  // Top band.
  px.shadeRect(
    r.x - 1,
    r.y,
    r.w + 2,
    surfaceHeight,
    top,
    outline: true,
    bevel: 1,
  );
  px.hline(r.x, r.y + 1, r.w, top.light);
  px.hline(r.x, r.y + surfaceHeight - 2, r.w, top.shade);
  for (var x = r.x + 6; x < r.right - 6; x += 23) {
    px.hline(x, r.y + 4 + (x ~/ 23) % 5, 9 + (x ~/ 7) % 6, top.shade);
  }
}

/// Desk return going back toward the wall (corner desk).
void paintDeskReturn(Px px, IRect r) {
  final top = ScenePalette.deskTop;
  px.dither(r.x + 2, r.bottom, r.w, 2, null, ScenePalette.shadowSoft);
  px.shadeRect(r.x, r.y, r.w, r.h, top, outline: true, bevel: 1);
  px.hline(r.x + 1, r.y + 1, r.w - 2, top.light);
  px.vline(r.right - 2, r.y + 1, r.h - 2, top.shade);
  px.hline(r.x + 4, r.y + 10, 12, top.shade);
  px.hline(r.x + 8, r.y + 19, 14, top.shade);
}

/// Pot plant with layered leaves; (x, y) is the top-left of the leaves,
/// the pot ends at y + 24.
void paintPlant(Px px, int x, int y) {
  final leaf = ScenePalette.leaf;
  px.shadowEllipse(x + 8, y + 24, 7, 2, ScenePalette.shadowSoft);
  px.shadeRect(x + 3, y + 14, 11, 10, ScenePalette.pot, outline: true);
  px.fill(x + 2, y + 13, 13, 3, ScenePalette.pot.light);
  px.ring(x + 2, y + 13, 13, 3, ScenePalette.pot.dark);
  px.hline(x + 4, y + 16, 9, ScenePalette.wood.dark);
  px.vline(x + 8, y + 7, 8, leaf.dark);
  px.vline(x + 9, y + 9, 6, leaf.dark);
  const back = <(int, int)>[
    (3, 3), (4, 3), (5, 3), (2, 4), (3, 4), (4, 4), (5, 4), (6, 4), //
    (1, 5), (2, 5), (3, 5), (4, 5), (5, 5), (6, 5), (7, 5), (8, 5), (9, 5),
    (10, 5), (11, 5), (12, 5), (2, 6), (3, 6), (4, 6), (10, 6), (11, 6),
    (12, 6), (13, 6), (3, 7), (12, 7), (13, 7), (14, 7),
  ];
  const mid = <(int, int)>[
    (7, 0), (8, 0), (6, 1), (7, 1), (8, 1), (9, 1), (5, 2), (6, 2), (7, 2), //
    (8, 2), (9, 2), (10, 2), (6, 3), (7, 3), (8, 3), (9, 3), (10, 3), (11, 3),
    (7, 4), (8, 4), (9, 4), (10, 4), (11, 4), (12, 4), (8, 5), (9, 5), (10, 5),
    (11, 5), (12, 5), (13, 5),
  ];
  const front = <(int, int)>[
    (4, 8), (5, 8), (6, 8), (5, 9), (6, 9), (7, 9), (6, 10), (7, 10), //
    (10, 8), (11, 8), (12, 8), (10, 9), (11, 9), (9, 10), (10, 10),
    (0, 7), (1, 7), (1, 8), (2, 8), (14, 9), (15, 9), (15, 10), (16, 10),
  ];
  px.blob(back, leaf.shade, x: x, y: y, edge: leaf.dark);
  px.blob(mid, leaf.base, x: x, y: y, edge: leaf.dark);
  px.blob(front, leaf.base, x: x, y: y, edge: leaf.dark);
  for (final (dx, dy) in const [
    (7, 1),
    (6, 2),
    (8, 3),
    (5, 9),
    (11, 9),
    (1, 7),
  ]) {
    px.dot(x + dx, y + dy, leaf.light);
  }
}

/// Office chair back, peeking out behind a seated character.
void paintChairBack(Px px, IRect r) {
  final c = ScenePalette.cushion;
  px.shadeRect(r.x, r.y, r.w, r.h, c, outline: true, rounded: true);
  px.hline(r.x + 2, r.y + 1, r.w - 4, c.light);
  px.ring(r.x + 3, r.y + 3, r.w - 6, r.h - 5, c.shade);
  px.fill(r.x + 4, r.y + 4, r.w - 8, r.h - 7, c.base);
  px.hline(r.x + 4, r.y + 4, r.w - 8, c.light);
}

/// Visitor chair: cushioned backrest, seat and four legs. Greyed when
/// nobody owns it.
void paintVisitorChair(Px px, IRect r, {required bool greyed}) {
  final c = greyed ? ScenePalette.slate : ScenePalette.cushion;
  final frame = ScenePalette.steel;
  px.shadowEllipse(r.centerX, r.bottom, r.w ~/ 2 + 2, 3, ScenePalette.shadow);
  // Legs.
  for (final lx in [r.x + 3, r.right - 5]) {
    px.fill(lx, r.y + 22, 2, 12, frame.dark);
    px.vline(lx, r.y + 22, 12, frame.shade);
  }
  px.fill(r.x + 6, r.y + 24, 2, 8, frame.dark);
  px.fill(r.right - 8, r.y + 24, 2, 8, frame.dark);
  // Backrest.
  px.shadeRect(r.x + 3, r.y, r.w - 6, 16, c, outline: true, rounded: true);
  px.hline(r.x + 5, r.y + 1, r.w - 10, c.light);
  px.ring(r.x + 6, r.y + 3, r.w - 12, 10, c.shade);
  px.fill(r.x + 7, r.y + 4, r.w - 14, 8, c.base);
  px.hline(r.x + 7, r.y + 4, r.w - 14, c.light);
  // Seat cushion.
  px.shadeRect(r.x, r.y + 15, r.w, 9, c, outline: true);
  px.hline(r.x + 1, r.y + 16, r.w - 2, c.light);
  px.hline(r.x + 1, r.y + 22, r.w - 2, c.shade);
  px.fill(r.x + 1, r.y + 24, r.w - 2, 2, frame.shade);
  px.hline(r.x + 1, r.y + 24, r.w - 2, frame.light);
}

/// Reception desk with a warm lamp, a paper stack and a pen cup on top.
void paintReceptionDesk(Px px, IRect r) {
  final top = ScenePalette.deskTop;
  final front = ScenePalette.deskFront;
  const surface = 8;
  px.dither(r.x + 2, r.bottom, r.w - 1, 3, null, ScenePalette.shadow);
  px.fill(r.x, r.y + surface, r.w, r.h - surface, front.base);
  px.ring(r.x, r.y + surface, r.w, r.h - surface, front.dark);
  px.vline(r.x + 1, r.y + surface + 1, r.h - surface - 2, front.light);
  final panelW = (r.w - 9) ~/ 2;
  for (final pxl in [r.x + 3, r.x + 6 + panelW]) {
    px.ring(pxl, r.y + surface + 3, panelW, r.h - surface - 7, front.dark);
    px.fill(
      pxl + 1,
      r.y + surface + 4,
      panelW - 2,
      r.h - surface - 9,
      front.shade,
    );
    px.hline(pxl + 1, r.y + surface + 4, panelW - 2, front.dark);
    px.hline(pxl + 1, r.bottom - 6, panelW - 2, front.light);
    px.fill(
      pxl + 3,
      r.y + surface + 6,
      panelW - 6,
      r.h - surface - 13,
      front.base,
    );
  }
  px.hline(r.x + 1, r.bottom - 2, r.w - 2, front.dark);
  px.shadeRect(r.x - 1, r.y, r.w + 2, surface, top, outline: true);
  px.hline(r.x, r.y + 1, r.w, top.light);
  px.hline(r.x + 10, r.y + 4, 14, top.shade);
  // Paper stack.
  px.fill(r.x + 36, r.y - 4, 14, 5, ScenePalette.paper.shade);
  px.fill(r.x + 36, r.y - 5, 14, 4, ScenePalette.paper.base);
  px.hline(r.x + 36, r.y - 5, 14, ScenePalette.paper.light);
  px.ring(r.x + 35, r.y - 6, 16, 7, ScenePalette.paper.dark);
  px.hline(r.x + 38, r.y - 3, 8, ScenePalette.paperLine);
  // Pen cup.
  px.shadeRect(r.x + 58, r.y - 6, 6, 7, ScenePalette.slate, outline: true);
  px.vline(r.x + 60, r.y - 10, 5, ScenePalette.teal.base);
  px.vline(r.x + 62, r.y - 9, 4, ScenePalette.yellow);
  // Lamp at the left end, glowing on the desk top.
  final lx = r.x + 14;
  px.dither(lx - 10, r.y + 1, 26, surface - 2, null, ScenePalette.lampGlow);
  px.shadeRect(lx - 3, r.y - 2, 8, 3, ScenePalette.steel, outline: true);
  px.fill(lx, r.y - 12, 2, 10, ScenePalette.lampStem);
  px.vline(lx, r.y - 12, 10, ScenePalette.steel.shade);
  for (var i = 0; i < 7; i++) {
    final half = 2 + (i * 0.7).round();
    px.hline(lx + 1 - half, r.y - 20 + i, half * 2, ScenePalette.lampShade);
    px.hline(lx + 2, r.y - 20 + i, half - 1, ScenePalette.lampShadeShade);
    px.dot(lx - half, r.y - 20 + i, ScenePalette.orangeDark);
    px.dot(lx + 1 + half, r.y - 20 + i, ScenePalette.orangeDark);
  }
  px.hline(lx - 6, r.y - 13, 14, ScenePalette.orangeDark);
  px.hline(lx - 2, r.y - 21, 6, ScenePalette.orangeDark);
  px.fill(lx - 1, r.y - 12, 4, 2, ScenePalette.lampBulb);
  for (final (dx, dy) in Px.discPixels(13)) {
    final sx = lx + 1 + dx;
    final sy = r.y - 14 + dy;
    if (sy >= r.y) continue;
    if (dx * dx + dy * dy <= 49) {
      px.dot(sx, sy, ScenePalette.lampGlowSoft);
    } else if ((sx + sy).isEven) {
      px.dot(sx, sy, ScenePalette.lampGlowSoft);
    }
  }
}

/// Mailbox on a post. The red flag is up when a report is waiting.
void paintMailbox(Px px, IRect r, {required bool flagUp}) {
  final steel = ScenePalette.steel;
  final wood = ScenePalette.deskFront;
  px.shadowEllipse(r.centerX, r.bottom + 24, 6, 2, ScenePalette.shadow);
  px.fill(r.centerX - 2, r.bottom - 1, 4, 25, wood.base);
  px.vline(r.centerX - 2, r.bottom - 1, 25, wood.light);
  px.vline(r.centerX + 1, r.bottom - 1, 25, wood.dark);
  px.shadeRect(r.x, r.y, r.w, r.h, steel, outline: true, rounded: true);
  px.fill(r.x + 1, r.y + 1, r.w - 2, 2, steel.light);
  px.hline(r.x + 1, r.y + 3, r.w - 2, steel.base);
  px.vline(r.right - 2, r.y + 2, r.h - 4, steel.shade);
  px.fill(r.x + 4, r.y + 7, r.w - 8, 2, steel.dark);
  px.hline(r.x + 4, r.y + 9, r.w - 8, steel.light);
  px.fill(r.x + 3, r.bottom - 5, 4, 2, steel.dark);
  if (flagUp) {
    px.fill(r.right - 5, r.y - 8, 2, 10, ScenePalette.redDark);
    px.fill(r.right - 4, r.y - 9, 5, 5, ScenePalette.red);
    px.hline(r.right - 4, r.y - 9, 5, Color(0xFFF08A8A));
    px.vline(r.right, r.y - 9, 5, ScenePalette.redDark);
  } else {
    px.fill(r.right - 1, r.y + 4, 7, 2, ScenePalette.redDark);
    px.fill(r.right, r.y + 2, 6, 4, ScenePalette.red);
    px.hline(r.right, r.y + 2, 6, Color(0xFFF08A8A));
    px.hline(r.right, r.y + 5, 6, ScenePalette.redDark);
  }
}

/// 20x5 keyboard at (x, y).
void paintKeyboard(Px px, int x, int y) {
  final slate = ScenePalette.slate;
  px.shadeRect(x, y, 20, 5, slate, outline: true);
  for (var i = 0; i < 8; i++) {
    px.dot(x + 2 + i * 2, y + 1, slate.light);
    px.dot(x + 3 + i * 2, y + 2, slate.light);
  }
  px.hline(x + 6, y + 3, 8, slate.light);
}

/// Paper tray on a desk, 14x4, with a couple of sheets in it.
void drawTray(Px px, int x, int y) {
  px.shadeRect(x, y, 14, 4, ScenePalette.steel, outline: true);
  px.fill(x + 2, y - 1, 10, 2, ScenePalette.paper.base);
  px.hline(x + 2, y - 1, 10, ScenePalette.paper.light);
  px.hline(x + 3, y, 6, ScenePalette.paperLine);
}
