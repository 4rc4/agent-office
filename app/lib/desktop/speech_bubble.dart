import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n_tr.dart';
import '../widgets/office_theme.dart';

/// The prompt bubble over a character: a rounded cream sheet with a pointer,
/// the title "Ne yapalım?", a multi-line text field, a folder button with
/// the chosen path next to it and a send button.
///
/// Enter calls [onSend] with the trimmed text (empty text is ignored),
/// Shift+Enter inserts a newline, Esc calls [onClose]. The parent owns the
/// folder: [onPickFolder] opens the picker and [folder] is what it shows.
class SpeechBubble extends StatefulWidget {
  const SpeechBubble({
    super.key,
    required this.folder,
    required this.onSend,
    required this.onClose,
    required this.onPickFolder,
    this.pointerX = 0.5,
  });

  static const Key fieldKey = Key('bubble.field');
  static const Key sendButtonKey = Key('bubble.send');
  static const Key folderButtonKey = Key('bubble.folder');
  static const Key closeButtonKey = Key('bubble.close');

  /// Width of the sheet; the parent clamps it to the screen.
  static const double width = 340;

  /// Height of the pointer under the sheet.
  static const double pointerHeight = 14;

  final String? folder;
  final ValueChanged<String> onSend;
  final VoidCallback onClose;
  final VoidCallback onPickFolder;

  /// Where the pointer tip sits along the bottom edge, 0..1 of the width.
  final double pointerX;

  @override
  State<SpeechBubble> createState() => _SpeechBubbleState();
}

class _SpeechBubbleState extends State<SpeechBubble> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _field = FocusNode(debugLabel: 'bubbleField');

  @override
  void initState() {
    super.initState();
    // Not `autofocus`: the stage's own focus node already holds focus in
    // this scope, which would make autofocus a no-op.
    _field.requestFocus();
  }

  @override
  void dispose() {
    _text.dispose();
    _field.dispose();
    super.dispose();
  }

  void _send() {
    final prompt = _text.text.trim();
    if (prompt.isEmpty) return;
    widget.onSend(prompt);
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BubblePainter(pointerX: widget.pointerX),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          14,
          10,
          14,
          12 + SpeechBubble.pointerHeight,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _title(),
            const SizedBox(height: 6),
            _promptField(),
            const SizedBox(height: 8),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _title() {
    return Row(
      children: [
        const Expanded(child: Text(Tr.whatShallWeDo, style: PixelText.title)),
        SizedBox(
          width: 24,
          height: 24,
          child: IconButton(
            key: SpeechBubble.closeButtonKey,
            onPressed: widget.onClose,
            padding: EdgeInsets.zero,
            iconSize: 18,
            color: PixelColors.inkMuted,
            tooltip: Tr.close,
            icon: const Icon(Icons.close_rounded),
          ),
        ),
      ],
    );
  }

  Widget _promptField() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _send,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _send,
        const SingleActivator(LogicalKeyboardKey.escape): widget.onClose,
      },
      child: TextField(
        key: SpeechBubble.fieldKey,
        controller: _text,
        focusNode: _field,
        minLines: 2,
        maxLines: 5,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        style: PixelText.body,
        cursorColor: PixelColors.ink,
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: PixelColors.paperLight,
          hintText: Tr.desktopPromptHint,
          hintStyle: PixelText.faint,
          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
            borderSide: BorderSide(color: PixelColors.paperEdge, width: 1.5),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(6)),
            borderSide: BorderSide(color: PixelColors.ink, width: 2),
          ),
        ),
      ),
    );
  }

  Widget _footer() {
    final folder = widget.folder;
    return Row(
      children: [
        OutlinedButton.icon(
          key: SpeechBubble.folderButtonKey,
          onPressed: widget.onPickFolder,
          style: OutlinedButton.styleFrom(
            foregroundColor: PixelColors.ink,
            side: const BorderSide(color: PixelColors.ink, width: 1.5),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.folder_outlined, size: 16),
          label: const Text(Tr.folder, style: PixelText.label),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Tooltip(
            message: folder ?? Tr.noFolder,
            child: Text(
              folder ?? Tr.noFolder,
              style: folder == null ? PixelText.faint : PixelText.muted,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.left,
            ),
          ),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: SpeechBubble.sendButtonKey,
          onPressed: _send,
          style: FilledButton.styleFrom(
            backgroundColor: PixelColors.tab,
            foregroundColor: PixelColors.ink,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, 32),
            visualDensity: VisualDensity.compact,
          ),
          icon: const Icon(Icons.send_rounded, size: 14),
          label: const Text(Tr.send, style: PixelText.label),
        ),
      ],
    );
  }
}

/// Paper sheet with a navy outline, a solid drop shadow and a pointer at
/// the bottom. Solid colours only: the desktop layer is colour keyed.
class _BubblePainter extends CustomPainter {
  const _BubblePainter({required this.pointerX});

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
      size.height - SpeechBubble.pointerHeight - outline / 2,
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
  bool shouldRepaint(_BubblePainter old) => old.pointerX != pointerX;
}
