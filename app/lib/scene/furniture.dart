import 'dart:math' as math;

import 'lighting.dart';
import 'palette.dart';
import 'pixel.dart';
import 'scene_layout.dart';

/// Furniture and fixtures. Each painter takes scene-pixel rects from
/// [SceneLayout] so the layout file stays the single source of positions.
/// Light comes from the window (upper left): highlights top-left, shades
/// bottom-right, drop shadows down and to the right. Everything is drawn in
/// the daylight palette; the [SceneLighting] tint on the buffer turns it into
/// night, and the few things that give off light are drawn with
/// [PixelBuffer.emissive].

// ---- window wall ----------------------------------------------------------

/// Big window: cream frame, the view (a sky for the [SceneLighting], far
/// hills and the same small city by day and by night), glass reflections, a
/// cross mullion and a sill with a small cactus.
void paintWindow(PixelBuffer b, IRect r, SceneLighting lighting) {
  // Architrave.
  b.ring(r.x - 7, r.y - 7, r.w + 14, r.h + 14, Palette.creamOutline);
  b.shadeRect(
    r.x - 6,
    r.y - 6,
    r.w + 12,
    r.h + 12,
    base: Palette.creamBase,
    light: Palette.creamLight,
    dark: Palette.creamShade,
    bevel: 2,
  );
  b.ring(r.x - 1, r.y - 1, r.w + 2, r.h + 2, Palette.creamDark);

  // The view is lit from outside: never tinted by the room.
  b.emissive(() {
    switch (lighting.sky) {
      case SkyKind.daylight:
        _paintDaySky(b, r);
      case SkyKind.night:
        _paintNightSky(b, r);
    }
  });

  // Glass reflections in the two upper panes.
  final glint = lighting.sky == SkyKind.daylight
      ? PixelBuffer.lightOf
      : _moonGlint;
  void streak(int x0, int y0, int len) {
    for (var i = 0; i < len; i++) {
      final x = x0 + i;
      final y = y0 - i;
      if (x >= r.x && x < r.right && y >= r.y && y < r.bottom) {
        b.set(x, y, glint(b.get(x, y)));
      }
    }
  }

  b.emissive(() {
    streak(r.x + 3, r.y + 22, 20);
    streak(r.x + 3, r.y + 27, 12);
    streak(r.centerX + 5, r.y + 20, 16);
  });

  // Mullions.
  final mx = r.centerX - 2;
  final my = r.y + (r.h * 0.46).round() - 2;
  b.shadeRect(
    mx,
    r.y,
    4,
    r.h,
    base: Palette.creamBase,
    light: Palette.creamLight,
    dark: Palette.creamShade,
  );
  b.shadeRect(
    r.x,
    my,
    r.w,
    4,
    base: Palette.creamBase,
    light: Palette.creamLight,
    dark: Palette.creamShade,
  );
  b.set(mx + 3, my + 3, Palette.creamDark);

  // Sill.
  final sillX = r.x - 10;
  final sillW = r.w + 20;
  final sillY = r.bottom + 6;
  b.shadeRect(
    sillX,
    sillY,
    sillW,
    6,
    base: Palette.creamBase,
    light: Palette.creamLight,
    dark: Palette.creamShade,
  );
  b.hline(sillX, sillY + 6, sillW, Palette.creamOutline);
  b.modify(sillX + 1, sillY + 7, sillW, 2, b.toward(Palette.wallDark, 0.55));
  b.modify(
    sillX + 2,
    sillY + 9,
    sillW,
    1,
    b.toward(Palette.wallDark, 0.55),
    checker: true,
  );

  // Cactus in a small pot on the sill.
  final cx = r.x + 12;
  b.shadeRect(
    cx - 4,
    sillY - 7,
    9,
    7,
    base: Palette.potBase,
    light: Palette.potLight,
    dark: Palette.potDark,
  );
  b.hline(cx - 5, sillY - 8, 11, Palette.potLight);
  b.hline(cx - 5, sillY - 9, 11, Palette.potDark);
  b.fill(cx - 1, sillY - 18, 3, 9, Palette.leafBase);
  b.vline(cx - 1, sillY - 18, 9, Palette.leafLight);
  b.vline(cx + 1, sillY - 17, 8, Palette.leafDark);
  b.fill(cx - 4, sillY - 15, 2, 4, Palette.leafBase);
  b.hline(cx - 4, sillY - 13, 3, Palette.leafBase);
  b.fill(cx + 3, sillY - 14, 2, 3, Palette.leafBase);
  b.hline(cx + 2, sillY - 12, 2, Palette.leafBase);
  b.set(cx, sillY - 19, Palette.pink);
}

int _moonGlint(int c) => PixelBuffer.mix(c, 0xFFDCE8FF, 0.3);

/// Skyline shared by both skies, relative to the window's left edge and
/// its ground line: (x, width, height). A far row of taller blocks and a
/// near row in front of it.
const List<(int, int, int)> _farBuildings = [
  (0, 10, 22), (9, 14, 18), (24, 11, 14), (36, 7, 26), (46, 9, 20), //
  (56, 12, 16), (64, 8, 24), (74, 13, 17), (84, 10, 21), (96, 8, 12),
];
const List<(int, int, int)> _nearBuildings = [
  (2, 9, 16), (13, 7, 12), (22, 12, 20), (37, 8, 9), (47, 10, 15), //
  (60, 6, 11), (68, 11, 18), (82, 8, 13), (92, 12, 10),
];

int _windowHash(int x, int y) {
  var h = x * 73856093 ^ y * 19349663;
  h = (h ^ (h >> 13)) * 1274126177;
  return (h ^ (h >> 16)) & 0x7FFFFFFF;
}

/// Hills behind the city: a far ridge and a near one.
void _paintHills(PixelBuffer b, IRect r, int ground, int far, int near) {
  for (var x = r.x; x < r.right; x++) {
    final fy =
        ground - 26 + (3.5 * math.sin(x / 9.0) + 2 * math.sin(x / 4.3)).round();
    b.vline(x, fy, ground - fy, far);
    final ny =
        ground -
        15 +
        (4 * math.sin(x / 13.0 + 1.2) + 2 * math.cos(x / 5.1)).round();
    b.vline(x, ny, ground - ny, near);
  }
}

