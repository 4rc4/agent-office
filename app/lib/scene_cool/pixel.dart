import 'dart:ui';

import 'palette.dart';

/// Dither density for [Px.dither]: how many of every four pixels take the
/// second colour.
enum Dither { quarter, half, threeQuarter }

/// Integer-pixel drawing helpers over a [Canvas] that is already scaled to
/// scene units. Every call maps to [Canvas.drawRect] or a rectangle path with
/// anti-aliasing off, so a 1x1 fill is exactly one scene pixel.
class Px {
  Px(this.canvas);

  final Canvas canvas;
  final Paint _paint = Paint()
    ..isAntiAlias = false
    ..filterQuality = FilterQuality.none
    ..style = PaintingStyle.fill;

  /// Fills a w x h block at (x, y). Zero or negative sizes draw nothing.
  void fill(int x, int y, int w, int h, Color color) {
    if (w <= 0 || h <= 0) return;
    _paint.color = color;
    canvas.drawRect(
      Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble()),
      _paint,
    );
  }

  void hline(int x, int y, int w, Color color) => fill(x, y, w, 1, color);

  void vline(int x, int y, int h, Color color) => fill(x, y, 1, h, color);

  void dot(int x, int y, Color color) => fill(x, y, 1, 1, color);

  /// One-pixel rectangle outline.
  void ring(int x, int y, int w, int h, Color color) {
    if (w <= 0 || h <= 0) return;
    fill(x, y, w, 1, color);
    fill(x, y + h - 1, w, 1, color);
    fill(x, y, 1, h, color);
    fill(x + w - 1, y, 1, h, color);
  }

  /// Outline whose four corner pixels are left out (reads as rounded).
  void roundRing(int x, int y, int w, int h, Color color) {
    if (w < 4 || h < 4) {
      ring(x, y, w, h, color);
      return;
    }
    fill(x + 1, y, w - 2, 1, color);
    fill(x + 1, y + h - 1, w - 2, 1, color);
    fill(x, y + 1, 1, h - 2, color);
    fill(x + w - 1, y + 1, 1, h - 2, color);
  }

  /// Bevelled block: [tones.base] fill, a light line on the top and left
  /// edges and a shade line on the bottom and right edges ([bevel] pixels
  /// wide). With [outline] a one-pixel dark ring surrounds the block and the
  /// bevel sits inside it.
  void shadeRect(
    int x,
    int y,
    int w,
    int h,
    Tones tones, {
    int bevel = 1,
    bool outline = false,
    bool rounded = false,
  }) {
    if (w <= 0 || h <= 0) return;
    var ix = x;
    var iy = y;
    var iw = w;
    var ih = h;
    if (outline) {
      if (rounded) {
        roundRing(x, y, w, h, tones.dark);
      } else {
        ring(x, y, w, h, tones.dark);
      }
      ix += 1;
      iy += 1;
      iw -= 2;
      ih -= 2;
    }
    if (iw <= 0 || ih <= 0) return;
    fill(ix, iy, iw, ih, tones.base);
    final b = bevel.clamp(0, iw ~/ 2).clamp(0, ih ~/ 2);
    if (b <= 0) return;
    fill(ix, iy, iw, b, tones.light);
    fill(ix, iy, b, ih, tones.light);
    fill(ix, iy + ih - b, iw, b, tones.shade);
    fill(ix + iw - b, iy, b, ih, tones.shade);
    fill(ix, iy + ih - b, b, b, tones.base);
    fill(ix + iw - b, iy, b, b, tones.base);
  }

  /// Fills (x, y, w, h) with [b] on the dithered pixels of the pattern,
  /// leaving the rest alone ([a] null) or painting them [a].
  void dither(
    int x,
    int y,
    int w,
    int h,
    Color? a,
    Color b, {
    Dither pattern = Dither.half,
  }) {
    if (w <= 0 || h <= 0) return;
    if (a != null) fill(x, y, w, h, a);
    final path = Path();
    for (var py = 0; py < h; py++) {
      for (var pxl = 0; pxl < w; pxl++) {
        final sx = x + pxl;
        final sy = y + py;
        final on = switch (pattern) {
          Dither.half => (sx + sy).isEven,
          Dither.quarter => sx.isEven && sy.isEven,
          Dither.threeQuarter => !(sx.isOdd && sy.isOdd),
        };
        if (on) {
          path.addRect(Rect.fromLTWH(sx.toDouble(), sy.toDouble(), 1, 1));
        }
      }
    }
    _paint.color = b;
    canvas.drawPath(path, _paint);
  }

  /// Soft ambient-occlusion patch: a dithered ellipse of [color] with a
  /// solid core, centred on (cx, cy) with radii rx and ry.
  void shadowEllipse(int cx, int cy, int rx, int ry, Color color) {
    if (rx <= 0 || ry <= 0) return;
    final core = Path();
    final rim = Path();
    for (var y = -ry; y <= ry; y++) {
      for (var x = -rx; x <= rx; x++) {
        final nx = x / (rx + 0.5);
        final ny = y / (ry + 0.5);
        final d = nx * nx + ny * ny;
        if (d > 1) continue;
        final sx = cx + x;
        final sy = cy + y;
        final rect = Rect.fromLTWH(sx.toDouble(), sy.toDouble(), 1, 1);
        if (d < 0.55) {
          core.addRect(rect);
        } else if ((sx + sy).isEven) {
          rim.addRect(rect);
        }
      }
    }
    _paint.color = color;
    canvas.drawPath(core, _paint);
    canvas.drawPath(rim, _paint);
  }

  /// Draws an ASCII sprite. Each row is one string, one char per pixel; '.'
  /// is transparent and every other char is looked up in [legend]. Horizontal
  /// runs of one colour are merged into one rect.
  void sprite(int x, int y, List<String> rows, Map<String, Color> legend) {
    for (var r = 0; r < rows.length; r++) {
      final row = rows[r];
      var c = 0;
      while (c < row.length) {
        final ch = row[c];
        if (ch == '.' || ch == ' ') {
          c++;
          continue;
        }
        var end = c + 1;
        while (end < row.length && row[end] == ch) {
          end++;
        }
        final color = legend[ch];
        if (color != null) fill(x + c, y + r, end - c, 1, color);
        c = end;
      }
    }
  }

  /// Fills a free-form set of pixels (relative to x, y) and surrounds it with
  /// a one-pixel [edge] over the 8-neighbourhood.
  void blob(
    Iterable<(int, int)> pixels,
    Color color, {
    int x = 0,
    int y = 0,
    Color edge = ScenePalette.ink,
  }) {
    final body = pixels.toSet();
    final rim = <(int, int)>{};
    for (final (bx, by) in body) {
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final n = (bx + dx, by + dy);
          if (!body.contains(n)) rim.add(n);
        }
      }
    }
    for (final (ex, ey) in rim) {
      fill(x + ex, y + ey, 1, 1, edge);
    }
    for (final (fx, fy) in body) {
      fill(x + fx, y + fy, 1, 1, color);
    }
  }

  /// Filled disc of radius [r] around the pixel (cx, cy), no outline.
  void discFill(int cx, int cy, int r, Color color) {
    for (final (dx, dy) in discPixels(r)) {
      fill(cx + dx, cy + dy, 1, 1, color);
    }
  }

  /// Shaded disc: base fill, light crescent on the upper left, shade crescent
  /// on the lower right and a dark rim.
  void shadeDisc(int cx, int cy, int r, Tones tones) {
    final body = discPixels(r);
    blob(body, tones.base, x: cx, y: cy, edge: tones.dark);
    for (final (dx, dy) in body) {
      final d2 = dx * dx + dy * dy;
      if (d2 < (r - 1) * (r - 1)) continue;
      if (dx + dy < -r ~/ 2) fill(cx + dx, cy + dy, 1, 1, tones.light);
      if (dx + dy > r ~/ 2) fill(cx + dx, cy + dy, 1, 1, tones.shade);
    }
  }

  /// Pixels of a disc of radius [r] centred on (0, 0).
  static List<(int, int)> discPixels(int r) {
    final out = <(int, int)>[];
    for (var y = -r; y <= r; y++) {
      for (var x = -r; x <= r; x++) {
        if (x * x + y * y <= r * r + r) out.add((x, y));
      }
    }
    return out;
  }
}
