import 'package:flutter/material.dart';

import '../widgets/office_theme.dart';

/// A cream sheet with a navy outline, a solid drop shadow and a pointer at
/// the bottom: the frame of every bubble on the desktop. [title] is set in
/// the pixel face; the close button calls [onClose]. Solid colours only,
/// because the desktop layer is colour keyed.
class BubbleSheet extends StatelessWidget {
  const BubbleSheet({
    super.key,
    required this.title,
    required this.onClose,
    required this.child,
    this.pointerX = 0.5,
    this.titleColor = PixelColors.ink,
  });

  static const Key closeButtonKey = Key('bubble.close');

  /// Height of the pointer under the sheet.
  static const double pointerHeight = 14;

  final String title;
  final VoidCallback onClose;
  final Widget child;

  /// Where the pointer tip sits along the bottom edge, 0..1 of the width.
  final double pointerX;
  final Color titleColor;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SheetPainter(pointerX: pointerX),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 12 + pointerHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: PixelText.title.copyWith(color: titleColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SizedBox(
                  width: 24,
                  height: 24,
                  child: IconButton(
                    key: closeButtonKey,
                    onPressed: onClose,
                    padding: EdgeInsets.zero,
                    iconSize: 18,
                    color: PixelColors.inkMuted,
                    icon: const Icon(Icons.close_rounded),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            child,
          ],
        ),
      ),
    );
  }
}

class _SheetPainter extends CustomPainter {
  const _SheetPainter({required this.pointerX});

  final double pointerX;

  static const double radius = 12;
  static const double outline = 2;
  static const double shadowOffset = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final sheet = Rect.fromLTWH(
      outline / 2,
      outline / 2,
      size.width - outline,
      size.height - BubbleSheet.pointerHeight - outline / 2,
    );
    final tipX = (size.width * pointerX).clamp(
      radius + 12,
      size.width - radius - 12,
    );
    final pointer = Path()
      ..moveTo(tipX - 10, sheet.bottom - 1)
      ..lineTo(tipX, size.height - outline / 2)
      ..lineTo(tipX + 10, sheet.bottom - 1)
      ..close();
    final shape = Path.combine(
      PathOperation.union,
      Path()..addRRect(RRect.fromRectAndRadius(sheet, Radius.circular(radius))),
      pointer,
    );
    canvas.save();
    canvas.translate(shadowOffset, shadowOffset);
    canvas.drawPath(shape, Paint()..color = PixelColors.shadow);
    canvas.restore();
    canvas.drawPath(shape, Paint()..color = PixelColors.paper);
    canvas.drawPath(
      shape,
      Paint()
        ..color = PixelColors.ink
        ..style = PaintingStyle.stroke
        ..strokeWidth = outline
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(_SheetPainter old) => old.pointerX != pointerX;
}

/// Small pixel-face button on paper: outlined by default, [filled] for the
/// primary action.
class SheetButton extends StatelessWidget {
  const SheetButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.filled = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final text = Text(label, style: PixelText.label);
    if (filled) {
      final style = FilledButton.styleFrom(
        backgroundColor: PixelColors.tab,
        foregroundColor: PixelColors.ink,
        disabledBackgroundColor: PixelColors.disabled,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        minimumSize: const Size(0, 32),
        visualDensity: VisualDensity.compact,
      );
      return icon == null
          ? FilledButton(onPressed: onPressed, style: style, child: text)
          : FilledButton.icon(
              onPressed: onPressed,
              style: style,
              icon: Icon(icon, size: 14),
              label: text,
            );
    }
    final style = OutlinedButton.styleFrom(
      foregroundColor: PixelColors.ink,
      side: const BorderSide(color: PixelColors.ink, width: 1.5),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      minimumSize: const Size(0, 32),
      visualDensity: VisualDensity.compact,
    );
    return icon == null
        ? OutlinedButton(onPressed: onPressed, style: style, child: text)
        : OutlinedButton.icon(
            onPressed: onPressed,
            style: style,
            icon: Icon(icon, size: 16),
            label: text,
          );
  }
}
