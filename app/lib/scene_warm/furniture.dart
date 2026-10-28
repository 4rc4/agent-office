import 'dart:math' as math;

import 'palette.dart';
import 'pixel.dart';
import 'scene_layout.dart';

/// Furniture and fixtures. Each painter takes scene-pixel rects from
/// [SceneLayout] so the layout file stays the single source of positions.
/// Light comes from the window (upper left): highlights top-left, shades
/// bottom-right, drop shadows down and to the right.

// ---- window wall ----------------------------------------------------------

/// Big window: cream frame, evening sky with a low sun and hills, glass
/// reflections, a cross mullion and a sill with a small cactus.
void paintWindow(PixelBuffer b, IRect r) {
  // Architrave.
  b.ring(r.x - 7, r.y - 7, r.w + 14, r.h + 14, Warm.creamOutline);
  b.shadeRect(
    r.x - 6,
    r.y - 6,
    r.w + 12,
    r.h + 12,
    base: Warm.creamBase,
    light: Warm.creamLight,
    dark: Warm.creamShade,
    bevel: 2,
  );
  b.ring(r.x - 1, r.y - 1, r.w + 2, r.h + 2, Warm.creamDark);

  // Sky.
  b.gradient(r.x, r.y, r.w, r.h, const [
    Warm.skyTop,
    Warm.skyHigh,
    Warm.skyMid,
    Warm.skyLow,
  ], (x, y) => (y - r.y) / r.h * 3.4 - 0.2);

  // Sun with a dithered halo.
  final sx = r.x + (r.w * 0.66).round();
  final sy = r.y + (r.h * 0.36).round();
  for (var y = sy - 13; y <= sy + 13; y++) {
    for (var x = sx - 13; x <= sx + 13; x++) {
      if (x < r.x || x >= r.right || y < r.y || y >= r.bottom) continue;
      final d = (x - sx) * (x - sx) + (y - sy) * (y - sy);
      if (d <= 52) {
        b.set(x, y, Warm.sun);
      } else if (d <= 90) {
        b.set(x, y, Warm.skyLow);
      } else if (d <= 150 && ((x + y) & 1) == 0) {
        b.set(x, y, Warm.skyLow);
      }
    }
  }

  // Hills: a far ridge and a near one with a few dark trees.
  for (var x = r.x; x < r.right; x++) {
    final far =
        r.bottom -
        30 +
        (3.5 * math.sin(x / 9.0) + 2 * math.sin(x / 4.3)).round();
    b.vline(x, far, r.bottom - far, Warm.hillsFar);
    final near =
        r.bottom -
        17 +
        (4 * math.sin(x / 13.0 + 1.2) + 2 * math.cos(x / 5.1)).round();
    b.vline(x, near, r.bottom - near, Warm.hillsNear);
    b.set(x, near, PixelBuffer.lightOf(Warm.hillsNear));
    if (x % 17 == 5) {
      b.fill(x - 1, near - 4, 3, 4, Warm.hillsDark);
      b.set(x, near - 5, Warm.hillsDark);
    }
  }
  b.fill(r.x, r.bottom - 5, r.w, 5, Warm.hillsDark);

  // Glass reflections in the two upper panes.
  void streak(int x0, int y0, int len) {
    for (var i = 0; i < len; i++) {
      final x = x0 + i;
      final y = y0 - i;
      if (x >= r.x && x < r.right && y >= r.y && y < r.bottom) {
        b.set(x, y, PixelBuffer.lightOf(b.get(x, y)));
      }
    }
  }

  streak(r.x + 3, r.y + 22, 20);
  streak(r.x + 3, r.y + 27, 12);
  streak(r.centerX + 5, r.y + 20, 16);

  // Mullions.
  final mx = r.centerX - 2;
  final my = r.y + (r.h * 0.46).round() - 2;
  b.shadeRect(
    mx,
    r.y,
    4,
    r.h,
    base: Warm.creamBase,
    light: Warm.creamLight,
    dark: Warm.creamShade,
  );
  b.shadeRect(
    r.x,
    my,
    r.w,
    4,
    base: Warm.creamBase,
    light: Warm.creamLight,
    dark: Warm.creamShade,
  );
  b.set(mx + 3, my + 3, Warm.creamDark);

  // Sill.
  final sillX = r.x - 10;
  final sillW = r.w + 20;
  final sillY = r.bottom + 6;
  b.shadeRect(
    sillX,
    sillY,
    sillW,
    6,
    base: Warm.creamBase,
    light: Warm.creamLight,
    dark: Warm.creamShade,
  );
  b.hline(sillX, sillY + 6, sillW, Warm.creamOutline);
  b.modify(
    sillX + 1,
    sillY + 7,
    sillW,
    2,
    (c) => PixelBuffer.mix(c, Warm.wallDark, 0.55),
  );
  b.modify(
    sillX + 2,
    sillY + 9,
    sillW,
    1,
    (c) => PixelBuffer.mix(c, Warm.wallDark, 0.55),
    checker: true,
  );

  // Cactus in a small pot on the sill.
  final cx = r.x + 12;
  b.shadeRect(
    cx - 4,
    sillY - 7,
    9,
    7,
    base: Warm.potBase,
    light: Warm.potLight,
    dark: Warm.potDark,
  );
  b.hline(cx - 5, sillY - 8, 11, Warm.potLight);
  b.hline(cx - 5, sillY - 9, 11, Warm.potDark);
  b.fill(cx - 1, sillY - 18, 3, 9, Warm.leafBase);
  b.vline(cx - 1, sillY - 18, 9, Warm.leafLight);
  b.vline(cx + 1, sillY - 17, 8, Warm.leafDark);
  b.fill(cx - 4, sillY - 15, 2, 4, Warm.leafBase);
  b.hline(cx - 4, sillY - 13, 3, Warm.leafBase);
  b.fill(cx + 3, sillY - 14, 2, 3, Warm.leafBase);
  b.hline(cx + 2, sillY - 12, 2, Warm.leafBase);
  b.set(cx, sillY - 19, Warm.pink);
}

/// Curtain rod with finials and a few rings.
void paintCurtainRod(PixelBuffer b, int x, int y, int w) {
  b.hline(x, y, w, Warm.woodShade);
  b.hline(x, y + 1, w, Warm.woodDark);
  b.hline(x + 1, y, w - 2, Warm.woodBase);
  b.fill(x - 2, y - 1, 3, 4, Warm.woodDark);
  b.fill(x + w - 1, y - 1, 3, 4, Warm.woodDark);
  b.set(x - 2, y - 1, Warm.woodBase);
  b.set(x + w - 1, y - 1, Warm.woodBase);
}