/// Daylight: blue sky, a high sun, three clouds, green hills and the city
/// in pale haze.
void _paintDaySky(PixelBuffer b, IRect r) {
  b.gradient(r.x, r.y, r.w, r.h, const [
    Palette.daySkyTop,
    Palette.daySkyHigh,
    Palette.daySkyMid,
    Palette.daySkyLow,
  ], (x, y) => (y - r.y) / r.h * 3.2 - 0.1);

  // Sun high in the left pane with a dithered halo.
  final sx = r.x + (r.w * 0.3).round();
  final sy = r.y + (r.h * 0.2).round();
  for (var y = sy - 12; y <= sy + 12; y++) {
    for (var x = sx - 12; x <= sx + 12; x++) {
      if (x < r.x || x >= r.right || y < r.y || y >= r.bottom) continue;
      final d = (x - sx) * (x - sx) + (y - sy) * (y - sy);
      if (d <= 40) {
        b.set(x, y, Palette.sun);
      } else if (d <= 62) {
        b.set(x, y, Palette.sunRim);
      } else if (d <= 120 && ((x + y) & 1) == 0) {
        b.set(x, y, Palette.sunHalo);
      }
    }
  }

  // Clouds: flat puffs, lit on top and shaded underneath.
  _cloud(b, r, r.x + 52, r.y + 14, 13, 4);
  _cloud(b, r, r.x + 14, r.y + 38, 10, 3);
  _cloud(b, r, r.x + 68, r.y + 40, 8, 3);

  final ground = r.bottom - 4;
  _paintHills(b, r, ground, Palette.dayHillFar, Palette.dayHillNear);
  for (final (bx, bw, bh) in _farBuildings) {
    if (r.x + bx >= r.right) continue;
    b.fill(r.x + bx, ground - bh, bw, bh, Palette.dayBuildingFar);
  }
  for (final (bx, bw, bh) in _nearBuildings) {
    final x0 = r.x + bx;
    if (x0 >= r.right) continue;
    final y0 = ground - bh;
    b.fill(x0, y0, bw, bh, Palette.dayBuilding);
    b.vline(x0, y0, bh, Palette.dayBuildingLight);
    b.hline(x0, y0, bw, Palette.dayBuildingLight);
    for (var wy = y0 + 2; wy < ground - 1; wy += 3) {
      for (var wx = x0 + 2; wx < x0 + bw - 1; wx += 2) {
        if (_windowHash(wx, wy) % 5 < 3) b.set(wx, wy, Palette.dayWindow);
      }
    }
  }
  b.fill(r.x, ground, r.w, r.bottom - ground, Palette.dayGround);
  b.hline(r.x, ground, r.w, Palette.dayHillNear);
}

/// One cloud: an ellipse of radii (rx, ry) plus a smaller puff on top,
/// clipped to the glass.
void _cloud(PixelBuffer b, IRect r, int cx, int cy, int rx, int ry) {
  void put(int x, int y, int c) {
    if (x >= r.x && x < r.right && y >= r.y && y < r.bottom) b.set(x, y, c);
  }

  for (final (dx, dy) in _ellipsePixels(rx, ry)) {
    put(cx + dx, cy + dy, dy >= ry - 1 ? Palette.cloudShade : Palette.cloud);
  }
  for (final (dx, dy) in _ellipsePixels(rx ~/ 2, ry)) {
    put(cx + dx - rx ~/ 4, cy + dy - ry, Palette.cloud);
  }
  put(cx - rx, cy + ry - 1, Palette.cloudShade);
}

