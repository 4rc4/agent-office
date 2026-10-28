import 'palette.dart';
import 'pixel.dart';
import 'scene_layout.dart';

/// The room shell: plaster wall with an evening vignette, wainscoting, the
/// skirting board, floorboards, the window's light shaft and the rug.

const int _w = SceneLayout.width;
const int _h = SceneLayout.height;

/// Deterministic pseudo-random for wood grain; the same scene every frame.
int _hash(int n) {
  var x = n * 374761393 + 668265263;
  x = (x ^ (x >> 13)) * 1274126177;
  return (x ^ (x >> 16)) & 0x7FFFFFFF;
}

/// Plaster wall: lightest beside the window, dithering darker toward the
/// right and the top corners.
void paintWall(PixelBuffer b) {
  final window = SceneLayout.window;
  final wx = window.centerX;
  b.gradient(
    0,
    0,
    _w,
    SceneLayout.chairRail,
    const [Warm.wallLight, Warm.wallBase, Warm.wallShade, Warm.wallDark],
    (x, y) {
      final dx = x - wx;
      final right = dx > 0 ? dx / 150.0 : 0.0;
      final left = x < 14 ? (14 - x) / 14.0 * 0.9 : 0.0;
      final top = y < 22 ? (22 - y) / 22.0 * 0.9 : 0.0;
      return right + left + top;
    },
  );
  // Faint warm glow on the wall around the window.
  b.modify(
    window.x - 16,
    window.y - 12,
    window.w + 32,
    window.h + 20,
    (c) => PixelBuffer.mix(c, Warm.lampGlow, 0.28),
    checker: true,
  );
}

/// Chair rail, recessed wainscot panels and the skirting board.
void paintWainscoting(PixelBuffer b) {
  const rail = SceneLayout.chairRail;
  const bottom = SceneLayout.wallBottom;
  // Rail.
  b.shadeRect(
    0,
    rail,
    _w,
    5,
    base: Warm.wainBase,
    light: Warm.wainLight,
    dark: Warm.wainDark,
  );
  b.hline(0, rail + 5, _w, Warm.wallShade);
  // Panel field.
  b.fill(0, rail + 6, _w, bottom - rail - 6, Warm.wainBase);
  const panelW = 30;
  const gap = 6;
  const top = rail + 9;
  const height = bottom - top - 4;
  for (var x = 4; x + panelW <= _w; x += panelW + gap) {
    // Recess: dark on the lit side, light on the far side.
    b.fill(x, top, panelW, height, Warm.wainShade);
    b.hline(x, top, panelW, Warm.wainDark);
    b.vline(x, top, height, Warm.wainDark);
    b.hline(x, top + height - 1, panelW, Warm.wainLight);
    b.vline(x + panelW - 1, top, height, Warm.wainLight);
    // Inner raised field.
    b.shadeRect(
      x + 3,
      top + 3,
      panelW - 6,
      height - 6,
      base: Warm.wainBase,
      light: Warm.wainLight,
      dark: Warm.wainDark,
    );
  }
  // Skirting.
  b.shadeRect(
    0,
    bottom,
    _w,
    SceneLayout.floorTop - bottom,
    base: Warm.wainBase,
    light: Warm.wainLight,
    dark: Warm.wainDark,
  );
  b.hline(0, bottom, _w, Warm.wainOutline);
  b.hline(0, SceneLayout.floorTop - 1, _w, Warm.wainOutline);
}

/// Floorboards: horizontal planks with a highlight edge, grain dashes,
/// staggered end seams and a dark gap between boards.
void paintFloor(PixelBuffer b) {
  const plank = 13;
  var row = 0;
  for (var y = SceneLayout.floorTop; y < _h; y += plank, row++) {
    final h = y + plank > _h ? _h - y : plank;
    b.fill(0, y, _w, h, Warm.floorBase);
    b.hline(0, y, _w, Warm.floorLight);
    b.hline(0, y + h - 2, _w, Warm.floorShade);
    b.hline(0, y + h - 1, _w, Warm.floorGap);
    for (var k = 0; k < 26; k++) {
      final gx = _hash(row * 131 + k * 17) % _w;
      final gy = y + 2 + _hash(row * 53 + k * 29) % (h - 4);
      final gw = 3 + _hash(row * 7 + k * 101) % 10;
      b.hline(gx, gy, gw, k.isEven ? Warm.floorShade : Warm.floorLight);
    }
    final offset = (row * 41) % 110;
    for (var x = offset; x < _w; x += 110) {
      b.vline(x, y, h - 1, Warm.floorGap);
      b.vline(x + 1, y + 1, h - 3, Warm.floorLight);
    }
  }
  // Shadow of the skirting on the floor.
  b.modify(0, SceneLayout.floorTop, _w, 2, PixelBuffer.shadowOf);
  b.modify(
    0,
    SceneLayout.floorTop + 2,
    _w,
    1,
    PixelBuffer.shadowOf,
    checker: true,
  );
}