/// Hanging curtain with vertical folds and a tie-back.
void paintCurtain(PixelBuffer b, IRect r, {required bool left}) {
  const fold = [
    Warm.curtainLight,
    Warm.curtainBase,
    Warm.curtainBase,
    Warm.curtainDark,
    Warm.curtainDark,
    Warm.curtainBase,
  ];
  for (var i = 0; i < r.w; i++) {
    final c = fold[(i + (left ? 1 : 4)) % fold.length];
    b.vline(r.x + i, r.y, r.h, c);
  }
  b.vline(left ? r.x : r.right - 1, r.y, r.h, Warm.curtainOutline);
  b.hline(r.x, r.bottom - 1, r.w, Warm.curtainOutline);
  b.hline(r.x, r.y, r.w, Warm.curtainDark);
  // Tie-back band.
  final ty = r.y + (r.h * 0.62).round();
  b.fill(r.x + 1, ty, r.w - 2, 3, Warm.amberDark);
  b.hline(r.x + 1, ty, r.w - 2, Warm.amber);
  // Rings.
  for (var x = r.x + 2; x < r.right - 1; x += 4) {
    b.set(x, r.y - 1, Warm.amber);
  }
}

/// Door with an architrave, a frosted glass pane, two recessed panels, a
/// brass knob and a steel kick plate.
void paintDoor(PixelBuffer b, IRect r) {
  // Architrave (no bottom: the leaf meets the skirting).
  b.hline(r.x - 6, r.y - 6, r.w + 12, Warm.creamOutline);
  b.vline(r.x - 6, r.y - 6, r.h + 6, Warm.creamOutline);
  b.vline(r.right + 5, r.y - 6, r.h + 6, Warm.creamOutline);
  b.shadeRect(
    r.x - 5,
    r.y - 5,
    r.w + 10,
    r.h + 5,
    base: Warm.creamBase,
    light: Warm.creamLight,
    dark: Warm.creamShade,
    bevel: 2,
  );
  // Leaf.
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Warm.woodBase,
    light: Warm.woodLight,
    dark: Warm.woodShade,
    bevel: 2,
  );
  b.vline(r.x, r.y, r.h, Warm.woodOutline);
  b.hline(r.x, r.y, r.w, Warm.woodOutline);
  b.vline(r.right - 1, r.y, r.h, Warm.woodDark);

  // Glass pane.
  final gx = r.x + 8;
  final gy = r.y + 9;
  final gw = r.w - 16;
  const gh = 32;
  b.ring(gx - 1, gy - 1, gw + 2, gh + 2, Warm.woodDark);
  b.hline(gx, gy + gh, gw, Warm.woodLight);
  b.vline(gx + gw, gy, gh, Warm.woodLight);
  b.gradient(gx, gy, gw, gh, const [
    Warm.creamLight,
    Warm.creamBase,
    Warm.creamShade,
  ], (x, y) => (y - gy) / gh * 2.2);
  for (var i = 0; i < 18; i++) {
    final x = gx + 3 + i;
    final y = gy + gh - 6 - i;
    if (x < gx + gw && y >= gy) b.set(x, y, Warm.creamLight);
    final x2 = gx + 8 + i;
    if (x2 < gx + gw && y >= gy) b.set(x2, y, Warm.creamLight);
  }

  // Panels.
  final py = gy + gh + 8;
  final ph = r.bottom - py - 12;
  final px = r.x + 8;
  final pw = r.w - 16;
  b.fill(px, py, pw, ph, Warm.woodShade);
  b.hline(px, py, pw, Warm.woodDark);
  b.vline(px, py, ph, Warm.woodDark);
  b.hline(px, py + ph - 1, pw, Warm.woodLight);
  b.vline(px + pw - 1, py, ph, Warm.woodLight);
  b.shadeRect(
    px + 3,
    py + 3,
    pw - 6,
    ph - 6,
    base: Warm.woodBase,
    light: Warm.woodLight,
    dark: Warm.woodShade,
  );

  // Knob on a brass plate.
  final kx = r.right - 9;
  final ky = r.y + 56;
  b.fill(kx - 1, ky - 2, 5, 8, Warm.amberDark);
  b.vline(kx - 1, ky - 2, 8, Warm.amber);
  b.fill(kx, ky, 3, 3, Warm.amber);
  b.set(kx, ky, Warm.amberLight);
  b.set(kx + 2, ky + 2, Warm.amberDark);
  b.set(kx + 1, ky + 4, Warm.woodOutline);

  // Kick plate.
  b.shadeRect(
    r.x + 3,
    r.bottom - 8,
    r.w - 6,
    6,
    base: Warm.steelBase,
    light: Warm.steelLight,
    dark: Warm.steelShade,
  );
}

// ---- back wall --------------------------------------------------------------

/// Whiteboard: aluminium frame with a bevel, a slight shadow on the wall, a
/// marker tray with two markers and an eraser. Notes are drawn on top.
void paintWhiteboard(PixelBuffer b, IRect r) {
  b.modify(
    r.x + 3,
    r.y + 3,
    r.w,
    r.h,
    (c) => PixelBuffer.mix(c, Warm.wallDark, 0.6),
    checker: true,
  );
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Warm.steelBase,
    light: Warm.steelLight,
    dark: Warm.steelShade,
    bevel: 2,
  );
  b.hline(r.x, r.bottom - 1, r.w, Warm.steelOutline);
  b.vline(r.right - 1, r.y, r.h, Warm.steelOutline);
  b.fill(r.x + 4, r.y + 4, r.w - 8, r.h - 8, Warm.boardFace);
  b.hline(r.x + 4, r.y + 4, r.w - 8, Warm.boardShade);
  b.vline(r.x + 4, r.y + 4, r.h - 8, Warm.boardShade);
  b.hline(
    r.x + 5,
    r.y + 5,
    r.w - 10,
    PixelBuffer.mix(Warm.boardShade, Warm.boardFace, 0.5),
  );
  // Faint old smudges.
  b.hline(r.x + 30, r.bottom - 12, 9, Warm.boardShade);
  b.hline(r.x + 70, r.bottom - 10, 5, Warm.boardShade);

  // Tray.
  final tx = r.x + 14;
  final ty = r.bottom - 2;
  final tw = r.w - 28;
  b.shadeRect(
    tx,
    ty,
    tw,
    5,
    base: Warm.steelShade,
    light: Warm.steelLight,
    dark: Warm.steelDark,
  );
  b.hline(tx, ty + 5, tw, Warm.steelOutline);
  // Markers and eraser.
  b.fill(tx + 6, ty - 2, 10, 3, Warm.red);
  b.hline(tx + 6, ty - 2, 8, PixelBuffer.lightOf(Warm.red));
  b.fill(tx + 14, ty - 2, 2, 3, Warm.redDark);
  b.fill(tx + 20, ty - 2, 10, 3, Warm.teal);
  b.hline(tx + 20, ty - 2, 8, Warm.tealLight);
  b.fill(tx + 28, ty - 2, 2, 3, Warm.tealDark);
  b.shadeRect(
    tx + tw - 18,
    ty - 3,
    12,
    4,
    base: Warm.slateBase,
    light: Warm.slateLight,
    dark: Warm.slateDark,
  );
}

