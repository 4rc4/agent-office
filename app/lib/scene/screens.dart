import 'dart:ui';

import '../state/seat_state.dart';
import 'palette.dart';
import 'pixel.dart';

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

const List<double> _lineLengths = [0.75, 0.5, 0.85, 0.4, 0.65, 0.55];

/// Draws a monitor whose screen box (frame included) is (x, y, w, h). The
/// stand hangs below the box: a 2-wide neck and a base ending at y + h + 5,
/// so the desk surface band must cover y + h + 2 .. y + h + 5.
void drawMonitor(
  Px px,
  int x,
  int y,
  int w,
  int h,
  ScreenMode mode,
  int frame,
) {
  final midX = x + w ~/ 2;
  px.fill(midX - 1, y + h - 1, 2, 4, ScenePalette.outline);
  px.roundBox(midX - 6, y + h + 2, 12, 3, ScenePalette.slate);
  px.roundBox(x, y, w, h, ScenePalette.slate);

  final sx = x + 3;
  final sy = y + 3;
  final sw = w - 6;
  final sh = h - 6;
  switch (mode) {
    case ScreenMode.off:
      px.fill(sx, sy, sw, sh, ScenePalette.screenOff);
    case ScreenMode.text:
      px.fill(sx, sy, sw, sh, ScenePalette.paper);
      _lines(px, sx, sy, sw, sh, ScenePalette.paperLine, frame, prompt: false);
    case ScreenMode.terminal:
      px.fill(sx, sy, sw, sh, ScenePalette.terminalBg);
      _lines(
        px,
        sx,
        sy,
        sw,
        sh,
        ScenePalette.terminalText,
        frame,
        prompt: true,
      );
    case ScreenMode.globe:
      px.fill(sx, sy, sw, sh, ScenePalette.globeBg);
      final r = (sw < sh ? sw : sh) ~/ 2 - 2;
      final cx = sx + sw ~/ 2;
      final cy = sy + sh ~/ 2;
      px.disc(cx, cy, r, ScenePalette.globeSea);
      const spin = [-2, 0, 2, 0];
      px.fill(cx + spin[frame % 4], cy - r, 1, 2 * r + 1, ScenePalette.outline);
      px.fill(cx - r, cy, 2 * r + 1, 1, ScenePalette.outline);
    case ScreenMode.flicker:
      px.fill(
        sx,
        sy,
        sw,
        sh,
        frame.isEven ? ScenePalette.alertBright : ScenePalette.alertDim,
      );
  }
}

/// Text lines of varying length with a blinking cursor after the last one.
/// With [prompt] each line starts with a one-pixel prompt dot (terminal).
void _lines(
  Px px,
  int sx,
  int sy,
  int sw,
  int sh,
  Color color,
  int frame, {
  required bool prompt,
}) {
  final left = sx + 2;
  final usable = sw - 4;
  var i = 0;
  var y = sy + 2;
  var lastEnd = left;
  while (y < sy + sh - 2 && i < _lineLengths.length) {
    final len = (usable * _lineLengths[i]).round();
    if (prompt) {
      px.fill(left, y, 1, 1, color);
      px.fill(left + 2, y, len - 2, 1, color);
    } else {
      px.fill(left, y, len, 1, color);
    }
    lastEnd = left + len;
    y += 3;
    i++;
  }
  if (frame.isEven) {
    px.fill(lastEnd + 1, y - 3, prompt ? 2 : 1, 1, color);
  }
}
