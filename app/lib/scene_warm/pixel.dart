import 'dart:typed_data';
import 'dart:ui';

/// A scene-sized ARGB framebuffer with pixel-art drawing helpers.
///
/// The whole office is composed here first (so shading, dithering and
/// ambient-occlusion passes can read what is already on the floor) and then
/// flushed to a [Canvas] by [emit] as merged, non-anti-aliased rectangles.
/// Coordinates are scene pixels; everything outside the buffer is clipped.
class PixelBuffer {
  PixelBuffer(this.width, this.height) : data = Int32List(width * height);

  final int width;
  final int height;
  final Int32List data;

  bool inside(int x, int y) => x >= 0 && y >= 0 && x < width && y < height;

  int get(int x, int y) => inside(x, y) ? data[y * width + x] : 0;

  /// Sets one pixel; colour 0 means "leave alone".
  void set(int x, int y, int color) {
    if (color == 0 || !inside(x, y)) return;
    data[y * width + x] = color;
  }

  /// Fills a w x h block at (x, y). Zero sizes and colour 0 draw nothing.
  void fill(int x, int y, int w, int h, int color) {
    if (color == 0) return;
    final x0 = x < 0 ? 0 : x;
    final y0 = y < 0 ? 0 : y;
    final x1 = x + w > width ? width : x + w;
    final y1 = y + h > height ? height : y + h;
    if (x1 <= x0 || y1 <= y0) return;
    for (var yy = y0; yy < y1; yy++) {
      final row = yy * width;
      data.fillRange(row + x0, row + x1, color);
    }
  }

  void hline(int x, int y, int w, int color) => fill(x, y, w, 1, color);

  void vline(int x, int y, int h, int color) => fill(x, y, 1, h, color);

  /// One-pixel rectangle outline.
  void ring(int x, int y, int w, int h, int color) {
    if (w <= 0 || h <= 0) return;
    hline(x, y, w, color);
    hline(x, y + h - 1, w, color);
    vline(x, y, h, color);
    vline(x + w - 1, y, h, color);
  }

  /// Outline whose four corner pixels are left out (rounded at pixel scale).
  void roundRing(int x, int y, int w, int h, int color) {
    if (w < 3 || h < 3) {
      ring(x, y, w, h, color);
      return;
    }
    hline(x + 1, y, w - 2, color);
    hline(x + 1, y + h - 1, w - 2, color);
    vline(x, y + 1, h - 2, color);
    vline(x + w - 1, y + 1, h - 2, color);
  }

  /// Filled block whose four corner pixels are left out.
  void roundFill(int x, int y, int w, int h, int color) {
    if (w < 3 || h < 3) {
      fill(x, y, w, h, color);
      return;
    }
    fill(x + 1, y, w - 2, h, color);
    fill(x, y + 1, 1, h - 2, color);
    fill(x + w - 1, y + 1, 1, h - 2, color);
  }

  /// Bevelled block: [base] fill, [light] along the top and left edges and
  /// [dark] along the bottom and right edges, [bevel] pixels thick. With
  /// [rounded] the corner pixels are dropped. Light comes from the top-left.
  void shadeRect(
    int x,
    int y,
    int w,
    int h, {
    required int base,
    int light = 0,
    int dark = 0,
    int bevel = 1,
    bool rounded = false,
  }) {
    if (w <= 0 || h <= 0) return;
    if (rounded) {
      roundFill(x, y, w, h, base);
    } else {
      fill(x, y, w, h, base);
    }
    for (var i = 0; i < bevel; i++) {
      final inset = rounded && i == 0 ? 1 : 0;
      hline(x + i + inset, y + i, w - 2 * i - 2 * inset, light);
      vline(x + i, y + i + inset, h - 2 * i - 2 * inset, light);
      hline(x + i + inset, y + h - 1 - i, w - 2 * i - 2 * inset, dark);
      vline(x + w - 1 - i, y + i + inset, h - 2 * i - 2 * inset, dark);
    }
  }

  /// 50% checkerboard of [a] and [b]; either may be 0 to keep what is there.
  void checker(int x, int y, int w, int h, int a, int b, {int phase = 0}) {
    for (var yy = y; yy < y + h; yy++) {
      for (var xx = x; xx < x + w; xx++) {
        set(xx, yy, ((xx + yy + phase) & 1) == 0 ? a : b);
      }
    }
  }

  /// 2x2 ordered-dither threshold for a pixel, in (0, 1).
  static double bayer(int x, int y) =>
      const [0.125, 0.625, 0.875, 0.375][((y & 1) << 1) | (x & 1)];