List<(int, int)> _ellipsePixels(int rx, int ry) {
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

/// Night: a starry gradient, a moon with a halo in the right pane, dark
/// hills and the same city with its windows lit.
void _paintNightSky(PixelBuffer b, IRect r) {
  b.gradient(r.x, r.y, r.w, r.h, const [
    Palette.nightSkyTop,
    Palette.nightSkyMid,
    Palette.nightSkyLow,
  ], (x, y) => (y - r.y) / r.h * 2.6 - 0.3);

  const stars = <(int, int)>[
    (6, 5), (14, 11), (22, 3), (31, 8), (40, 14), (48, 4), (57, 10), //
    (66, 6), (75, 13), (84, 3), (93, 9), (11, 20), (36, 22), (60, 19),
    (89, 23), (20, 28), (70, 30), (45, 33), (96, 34), (8, 44), (30, 40),
  ];
  for (var i = 0; i < stars.length; i++) {
    final (sx, sy) = stars[i];
    if (sx >= r.w - 1 || sy >= r.h) continue;
    b.set(r.x + sx, r.y + sy, i % 3 == 0 ? Palette.star : Palette.starDim);
  }

  // Moon with a dithered halo.
  final mx = r.x + r.w - 24;
  final my = r.y + 20;
  for (final (dx, dy) in PixelBuffer.discPixels(12)) {
    final d2 = dx * dx + dy * dy;
    final x = mx + dx;
    final y = my + dy;
    if (x < r.x || x >= r.right || y < r.y || y >= r.bottom) continue;
    if (d2 > 64 && ((x + y) & 1) == 0) {
      b.set(x, y, PixelBuffer.mix(b.get(x, y), Palette.moon, 0.22));
    } else if (d2 > 49 && d2 <= 64) {
      b.set(x, y, PixelBuffer.mix(b.get(x, y), Palette.moon, 0.3));
    }
  }
  b.disc(mx, my, 7, Palette.moon);
  for (final (dx, dy) in PixelBuffer.discPixels(7)) {
    if (dx + dy > 5) b.set(mx + dx, my + dy, Palette.moonShade);
  }
  b.set(mx - 2, my - 1, Palette.moonShade);
  b.hline(mx + 1, my + 2, 2, Palette.moonShade);
  b.set(mx - 3, my + 3, Palette.moonShade);

  final ground = r.bottom - 4;
  _paintHills(b, r, ground, Palette.nightHillFar, Palette.nightHillNear);
  for (final (bx, bw, bh) in _farBuildings) {
    if (r.x + bx >= r.right) continue;
    b.fill(r.x + bx, ground - bh, bw, bh, Palette.nightBuildingFar);
  }
  for (final (bx, bw, bh) in _nearBuildings) {
    final x0 = r.x + bx;
    if (x0 >= r.right) continue;
    final y0 = ground - bh;
    b.fill(x0, y0, bw, bh, Palette.nightBuilding);
    b.vline(x0, y0, bh, Palette.nightBuildingFar);
    for (var wy = y0 + 2; wy < ground - 1; wy += 3) {
      for (var wx = x0 + 1; wx < x0 + bw - 1; wx += 2) {
        final h = _windowHash(wx, wy);
        if (h % 5 < 2) {
          b.set(wx, wy, h % 3 == 0 ? Palette.cityTeal : Palette.cityWarm);
        }
      }
    }
  }
  // Antenna with a red beacon on the tallest block.
  b.vline(r.x + 39, ground - 30, 4, Palette.nightBuildingFar);
  b.set(r.x + 39, ground - 31, Palette.red);
  b.fill(r.x, ground, r.w, r.bottom - ground, Palette.nightGround);
}

/// Curtain rod with finials and a few rings.
void paintCurtainRod(PixelBuffer b, int x, int y, int w) {
  b.hline(x, y, w, Palette.woodShade);
  b.hline(x, y + 1, w, Palette.woodDark);
  b.hline(x + 1, y, w - 2, Palette.woodBase);
  b.fill(x - 2, y - 1, 3, 4, Palette.woodDark);
  b.fill(x + w - 1, y - 1, 3, 4, Palette.woodDark);
  b.set(x - 2, y - 1, Palette.woodBase);
  b.set(x + w - 1, y - 1, Palette.woodBase);
}

/// Hanging curtain with vertical folds and a tie-back, in the lighting's
/// curtain tones.
void paintCurtain(
  PixelBuffer b,
  IRect r,
  SceneLighting lighting, {
  required bool left,
}) {
  final fold = [
    lighting.curtainLight,
    lighting.curtainBase,
    lighting.curtainBase,
    lighting.curtainDark,
    lighting.curtainDark,
    lighting.curtainBase,
  ];
  for (var i = 0; i < r.w; i++) {
    final c = fold[(i + (left ? 1 : 4)) % fold.length];
    b.vline(r.x + i, r.y, r.h, c);
  }
  b.vline(left ? r.x : r.right - 1, r.y, r.h, lighting.curtainOutline);
  b.hline(r.x, r.bottom - 1, r.w, lighting.curtainOutline);
  b.hline(r.x, r.y, r.w, lighting.curtainDark);
  // Tie-back band.
  final ty = r.y + (r.h * 0.62).round();
  b.fill(r.x + 1, ty, r.w - 2, 3, Palette.amberDark);
  b.hline(r.x + 1, ty, r.w - 2, Palette.amber);
  // Rings.
  for (var x = r.x + 2; x < r.right - 1; x += 4) {
    b.set(x, r.y - 1, Palette.amber);
  }
}

/// String lights along the top of the back wall, right of the curtain rod:
/// a wire sagging between hooks and a bulb every twelve pixels. Lit bulbs
/// alternate warm and cool, one in four dimming by [frame], and throw a
/// small glow on the wall; unlit ones are plain glass.
void paintStringLights(PixelBuffer b, SceneLighting lighting, int frame) {
  const x0 = SceneLayout.stringLightsX;
  const hookGap = 60;
  int wireY(int x) {
    final t = ((x - x0) % hookGap) / hookGap;
    return SceneLayout.stringLightsY + (5 * math.sin(math.pi * t)).round();
  }

  for (var x = x0; x < SceneLayout.width; x++) {
    b.set(x, wireY(x), Palette.ink);
  }
  for (var x = x0; x < SceneLayout.width; x += hookGap) {
    b.fill(x - 1, SceneLayout.stringLightsY - 2, 2, 3, Palette.steelShade);
  }
  var i = 0;
  for (var x = x0 + 6; x < SceneLayout.width - 2; x += 12, i++) {
    final y = wireY(x);
    final warm = i.isEven;
    if (lighting.stringLightsOn) {
      final dim = (i + frame) % 4 == 0;
      final color = dim
          ? (warm ? Palette.amber : Palette.starDim)
          : (warm ? Palette.bulbWarm : Palette.bulbCool);
      b.lightPool(
        x + 1,
        y + 3,
        6,
        5,
        tint: warm ? Palette.bulbWarm : Palette.bulbCool,
        strength: dim ? 0.18 : 0.32,
      );
      b.emissive(() => _bulb(b, x, y, color));
    } else {
      _bulb(b, x, y, Palette.steelLight);
      b.set(x + 1, y + 3, Palette.steelBase);
    }
  }
}

void _bulb(PixelBuffer b, int x, int y, int color) {
  b.fill(x, y + 1, 2, 1, Palette.ink);
  b.fill(x, y + 2, 2, 2, color);
  b.set(x - 1, y + 3, color);
  b.set(x + 2, y + 3, color);
  b.fill(x, y + 4, 2, 1, color);
}

/// Door with an architrave, a frosted glass pane, two recessed panels, a
/// brass knob and a steel kick plate.
void paintDoor(PixelBuffer b, IRect r) {
  // Architrave (no bottom: the leaf meets the skirting).
  b.hline(r.x - 6, r.y - 6, r.w + 12, Palette.creamOutline);
  b.vline(r.x - 6, r.y - 6, r.h + 6, Palette.creamOutline);
  b.vline(r.right + 5, r.y - 6, r.h + 6, Palette.creamOutline);
  b.shadeRect(
    r.x - 5,
    r.y - 5,
    r.w + 10,
    r.h + 5,
    base: Palette.creamBase,
    light: Palette.creamLight,
    dark: Palette.creamShade,
    bevel: 2,
  );
  // Leaf.
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Palette.woodBase,
    light: Palette.woodLight,
    dark: Palette.woodShade,
    bevel: 2,
  );
  b.vline(r.x, r.y, r.h, Palette.woodOutline);
  b.hline(r.x, r.y, r.w, Palette.woodOutline);
  b.vline(r.right - 1, r.y, r.h, Palette.woodDark);

  // Glass pane.
  final gx = r.x + 8;
  final gy = r.y + 9;
  final gw = r.w - 16;
  const gh = 32;
  b.ring(gx - 1, gy - 1, gw + 2, gh + 2, Palette.woodDark);
  b.hline(gx, gy + gh, gw, Palette.woodLight);
  b.vline(gx + gw, gy, gh, Palette.woodLight);
  b.gradient(gx, gy, gw, gh, const [
    Palette.creamLight,
    Palette.creamBase,
    Palette.creamShade,
  ], (x, y) => (y - gy) / gh * 2.2);
  for (var i = 0; i < 18; i++) {
    final x = gx + 3 + i;
    final y = gy + gh - 6 - i;
    if (x < gx + gw && y >= gy) b.set(x, y, Palette.creamLight);
    final x2 = gx + 8 + i;
    if (x2 < gx + gw && y >= gy) b.set(x2, y, Palette.creamLight);
  }

  // Panels.
  final py = gy + gh + 8;
  final ph = r.bottom - py - 12;
  final px = r.x + 8;
  final pw = r.w - 16;
  b.fill(px, py, pw, ph, Palette.woodShade);
  b.hline(px, py, pw, Palette.woodDark);
  b.vline(px, py, ph, Palette.woodDark);
  b.hline(px, py + ph - 1, pw, Palette.woodLight);
  b.vline(px + pw - 1, py, ph, Palette.woodLight);
  b.shadeRect(
    px + 3,
    py + 3,
    pw - 6,
    ph - 6,
    base: Palette.woodBase,
    light: Palette.woodLight,
    dark: Palette.woodShade,
  );

  // Knob on a brass plate.
  final kx = r.right - 9;
  final ky = r.y + 56;
  b.fill(kx - 1, ky - 2, 5, 8, Palette.amberDark);
  b.vline(kx - 1, ky - 2, 8, Palette.amber);
  b.fill(kx, ky, 3, 3, Palette.amber);
  b.set(kx, ky, Palette.amberLight);
  b.set(kx + 2, ky + 2, Palette.amberDark);
  b.set(kx + 1, ky + 4, Palette.woodOutline);

  // Kick plate.
  b.shadeRect(
    r.x + 3,
    r.bottom - 8,
    r.w - 6,
    6,
    base: Palette.steelBase,
    light: Palette.steelLight,
    dark: Palette.steelShade,
  );
}

// ---- back wall --------------------------------------------------------------