/// One sticky note: lit top edge, shaded right/bottom edges, a curled
/// corner, two scribble lines and either a red pin (root task) or a strip
/// of tape.
void paintStickyNote(
  PixelBuffer b,
  int x,
  int y,
  int w,
  int h,
  int fill,
  int dark, {
  required bool pinned,
}) {
  b.fill(x + 1, y + 1, w, h, Warm.boardShade);
  b.fill(x, y, w, h, fill);
  b.hline(x, y, w, PixelBuffer.lightOf(fill));
  b.vline(x + w - 1, y, h, dark);
  b.hline(x, y + h - 1, w, dark);
  // Curled corner.
  b.set(x + w - 1, y + h - 1, Warm.boardFace);
  b.set(x + w - 2, y + h - 1, dark);
  b.set(x + w - 1, y + h - 2, dark);
  b.set(x + w - 2, y + h - 2, PixelBuffer.lightOf(fill));
  b.set(x + w - 3, y + h - 2, dark);
  b.set(x + w - 2, y + h - 3, dark);
  // Scribble.
  final ink = PixelBuffer.mix(fill, dark, 0.7);
  b.hline(x + 4, y + 7, w - 10, ink);
  b.hline(x + 4, y + 10, w - 14, ink);
  b.hline(x + 4, y + 13, w - 12, ink);
  if (pinned) {
    final cx = x + w ~/ 2;
    b.fill(cx - 1, y + 1, 3, 3, Warm.red);
    b.set(cx - 1, y + 1, PixelBuffer.lightOf(Warm.red));
    b.set(cx + 1, y + 3, Warm.redDark);
    b.set(cx, y + 4, Warm.ink);
  } else {
    final cx = x + w ~/ 2;
    b.fill(cx - 3, y - 1, 7, 3, PixelBuffer.mix(fill, Warm.boardFace, 0.55));
  }
}

/// Round wall clock with a wooden rim, a cream face and hands at ten past
/// ten.
void paintClock(PixelBuffer b, IRect r) {
  final cx = r.centerX;
  final cy = r.centerY;
  b.modify(
    cx - 10,
    cy - 9,
    24,
    24,
    (c) => PixelBuffer.mix(c, Warm.wallDark, 0.5),
    checker: true,
  );
  b.disc(cx, cy, 11, Warm.woodBase, outline: Warm.woodOutline);
  for (final (dx, dy) in PixelBuffer.discPixels(11)) {
    final d = dx * dx + dy * dy;
    if (d < 70) continue;
    if (dx + dy < -4) {
      b.set(cx + dx, cy + dy, Warm.woodLight);
    } else if (dx + dy > 4) {
      b.set(cx + dx, cy + dy, Warm.woodShade);
    }
  }
  b.disc(cx, cy, 8, Warm.paper);
  for (final (dx, dy) in PixelBuffer.discPixels(8)) {
    if (dx * dx + dy * dy >= 56 && dx + dy > 2) {
      b.set(cx + dx, cy + dy, Warm.paperShade);
    }
  }
  b.set(cx, cy - 7, Warm.ink);
  b.set(cx, cy + 7, Warm.ink);
  b.set(cx - 7, cy, Warm.ink);
  b.set(cx + 7, cy, Warm.ink);
  b.line(cx, cy, cx - 3, cy - 4, Warm.ink);
  b.line(cx, cy, cx + 3, cy - 6, Warm.ink);
  b.line(cx, cy, cx - 2, cy + 5, Warm.red);
  b.set(cx, cy, Warm.ink);
}

/// Three usage meters in dark bezels: a glass column that fills from the
/// bottom in the seat's accent, a glossy highlight and a status LED on top.
void paintGauges(
  PixelBuffer b,
  IRect r,
  List<int> accents,
  List<int> accentDarks,
  List<double> levels,
) {
  for (var i = 0; i < accents.length; i++) {
    final x = r.x + i * (SceneLayout.gaugeWidth + SceneLayout.gaugeGap);
    const w = SceneLayout.gaugeWidth;
    b.modify(
      x + 2,
      r.y + 2,
      w,
      r.h,
      (c) => PixelBuffer.mix(c, Warm.wallDark, 0.5),
      checker: true,
    );
    b.shadeRect(
      x,
      r.y,
      w,
      r.h,
      base: Warm.slateBase,
      light: Warm.slateLight,
      dark: Warm.slateDark,
      rounded: true,
    );
    b.fill(x + 3, r.y + 6, w - 6, r.h - 9, Warm.screenOff);
    final level = i < levels.length ? levels[i].clamp(0.0, 1.0) : 0.0;
    final maxH = r.h - 11;
    final lh = (maxH * level).round();
    if (lh > 0) {
      b.fill(x + 4, r.bottom - 4 - lh, w - 8, lh, accents[i]);
      b.hline(x + 4, r.bottom - 4 - lh, w - 8, PixelBuffer.lightOf(accents[i]));
    }
    b.vline(x + 3, r.y + 6, r.h - 9, Warm.screenGlint);
    for (var t = 0; t < 4; t++) {
      b.set(x + w - 4, r.y + 7 + t * 4, Warm.slateLight);
    }
    b.fill(x + 3, r.y + 2, w - 6, 2, level > 0 ? accents[i] : accentDarks[i]);
    b.set(x + 3, r.y + 2, PixelBuffer.lightOf(accents[i]));
  }
}

/// Framed poster: a tiny landscape in the office's own colours.
void paintPosterLandscape(PixelBuffer b, IRect r) {
  _posterFrame(b, r);
  final px = r.x + 4;
  final py = r.y + 4;
  final pw = r.w - 8;
  final ph = r.h - 8;
  b.gradient(px, py, pw, ph, const [
    Warm.amberLight,
    Warm.amber,
    Warm.orange,
  ], (x, y) => (y - py) / ph * 2.4);
  b.disc(px + pw - 7, py + 5, 2, Warm.cream);
  for (var x = px; x < px + pw; x++) {
    final far = py + ph - 9 + (2 * math.sin(x / 3.0)).round();
    b.vline(x, far, py + ph - far, Warm.violetDark);
    final near = py + ph - 5 + (1.5 * math.cos(x / 2.2)).round();
    b.vline(x, near, py + ph - near, Warm.tealDark);
  }
}

/// Framed poster: three overlapping discs in the three agents' colours.
void paintPosterCircles(PixelBuffer b, IRect r) {
  _posterFrame(b, r);
  b.fill(r.x + 4, r.y + 4, r.w - 8, r.h - 8, Warm.paper);
  final cx = r.centerX;
  final cy = r.centerY;
  b.disc(cx - 4, cy - 5, 5, Warm.orange);
  b.disc(cx + 4, cy - 3, 5, Warm.teal);
  b.disc(cx, cy + 5, 5, Warm.violet);
  b.set(cx - 6, cy - 7, Warm.amberLight);
  b.set(cx + 2, cy - 5, Warm.tealLight);
  b.set(cx - 2, cy + 3, Warm.violetLight);
}