  /// Dithered gradient: [value] returns a position along [tones] (0 .. n-1,
  /// fractional) for each pixel and the fraction is ordered-dithered.
  void gradient(
    int x,
    int y,
    int w,
    int h,
    List<int> tones,
    double Function(int x, int y) value,
  ) {
    final last = tones.length - 1;
    for (var yy = y; yy < y + h; yy++) {
      for (var xx = x; xx < x + w; xx++) {
        var v = value(xx, yy);
        if (v < 0) v = 0;
        if (v > last) v = last.toDouble();
        final i = v.floor();
        final f = v - i;
        var idx = f > bayer(xx, yy) ? i + 1 : i;
        if (idx > last) idx = last;
        set(xx, yy, tones[idx]);
      }
    }
  }

  /// Applies [f] to the pixels already in the block, optionally only on one
  /// half of a checkerboard (a soft, dithered effect).
  void modify(
    int x,
    int y,
    int w,
    int h,
    int Function(int) f, {
    bool checker = false,
    int phase = 0,
  }) {
    final x0 = x < 0 ? 0 : x;
    final y0 = y < 0 ? 0 : y;
    final x1 = x + w > width ? width : x + w;
    final y1 = y + h > height ? height : y + h;
    for (var yy = y0; yy < y1; yy++) {
      for (var xx = x0; xx < x1; xx++) {
        if (checker && ((xx + yy + phase) & 1) == 1) continue;
        final i = yy * width + xx;
        data[i] = f(data[i]);
      }
    }
  }

  /// Ambient-occlusion shadow: the inner block is darkened solid and a
  /// [feather]-wide band around it is darkened on a checkerboard.
  void shadow(int x, int y, int w, int h, {int feather = 2}) {
    modify(x, y, w, h, shadowOf, checker: true);
    modify(
      x + feather,
      y + feather,
      w - 2 * feather,
      h - 2 * feather,
      shadowOf,
    );
  }

  /// Soft elliptical shadow, e.g. under a standing character.
  void ellipseShadow(int cx, int cy, int rx, int ry) {
    for (var yy = cy - ry; yy <= cy + ry; yy++) {
      for (var xx = cx - rx; xx <= cx + rx; xx++) {
        if (!inside(xx, yy)) continue;
        final dx = (xx - cx) / rx;
        final dy = (yy - cy) / ry;
        final d = dx * dx + dy * dy;
        if (d > 1.0) continue;
        if (d > 0.45 && ((xx + yy) & 1) == 1) continue;
        final i = yy * width + xx;
        data[i] = shadowOf(data[i]);
      }
    }
  }

  /// Warm light pool on whatever is under it: the inner ellipse is lit solid,
  /// the rim on a checkerboard. [strength] 0..1 mixes toward [tint].
  void lightPool(
    int cx,
    int cy,
    int rx,
    int ry, {
    required int tint,
    double strength = 0.45,
  }) {
    for (var yy = cy - ry; yy <= cy + ry; yy++) {
      for (var xx = cx - rx; xx <= cx + rx; xx++) {
        if (!inside(xx, yy)) continue;
        final dx = (xx - cx) / rx;
        final dy = (yy - cy) / ry;
        final d = dx * dx + dy * dy;
        if (d > 1.0) continue;
        if (d > 0.5 && ((xx + yy) & 1) == 1) continue;
        final i = yy * width + xx;
        data[i] = mix(data[i], tint, strength);
      }
    }
  }

  /// Draws an ASCII sprite: one string per row, one char per pixel, '.' is
  /// transparent and every other char is looked up in [legend]. Rows at or
  /// below [clipBottom] are skipped (a character behind a desk).
  void sprite(
    int x,
    int y,
    List<String> rows,
    Map<String, int> legend, {
    int clipBottom = 1 << 20,
  }) {
    for (var r = 0; r < rows.length; r++) {
      final yy = y + r;
      if (yy >= clipBottom) return;
      if (yy < 0 || yy >= height) continue;
      final row = rows[r];
      for (var c = 0; c < row.length; c++) {
        final ch = row[c];
        if (ch == '.') continue;
        final color = legend[ch];
        if (color != null) set(x + c, yy, color);
      }
    }
  }

  /// Fills a free-form set of pixels (relative to x, y) and, when [outline]
  /// is given, surrounds it with a one-pixel edge over the 4-neighbourhood.
  void blob(
    Iterable<(int, int)> pixels,
    int color, {
    int outline = 0,
    int x = 0,
    int y = 0,
  }) {
    final body = pixels.toSet();
    if (outline != 0) {
      for (final (bx, by) in body) {
        for (final (dx, dy) in const [(1, 0), (-1, 0), (0, 1), (0, -1)]) {
          final n = (bx + dx, by + dy);
          if (!body.contains(n)) set(x + n.$1, y + n.$2, outline);
        }
      }
    }
    for (final (fx, fy) in body) {
      set(x + fx, y + fy, color);
    }
  }