/// Whiteboard: aluminium frame with a bevel, a slight shadow on the wall, a
/// marker tray with two markers and an eraser. The face is drawn in the
/// lighting's [SceneLighting.lit] tint so it stays readable at night. Notes
/// are drawn on top by the painter.
void paintWhiteboard(PixelBuffer b, IRect r, SceneLighting lighting) {
  b.modify(
    r.x + 3,
    r.y + 3,
    r.w,
    r.h,
    b.toward(Palette.wallDark, 0.6),
    checker: true,
  );
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Palette.steelBase,
    light: Palette.steelLight,
    dark: Palette.steelShade,
    bevel: 2,
  );
  b.hline(r.x, r.bottom - 1, r.w, Palette.steelOutline);
  b.vline(r.right - 1, r.y, r.h, Palette.steelOutline);
  b.withTint(lighting.lit, () {
    b.fill(r.x + 4, r.y + 4, r.w - 8, r.h - 8, Palette.boardFace);
    b.hline(r.x + 4, r.y + 4, r.w - 8, Palette.boardShade);
    b.vline(r.x + 4, r.y + 4, r.h - 8, Palette.boardShade);
    b.hline(
      r.x + 5,
      r.y + 5,
      r.w - 10,
      PixelBuffer.mix(Palette.boardShade, Palette.boardFace, 0.5),
    );
    // Faint old smudges.
    b.hline(r.x + 30, r.bottom - 12, 9, Palette.boardShade);
    b.hline(r.x + 70, r.bottom - 10, 5, Palette.boardShade);
  });

  // Tray.
  final tx = r.x + 14;
  final ty = r.bottom - 2;
  final tw = r.w - 28;
  b.shadeRect(
    tx,
    ty,
    tw,
    5,
    base: Palette.steelShade,
    light: Palette.steelLight,
    dark: Palette.steelDark,
  );
  b.hline(tx, ty + 5, tw, Palette.steelOutline);
  // Markers and eraser.
  b.fill(tx + 6, ty - 2, 10, 3, Palette.red);
  b.hline(tx + 6, ty - 2, 8, PixelBuffer.lightOf(Palette.red));
  b.fill(tx + 14, ty - 2, 2, 3, Palette.redDark);
  b.fill(tx + 20, ty - 2, 10, 3, Palette.teal);
  b.hline(tx + 20, ty - 2, 8, Palette.tealLight);
  b.fill(tx + 28, ty - 2, 2, 3, Palette.tealDark);
  b.shadeRect(
    tx + tw - 18,
    ty - 3,
    12,
    4,
    base: Palette.slateBase,
    light: Palette.slateLight,
    dark: Palette.slateDark,
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
  b.fill(x + 1, y + 1, w, h, Palette.boardShade);
  b.fill(x, y, w, h, fill);
  b.hline(x, y, w, PixelBuffer.lightOf(fill));
  b.vline(x + w - 1, y, h, dark);
  b.hline(x, y + h - 1, w, dark);
  // Curled corner.
  b.set(x + w - 1, y + h - 1, Palette.boardFace);
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
    b.fill(cx - 1, y + 1, 3, 3, Palette.red);
    b.set(cx - 1, y + 1, PixelBuffer.lightOf(Palette.red));
    b.set(cx + 1, y + 3, Palette.redDark);
    b.set(cx, y + 4, Palette.ink);
  } else {
    final cx = x + w ~/ 2;
    b.fill(cx - 3, y - 1, 7, 3, PixelBuffer.mix(fill, Palette.boardFace, 0.55));
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
    b.toward(Palette.wallDark, 0.5),
    checker: true,
  );
  b.disc(cx, cy, 11, Palette.woodBase, outline: Palette.woodOutline);
  for (final (dx, dy) in PixelBuffer.discPixels(11)) {
    final d = dx * dx + dy * dy;
    if (d < 70) continue;
    if (dx + dy < -4) {
      b.set(cx + dx, cy + dy, Palette.woodLight);
    } else if (dx + dy > 4) {
      b.set(cx + dx, cy + dy, Palette.woodShade);
    }
  }
  b.disc(cx, cy, 8, Palette.paper);
  for (final (dx, dy) in PixelBuffer.discPixels(8)) {
    if (dx * dx + dy * dy >= 56 && dx + dy > 2) {
      b.set(cx + dx, cy + dy, Palette.paperShade);
    }
  }
  b.set(cx, cy - 7, Palette.ink);
  b.set(cx, cy + 7, Palette.ink);
  b.set(cx - 7, cy, Palette.ink);
  b.set(cx + 7, cy, Palette.ink);
  b.line(cx, cy, cx - 3, cy - 4, Palette.ink);
  b.line(cx, cy, cx + 3, cy - 6, Palette.ink);
  b.line(cx, cy, cx - 2, cy + 5, Palette.red);
  b.set(cx, cy, Palette.ink);
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
      b.toward(Palette.wallDark, 0.5),
      checker: true,
    );
    b.shadeRect(
      x,
      r.y,
      w,
      r.h,
      base: Palette.slateBase,
      light: Palette.slateLight,
      dark: Palette.slateDark,
      rounded: true,
    );
    b.fill(x + 3, r.y + 6, w - 6, r.h - 9, Palette.screenOff);
    final level = i < levels.length ? levels[i].clamp(0.0, 1.0) : 0.0;
    final maxH = r.h - 11;
    final lh = (maxH * level).round();
    b.emissive(() {
      if (lh > 0) {
        b.fill(x + 4, r.bottom - 4 - lh, w - 8, lh, accents[i]);
        b.hline(
          x + 4,
          r.bottom - 4 - lh,
          w - 8,
          PixelBuffer.lightOf(accents[i]),
        );
      }
      b.fill(x + 3, r.y + 2, w - 6, 2, level > 0 ? accents[i] : accentDarks[i]);
      b.set(x + 3, r.y + 2, PixelBuffer.lightOf(accents[i]));
    });
    b.vline(x + 3, r.y + 6, r.h - 9, Palette.screenGlint);
    for (var t = 0; t < 4; t++) {
      b.set(x + w - 4, r.y + 7 + t * 4, Palette.slateLight);
    }
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
    Palette.amberLight,
    Palette.amber,
    Palette.orange,
  ], (x, y) => (y - py) / ph * 2.4);
  b.disc(px + pw - 7, py + 5, 2, Palette.cream);
  for (var x = px; x < px + pw; x++) {
    final far = py + ph - 9 + (2 * math.sin(x / 3.0)).round();
    b.vline(x, far, py + ph - far, Palette.violetDark);
    final near = py + ph - 5 + (1.5 * math.cos(x / 2.2)).round();
    b.vline(x, near, py + ph - near, Palette.tealDark);
  }
}

/// Framed poster: three overlapping discs in the three agents' colours.
void paintPosterCircles(PixelBuffer b, IRect r) {
  _posterFrame(b, r);
  b.fill(r.x + 4, r.y + 4, r.w - 8, r.h - 8, Palette.paper);
  final cx = r.centerX;
  final cy = r.centerY;
  b.disc(cx - 4, cy - 5, 5, Palette.orange);
  b.disc(cx + 4, cy - 3, 5, Palette.teal);
  b.disc(cx, cy + 5, 5, Palette.violet);
  b.set(cx - 6, cy - 7, Palette.amberLight);
  b.set(cx + 2, cy - 5, Palette.tealLight);
  b.set(cx - 2, cy + 3, Palette.violetLight);
}

