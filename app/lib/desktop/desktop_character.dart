import 'package:flutter/widgets.dart';

import '../scene/palette.dart';
import '../scene/pixel.dart';
import '../scene/sprites.dart';

/// What the desktop character is doing. Step 2 maps engine visuals here.
enum DesktopVisual { idle, typing }

/// Claude standing on the desktop: the shaded 24x32 beanie sprite of the
/// room scene at an integer [scale], with its 2-frame breathing idle and a
/// 4-frame typing pose (hands alternating over a small tablet).
///
/// The widget's bottom edge is the floor. One spare sprite row at the top
/// gives the hover [bob] room above the ears.
class DesktopCharacter extends StatelessWidget {
  const DesktopCharacter({
    super.key,
    required this.visual,
    required this.tick,
    this.hovered = false,
    this.scale = 4,
  });

  final DesktopVisual visual;

  /// Animation clock; the frame is `tick % 4`.
  final int tick;

  /// Bobs one sprite pixel up and down while the pointer is on the sprite.
  final bool hovered;

  /// Device pixels per sprite pixel.
  final int scale;

  /// Sprite rows: one bob row, the ear rows and the 32-row sprite box.
  static const int rows = 1 + spriteEarRows + spriteHeight;

  /// Logical size of the widget at [scale].
  Size get size =>
      Size((spriteWidth * scale).toDouble(), (rows * scale).toDouble());

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: size,
      painter: _CharacterPainter(
        visual: visual,
        frame: tick % 4,
        bob: hovered && tick.isEven ? -1 : 0,
        scale: scale,
      ),
    );
  }
}

class _CharacterPainter extends CustomPainter {
  const _CharacterPainter({
    required this.visual,
    required this.frame,
    required this.bob,
    required this.scale,
  });

  final DesktopVisual visual;
  final int frame;
  final int bob;
  final int scale;

  /// Row of the sprite box's top edge inside the buffer.
  static const int baseY = 1 + spriteEarRows;

  @override
  void paint(Canvas canvas, Size size) {
    final b = PixelBuffer(spriteWidth, DesktopCharacter.rows);
    _drawShadow(b);
    final breath = frame ~/ 2 == 1 ? 1 : 0;
    final pose = switch (visual) {
      DesktopVisual.idle => CharacterPose(
        stance: Stance.standing,
        headDy: breath,
        dy: bob,
      ),
      DesktopVisual.typing => CharacterPose(
        stance: Stance.standing,
        arms: Arms.onDesk,
        dy: bob,
      ),
    };
    drawCharacter(
      b,
      0,
      baseY,
      pose,
      CharacterPalette.claude,
      CharacterStyle.beanie,
    );
    if (visual == DesktopVisual.typing) _drawTablet(b, bob);
    canvas.save();
    canvas.scale(scale.toDouble());
    b.emit(canvas);
    canvas.restore();
  }

  /// Dithered ink ellipse under the feet: a soft shadow without alpha, so it
  /// survives the colour-keyed window.
  void _drawShadow(PixelBuffer b) {
    const cy = DesktopCharacter.rows - 1;
    const cx = spriteWidth ~/ 2;
    for (var y = -1; y <= 0; y++) {
      for (var x = -8; x <= 7; x++) {
        final edge = x < -5 || x > 4 || y == -1;
        if (edge && ((x + y) & 1) == 0) continue;
        b.set(cx + x, cy + y, Palette.ink);
      }
    }
  }

  /// A small tablet held at the waist and two hands typing on it; the hands
  /// alternate lifting one pixel every two frames.
  void _drawTablet(PixelBuffer b, int dy) {
    final y = baseY + dy;
    b.shadeRect(
      7,
      y + 19,
      10,
      5,
      base: Palette.slateBase,
      light: Palette.slateLight,
      dark: Palette.slateDark,
    );
    b.fill(8, y + 20, 8, 3, Palette.terminalBg);
    b.hline(9, y + 21, 2 + frame % 3, Palette.terminalText);
    const hand = ['.kkkk.', 'kLsssk', 'kssSSk', '.kkkk.'];
    const legend = {
      'k': CharacterPalette.skinOutline,
      'L': CharacterPalette.skinLight,
      's': CharacterPalette.skin,
      'S': CharacterPalette.skinShade,
    };
    final phase = frame ~/ 2;
    b.sprite(5, y + 21 - (phase == 0 ? 1 : 0), hand, legend);
    b.sprite(13, y + 21 - (phase == 1 ? 1 : 0), hand, legend);
  }

  @override
  bool shouldRepaint(_CharacterPainter old) =>
      old.visual != visual ||
      old.frame != frame ||
      old.bob != bob ||
      old.scale != scale;
}