  /// Filled disc of radius [r] around (cx, cy); [outline] rings it.
  void disc(int cx, int cy, int r, int color, {int outline = 0}) =>
      blob(discPixels(r), color, outline: outline, x: cx, y: cy);

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

  /// Bresenham line, one pixel wide.
  void line(int x0, int y0, int x1, int y1, int color) {
    var dx = (x1 - x0).abs();
    var dy = -(y1 - y0).abs();
    final sx = x0 < x1 ? 1 : -1;
    final sy = y0 < y1 ? 1 : -1;
    var err = dx + dy;
    var x = x0;
    var y = y0;
    while (true) {
      set(x, y, color);
      if (x == x1 && y == y1) break;
      final e2 = 2 * err;
      if (e2 >= dy) {
        err += dy;
        x += sx;
      }
      if (e2 <= dx) {
        err += dx;
        y += sy;
      }
    }
  }

  // ---- tone helpers -------------------------------------------------------

  static final Map<int, int> _shadowCache = {};
  static final Map<int, int> _lightCache = {};

  /// Cooler, darker version of a colour (cast shadow).
  static int shadowOf(int c) => _shadowCache.putIfAbsent(c, () {
    final a = c & 0xFF000000;
    final r = ((c >> 16) & 0xFF) * 0.64;
    final g = ((c >> 8) & 0xFF) * 0.60;
    final b = (c & 0xFF) * 0.72;
    return a | (r.round() << 16) | (g.round() << 8) | b.round();
  });

  /// Warmer, lighter version of a colour (sunlight).
  static int lightOf(int c) => _lightCache.putIfAbsent(c, () {
    final a = c & 0xFF000000;
    final r = _clamp(((c >> 16) & 0xFF) * 1.08 + 30);
    final g = _clamp(((c >> 8) & 0xFF) * 1.04 + 18);
    final b = _clamp((c & 0xFF) * 0.92 + 2);
    return a | (r << 16) | (g << 8) | b;
  });

  /// Linear mix of two colours, [t] toward [b].
  static int mix(int a, int b, double t) {
    final ar = (a >> 16) & 0xFF, ag = (a >> 8) & 0xFF, ab = a & 0xFF;
    final br = (b >> 16) & 0xFF, bg = (b >> 8) & 0xFF, bb = b & 0xFF;
    final r = (ar + (br - ar) * t).round();
    final g = (ag + (bg - ag) * t).round();
    final bl = (ab + (bb - ab) * t).round();
    return 0xFF000000 | (r << 16) | (g << 8) | bl;
  }

  static int _clamp(double v) => v < 0 ? 0 : (v > 255 ? 255 : v.round());

  // ---- output -------------------------------------------------------------

  /// Flushes the buffer to [canvas] (already scaled to scene units) as
  /// axis-aligned rectangles: horizontal runs of one colour, merged with the
  /// identical run above them, drawn without anti-aliasing.
  void emit(Canvas canvas) {
    final paint = Paint()
      ..isAntiAlias = false
      ..filterQuality = FilterQuality.none
      ..style = PaintingStyle.fill;
    var open = List<_Run?>.filled(width, null);
    var next = List<_Run?>.filled(width, null);

    void draw(_Run r) {
      paint.color = Color(r.color);
      canvas.drawRect(
        Rect.fromLTWH(
          r.x.toDouble(),
          r.y.toDouble(),
          r.w.toDouble(),
          r.h.toDouble(),
        ),
        paint,
      );
    }

    for (var y = 0; y < height; y++) {
      final row = y * width;
      var x = 0;
      while (x < width) {
        final c = data[row + x];
        var end = x + 1;
        while (end < width && data[row + end] == c) {
          end++;
        }
        final w = end - x;
        if (c != 0) {
          final above = open[x];
          if (above != null && above.w == w && above.color == c) {
            above.h++;
            next[x] = above;
            open[x] = null;
          } else {
            next[x] = _Run(x, y, w, c);
          }
        }
        x = end;
      }
      for (var i = 0; i < width; i++) {
        final r = open[i];
        if (r != null) {
          draw(r);
          open[i] = null;
        }
      }
      final t = open;
      open = next;
      next = t;
    }
    for (final r in open) {
      if (r != null) draw(r);
    }
  }
}

class _Run {
  _Run(this.x, this.y, this.w, this.color);

  final int x;
  final int y;
  final int w;
  final int color;
  int h = 1;
}