void _posterFrame(PixelBuffer b, IRect r) {
  b.modify(
    r.x + 2,
    r.y + 2,
    r.w,
    r.h,
    b.toward(Palette.wallDark, 0.5),
    checker: true,
  );
  b.fill(r.x, r.y, r.w, r.h, Palette.woodDark);
  b.hline(r.x, r.y, r.w, Palette.woodBase);
  b.vline(r.x, r.y, r.h, Palette.woodBase);
  b.hline(r.x, r.bottom - 1, r.w, Palette.woodOutline);
  b.vline(r.right - 1, r.y, r.h, Palette.woodOutline);
  b.fill(r.x + 2, r.y + 2, r.w - 4, r.h - 4, Palette.creamBase);
  b.hline(r.x + 2, r.y + 2, r.w - 4, Palette.creamShade);
  b.vline(r.x + 2, r.y + 2, r.h - 4, Palette.creamShade);
}

/// Steel filing cabinet with three drawers, label holders and handles, a
/// row of binders on top and a shadow on the wall.
void paintCabinet(PixelBuffer b, IRect r) {
  b.modify(
    r.x + 3,
    r.y + 3,
    r.w,
    r.h - 3,
    b.toward(Palette.wallDark, 0.6),
    checker: true,
  );
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Palette.steelBase,
    light: Palette.steelLight,
    dark: Palette.steelShade,
    rounded: true,
  );
  b.vline(r.right - 1, r.y + 1, r.h - 1, Palette.steelOutline);
  b.hline(r.x + 1, r.y + 1, r.w - 2, Palette.steelLight);
  final drawerH = (r.h - 5) ~/ 3;
  final cx = r.centerX;
  for (var i = 0; i < 3; i++) {
    final y = r.y + 3 + i * drawerH;
    b.hline(r.x + 1, y, r.w - 2, Palette.steelDark);
    b.hline(r.x + 2, y + 1, r.w - 4, Palette.steelLight);
    b.vline(r.x + 2, y + 1, drawerH - 1, Palette.steelLight);
    b.vline(r.right - 3, y + 1, drawerH - 1, Palette.steelShade);
    b.fill(cx - 5, y + 4, 10, 4, Palette.paper);
    b.hline(cx - 5, y + 7, 10, Palette.paperShade);
    b.hline(cx - 3, y + 5, 6, Palette.paperLine);
    b.fill(cx - 4, y + drawerH - 6, 8, 2, Palette.steelOutline);
    b.set(cx - 4, y + drawerH - 6, Palette.steelLight);
  }
  b.fill(r.x + 1, r.bottom - 3, r.w - 2, 3, Palette.steelDark);
  b.hline(r.x, r.bottom - 1, r.w, Palette.steelOutline);
  // Binders on top.
  const binders = [
    (Palette.teal, Palette.tealDark),
    (Palette.orange, Palette.orangeDark),
    (Palette.violet, Palette.violetDark),
    (Palette.amber, Palette.amberDark),
  ];
  for (var i = 0; i < binders.length; i++) {
    final (base, dark) = binders[i];
    final x = r.x + 5 + i * 6;
    b.fill(x, r.y - 9, 5, 9, base);
    b.vline(x + 4, r.y - 9, 9, dark);
    b.hline(x, r.y - 9, 4, PixelBuffer.lightOf(base));
    b.fill(x + 1, r.y - 6, 2, 2, Palette.paper);
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
  final base = back ? Palette.leafDark : Palette.leafBase;
  b.blob(_ellipse(rx, ry), base, outline: Palette.leafOutline, x: cx, y: cy);
  if (back) return;
  for (final (dx, dy) in _ellipse(rx, ry)) {
    if (dx + dy * 2 <= -(rx ~/ 2 + 1)) {
      b.set(cx + dx, cy + dy, Palette.leafLight);
    } else if (dx + dy * 2 >= rx + 1) {
      b.set(cx + dx, cy + dy, Palette.leafDark);
    }
  }
  b.line(cx - rx ~/ 2, cy, cx + rx ~/ 2, cy, Palette.leafDark);
}

/// Terracotta pot: lip, body with a lit left side, dark soil.
void _pot(PixelBuffer b, int x, int y, int w, int h) {
  b.fill(x + 1, y + 2, w - 2, h - 2, Palette.potBase);
  b.vline(x + 1, y + 2, h - 2, Palette.potLight);
  b.vline(x + 2, y + 2, h - 3, Palette.potLight);
  b.fill(x + w - 3, y + 2, 2, h - 2, Palette.potDark);
  b.vline(x, y + 2, h - 3, Palette.potDark);
  b.vline(x + w - 1, y + 2, h - 3, Palette.potDark);
  b.hline(x + 1, y + h - 1, w - 2, Palette.potDark);
  b.shadeRect(
    x - 1,
    y,
    w + 2,
    3,
    base: Palette.potBase,
    light: Palette.potLight,
    dark: Palette.potDark,
  );
  b.hline(x - 1, y + 3, w + 2, Palette.potDark);
}

