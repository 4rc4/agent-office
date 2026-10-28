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

/// Colour a lit screen throws onto the desk, or 0 when it is off.
int screenGlow(ScreenMode mode, int frame) => switch (mode) {
  ScreenMode.off => 0,
  ScreenMode.text => Palette.paper,
  ScreenMode.terminal => Palette.terminalText,
  ScreenMode.globe => Palette.globeSea,
  ScreenMode.flicker => frame.isEven ? Palette.alertBright : Palette.alertDim,
};

const List<double> _lineLengths = [0.7, 0.45, 0.85, 0.35, 0.6, 0.5, 0.75];

/// Monitor whose bezel box is [m]. The stand hangs below it: a neck and a
/// base ending at m.bottom + 6, which the desk surface band must cover.
void paintMonitor(PixelBuffer b, IRect m, ScreenMode mode, int frame) {
  final midX = m.centerX;
  // Stand.
  b.fill(midX - 2, m.bottom - 1, 4, 5, Palette.slateShade);
  b.vline(midX - 2, m.bottom - 1, 5, Palette.slateLight);
  b.vline(midX + 1, m.bottom - 1, 5, Palette.slateDark);
  b.shadeRect(
    midX - 9,
    m.bottom + 3,
    18,
    3,
    base: Palette.slateBase,
    light: Palette.slateLight,
    dark: Palette.slateDark,
    rounded: true,
  );
  b.hline(midX - 8, m.bottom + 6, 19, PixelBuffer.shadowOf(Palette.woodLight));
  // Bezel.
  b.roundFill(m.x, m.y, m.w, m.h, Palette.slateBase);
  b.roundRing(m.x, m.y, m.w, m.h, Palette.slateDark);
  b.hline(m.x + 1, m.y + 1, m.w - 2, Palette.slateLight);
  b.vline(m.x + 1, m.y + 1, m.h - 2, Palette.slateLight);
  b.hline(m.x + 1, m.bottom - 2, m.w - 2, Palette.slateShade);
  b.vline(m.right - 2, m.y + 1, m.h - 2, Palette.slateShade);
  b.set(m.right - 4, m.bottom - 2, Palette.amber);

  final sx = m.x + 3;
  final sy = m.y + 3;
  final sw = m.w - 6;
  final sh = m.h - 6;
  // The glass gives off its own light: never tinted by the room.
  b.emissive(() => _screen(b, sx, sy, sw, sh, mode, frame));
  // Glossy reflection in the top-left corner of the glass.
  b.emissive(() {
    for (var i = 0; i < 6; i++) {
      final x = sx + 1 + i;
      final y = sy + 6 - i;
      if (y >= sy) b.set(x, y, PixelBuffer.lightOf(b.get(x, y)));
    }
  });
}

void _screen(
  PixelBuffer b,
  int sx,
  int sy,
  int sw,
  int sh,
  ScreenMode mode,
  int frame,
) {
  switch (mode) {
    case ScreenMode.off:
      b.fill(sx, sy, sw, sh, Palette.screenOff);
      b.fill(sx + 2, sy + 2, 6, 4, Palette.screenGlint);
      b.fill(sx + 9, sy + 2, 3, 4, Palette.screenGlint);
    case ScreenMode.text:
      b.fill(sx, sy, sw, sh, Palette.paper);
      b.fill(sx, sy, sw, 3, Palette.steelLight);
      b.set(sx + 1, sy + 1, Palette.red);
      b.set(sx + 3, sy + 1, Palette.amber);
      b.set(sx + 5, sy + 1, Palette.green);
      b.fill(sx, sy + 3, 4, sh - 3, Palette.paperShade);
      _lines(
        b,
        sx + 4,
        sy + 3,
        sw - 4,
        sh - 3,
        Palette.paperLine,
        frame,
        prompt: false,
      );
    case ScreenMode.terminal:
      b.fill(sx, sy, sw, sh, Palette.terminalBg);
      _lines(b, sx, sy, sw, sh, Palette.terminalText, frame, prompt: true);
    case ScreenMode.globe:
      b.fill(sx, sy, sw, sh, Palette.globeBg);
      final r = (sw < sh ? sw : sh) ~/ 2 - 2;
      final cx = sx + sw ~/ 2;
      final cy = sy + sh ~/ 2;
      b.disc(cx, cy, r, Palette.globeSea, outline: Palette.screenOff);
      final spin = (frame % 4) * 2 - 3;
      for (final (dx, dy) in PixelBuffer.discPixels(r - 1)) {
        final lx = dx - spin;
        final land =
            (lx >= -5 && lx <= -2 && dy >= -4 && dy <= 1) ||
            (lx >= 1 && lx <= 5 && dy >= -2 && dy <= 3) ||
            (lx >= -3 && lx <= 0 && dy >= 3 && dy <= 5);
        if (land) b.set(cx + dx, cy + dy, Palette.globeLand);
      }
      for (final (dx, dy) in PixelBuffer.discPixels(r)) {
        if (dx + dy <= -r + 1) b.set(cx + dx, cy + dy, Palette.water);
      }
    case ScreenMode.flicker:
      final bright = frame.isEven;
      b.fill(sx, sy, sw, sh, bright ? Palette.alertBright : Palette.alertDim);
      for (var y = sy; y < sy + sh; y++) {
        for (var x = sx; x < sx + sw; x++) {
          if (((x + y + frame) ~/ 3) % 2 == 0) {
            b.set(x, y, bright ? Palette.alertDim : Palette.alertBright);
          }
        }
      }
      b.disc(sx + sw ~/ 2, sy + sh ~/ 2, 3, Palette.paper, outline: Palette.alertDim);
      b.set(sx + sw ~/ 2, sy + sh ~/ 2 - 1, Palette.alertDim);
      b.set(sx + sw ~/ 2, sy + sh ~/ 2 + 1, Palette.alertDim);
  }
}

/// Text lines of varying length with a blinking cursor after the last one.
/// With [prompt] each line starts with a prompt dot (terminal).
void _lines(
  PixelBuffer b,
  int sx,
  int sy,
  int sw,
  int sh,
  int color,
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
      b.set(left, y, Palette.terminalDim);
      b.hline(left + 2, y, len - 2, color);
    } else {
      b.hline(left, y, len, color);
      if (i % 3 == 1) b.hline(left, y, 3, Palette.violet);
      if (i % 3 == 2) b.hline(left + len - 3, y, 3, Palette.teal);
    }
    lastEnd = left + len;
    y += 3;
    i++;
  }
  if (frame.isEven) {
    b.hline(lastEnd + 1, y - 3, prompt ? 2 : 1, color);
  }
}