/// Rug under the main desk: bordered, with a diamond lattice and fringes.
void paintRug(PixelBuffer b, IRect r) {
  b.fill(r.x, r.y, r.w, r.h, Warm.rugBase);
  b.ring(r.x, r.y, r.w, r.h, Warm.rugOutline);
  b.ring(r.x + 2, r.y + 2, r.w - 4, r.h - 4, Warm.rugPattern);
  b.ring(r.x + 4, r.y + 4, r.w - 8, r.h - 8, Warm.rugDark);
  b.hline(r.x + 1, r.y + 1, r.w - 2, Warm.rugLight);
  b.vline(r.x + 1, r.y + 1, r.h - 2, Warm.rugLight);
  // Lattice of diamonds in the field.
  const cell = 14;
  final fx = r.x + 6;
  final fy = r.y + 6;
  final fw = r.w - 12;
  final fh = r.h - 12;
  for (var cy = 0; cy * cell < fh; cy++) {
    for (var cx = 0; cx * cell < fw; cx++) {
      final ox = fx + cx * cell;
      final oy = fy + cy * cell;
      for (var i = 0; i < 4; i++) {
        final d = 3 - i;
        final yy = oy + 3 + i;
        if (yy >= fy + fh) break;
        b.set(ox + 3 + d, yy, Warm.rugPattern);
        b.set(ox + 3 + 6 - d, yy, Warm.rugPattern);
        final yy2 = oy + 10 - i;
        if (yy2 < fy + fh) {
          b.set(ox + 3 + d, yy2, Warm.rugDark);
          b.set(ox + 3 + 6 - d, yy2, Warm.rugDark);
        }
      }
      b.set(ox + 6, oy + 6, Warm.rugLight);
      b.set(ox + 6, oy + 7, Warm.rugLight);
    }
  }
  // Fringe.
  for (var y = r.y + 1; y < r.bottom - 1; y += 2) {
    b.hline(r.x - 3, y, 3, Warm.rugPattern);
    b.hline(r.right, y, 3, Warm.rugPattern);
  }
}

/// Sunlight from the window on the floor: a widening shaft going down and
/// to the right, dithered at the edges, with the window mullions' shadows
/// left unlit inside it.
void paintLightShaft(PixelBuffer b) {
  const top = SceneLayout.floorTop;
  final window = SceneLayout.window;
  final span = _h - top;
  final barY = top + (span * 0.42).round();
  for (var y = top; y < _h; y++) {
    final t = (y - top) / span;
    final l = (window.x + 2 + t * 46).round();
    final r = (window.right - 2 + t * 110).round();
    final mid = l + (r - l) ~/ 2;
    final edgeFade = ((y - top) < 3) ? 0 : 1;
    for (var x = l; x <= r; x++) {
      final edge = x - l < r - x ? x - l : r - x;
      if ((x - mid).abs() <= 1 + (t * 1.5).round()) continue;
      if ((y - barY).abs() <= 1) continue;
      if (edge < 5 && ((x + y) & 1) == 1) continue;
      if (edge < 2 && ((x + y) & 3) != 0) continue;
      if (edgeFade == 0 && ((x + y) & 1) == 1) continue;
      b.set(x, y, PixelBuffer.lightOf(b.get(x, y)));
    }
  }
}

/// Door mat with a woven border.
void paintDoorMat(PixelBuffer b, IRect r) {
  b.fill(r.x, r.y, r.w, r.h, Warm.curtainBase);
  b.ring(r.x, r.y, r.w, r.h, Warm.curtainOutline);
  b.hline(r.x + 1, r.y + 1, r.w - 2, Warm.curtainLight);
  b.ring(r.x + 2, r.y + 2, r.w - 4, r.h - 4, Warm.rugPattern);
  b.checker(r.x + 3, r.y + 3, r.w - 6, r.h - 6, Warm.curtainDark, 0);
}