/// Small desk plant: pot ends at y + 22.
void paintDeskPlant(PixelBuffer b, int x, int y) {
  _pot(b, x + 3, y + 13, 10, 9);
  b.fill(x + 4, y + 13, 8, 1, Palette.soil);
  b.vline(x + 7, y + 6, 8, Palette.leafDark);
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
  b.fill(x + 5, y + 46, 16, 1, Palette.soil);
  b.vline(x + 12, y + 22, 24, Palette.leafDark);
  b.vline(x + 13, y + 22, 24, Palette.leafOutline);
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
    b.toward(Palette.wallDark, 0.5),
    checker: true,
  );
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Palette.woodBase,
    light: Palette.woodLight,
    dark: Palette.woodDark,
  );
  b.hline(r.x, r.bottom, r.w, Palette.woodOutline);
  for (final bx in [r.x + 3, r.right - 5]) {
    b.vline(bx, r.bottom + 1, 3, Palette.woodDark);
    b.set(bx + 1, r.bottom + 1, Palette.woodDark);
  }
  // Pot and vine.
  _pot(b, r.x + 10, r.y - 9, 9, 9);
  b.hline(r.x + 11, r.y - 9, 7, Palette.soil);
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
      Palette.leafDark,
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
    b.toward(Palette.wallDark, 0.6),
    checker: true,
  );
  b.modify(
    machine.x + 3,
    machine.y + 3,
    machine.w,
    machine.h - 3,
    b.toward(Palette.wallDark, 0.6),
    checker: true,
  );
  // Worktop.
  b.shadeRect(
    counter.x - 2,
    counter.y,
    counter.w + 4,
    7,
    base: Palette.woodLight,
    light: Palette.creamLight,
    dark: Palette.woodBase,
  );
  b.hline(counter.x - 2, counter.y + 6, counter.w + 4, Palette.woodShade);
  b.hline(counter.x - 2, counter.y + 7, counter.w + 4, Palette.woodOutline);
  // Body and cupboards.
  b.fill(counter.x, counter.y + 8, counter.w, counter.h - 8, Palette.woodShade);
  b.vline(counter.x, counter.y + 8, counter.h - 8, Palette.woodOutline);
  b.vline(counter.right - 1, counter.y + 8, counter.h - 8, Palette.woodOutline);
  final doorW = counter.w ~/ 2 - 6;
  for (final dx in [counter.x + 4, counter.x + counter.w ~/ 2 + 2]) {
    final dy = counter.y + 11;
    final dh = counter.h - 17;
    b.shadeRect(
      dx,
      dy,
      doorW,
      dh,
      base: Palette.woodBase,
      light: Palette.woodLight,
      dark: Palette.woodDark,
    );
    b.fill(dx + 3, dy + 3, doorW - 6, dh - 6, Palette.woodShade);
    b.hline(dx + 3, dy + dh - 4, doorW - 6, Palette.woodLight);
    b.vline(dx + doorW - 4, dy + 3, dh - 6, Palette.woodLight);
    b.hline(dx + 3, dy + 3, doorW - 6, Palette.woodDark);
    b.vline(dx + 3, dy + 3, dh - 6, Palette.woodDark);
  }
  final hx = counter.x + counter.w ~/ 2;
  b.fill(hx - 7, counter.y + 22, 2, 6, Palette.amber);
  b.fill(hx + 5, counter.y + 22, 2, 6, Palette.amber);
  b.set(hx - 7, counter.y + 22, Palette.amberLight);
  b.set(hx + 5, counter.y + 22, Palette.amberLight);
  b.fill(counter.x, counter.bottom - 3, counter.w, 3, Palette.woodDark);
  b.hline(counter.x, counter.bottom - 1, counter.w, Palette.woodOutline);

  // Mug stack.
  for (var i = 0; i < 3; i++) {
    final mx = counter.x + 8 + i * 3;
    final my = counter.y - 7 + i * 2;
    paintMug(b, mx, my, stripe: i.isEven ? Palette.teal : Palette.orange);
  }
  // Fruit bowl.
  final bx = counter.right - 26;
  final by = counter.y - 4;
  b.fill(bx + 1, by + 1, 14, 3, Palette.woodDark);
  b.hline(bx, by, 16, Palette.woodShade);
  b.hline(bx + 2, by + 4, 12, Palette.woodOutline);
  b.disc(bx + 4, by - 1, 2, Palette.orange, outline: Palette.orangeDark);
  b.disc(bx + 11, by - 1, 2, Palette.orange, outline: Palette.orangeDark);
  b.disc(bx + 8, by - 3, 2, Palette.amber, outline: Palette.amberDark);
  b.set(bx + 3, by - 2, Palette.amberLight);
  b.set(bx + 7, by - 4, Palette.amberLight);
  b.set(bx + 10, by - 2, Palette.amberLight);
}

/// Coffee machine on the counter; [frame] drives the steam puff.
void paintCoffeeMachine(PixelBuffer b, IRect m, int frame) {
  b.shadeRect(
    m.x,
    m.y,
    m.w,
    m.h,
    base: Palette.slateBase,
    light: Palette.slateLight,
    dark: Palette.slateDark,
    rounded: true,
  );
  b.roundRing(m.x, m.y, m.w, m.h, Palette.slateDark);
  b.hline(m.x + 1, m.y + 1, m.w - 2, Palette.slateLight);
  b.fill(m.x + 2, m.y + 3, m.w - 4, 2, Palette.steelBase);
  b.hline(m.x + 2, m.y + 3, m.w - 4, Palette.steelLight);
  // Panel: red and green LEDs and a dial.
  b.emissive(() {
    b.fill(m.x + 4, m.y + 8, 2, 2, Palette.red);
    b.set(m.x + 4, m.y + 8, PixelBuffer.lightOf(Palette.red));
    b.fill(m.x + 7, m.y + 8, 2, 2, Palette.green);
  });
  b.disc(m.right - 6, m.y + 9, 2, Palette.steelBase, outline: Palette.slateDark);
  b.set(m.right - 7, m.y + 8, Palette.steelLight);
  // Brew head and recess.
  b.fill(m.x + 3, m.y + 14, m.w - 6, m.h - 19, Palette.slateDark);
  b.hline(m.x + 3, m.y + 14, m.w - 6, Palette.slateShade);
  b.fill(m.centerX - 2, m.y + 14, 4, 3, Palette.steelShade);
  b.fill(m.centerX - 1, m.y + 17, 2, 2, Palette.steelDark);
  // Drip tray.
  b.fill(m.x + 3, m.bottom - 5, m.w - 6, 3, Palette.steelShade);
  b.hline(m.x + 3, m.bottom - 5, m.w - 6, Palette.steelLight);
  b.hline(m.x + 1, m.bottom - 2, m.w - 2, Palette.slateDark);
  // Cup under the spout.
  paintMug(b, m.centerX - 3, m.bottom - 11, stripe: Palette.orange);
  // Steam.
  final cx = m.centerX;
  final cy = m.bottom - 12;
  switch (frame % 4) {
    case 0:
      b.set(cx, cy, Palette.steam);
    case 1:
      b.set(cx - 1, cy - 1, Palette.steam);
      b.set(cx + 1, cy - 2, Palette.steam);
    case 2:
      b.set(cx - 1, cy - 2, Palette.steam);
      b.set(cx, cy - 3, Palette.steam);
      b.set(cx + 1, cy - 1, Palette.steam);
    case 3:
      b.set(cx, cy - 4, Palette.steam);
      b.set(cx + 1, cy - 3, Palette.steam);
  }
}

/// Stool: round padded seat on three legs with a foot ring.
void paintStool(PixelBuffer b, IRect s) {
  b.ellipseShadow(s.centerX + 1, s.bottom, s.w ~/ 2 + 1, 2);
  b.vline(s.x + 3, s.y + 4, s.h - 4, Palette.woodDark);
  b.vline(s.right - 4, s.y + 4, s.h - 4, Palette.woodDark);
  b.vline(s.centerX, s.y + 4, s.h - 5, Palette.woodShade);
  b.hline(s.x + 3, s.y + s.h - 6, s.w - 6, Palette.woodShade);
  b.shadeRect(
    s.x,
    s.y,
    s.w,
    5,
    base: Palette.curtainBase,
    light: Palette.curtainLight,
    dark: Palette.curtainDark,
    rounded: true,
  );
  b.hline(s.x + 1, s.y + 5, s.w - 2, Palette.curtainOutline);
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
    base: Palette.woodLight,
    light: Palette.creamLight,
    dark: Palette.woodBase,
  );
  b.hline(r.x, r.y + surfaceH - 1, r.w, Palette.woodShade);
  b.vline(r.x, r.y, surfaceH, Palette.woodBase);
  // Front.
  final fy = r.y + surfaceH;
  final fh = r.h - surfaceH;
  b.fill(r.x, fy, r.w, fh, Palette.woodBase);
  b.hline(r.x, fy, r.w, Palette.woodDark);
  b.hline(r.x, fy + 1, r.w, Palette.woodShade);
  b.fill(r.x, fy + fh ~/ 2, r.w, fh - fh ~/ 2, Palette.woodShade);
  b.checker(r.x, fy + fh ~/ 2 - 1, r.w, 2, Palette.woodShade, 0);
  b.hline(r.x, r.bottom - 1, r.w, Palette.woodOutline);
  b.vline(r.x, r.y + 1, r.h - 1, Palette.woodOutline);
  b.vline(r.right - 1, r.y + 1, r.h - 1, Palette.woodDark);
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
      base: Palette.woodBase,
      light: Palette.woodLight,
      dark: Palette.woodDark,
    );
    b.fill(ux + uw ~/ 2 - 3, dy + dh ~/ 2, 6, 2, Palette.amber);
    b.set(ux + uw ~/ 2 - 3, dy + dh ~/ 2, Palette.amberLight);
    b.hline(ux + uw ~/ 2 - 3, dy + dh ~/ 2 + 2, 6, Palette.woodOutline);
  }
}