void _posterFrame(PixelBuffer b, IRect r) {
  b.modify(
    r.x + 2,
    r.y + 2,
    r.w,
    r.h,
    (c) => PixelBuffer.mix(c, Warm.wallDark, 0.5),
    checker: true,
  );
  b.fill(r.x, r.y, r.w, r.h, Warm.woodDark);
  b.hline(r.x, r.y, r.w, Warm.woodBase);
  b.vline(r.x, r.y, r.h, Warm.woodBase);
  b.hline(r.x, r.bottom - 1, r.w, Warm.woodOutline);
  b.vline(r.right - 1, r.y, r.h, Warm.woodOutline);
  b.fill(r.x + 2, r.y + 2, r.w - 4, r.h - 4, Warm.creamBase);
  b.hline(r.x + 2, r.y + 2, r.w - 4, Warm.creamShade);
  b.vline(r.x + 2, r.y + 2, r.h - 4, Warm.creamShade);
}

/// Steel filing cabinet with three drawers, label holders and handles, a
/// row of binders on top and a shadow on the wall.
void paintCabinet(PixelBuffer b, IRect r) {
  b.modify(
    r.x + 3,
    r.y + 3,
    r.w,
    r.h - 3,
    (c) => PixelBuffer.mix(c, Warm.wallDark, 0.6),
    checker: true,
  );
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Warm.steelBase,
    light: Warm.steelLight,
    dark: Warm.steelShade,
    rounded: true,
  );
  b.vline(r.right - 1, r.y + 1, r.h - 1, Warm.steelOutline);
  b.hline(r.x + 1, r.y + 1, r.w - 2, Warm.steelLight);
  final drawerH = (r.h - 5) ~/ 3;
  final cx = r.centerX;
  for (var i = 0; i < 3; i++) {
    final y = r.y + 3 + i * drawerH;
    b.hline(r.x + 1, y, r.w - 2, Warm.steelDark);
    b.hline(r.x + 2, y + 1, r.w - 4, Warm.steelLight);
    b.vline(r.x + 2, y + 1, drawerH - 1, Warm.steelLight);
    b.vline(r.right - 3, y + 1, drawerH - 1, Warm.steelShade);
    b.fill(cx - 5, y + 4, 10, 4, Warm.paper);
    b.hline(cx - 5, y + 7, 10, Warm.paperShade);
    b.hline(cx - 3, y + 5, 6, Warm.paperLine);
    b.fill(cx - 4, y + drawerH - 6, 8, 2, Warm.steelOutline);
    b.set(cx - 4, y + drawerH - 6, Warm.steelLight);
  }
  b.fill(r.x + 1, r.bottom - 3, r.w - 2, 3, Warm.steelDark);
  b.hline(r.x, r.bottom - 1, r.w, Warm.steelOutline);
  // Binders on top.
  const binders = [
    (Warm.teal, Warm.tealDark),
    (Warm.orange, Warm.orangeDark),
    (Warm.violet, Warm.violetDark),
    (Warm.amber, Warm.amberDark),
  ];
  for (var i = 0; i < binders.length; i++) {
    final (base, dark) = binders[i];
    final x = r.x + 5 + i * 6;
    b.fill(x, r.y - 9, 5, 9, base);
    b.vline(x + 4, r.y - 9, 9, dark);
    b.hline(x, r.y - 9, 4, PixelBuffer.lightOf(base));
    b.fill(x + 1, r.y - 6, 2, 2, Warm.paper);
  }
}

// ---- plants -----------------------------------------------------------------

List<(int, int)> _ellipse(int rx, int ry) {
  final out = <(int, int)>[];
  for (var y = -ry; y <= ry; y++) {
    for (var x = -rx; x <= rx; x++) {
      final v =
          (x * x) / ((rx + 0.5) * (rx + 0.5)) +
          (y * y) / ((ry + 0.5) * (ry + 0.5));
      if (v <= 1.0) out.add((x, y));
    }
  }
  return out;
}

/// One leaf: outlined ellipse with a lit top-left and a shaded bottom-right.
void _leaf(PixelBuffer b, int cx, int cy, int rx, int ry, {bool back = false}) {
  final base = back ? Warm.leafDark : Warm.leafBase;
  b.blob(_ellipse(rx, ry), base, outline: Warm.leafOutline, x: cx, y: cy);
  if (back) return;
  for (final (dx, dy) in _ellipse(rx, ry)) {
    if (dx + dy * 2 <= -(rx ~/ 2 + 1)) {
      b.set(cx + dx, cy + dy, Warm.leafLight);
    } else if (dx + dy * 2 >= rx + 1) {
      b.set(cx + dx, cy + dy, Warm.leafDark);
    }
  }
  b.line(cx - rx ~/ 2, cy, cx + rx ~/ 2, cy, Warm.leafDark);
}

/// Terracotta pot: lip, body with a lit left side, dark soil.
void _pot(PixelBuffer b, int x, int y, int w, int h) {
  b.fill(x + 1, y + 2, w - 2, h - 2, Warm.potBase);
  b.vline(x + 1, y + 2, h - 2, Warm.potLight);
  b.vline(x + 2, y + 2, h - 3, Warm.potLight);
  b.fill(x + w - 3, y + 2, 2, h - 2, Warm.potDark);
  b.vline(x, y + 2, h - 3, Warm.potDark);
  b.vline(x + w - 1, y + 2, h - 3, Warm.potDark);
  b.hline(x + 1, y + h - 1, w - 2, Warm.potDark);
  b.shadeRect(
    x - 1,
    y,
    w + 2,
    3,
    base: Warm.potBase,
    light: Warm.potLight,
    dark: Warm.potDark,
  );
  b.hline(x - 1, y + 3, w + 2, Warm.potDark);
}

/// Small desk plant: pot ends at y + 22.
void paintDeskPlant(PixelBuffer b, int x, int y) {
  _pot(b, x + 3, y + 13, 10, 9);
  b.fill(x + 4, y + 13, 8, 1, Warm.soil);
  b.vline(x + 7, y + 6, 8, Warm.leafDark);
  _leaf(b, x + 4, y + 8, 3, 2, back: true);
  _leaf(b, x + 11, y + 7, 3, 2, back: true);
  _leaf(b, x + 7, y + 4, 3, 2);
  _leaf(b, x + 3, y + 10, 3, 2);
  _leaf(b, x + 12, y + 10, 3, 2);
}

/// Tall floor plant: pot ends at y + 62.
void paintFloorPlant(PixelBuffer b, int x, int y) {
  b.ellipseShadow(x + 13, y + 63, 13, 3);
  _pot(b, x + 4, y + 46, 18, 16);
  b.fill(x + 5, y + 46, 16, 1, Warm.soil);
  b.vline(x + 12, y + 22, 24, Warm.leafDark);
  b.vline(x + 13, y + 22, 24, Warm.leafOutline);
  _leaf(b, x + 5, y + 18, 5, 3, back: true);
  _leaf(b, x + 21, y + 16, 5, 3, back: true);
  _leaf(b, x + 14, y + 8, 5, 3, back: true);
  _leaf(b, x + 3, y + 30, 5, 3, back: true);
  _leaf(b, x + 23, y + 30, 5, 3, back: true);
  _leaf(b, x + 9, y + 12, 6, 4);
  _leaf(b, x + 19, y + 22, 6, 4);
  _leaf(b, x + 6, y + 25, 6, 4);
  _leaf(b, x + 14, y + 33, 6, 3);
  _leaf(b, x + 13, y + 4, 5, 3);
  _leaf(b, x + 22, y + 10, 4, 3);
}

