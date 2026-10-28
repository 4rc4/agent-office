import 'dart:ui';

import 'palette.dart';

/// Integer-pixel drawing helpers over a [Canvas] that is already scaled to
/// scene units. Every call maps to [Canvas.drawRect] with anti-aliasing off,
/// so a 1x1 fill is exactly one scene pixel.
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

  /// One-pixel rectangle outline.
  void ring(int x, int y, int w, int h, [Color color = ScenePalette.outline]) {
    if (w <= 0 || h <= 0) return;
    fill(x, y, w, 1, color);
    fill(x, y + h - 1, w, 1, color);
    fill(x, y, 1, h, color);
    fill(x + w - 1, y, 1, h, color);
  }

  /// Outlined, filled box with square corners.
  void box(int x, int y, int w, int h, Color color) {
    ring(x, y, w, h);
    fill(x + 1, y + 1, w - 2, h - 2, color);
  }

  /// Outlined, filled box whose four corner pixels are left out, which reads
  /// as a rounded corner at pixel scale. Falls back to [box] when too small.
  void roundBox(int x, int y, int w, int h, Color color) {
    if (w < 4 || h < 4) {
      box(x, y, w, h, color);
      return;
    }
    fill(x + 1, y, w - 2, 1, ScenePalette.outline);
    fill(x + 1, y + h - 1, w - 2, 1, ScenePalette.outline);
    fill(x, y + 1, 1, h - 2, ScenePalette.outline);
    fill(x + w - 1, y + 1, 1, h - 2, ScenePalette.outline);
    fill(x + 1, y + 1, w - 2, h - 2, color);
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
        if (ch == '.') {
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
  /// a one-pixel outline over the 8-neighbourhood, so small props get the
  /// navy edge for free.
  void blob(Iterable<(int, int)> pixels, Color color, {int x = 0, int y = 0}) {
    final body = pixels.toSet();
    final edge = <(int, int)>{};
    for (final (bx, by) in body) {
      for (var dx = -1; dx <= 1; dx++) {
        for (var dy = -1; dy <= 1; dy++) {
          final n = (bx + dx, by + dy);
          if (!body.contains(n)) edge.add(n);
        }
      }
    }
    for (final (ex, ey) in edge) {
      fill(x + ex, y + ey, 1, 1, ScenePalette.outline);
    }
    for (final (fx, fy) in body) {
      fill(x + fx, y + fy, 1, 1, color);
    }
  }

  /// Filled disc of radius [r] around the pixel (cx, cy), auto-outlined.
  void disc(int cx, int cy, int r, Color color) =>
      blob(discPixels(r), color, x: cx, y: cy);

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