/// Desk return going back toward the wall (corner desk), top only.
void paintDeskReturn(PixelBuffer b, IRect r) {
  b.fill(r.x, r.y, r.w, r.h, Palette.woodLight);
  b.hline(r.x, r.y, r.w, Palette.creamLight);
  b.vline(r.x, r.y, r.h, Palette.woodOutline);
  b.vline(r.x + 1, r.y + 1, r.h - 1, Palette.woodBase);
  b.vline(r.right - 1, r.y, r.h, Palette.woodShade);
  b.hline(r.x + 1, r.y + 1, r.w - 2, Palette.woodLight);
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
  final up = greyed ? Palette.steelShade : p.chair;
  final upLight = greyed ? Palette.steelBase : p.chairLight;
  final upDark = greyed ? Palette.steelDark : p.chairDark;
  final outline = greyed ? Palette.steelOutline : Palette.woodOutline;
  final wood = greyed ? Palette.steelBase : Palette.woodBase;
  final woodDark = greyed ? Palette.steelDark : Palette.woodDark;
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
  final light = greyed ? Palette.steelLight : Palette.woodLight;
  final base = greyed ? Palette.steelBase : Palette.woodBase;
  final dark = greyed ? Palette.steelShade : Palette.woodDark;
  final outline = greyed ? Palette.steelOutline : Palette.woodOutline;
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
    (Palette.violet, Palette.violetDark, 15),
    (Palette.orange, Palette.orangeDark, 13),
    (Palette.teal, Palette.tealDark, 16),
  ];
  var yy = y;
  for (final (base, dark, w) in books) {
    b.fill(x, yy, w, 3, base);
    b.hline(x, yy, w, PixelBuffer.lightOf(base));
    b.vline(x + w - 1, yy, 3, dark);
    b.hline(x + 1, yy + 2, w - 2, dark);
    b.set(x + 1, yy + 1, Palette.paper);
    yy += 3;
  }
  b.hline(x + 1, yy, 17, PixelBuffer.shadowOf(Palette.woodLight));
}

/// Tapered wastebasket with ribs and a crumpled sheet peeking out.
void paintWasteBin(PixelBuffer b, IRect r) {
  b.ellipseShadow(r.centerX + 1, r.bottom, r.w ~/ 2 + 1, 2);
  for (var i = 0; i < r.h; i++) {
    final inset = (i * 2) ~/ r.h;
    b.hline(r.x + inset, r.y + i, r.w - 2 * inset, Palette.slateBase);
    b.set(r.x + inset, r.y + i, Palette.slateLight);
    b.set(r.right - 1 - inset, r.y + i, Palette.slateDark);
  }
  for (var k = 1; k < 4; k++) {
    b.vline(r.x + k * 3, r.y + 2, r.h - 4, Palette.slateShade);
  }
  b.hline(r.x, r.y, r.w, Palette.slateLight);
  b.hline(r.x + 2, r.bottom - 1, r.w - 4, Palette.slateDark);
  b.fill(r.x + 3, r.y - 3, 5, 3, Palette.paper);
  b.set(r.x + 7, r.y - 3, Palette.paperShade);
  b.set(r.x + 4, r.y - 2, Palette.paperShade);
}

/// Reception desk with an inset front panel, a paper stack and a pen cup.
void paintReceptionDesk(PixelBuffer b, IRect r) {
  const surface = 8;
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    surface,
    base: Palette.woodLight,
    light: Palette.creamLight,
    dark: Palette.woodBase,
  );
  b.hline(r.x, r.y + surface - 1, r.w, Palette.woodShade);
  final fy = r.y + surface;
  final fh = r.h - surface;
  b.fill(r.x, fy, r.w, fh, Palette.woodBase);
  b.hline(r.x, fy, r.w, Palette.woodDark);
  b.fill(r.x, fy + fh ~/ 2, r.w, fh - fh ~/ 2, Palette.woodShade);
  b.checker(r.x, fy + fh ~/ 2 - 1, r.w, 2, Palette.woodShade, 0);
  b.vline(r.x, r.y + 1, r.h - 1, Palette.woodOutline);
  b.vline(r.right - 1, r.y + 1, r.h - 1, Palette.woodDark);
  b.hline(r.x, r.bottom - 1, r.w, Palette.woodOutline);
  // Inset panel.
  b.fill(r.x + 6, fy + 4, r.w - 12, fh - 8, Palette.woodShade);
  b.hline(r.x + 6, fy + 4, r.w - 12, Palette.woodDark);
  b.vline(r.x + 6, fy + 4, fh - 8, Palette.woodDark);
  b.hline(r.x + 6, fy + fh - 5, r.w - 12, Palette.woodLight);
  b.vline(r.right - 7, fy + 4, fh - 8, Palette.woodLight);
  b.shadeRect(
    r.x + 9,
    fy + 7,
    r.w - 18,
    fh - 14,
    base: Palette.woodBase,
    light: Palette.woodLight,
    dark: Palette.woodShade,
  );
  // Paper stack and a pen cup.
  paintPapers(b, r.x + 28, r.y - 4, 14, 6);
  b.fill(r.x + 50, r.y - 6, 6, 7, Palette.slateBase);
  b.vline(r.x + 50, r.y - 6, 7, Palette.slateLight);
  b.vline(r.x + 55, r.y - 6, 7, Palette.slateDark);
  b.vline(r.x + 51, r.y - 10, 4, Palette.amber);
  b.vline(r.x + 53, r.y - 9, 3, Palette.teal);
}