/// Wall shelf on two brackets with a pot whose vine trails down the left.
void paintWallShelf(PixelBuffer b, IRect r) {
  b.modify(
    r.x + 2,
    r.y + 2,
    r.w,
    r.h + 2,
    (c) => PixelBuffer.mix(c, Warm.wallDark, 0.5),
    checker: true,
  );
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Warm.woodBase,
    light: Warm.woodLight,
    dark: Warm.woodDark,
  );
  b.hline(r.x, r.bottom, r.w, Warm.woodOutline);
  for (final bx in [r.x + 3, r.right - 5]) {
    b.vline(bx, r.bottom + 1, 3, Warm.woodDark);
    b.set(bx + 1, r.bottom + 1, Warm.woodDark);
  }
  // Pot and vine.
  _pot(b, r.x + 10, r.y - 9, 9, 9);
  b.hline(r.x + 11, r.y - 9, 7, Warm.soil);
  _leaf(b, r.x + 12, r.y - 11, 2, 1);
  _leaf(b, r.x + 17, r.y - 12, 2, 1);
  final vine = <(int, int)>[
    (r.x + 10, r.y - 6),
    (r.x + 8, r.y - 3),
    (r.x + 7, r.y + 1),
    (r.x + 5, r.y + 5),
    (r.x + 4, r.y + 9),
    (r.x + 6, r.y + 13),
    (r.x + 3, r.y + 17),
  ];
  for (var i = 1; i < vine.length; i++) {
    b.line(
      vine[i - 1].$1,
      vine[i - 1].$2,
      vine[i].$1,
      vine[i].$2,
      Warm.leafDark,
    );
  }
  for (var i = 1; i < vine.length; i++) {
    final (vx, vy) = vine[i];
    _leaf(b, vx + (i.isEven ? 2 : -2), vy, 2, 1, back: i == 3);
  }
}

// ---- coffee corner ----------------------------------------------------------

/// Counter with two cupboard doors, a coffee machine with a cup and steam,
/// a mug stack, a fruit bowl and two stools in front.
void paintCoffeeCounter(PixelBuffer b, IRect counter, IRect machine) {
  // Wall shadow of the counter and machine.
  b.modify(
    counter.x + 3,
    counter.y + 3,
    counter.w,
    counter.h - 3,
    (c) => PixelBuffer.mix(c, Warm.wallDark, 0.6),
    checker: true,
  );
  b.modify(
    machine.x + 3,
    machine.y + 3,
    machine.w,
    machine.h - 3,
    (c) => PixelBuffer.mix(c, Warm.wallDark, 0.6),
    checker: true,
  );
  // Worktop.
  b.shadeRect(
    counter.x - 2,
    counter.y,
    counter.w + 4,
    7,
    base: Warm.woodLight,
    light: Warm.creamLight,
    dark: Warm.woodBase,
  );
  b.hline(counter.x - 2, counter.y + 6, counter.w + 4, Warm.woodShade);
  b.hline(counter.x - 2, counter.y + 7, counter.w + 4, Warm.woodOutline);
  // Body and cupboards.
  b.fill(counter.x, counter.y + 8, counter.w, counter.h - 8, Warm.woodShade);
  b.vline(counter.x, counter.y + 8, counter.h - 8, Warm.woodOutline);
  b.vline(counter.right - 1, counter.y + 8, counter.h - 8, Warm.woodOutline);
  final doorW = counter.w ~/ 2 - 6;
  for (final dx in [counter.x + 4, counter.x + counter.w ~/ 2 + 2]) {
    final dy = counter.y + 11;
    final dh = counter.h - 17;
    b.shadeRect(
      dx,
      dy,
      doorW,
      dh,
      base: Warm.woodBase,
      light: Warm.woodLight,
      dark: Warm.woodDark,
    );
    b.fill(dx + 3, dy + 3, doorW - 6, dh - 6, Warm.woodShade);
    b.hline(dx + 3, dy + dh - 4, doorW - 6, Warm.woodLight);
    b.vline(dx + doorW - 4, dy + 3, dh - 6, Warm.woodLight);
    b.hline(dx + 3, dy + 3, doorW - 6, Warm.woodDark);
    b.vline(dx + 3, dy + 3, dh - 6, Warm.woodDark);
  }
  final hx = counter.x + counter.w ~/ 2;
  b.fill(hx - 7, counter.y + 22, 2, 6, Warm.amber);
  b.fill(hx + 5, counter.y + 22, 2, 6, Warm.amber);
  b.set(hx - 7, counter.y + 22, Warm.amberLight);
  b.set(hx + 5, counter.y + 22, Warm.amberLight);
  b.fill(counter.x, counter.bottom - 3, counter.w, 3, Warm.woodDark);
  b.hline(counter.x, counter.bottom - 1, counter.w, Warm.woodOutline);

  // Mug stack.
  for (var i = 0; i < 3; i++) {
    final mx = counter.x + 8 + i * 3;
    final my = counter.y - 7 + i * 2;
    paintMug(b, mx, my, stripe: i.isEven ? Warm.teal : Warm.orange);
  }
  // Fruit bowl.
  final bx = counter.right - 26;
  final by = counter.y - 4;
  b.fill(bx + 1, by + 1, 14, 3, Warm.woodDark);
  b.hline(bx, by, 16, Warm.woodShade);
  b.hline(bx + 2, by + 4, 12, Warm.woodOutline);
  b.disc(bx + 4, by - 1, 2, Warm.orange, outline: Warm.orangeDark);
  b.disc(bx + 11, by - 1, 2, Warm.orange, outline: Warm.orangeDark);
  b.disc(bx + 8, by - 3, 2, Warm.amber, outline: Warm.amberDark);
  b.set(bx + 3, by - 2, Warm.amberLight);
  b.set(bx + 7, by - 4, Warm.amberLight);
  b.set(bx + 10, by - 2, Warm.amberLight);
}

