import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n_tr.dart';
import '../widgets/office_theme.dart';
import 'bubble_sheet.dart';
import 'folder_name.dart';

/// The prompt bubble over a character: a title per seat ("Ne yapalım?" for
/// Claude, who plans; "GPT ne yapsın?" for a direct task), a multi-line text
/// field, a folder button with the chosen path, chips of the last folders
/// and a send button.
///
/// Enter calls [onSend] with the trimmed text (empty text is ignored),
/// Shift+Enter inserts a newline, Esc calls [onClose]. The parent owns the
/// folder: [onPickFolder] opens the picker, [onFolderChosen] takes a chip.
class PromptBubble extends StatefulWidget {
  const PromptBubble({
    super.key,
    required this.title,
    required this.folder,
    required this.recentFolders,
    required this.onSend,
    required this.onClose,
    required this.onPickFolder,
    required this.onFolderChosen,
    this.pointerX = 0.5,
  });

  static const Key fieldKey = Key('bubble.field');
  static const Key sendButtonKey = Key('bubble.send');
  static const Key folderButtonKey = Key('bubble.folder');

  /// Width of the sheet; the parent clamps it to the screen.
  static const double width = 360;

  final String title;
  final String? folder;
  final List<String> recentFolders;
  final ValueChanged<String> onSend;
  final VoidCallback onClose;
  final VoidCallback onPickFolder;
  final ValueChanged<String> onFolderChosen;
  final double pointerX;

  @override
  State<PromptBubble> createState() => _PromptBubbleState();
}

class _PromptBubbleState extends State<PromptBubble> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _field = FocusNode(debugLabel: 'promptField');

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
    final folder = widget.folder;
    final chips = widget.recentFolders.where((f) => f != folder).toList();
    return BubbleSheet(
      title: widget.title,
      onClose: widget.onClose,
      pointerX: widget.pointerX,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _promptField(),
          const SizedBox(height: 8),
          Row(
            children: [
              SheetButton(
                key: PromptBubble.folderButtonKey,
                label: Tr.folder,
                icon: Icons.folder_outlined,
                onPressed: widget.onPickFolder,
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
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SheetButton(
                key: PromptBubble.sendButtonKey,
                label: Tr.send,
                icon: Icons.send_rounded,
                filled: true,
                onPressed: _send,
              ),
            ],
          ),
          if (chips.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final f in chips)
                  Tooltip(
                    message: f,
                    child: ActionChip(
                      label: Text(folderName(f), style: PixelText.faint),
                      onPressed: () => widget.onFolderChosen(f),
                      backgroundColor: PixelColors.paperLight,
                      side: const BorderSide(color: PixelColors.paperEdge),
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
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
        key: PromptBubble.fieldKey,
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
}
