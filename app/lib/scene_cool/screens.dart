import 'dart:ui';

import '../state/seat_state.dart';
import 'palette.dart';
import 'pixel.dart';
import 'scene_layout.dart';

/// What a monitor shows.
enum ScreenMode { off, text, terminal, globe, flicker }

/// Screen content for a seat visual.
ScreenMode screenFor(SeatVisual visual) => switch (visual) {
  SeatVisual.empty ||
  SeatVisual.idle ||
  SeatVisual.sleeping ||
  SeatVisual.arriving ||
  SeatVisual.onBreak => ScreenMode.off,
  SeatVisual.shell => ScreenMode.terminal,
  SeatVisual.browsing => ScreenMode.globe,
  SeatVisual.failed => ScreenMode.flicker,
  _ => ScreenMode.text,
};

/// Glow colour a screen mode throws on the desk, or null when dark.
Color? screenGlow(ScreenMode mode) => switch (mode) {
  ScreenMode.off => null,
  ScreenMode.text => ScenePalette.glowTeal,
  ScreenMode.terminal => ScenePalette.glowGreen,
  ScreenMode.globe => ScenePalette.glowTeal,
  ScreenMode.flicker => ScenePalette.glowRed,
};

/// Monitor bezel, stand and power LED. The screen box (bezel included) is
/// (x, y, w, h); the stand hangs below it: a neck and a base ending at
/// y + h + 7, so the desk surface band must cover that.
void drawMonitorBody(Px px, int x, int y, int w, int h) {
  final slate = ScenePalette.slate;
  final midX = x + w ~/ 2;
  // Base and neck.
  px.shadeRect(midX - 9, y + h + 4, 18, 3, slate, outline: true, rounded: true);
  px.fill(midX - 2, y + h - 1, 4, 6, slate.base);
  px.vline(midX - 2, y + h - 1, 6, slate.light);
  px.vline(midX + 1, y + h - 1, 6, slate.dark);
  // Bezel.
  px.shadeRect(x, y, w, h, slate, outline: true, rounded: true, bevel: 1);
  px.hline(x + 2, y + 1, w - 4, ScenePalette.steel.base);
  px.vline(x + 1, y + 2, h - 4, ScenePalette.steel.shade);
  px.ring(x + 2, y + 2, w - 4, h - 4, slate.dark);
}

const List<double> _lineLengths = [0.7, 0.45, 0.85, 0.35, 0.6, 0.5, 0.75];

/// Screen content inside the monitor box (x, y, w, h) incl. bezel.
void drawScreen(Px px, int x, int y, int w, int h, ScreenMode mode, int frame) {
  final sx = x + 3;
  final sy = y + 3;
  final sw = w - 6;
  final sh = h - 6;
  switch (mode) {
    case ScreenMode.off:
      px.fill(sx, sy, sw, sh, ScenePalette.screenOff);
      for (var i = 0; i < sh; i++) {
        final start = sx + sw - 12 - i;
        px.hline(start, sy + i, 6, ScenePalette.screenOffReflect);
      }
      px.dot(x + w - 6, y + h - 2, ScenePalette.slate.light);
    case ScreenMode.text:
      px.fill(sx, sy, sw, sh, ScenePalette.editorBg);
      px.fill(sx, sy, 3, sh, ScenePalette.editorGutter);
      _codeLines(px, sx + 4, sy, sw - 5, sh, frame);
      px.dot(x + w - 6, y + h - 2, ScenePalette.led);
    case ScreenMode.terminal:
      px.fill(sx, sy, sw, sh, ScenePalette.terminalBg);
      px.hline(sx, sy, sw, ScenePalette.terminalDim);
      _terminalLines(px, sx, sy + 2, sw, sh - 2, frame);
      px.dot(x + w - 6, y + h - 2, ScenePalette.led);
    case ScreenMode.globe:
      px.fill(sx, sy, sw, sh, ScenePalette.globeBg);
      px.fill(sx, sy, sw, 3, ScenePalette.editorGutter);
      px.hline(sx + 2, sy + 1, sw - 8, ScenePalette.slate.light);
      px.dot(sx + sw - 3, sy + 1, ScenePalette.red);
      final r = ((sw < sh ? sw : sh) ~/ 2) - 3;
      final cx = sx + sw ~/ 2;
      final cy = sy + 3 + (sh - 3) ~/ 2;
      px.discFill(cx, cy, r, ScenePalette.globeSea);
      const spin = [-2, -1, 0, 1];
      final s = spin[frame % 4];
      for (final (dx, dy) in Px.discPixels(r)) {
        if (dx * dx + dy * dy >= (r - 1) * (r - 1) && dx + dy > 0) {
          px.dot(cx + dx, cy + dy, ScenePalette.waterDark);
        }
      }
      px.fill(cx + s - 2, cy - 3, 3, 2, ScenePalette.globeLand);
      px.fill(cx + s - 3, cy - 1, 4, 2, ScenePalette.globeLand);
      px.fill(cx + s + 1, cy + 1, 2, 3, ScenePalette.globeLand);
      px.dot(cx + s - 1, cy + 3, ScenePalette.globeLand);
      px.dot(cx - r + 1, cy - 1, Color(0xFFBFF2FF));
      px.dot(x + w - 6, y + h - 2, ScenePalette.led);
    case ScreenMode.flicker:
      final bright = frame.isEven;
      px.fill(
        sx,
        sy,
        sw,
        sh,
        bright ? ScenePalette.alertBright : ScenePalette.alertDim,
      );
      final text = bright ? ScenePalette.alertDim : ScenePalette.alertBright;
      var ly = sy + 3;
      for (var i = 0; i < 3 && ly < sy + sh - 2; i++) {
        px.hline(sx + 2, ly, (sw * (0.6 - i * 0.15)).round(), text);
        ly += 3;
      }
      px.fill(sx + sw - 8, sy + sh - 8, 5, 5, text);
      px.fill(
        sx + sw - 7,
        sy + sh - 7,
        3,
        3,
        bright ? ScenePalette.alertBright : ScenePalette.alertDim,
      );
      px.dot(x + w - 6, y + h - 2, ScenePalette.red);
  }
  // Glass reflection on the top-left corner.
  for (var i = 0; i < 5; i++) {
    px.dot(sx + 1 + i, sy + 5 - i, ScenePalette.glassHighlight);
  }
  for (var i = 0; i < 3; i++) {
    px.dot(sx + 4 + i, sy + 6 - i, ScenePalette.glassHighlight);
  }
}