/// Coffee machine on the counter; [frame] drives the steam puff.
void paintCoffeeMachine(PixelBuffer b, IRect m, int frame) {
  b.shadeRect(
    m.x,
    m.y,
    m.w,
    m.h,
    base: Warm.slateBase,
    light: Warm.slateLight,
    dark: Warm.slateDark,
    rounded: true,
  );
  b.roundRing(m.x, m.y, m.w, m.h, Warm.slateDark);
  b.hline(m.x + 1, m.y + 1, m.w - 2, Warm.slateLight);
  b.fill(m.x + 2, m.y + 3, m.w - 4, 2, Warm.steelBase);
  b.hline(m.x + 2, m.y + 3, m.w - 4, Warm.steelLight);
  // Panel: red and green LEDs and a dial.
  b.fill(m.x + 4, m.y + 8, 2, 2, Warm.red);
  b.set(m.x + 4, m.y + 8, PixelBuffer.lightOf(Warm.red));
  b.fill(m.x + 7, m.y + 8, 2, 2, Warm.green);
  b.disc(m.right - 6, m.y + 9, 2, Warm.steelBase, outline: Warm.slateDark);
  b.set(m.right - 7, m.y + 8, Warm.steelLight);
  // Brew head and recess.
  b.fill(m.x + 3, m.y + 14, m.w - 6, m.h - 19, Warm.slateDark);
  b.hline(m.x + 3, m.y + 14, m.w - 6, Warm.slateShade);
  b.fill(m.centerX - 2, m.y + 14, 4, 3, Warm.steelShade);
  b.fill(m.centerX - 1, m.y + 17, 2, 2, Warm.steelDark);
  // Drip tray.
  b.fill(m.x + 3, m.bottom - 5, m.w - 6, 3, Warm.steelShade);
  b.hline(m.x + 3, m.bottom - 5, m.w - 6, Warm.steelLight);
  b.hline(m.x + 1, m.bottom - 2, m.w - 2, Warm.slateDark);
  // Cup under the spout.
  paintMug(b, m.centerX - 3, m.bottom - 11, stripe: Warm.orange);
  // Steam.
  final cx = m.centerX;
  final cy = m.bottom - 12;
  switch (frame % 4) {
    case 0:
      b.set(cx, cy, Warm.steam);
    case 1:
      b.set(cx - 1, cy - 1, Warm.steam);
      b.set(cx + 1, cy - 2, Warm.steam);
    case 2:
      b.set(cx - 1, cy - 2, Warm.steam);
      b.set(cx, cy - 3, Warm.steam);
      b.set(cx + 1, cy - 1, Warm.steam);
    case 3:
      b.set(cx, cy - 4, Warm.steam);
      b.set(cx + 1, cy - 3, Warm.steam);
  }
}

/// Stool: round padded seat on three legs with a foot ring.
void paintStool(PixelBuffer b, IRect s) {
  b.ellipseShadow(s.centerX + 1, s.bottom, s.w ~/ 2 + 1, 2);
  b.vline(s.x + 3, s.y + 4, s.h - 4, Warm.woodDark);
  b.vline(s.right - 4, s.y + 4, s.h - 4, Warm.woodDark);
  b.vline(s.centerX, s.y + 4, s.h - 5, Warm.woodShade);
  b.hline(s.x + 3, s.y + s.h - 6, s.w - 6, Warm.woodShade);
  b.shadeRect(
    s.x,
    s.y,
    s.w,
    5,
    base: Warm.curtainBase,
    light: Warm.curtainLight,
    dark: Warm.curtainDark,
    rounded: true,
  );
  b.hline(s.x + 1, s.y + 5, s.w - 2, Warm.curtainOutline);
}

// ---- desks ------------------------------------------------------------------

/// Desk: lit top with a bevel, front panel darkening toward the floor, a
/// drawer unit on the right with brass handles.
void paintDesk(PixelBuffer b, IRect r, int surfaceH) {
  // Top.
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    surfaceH,
    base: Warm.woodLight,
    light: Warm.creamLight,
    dark: Warm.woodBase,
  );
  b.hline(r.x, r.y + surfaceH - 1, r.w, Warm.woodShade);
  b.vline(r.x, r.y, surfaceH, Warm.woodBase);
  // Front.
  final fy = r.y + surfaceH;
  final fh = r.h - surfaceH;
  b.fill(r.x, fy, r.w, fh, Warm.woodBase);
  b.hline(r.x, fy, r.w, Warm.woodDark);
  b.hline(r.x, fy + 1, r.w, Warm.woodShade);
  b.fill(r.x, fy + fh ~/ 2, r.w, fh - fh ~/ 2, Warm.woodShade);
  b.checker(r.x, fy + fh ~/ 2 - 1, r.w, 2, Warm.woodShade, 0);
  b.hline(r.x, r.bottom - 1, r.w, Warm.woodOutline);
  b.vline(r.x, r.y + 1, r.h - 1, Warm.woodOutline);
  b.vline(r.right - 1, r.y + 1, r.h - 1, Warm.woodDark);
  // Drawer unit.
  final ux = r.right - 32;
  final uw = 28;
  final dh = (fh - 5) ~/ 2;
  for (var i = 0; i < 2; i++) {
    final dy = fy + 3 + i * (dh + 1);
    b.shadeRect(
      ux,
      dy,
      uw,
      dh,
      base: Warm.woodBase,
      light: Warm.woodLight,
      dark: Warm.woodDark,
    );
    b.fill(ux + uw ~/ 2 - 3, dy + dh ~/ 2, 6, 2, Warm.amber);
    b.set(ux + uw ~/ 2 - 3, dy + dh ~/ 2, Warm.amberLight);
    b.hline(ux + uw ~/ 2 - 3, dy + dh ~/ 2 + 2, 6, Warm.woodOutline);
  }
}

/// Desk return going back toward the wall (corner desk), top only.
void paintDeskReturn(PixelBuffer b, IRect r) {
  b.fill(r.x, r.y, r.w, r.h, Warm.woodLight);
  b.hline(r.x, r.y, r.w, Warm.creamLight);
  b.vline(r.x, r.y, r.h, Warm.woodOutline);
  b.vline(r.x + 1, r.y + 1, r.h - 1, Warm.woodBase);
  b.vline(r.right - 1, r.y, r.h, Warm.woodShade);
  b.hline(r.x + 1, r.y + 1, r.w - 2, Warm.woodLight);
}

/// Office chair back: padded, with a seam, a lit top and a dark base.
void paintChairBack(PixelBuffer b, IRect r, CharacterPalette p) {
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: p.chair,
    light: p.chairLight,
    dark: p.chairDark,
    bevel: 2,
    rounded: true,
  );
  b.roundRing(r.x, r.y, r.w, r.h, p.chairDark);
  b.hline(r.x + 1, r.y, r.w - 2, p.chairLight);
  b.hline(r.x + 3, r.y + r.h ~/ 2, r.w - 6, p.chairDark);
  b.hline(r.x + 3, r.y + r.h ~/ 2 + 1, r.w - 6, p.chairLight);
}