/// Mailbox on a post. The red flag is up when a report is waiting.
void paintMailbox(PixelBuffer b, IRect r, {required bool flagUp}) {
  final cx = r.centerX;
  b.fill(cx - 2, r.bottom - 1, 4, 26, Palette.woodShade);
  b.vline(cx - 2, r.bottom - 1, 26, Palette.woodBase);
  b.vline(cx + 1, r.bottom - 1, 26, Palette.woodDark);
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Palette.steelBase,
    light: Palette.steelLight,
    dark: Palette.steelShade,
    rounded: true,
  );
  b.roundRing(r.x, r.y, r.w, r.h, Palette.steelOutline);
  b.hline(r.x + 2, r.y + 1, r.w - 4, Palette.steelLight);
  b.vline(r.x + 5, r.y + 2, r.h - 4, Palette.steelShade);
  b.vline(r.x + 6, r.y + 2, r.h - 4, Palette.steelLight);
  b.fill(r.x + 2, r.y + r.h ~/ 2 - 1, 2, 2, Palette.amber);
  if (flagUp) {
    b.fill(r.right - 5, r.y - 8, 3, 10, Palette.red);
    b.vline(r.right - 5, r.y - 8, 10, PixelBuffer.lightOf(Palette.red));
    b.set(r.right - 3, r.y - 8, Palette.redDark);
    b.hline(r.right - 5, r.y - 8, 3, Palette.redDark);
    b.set(r.right - 4, r.y - 9, Palette.red);
  } else {
    b.fill(r.right - 2, r.y + 5, 8, 3, Palette.red);
    b.hline(r.right - 2, r.y + 5, 8, PixelBuffer.lightOf(Palette.red));
    b.set(r.right + 5, r.y + 7, Palette.redDark);
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
    base: Palette.slateBase,
    light: Palette.slateLight,
    dark: Palette.slateDark,
    rounded: true,
  );
  for (var i = 0; i < 9; i++) {
    b.set(x + 2 + i * 2, y + 2, Palette.slateLight);
    b.set(x + 3 + i * 2, y + 4, Palette.slateLight);
  }
  b.hline(x + 6, y + 4, 8, Palette.slateLight);
  b.hline(x, y + 6, 22, PixelBuffer.shadowOf(Palette.woodLight));
}

/// Mouse beside the keyboard.
void paintMouse(PixelBuffer b, int x, int y) {
  b.roundFill(x, y, 5, 7, Palette.cream);
  b.vline(x + 4, y + 1, 5, Palette.creamShade);
  b.hline(x + 1, y + 6, 3, Palette.creamShade);
  b.hline(x + 1, y + 2, 3, Palette.creamDark);
  b.hline(x + 1, y + 7, 4, PixelBuffer.shadowOf(Palette.woodLight));
}

/// Paper tray, 14x4, with a sheet in it.
void paintTray(PixelBuffer b, int x, int y) {
  b.fill(x + 1, y - 2, 12, 2, Palette.paper);
  b.hline(x + 1, y - 2, 12, Palette.paperShade);
  b.shadeRect(
    x,
    y,
    14,
    4,
    base: Palette.steelShade,
    light: Palette.steelLight,
    dark: Palette.steelDark,
  );
  b.hline(x + 1, y + 4, 14, PixelBuffer.shadowOf(Palette.woodLight));
}

/// Stack of papers, [w] x [h], lined.
void paintPapers(PixelBuffer b, int x, int y, int w, int h) {
  b.fill(x + 1, y + 1, w, h, Palette.paperShade);
  b.fill(x, y, w, h, Palette.paper);
  b.vline(x + w - 1, y, h, Palette.paperShade);
  b.hline(x, y + h - 1, w, Palette.paperShade);
  b.hline(x + 2, y + 2, w - 6, Palette.paperLine);
  if (h > 4) b.hline(x + 2, y + 4, w - 8, Palette.paperLine);
  b.hline(x + 1, y + h + 1, w, PixelBuffer.shadowOf(Palette.woodLight));
}

/// Mug, 7x7 with a handle on the right and a coloured stripe.
void paintMug(PixelBuffer b, int x, int y, {int stripe = Palette.teal}) {
  b.fill(x, y, 6, 7, Palette.cream);
  b.vline(x, y, 7, PixelBuffer.lightOf(Palette.cream));
  b.vline(x + 5, y, 7, Palette.creamMug);
  b.hline(x, y + 6, 6, Palette.creamDark);
  b.hline(x, y, 6, Palette.creamMug);
  b.hline(x, y + 2, 6, stripe);
  b.set(x + 6, y + 1, Palette.creamDark);
  b.set(x + 7, y + 2, Palette.creamDark);
  b.set(x + 7, y + 3, Palette.creamDark);
  b.set(x + 6, y + 4, Palette.creamDark);
  b.hline(x + 1, y + 7, 6, PixelBuffer.shadowOf(Palette.woodLight));
}

/// Rising steam over a mug at (x, y) (top-left of the mug); [frame] 0-3.
void paintMugSteam(PixelBuffer b, int x, int y, int frame) {
  final cx = x + 3;
  switch (frame % 4) {
    case 0:
      b.set(cx, y - 2, Palette.steam);
      b.set(cx + 1, y - 4, Palette.steam);
    case 1:
      b.set(cx - 1, y - 3, Palette.steam);
      b.set(cx + 1, y - 5, Palette.steam);
    case 2:
      b.set(cx, y - 4, Palette.steam);
      b.set(cx - 1, y - 6, Palette.steam);
    case 3:
      b.set(cx + 1, y - 3, Palette.steam);
      b.set(cx, y - 6, Palette.steam);
  }
}

/// Desk lamp: (x, y) is the bottom-centre of the base on the desk top. The
/// shade leans left over the desk. When [lit] (only while the lighting has
/// lamps on) the shade glows, a pool of light falls on the desk and, at
/// night, a halo spreads around the shade.
void paintDeskLamp(
  PixelBuffer b,
  int x,
  int y,
  SceneLighting lighting, {
  bool lit = true,
}) {
  final on = lit && lighting.lampsOn;
  if (on) {
    if (lighting.lampHaloRadius > 0) {
      b.lightPool(
        x - 9,
        y - 20,
        lighting.lampHaloRadius,
        lighting.lampHaloRadius - 4,
        tint: lighting.lampGlow,
        strength: lighting.lampHaloStrength,
      );
    }
    b.lightPool(
      x - 9,
      y - 1,
      14,
      4,
      tint: lighting.lampGlow,
      strength: lighting.lampPoolStrength,
    );
  }
  b.shadeRect(
    x - 4,
    y - 3,
    9,
    3,
    base: Palette.slateBase,
    light: Palette.slateLight,
    dark: Palette.slateDark,
    rounded: true,
  );
  b.hline(x - 3, y, 9, PixelBuffer.shadowOf(Palette.woodLight));
  b.vline(x, y - 15, 12, Palette.slateShade);
  b.vline(x + 1, y - 15, 12, Palette.slateDark);
  b.line(x, y - 15, x - 6, y - 20, Palette.slateShade);
  b.line(x + 1, y - 15, x - 5, y - 20, Palette.slateDark);
  // Shade: a trapezoid opening down-left.
  void shade() {
    for (var i = 0; i < 7; i++) {
      final sy = y - 26 + i;
      final sw = 8 + i * 2;
      final sx = x - 12 - i + 1;
      b.hline(sx, sy, sw, Palette.amber);
      b.set(sx, sy, Palette.amberDark);
      b.set(sx + sw - 1, sy, Palette.amberDark);
    }
    b.hline(x - 11, y - 26, 8, Palette.amberLight);
    b.hline(x - 18, y - 19, 20, Palette.amberDark);
    b.hline(x - 16, y - 18, 16, on ? Palette.lampGlow : Palette.slateShade);
    if (on) {
      b.hline(
        x - 17,
        y - 17,
        18,
        PixelBuffer.mix(Palette.lampGlow, Palette.amber, 0.5),
      );
    }
  }

  if (on) {
    b.emissive(shade);
  } else {
    shade();
  }
}
