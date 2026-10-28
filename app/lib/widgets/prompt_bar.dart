import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';
import 'office_theme.dart';

/// Where a prompt goes: the whole office (Claude plans) or one desk alone.
enum PromptMode {
  office,
  claudeOnly,
  gptOnly;

  /// The desk a direct prompt goes to; null lets Claude plan and delegate.
  Seat? get directSeat => switch (this) {
    PromptMode.office => null,
    PromptMode.claudeOnly => Seat.claude,
    PromptMode.gptOnly => Seat.gpt,
  };

  /// Dropdown label.
  String get label => switch (this) {
    PromptMode.office => Tr.modeOffice,
    PromptMode.claudeOnly => Tr.modeClaudeOnly,
    PromptMode.gptOnly => Tr.modeGptOnly,
  };
}

/// The bottom bar: status line, folder field, mode dropdown, prompt field,
/// Send and (while busy) Stop.
///
/// Enter sends, Shift+Enter inserts a newline. [onSubmit] gets the trimmed
/// prompt and the mode and returns whether the prompt was accepted; the field
/// is cleared only then. The parent owns the busy flag and the folder path.
class PromptBar extends StatefulWidget {
  const PromptBar({
    super.key,
    required this.busy,
    required this.cwd,
    required this.onSubmit,
    required this.onCwdChanged,
    required this.onStop,
    this.statusLine = '',
    this.initialMode = PromptMode.office,
  });

  /// Keys for tests and the integrator.
  static const Key promptFieldKey = Key('promptBar.prompt');
  static const Key folderFieldKey = Key('promptBar.folder');
  static const Key modeDropdownKey = Key('promptBar.mode');
  static const Key sendButtonKey = Key('promptBar.send');
  static const Key stopButtonKey = Key('promptBar.stop');
  static const Key statusLineKey = Key('promptBar.status');

  final bool busy;
  final String cwd;
  final String statusLine;
  final PromptMode initialMode;
  final Future<bool> Function(String prompt, PromptMode mode) onSubmit;
  final ValueChanged<String> onCwdChanged;
  final VoidCallback onStop;

  @override
  State<PromptBar> createState() => _PromptBarState();
}

class _PromptBarState extends State<PromptBar> {
  late final TextEditingController _prompt = TextEditingController();
  late final TextEditingController _folder = TextEditingController(
    text: widget.cwd,
  );
  late PromptMode _mode = widget.initialMode;
  bool _sending = false;

  @override
  void didUpdateWidget(PromptBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cwd != oldWidget.cwd && widget.cwd != _folder.text) {
      _folder.text = widget.cwd;
    }
  }

  @override
  void dispose() {
    _prompt.dispose();
    _folder.dispose();
    super.dispose();
  }

  bool get _canSend => !widget.busy && !_sending;

  Future<void> _send() async {
    final text = _prompt.text.trim();
    if (text.isEmpty || !_canSend) return;
    setState(() => _sending = true);
    try {
      if (await widget.onSubmit(text, _mode)) _prompt.clear();
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: OfficeColors.surface,
        border: Border(top: BorderSide(color: OfficeColors.outline, width: 2)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatusLine(text: widget.statusLine, busy: widget.busy),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(flex: 3, child: _folderField()),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: _modeDropdown()),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(child: _promptField()),
              const SizedBox(width: 8),
              if (widget.busy) ...[_stopButton(), const SizedBox(width: 8)],
              _sendButton(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _folderField() {
    return TextField(
      key: PromptBar.folderFieldKey,
      controller: _folder,
      onChanged: widget.onCwdChanged,
      style: const TextStyle(fontSize: 13),
      decoration: const InputDecoration(
        labelText: Tr.folder,
        hintText: Tr.folderHint,
        prefixIcon: Icon(Icons.folder_outlined, size: 18),
      ),
    );
  }

  Widget _modeDropdown() {
    return InputDecorator(
      decoration: const InputDecoration(labelText: Tr.mode),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<PromptMode>(
          key: PromptBar.modeDropdownKey,
          value: _mode,
          isDense: true,
          isExpanded: true,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            color: OfficeColors.text,
          ),
          dropdownColor: OfficeColors.surfaceRaised,
          borderRadius: BorderRadius.circular(10),
          items: [
            for (final mode in PromptMode.values)
              DropdownMenuItem(value: mode, child: Text(mode.label)),
          ],
          onChanged: (mode) {
            if (mode != null) setState(() => _mode = mode);
          },
        ),
      ),
    );
  }

  Widget _promptField() {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): _send,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): _send,
      },
      child: TextField(
        key: PromptBar.promptFieldKey,
        controller: _prompt,
        minLines: 1,
        maxLines: 6,
        keyboardType: TextInputType.multiline,
        textInputAction: TextInputAction.newline,
        decoration: const InputDecoration(hintText: Tr.promptHint),
      ),
    );
  }

  Widget _sendButton() {
    final spinning = widget.busy || _sending;
    return FilledButton.icon(
      key: PromptBar.sendButtonKey,
      onPressed: _canSend ? _send : null,
      icon: spinning
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: OfficeColors.textMuted,
              ),
            )
          : const Icon(Icons.send_rounded, size: 16),
      label: Text(spinning ? Tr.working : Tr.send),
    );
  }

  Widget _stopButton() {
    return OutlinedButton.icon(
      key: PromptBar.stopButtonKey,
      onPressed: widget.onStop,
      icon: const Icon(Icons.stop_rounded, size: 16, color: OfficeColors.red),
      label: const Text(Tr.stop),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.text, required this.busy});

  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Row(
      key: PromptBar.statusLineKey,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: busy ? OfficeColors.accent : OfficeColors.green,
            shape: BoxShape.circle,
            border: Border.all(color: OfficeColors.outline, width: 1.5),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text.isEmpty ? Tr.officeQuiet : text,
            style: const TextStyle(fontSize: 12, color: OfficeColors.textMuted),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