/// Visitor armchair, the part behind the character: a padded back in the
/// seat's upholstery on a wooden frame, and the seat cushion. Greyed when
/// nobody owns it.
void paintVisitorChairBack(
  PixelBuffer b,
  IRect r,
  CharacterPalette p, {
  required bool greyed,
}) {
  final up = greyed ? Warm.steelShade : p.chair;
  final upLight = greyed ? Warm.steelBase : p.chairLight;
  final upDark = greyed ? Warm.steelDark : p.chairDark;
  final outline = greyed ? Warm.steelOutline : Warm.woodOutline;
  final wood = greyed ? Warm.steelBase : Warm.woodBase;
  final woodDark = greyed ? Warm.steelDark : Warm.woodDark;
  b.ellipseShadow(r.centerX + 2, r.bottom - 1, r.w ~/ 2 + 2, 3);
  // Back panel.
  b.shadeRect(
    r.x + 3,
    r.y,
    r.w - 6,
    19,
    base: up,
    light: upLight,
    dark: upDark,
    bevel: 2,
    rounded: true,
  );
  b.roundRing(r.x + 3, r.y, r.w - 6, 19, outline);
  b.hline(r.x + 5, r.y + 1, r.w - 10, upLight);
  b.hline(r.x + 6, r.y + 9, r.w - 12, upDark);
  b.hline(r.x + 6, r.y + 10, r.w - 12, upLight);
  // Wooden back posts.
  b.vline(r.x + 2, r.y + 2, 22, woodDark);
  b.vline(r.right - 3, r.y + 2, 22, woodDark);
  b.vline(r.x + 3, r.y + 3, 20, wood);
  b.vline(r.right - 4, r.y + 3, 20, wood);
  // Seat cushion and rail.
  b.shadeRect(
    r.x,
    r.y + 19,
    r.w,
    7,
    base: up,
    light: upLight,
    dark: upDark,
    rounded: true,
  );
  b.hline(r.x + 1, r.y + 25, r.w - 2, woodDark);
  b.hline(r.x + 1, r.y + 26, r.w - 2, outline);
}

/// Visitor armchair, the part in front of the character: armrests and the
/// two front legs.
void paintVisitorChairFront(PixelBuffer b, IRect r, {required bool greyed}) {
  final light = greyed ? Warm.steelLight : Warm.woodLight;
  final base = greyed ? Warm.steelBase : Warm.woodBase;
  final dark = greyed ? Warm.steelShade : Warm.woodDark;
  final outline = greyed ? Warm.steelOutline : Warm.woodOutline;
  for (final ax in [r.x, r.right - 7]) {
    b.shadeRect(
      ax,
      r.y + 13,
      7,
      3,
      base: base,
      light: light,
      dark: dark,
      rounded: true,
    );
    b.hline(ax + 1, r.y + 16, 5, outline);
    b.vline(ax + 3, r.y + 16, 3, dark);
  }
  for (final lx in [r.x + 2, r.right - 4]) {
    b.vline(lx, r.y + 27, r.h - 27, base);
    b.vline(lx + 1, r.y + 27, r.h - 27, dark);
  }
  b.hline(r.x + 4, r.bottom - 2, r.w - 8, dark);
}

/// Stack of three books on a desk; (x, y) is the top-left, 16x9.
void paintBooks(PixelBuffer b, int x, int y) {
  const books = [
    (Warm.violet, Warm.violetDark, 15),
    (Warm.orange, Warm.orangeDark, 13),
    (Warm.teal, Warm.tealDark, 16),
  ];
  var yy = y;
  for (final (base, dark, w) in books) {
    b.fill(x, yy, w, 3, base);
    b.hline(x, yy, w, PixelBuffer.lightOf(base));
    b.vline(x + w - 1, yy, 3, dark);
    b.hline(x + 1, yy + 2, w - 2, dark);
    b.set(x + 1, yy + 1, Warm.paper);
    yy += 3;
  }
  b.hline(x + 1, yy, 17, PixelBuffer.shadowOf(Warm.woodLight));
}

/// Tapered wastebasket with ribs and a crumpled sheet peeking out.
void paintWasteBin(PixelBuffer b, IRect r) {
  b.ellipseShadow(r.centerX + 1, r.bottom, r.w ~/ 2 + 1, 2);
  for (var i = 0; i < r.h; i++) {
    final inset = (i * 2) ~/ r.h;
    b.hline(r.x + inset, r.y + i, r.w - 2 * inset, Warm.slateBase);
    b.set(r.x + inset, r.y + i, Warm.slateLight);
    b.set(r.right - 1 - inset, r.y + i, Warm.slateDark);
  }
  for (var k = 1; k < 4; k++) {
    b.vline(r.x + k * 3, r.y + 2, r.h - 4, Warm.slateShade);
  }
  b.hline(r.x, r.y, r.w, Warm.slateLight);
  b.hline(r.x + 2, r.bottom - 1, r.w - 4, Warm.slateDark);
  b.fill(r.x + 3, r.y - 3, 5, 3, Warm.paper);
  b.set(r.x + 7, r.y - 3, Warm.paperShade);
  b.set(r.x + 4, r.y - 2, Warm.paperShade);
}

/// Reception desk with an inset front panel, a paper stack and a pen cup.
void paintReceptionDesk(PixelBuffer b, IRect r) {
  const surface = 8;
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    surface,
    base: Warm.woodLight,
    light: Warm.creamLight,
    dark: Warm.woodBase,
  );
  b.hline(r.x, r.y + surface - 1, r.w, Warm.woodShade);
  final fy = r.y + surface;
  final fh = r.h - surface;
  b.fill(r.x, fy, r.w, fh, Warm.woodBase);
  b.hline(r.x, fy, r.w, Warm.woodDark);
  b.fill(r.x, fy + fh ~/ 2, r.w, fh - fh ~/ 2, Warm.woodShade);
  b.checker(r.x, fy + fh ~/ 2 - 1, r.w, 2, Warm.woodShade, 0);
  b.vline(r.x, r.y + 1, r.h - 1, Warm.woodOutline);
  b.vline(r.right - 1, r.y + 1, r.h - 1, Warm.woodDark);
  b.hline(r.x, r.bottom - 1, r.w, Warm.woodOutline);
  // Inset panel.
  b.fill(r.x + 6, fy + 4, r.w - 12, fh - 8, Warm.woodShade);
  b.hline(r.x + 6, fy + 4, r.w - 12, Warm.woodDark);
  b.vline(r.x + 6, fy + 4, fh - 8, Warm.woodDark);
  b.hline(r.x + 6, fy + fh - 5, r.w - 12, Warm.woodLight);
  b.vline(r.right - 7, fy + 4, fh - 8, Warm.woodLight);
  b.shadeRect(
    r.x + 9,
    fy + 7,
    r.w - 18,
    fh - 14,
    base: Warm.woodBase,
    light: Warm.woodLight,
    dark: Warm.woodShade,
  );
  // Paper stack and a pen cup.
  paintPapers(b, r.x + 28, r.y - 4, 14, 6);
  b.fill(r.x + 50, r.y - 6, 6, 7, Warm.slateBase);
  b.vline(r.x + 50, r.y - 6, 7, Warm.slateLight);
  b.vline(r.x + 55, r.y - 6, 7, Warm.slateDark);
  b.vline(r.x + 51, r.y - 10, 4, Warm.amber);
  b.vline(r.x + 53, r.y - 9, 3, Warm.teal);
}

