import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;

import '../l10n_tr.dart';
import '../widgets/office_theme.dart';
import 'bubble_sheet.dart';
import 'choice_widgets.dart';
import 'folder_name.dart';
import 'model_choices.dart';

/// The prompt bubble over a character: a title per seat ("Ne yapalım?" for
/// Claude, who plans; "GPT ne yapsın?" for a direct task), a multi-line text
/// field, a folder button with the chosen path, chips of the last folders
/// and a send button.
///
/// Enter calls [onSend] with the trimmed text (empty text is ignored),
/// Shift+Enter inserts a newline, Esc calls [onClose]. The parent owns the
/// folder ([onPickFolder] opens the picker, [onFolderChosen] takes a chip),
/// the run [options] (a model chip and an effort chip, menus from
/// [ModelChoices] for [seat]) and the [attachments] ("Dosya" calls
/// [onPickFiles]; a chip's cross calls [onRemoveAttachment]).
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
    this.seat = Seat.claude,
    this.options = const PromptOptions(),
    this.onOptionsChanged,
    this.attachments = const [],
    this.onPickFiles,
    this.onRemoveAttachment,
    this.pointerX = 0.5,
  });

  static const Key fieldKey = Key('bubble.field');
  static const Key sendButtonKey = Key('bubble.send');
  static const Key folderButtonKey = Key('bubble.folder');
  static const Key modelChipKey = Key('bubble.model');
  static const Key effortChipKey = Key('bubble.effort');
  static const Key filesButtonKey = Key('bubble.files');
  static Key attachmentKey(String path) => Key('bubble.attachment.$path');

  /// Width of the sheet; the parent clamps it to the screen.
  static const double width = 360;

  final String title;
  final String? folder;
  final List<String> recentFolders;
  final ValueChanged<String> onSend;
  final VoidCallback onClose;
  final VoidCallback onPickFolder;
  final ValueChanged<String> onFolderChosen;
  final Seat seat;
  final PromptOptions options;
  final ValueChanged<PromptOptions>? onOptionsChanged;
  final List<String> attachments;
  final VoidCallback? onPickFiles;
  final ValueChanged<String>? onRemoveAttachment;
  final double pointerX;

  @override
  State<PromptBubble> createState() => _PromptBubbleState();
}

class _PromptBubbleState extends State<PromptBubble> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _field = FocusNode(debugLabel: 'promptField');

  /// Which choice is open under the chips: 'model', 'effort' or null.
  String? _menu;

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
          const SizedBox(height: 6),
          _optionsRow(),
          const SizedBox(height: 6),
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
                child: Text(
                  folder ?? Tr.noFolder,
                  style: folder == null ? PixelText.faint : PixelText.muted,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                  ActionChip(
                    label: Text(folderName(f), style: PixelText.faint),
                    onPressed: () => widget.onFolderChosen(f),
                    backgroundColor: PixelColors.paperLight,
                    side: const BorderSide(color: PixelColors.paperEdge),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Model chip, effort chip, the file button and the attachment chips;
  /// an open chip lists its choices right below, inside the bubble.
  Widget _optionsRow() {
    final options = widget.options;
    final menu = _menu;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 4,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ValueChip(
              key: PromptBubble.modelChipKey,
              label: '${Tr.model}: ${Tr.modelLabel(options.model)}',
              open: menu == 'model',
              onTap: () => _toggle('model'),
            ),
            ValueChip(
              key: PromptBubble.effortChipKey,
              label: '${Tr.effort}: ${Tr.effortLabel(options.effort)}',
              open: menu == 'effort',
              onTap: () => _toggle('effort'),
            ),
            SheetButton(
              key: PromptBubble.filesButtonKey,
              label: Tr.files,
              icon: Icons.attach_file_rounded,
              onPressed: widget.onPickFiles,
            ),
            for (final path in widget.attachments)
              Container(
                key: PromptBubble.attachmentKey(path),
                padding: const EdgeInsets.only(left: 8, right: 2),
                decoration: BoxDecoration(
                  color: PixelColors.paperLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: PixelColors.paperEdge, width: 1.5),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(p.basename(path), style: PixelText.faint),
                    InkWell(
                      onTap: () => widget.onRemoveAttachment?.call(path),
                      borderRadius: BorderRadius.circular(10),
                      child: const Padding(
                        padding: EdgeInsets.all(3),
                        child: Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: PixelColors.ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
        if (menu == 'model') ...[
          const SizedBox(height: 4),
          ChoiceStrip(
            choices: ['', ...ModelChoices.modelsFor(widget.seat)],
            selected: options.model,
            labelOf: Tr.modelLabel,
            onChosen: (m) => _choose(options.copyWith(model: m)),
          ),
        ],
        if (menu == 'effort') ...[
          const SizedBox(height: 4),
          ChoiceStrip(
            choices: ['', ...ModelChoices.effortsFor(widget.seat)],
            selected: options.effort,
            labelOf: Tr.effortLabel,
            onChosen: (e) => _choose(options.copyWith(effort: e)),
          ),
        ],
      ],
    );
  }

  void _toggle(String menu) =>
      setState(() => _menu = _menu == menu ? null : menu);

  void _choose(PromptOptions next) {
    setState(() => _menu = null);
    widget.onOptionsChanged?.call(next);
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