/// Glow the screen throws on the desk surface in front of the monitor and
/// on the wall behind it.
void drawScreenGlow(Px px, IRect m, ScreenMode mode, {required bool onDesk}) {
  final color = screenGlow(mode);
  if (color == null) return;
  if (onDesk) {
    px.dither(m.x - 2, m.bottom + 7, m.w + 4, 3, null, color);
    px.dither(
      m.x - 6,
      m.bottom + 10,
      m.w + 12,
      3,
      null,
      color,
      pattern: Dither.quarter,
    );
  } else {
    px.dither(
      m.x - 4,
      m.y - 3,
      m.w + 8,
      m.h + 6,
      null,
      color,
      pattern: Dither.quarter,
    );
    px.dither(m.x - 2, m.y - 1, m.w + 4, m.h + 2, null, color);
  }
}

/// Editor: coloured code tokens on each line, blinking cursor after the
/// last one.
void _codeLines(Px px, int left, int top, int width, int height, int frame) {
  var y = top + 2;
  var i = 0;
  var lastEnd = left;
  const tokens = [
    [ScenePalette.codeViolet, ScenePalette.codePale, ScenePalette.codeTeal],
    [ScenePalette.codePale, ScenePalette.codeOrange],
    [ScenePalette.codeTeal, ScenePalette.codePale, ScenePalette.codeOrange],
    [ScenePalette.codePale],
    [ScenePalette.codeViolet, ScenePalette.codeTeal],
    [ScenePalette.codePale, ScenePalette.codeOrange, ScenePalette.codePale],
    [ScenePalette.codeTeal, ScenePalette.codePale],
  ];
  while (y < top + height - 2 && i < _lineLengths.length) {
    final indent = (i % 3) * 2;
    final total = ((width - indent) * _lineLengths[i]).round();
    final parts = tokens[i % tokens.length];
    var x = left + indent;
    var remaining = total;
    for (var p = 0; p < parts.length; p++) {
      final len = p == parts.length - 1 ? remaining : (total ~/ parts.length);
      if (len <= 0) break;
      px.hline(x, y, len, parts[p]);
      x += len + 1;
      remaining -= len + 1;
    }
    lastEnd = left + indent + total;
    y += 3;
    i++;
  }
  if (frame.isEven) px.fill(lastEnd + 1, y - 3, 1, 2, ScenePalette.codePale);
}

/// Terminal: prompt dots and green text with a block cursor.
void _terminalLines(
  Px px,
  int left,
  int top,
  int width,
  int height,
  int frame,
) {
  var y = top + 1;
  var i = 0;
  var lastEnd = left + 2;
  while (y < top + height - 2 && i < _lineLengths.length) {
    final len = ((width - 6) * _lineLengths[i]).round();
    px.dot(left + 2, y, ScenePalette.terminalDim);
    px.hline(
      left + 4,
      y,
      len,
      i % 4 == 1 ? ScenePalette.terminalDim : ScenePalette.terminalText,
    );
    lastEnd = left + 4 + len;
    y += 3;
    i++;
  }
  if (frame.isEven) {
    px.fill(lastEnd + 1, y - 3, 2, 2, ScenePalette.terminalText);
  }
}