/// Mailbox on a post. The red flag is up when a report is waiting.
void paintMailbox(PixelBuffer b, IRect r, {required bool flagUp}) {
  final cx = r.centerX;
  b.fill(cx - 2, r.bottom - 1, 4, 26, Warm.woodShade);
  b.vline(cx - 2, r.bottom - 1, 26, Warm.woodBase);
  b.vline(cx + 1, r.bottom - 1, 26, Warm.woodDark);
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Warm.steelBase,
    light: Warm.steelLight,
    dark: Warm.steelShade,
    rounded: true,
  );
  b.roundRing(r.x, r.y, r.w, r.h, Warm.steelOutline);
  b.hline(r.x + 2, r.y + 1, r.w - 4, Warm.steelLight);
  b.vline(r.x + 5, r.y + 2, r.h - 4, Warm.steelShade);
  b.vline(r.x + 6, r.y + 2, r.h - 4, Warm.steelLight);
  b.fill(r.x + 2, r.y + r.h ~/ 2 - 1, 2, 2, Warm.amber);
  if (flagUp) {
    b.fill(r.right - 5, r.y - 8, 3, 10, Warm.red);
    b.vline(r.right - 5, r.y - 8, 10, PixelBuffer.lightOf(Warm.red));
    b.set(r.right - 3, r.y - 8, Warm.redDark);
    b.hline(r.right - 5, r.y - 8, 3, Warm.redDark);
    b.set(r.right - 4, r.y - 9, Warm.red);
  } else {
    b.fill(r.right - 2, r.y + 5, 8, 3, Warm.red);
    b.hline(r.right - 2, r.y + 5, 8, PixelBuffer.lightOf(Warm.red));
    b.set(r.right + 5, r.y + 7, Warm.redDark);
  }
}

// ---- desk props -------------------------------------------------------------

/// 22x6 keyboard with two rows of keys.
void paintKeyboard(PixelBuffer b, int x, int y) {
  b.shadeRect(
    x,
    y,
    22,
    6,
    base: Warm.slateBase,
    light: Warm.slateLight,
    dark: Warm.slateDark,
    rounded: true,
  );
  for (var i = 0; i < 9; i++) {
    b.set(x + 2 + i * 2, y + 2, Warm.slateLight);
    b.set(x + 3 + i * 2, y + 4, Warm.slateLight);
  }
  b.hline(x + 6, y + 4, 8, Warm.slateLight);
  b.hline(x, y + 6, 22, PixelBuffer.shadowOf(Warm.woodLight));
}

/// Mouse beside the keyboard.
void paintMouse(PixelBuffer b, int x, int y) {
  b.roundFill(x, y, 5, 7, Warm.cream);
  b.vline(x + 4, y + 1, 5, Warm.creamShade);
  b.hline(x + 1, y + 6, 3, Warm.creamShade);
  b.hline(x + 1, y + 2, 3, Warm.creamDark);
  b.hline(x + 1, y + 7, 4, PixelBuffer.shadowOf(Warm.woodLight));
}

/// Paper tray, 14x4, with a sheet in it.
void paintTray(PixelBuffer b, int x, int y) {
  b.fill(x + 1, y - 2, 12, 2, Warm.paper);
  b.hline(x + 1, y - 2, 12, Warm.paperShade);
  b.shadeRect(
    x,
    y,
    14,
    4,
    base: Warm.steelShade,
    light: Warm.steelLight,
    dark: Warm.steelDark,
  );
  b.hline(x + 1, y + 4, 14, PixelBuffer.shadowOf(Warm.woodLight));
}

/// Stack of papers, [w] x [h], lined.
void paintPapers(PixelBuffer b, int x, int y, int w, int h) {
  b.fill(x + 1, y + 1, w, h, Warm.paperShade);
  b.fill(x, y, w, h, Warm.paper);
  b.vline(x + w - 1, y, h, Warm.paperShade);
  b.hline(x, y + h - 1, w, Warm.paperShade);
  b.hline(x + 2, y + 2, w - 6, Warm.paperLine);
  if (h > 4) b.hline(x + 2, y + 4, w - 8, Warm.paperLine);
  b.hline(x + 1, y + h + 1, w, PixelBuffer.shadowOf(Warm.woodLight));
}

/// Mug, 7x7 with a handle on the right and a coloured stripe.
void paintMug(PixelBuffer b, int x, int y, {int stripe = Warm.teal}) {
  b.fill(x, y, 6, 7, Warm.cream);
  b.vline(x, y, 7, PixelBuffer.lightOf(Warm.cream));
  b.vline(x + 5, y, 7, Warm.creamMug);
  b.hline(x, y + 6, 6, Warm.creamDark);
  b.hline(x, y, 6, Warm.creamMug);
  b.hline(x, y + 2, 6, stripe);
  b.set(x + 6, y + 1, Warm.creamDark);
  b.set(x + 7, y + 2, Warm.creamDark);
  b.set(x + 7, y + 3, Warm.creamDark);
  b.set(x + 6, y + 4, Warm.creamDark);
  b.hline(x + 1, y + 7, 6, PixelBuffer.shadowOf(Warm.woodLight));
}

/// Rising steam over a mug at (x, y) (top-left of the mug); [frame] 0-3.
void paintMugSteam(PixelBuffer b, int x, int y, int frame) {
  final cx = x + 3;
  switch (frame % 4) {
    case 0:
      b.set(cx, y - 2, Warm.steam);
      b.set(cx + 1, y - 4, Warm.steam);
    case 1:
      b.set(cx - 1, y - 3, Warm.steam);
      b.set(cx + 1, y - 5, Warm.steam);
    case 2:
      b.set(cx, y - 4, Warm.steam);
      b.set(cx - 1, y - 6, Warm.steam);
    case 3:
      b.set(cx + 1, y - 3, Warm.steam);
      b.set(cx, y - 6, Warm.steam);
  }
}

/// Desk lamp: (x, y) is the bottom-centre of the base on the desk top. The
/// shade leans left over the desk; [lit] adds a glow and a light pool.
void paintDeskLamp(PixelBuffer b, int x, int y, {bool lit = true}) {
  if (lit) {
    b.lightPool(x - 9, y - 1, 14, 4, tint: Warm.lampGlow, strength: 0.5);
  }
  b.shadeRect(
    x - 4,
    y - 3,
    9,
    3,
    base: Warm.slateBase,
    light: Warm.slateLight,
    dark: Warm.slateDark,
    rounded: true,
  );
  b.hline(x - 3, y, 9, PixelBuffer.shadowOf(Warm.woodLight));
  b.vline(x, y - 15, 12, Warm.slateShade);
  b.vline(x + 1, y - 15, 12, Warm.slateDark);
  b.line(x, y - 15, x - 6, y - 20, Warm.slateShade);
  b.line(x + 1, y - 15, x - 5, y - 20, Warm.slateDark);
  // Shade: a trapezoid opening down-left.
  for (var i = 0; i < 7; i++) {
    final sy = y - 26 + i;
    final sw = 8 + i * 2;
    final sx = x - 12 - i + 1;
    b.hline(sx, sy, sw, Warm.amber);
    b.set(sx, sy, Warm.amberDark);
    b.set(sx + sw - 1, sy, Warm.amberDark);
  }
  b.hline(x - 11, y - 26, 8, Warm.amberLight);
  b.hline(x - 18, y - 19, 20, Warm.amberDark);
  b.hline(x - 16, y - 18, 16, lit ? Warm.lampGlow : Warm.slateShade);
  if (lit) {
    b.hline(
      x - 17,
      y - 17,
      18,
      PixelBuffer.mix(Warm.lampGlow, Warm.amber, 0.5),
    );
  }
}
