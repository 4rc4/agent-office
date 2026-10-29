import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n_tr.dart';
import '../runtime/office_settings.dart';
import '../widgets/office_theme.dart';
import 'autostart.dart';
import 'bubble_sheet.dart';
import 'model_choices.dart';

/// The settings sheet (opened from the tray): the `claude` and `codex`
/// executables with "Bul" file pickers, the permission mode, the fake mode
/// switch and "Windows ile başlat". "Kaydet" hands the new [OfficeSettings]
/// to [onSave]; executables and fake mode apply on the next start.
class SettingsBubble extends StatefulWidget {
  const SettingsBubble({
    super.key,
    required this.settings,
    required this.autostart,
    required this.onSave,
    required this.onClose,
    this.pointerX = 0.5,
  });

  static const Key claudeFieldKey = Key('settings.claude');
  static const Key codexFieldKey = Key('settings.codex');
  static const Key findClaudeKey = Key('settings.findClaude');
  static const Key findCodexKey = Key('settings.findCodex');
  static const Key modeKey = Key('settings.mode');
  static const Key fakeKey = Key('settings.fake');
  static const Key autostartKey = Key('settings.autostart');
  static const Key saveKey = Key('settings.save');
  static const Key claudeModelKey = Key('settings.claudeModel');
  static const Key claudeEffortKey = Key('settings.claudeEffort');
  static const Key codexModelKey = Key('settings.codexModel');
  static const Key codexEffortKey = Key('settings.codexEffort');

  static const double width = 380;

  /// Claude `--permission-mode` values offered.
  static const List<String> permissionModes = [
    'default',
    'acceptEdits',
    'plan',
    'bypassPermissions',
  ];

  final OfficeSettings settings;
  final Autostart autostart;
  final ValueChanged<OfficeSettings> onSave;
  final VoidCallback onClose;
  final double pointerX;

  @override
  State<SettingsBubble> createState() => _SettingsBubbleState();
}

class _SettingsBubbleState extends State<SettingsBubble> {
  late final TextEditingController _claude = TextEditingController(
    text: widget.settings.claudeExecutable,
  );
  late final TextEditingController _codex = TextEditingController(
    text: widget.settings.codexExecutable,
  );
  late String _mode = widget.settings.permissionMode;
  late bool _fake = widget.settings.fake;
  late String _claudeModel = widget.settings.claudeModel;
  late String _claudeEffort = widget.settings.claudeEffort;
  late String _codexModel = widget.settings.codexModel;
  late String _codexEffort = widget.settings.codexEffort;
  bool _autostart = false;

  @override
  void initState() {
    super.initState();
    widget.autostart.isEnabled().then((value) {
      if (mounted) setState(() => _autostart = value);
    });
  }

  @override
  void dispose() {
    _claude.dispose();
    _codex.dispose();
    super.dispose();
  }

  Future<void> _find(TextEditingController controller) async {
    try {
      final file = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'exe', extensions: ['exe', 'cmd', 'bat']),
        ],
      );
      if (file != null && mounted) setState(() => controller.text = file.path);
    } on MissingPluginException {
      // No native picker here.
    }
  }

  Future<void> _setAutostart(bool value) async {
    final state = await widget.autostart.setEnabled(value);
    if (mounted) setState(() => _autostart = state);
  }

  void _save() {
    final defaults = OfficeSettings.defaults();
    widget.onSave(
      widget.settings.copyWith(
        claudeExecutable: _claude.text.trim().isEmpty
            ? defaults.claudeExecutable
            : _claude.text.trim(),
        codexExecutable: _codex.text.trim().isEmpty
            ? defaults.codexExecutable
            : _codex.text.trim(),
        permissionMode: _mode,
        fake: _fake,
        claudeModel: _claudeModel,
        claudeEffort: _claudeEffort,
        codexModel: _codexModel,
        codexEffort: _codexEffort,
      ),
    );
    widget.onClose();
  }

  @override
  Widget build(BuildContext context) {
    final modes = [
      ...SettingsBubble.permissionModes,
      if (!SettingsBubble.permissionModes.contains(_mode)) _mode,
    ];
    return BubbleSheet(
      title: Tr.settings,
      onClose: widget.onClose,
      pointerX: widget.pointerX,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _exeRow(
            Tr.claudeExecutable,
            _claude,
            SettingsBubble.claudeFieldKey,
            SettingsBubble.findClaudeKey,
          ),
          const SizedBox(height: 6),
          _exeRow(
            Tr.codexExecutable,
            _codex,
            SettingsBubble.codexFieldKey,
            SettingsBubble.findCodexKey,
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              const Expanded(
                child: Text(Tr.permissionMode, style: PixelText.muted),
              ),
              DropdownButton<String>(
                key: SettingsBubble.modeKey,
                value: _mode,
                isDense: true,
                style: PixelText.body,
                dropdownColor: PixelColors.paperLight,
                items: [
                  for (final mode in modes)
                    DropdownMenuItem(value: mode, child: Text(mode)),
                ],
                onChanged: (mode) {
                  if (mode != null) setState(() => _mode = mode);
                },
              ),
            ],
          ),
          _choiceRow(
            Tr.claudeModel,
            SettingsBubble.claudeModelKey,
            _claudeModel,
            ['', ...ModelChoices.claudeModels],
            Tr.modelLabel,
            (v) => setState(() => _claudeModel = v),
          ),
          _choiceRow(
            Tr.claudeEffort,
            SettingsBubble.claudeEffortKey,
            _claudeEffort,
            ['', ...ModelChoices.claudeEfforts],
            Tr.effortLabel,
            (v) => setState(() => _claudeEffort = v),
          ),
          _choiceRow(
            Tr.codexModel,
            SettingsBubble.codexModelKey,
            _codexModel,
            ['', ...ModelChoices.codexModels],
            Tr.modelLabel,
            (v) => setState(() => _codexModel = v),
          ),
          _choiceRow(
            Tr.codexEffort,
            SettingsBubble.codexEffortKey,
            _codexEffort,
            ['', ...ModelChoices.codexEfforts],
            Tr.effortLabel,
            (v) => setState(() => _codexEffort = v),
          ),
          _switchRow(
            Tr.fakeMode,
            _fake,
            SettingsBubble.fakeKey,
            (v) => setState(() => _fake = v),
          ),
          _switchRow(
            Tr.startWithWindows,
            _autostart,
            SettingsBubble.autostartKey,
            _setAutostart,
          ),
          const SizedBox(height: 4),
          const Text(Tr.settingsRestartNote, style: PixelText.faint),
          const SizedBox(height: 8),
          Row(
            children: [
              const Spacer(),
              SheetButton(
                key: SettingsBubble.saveKey,
                label: Tr.save,
                icon: Icons.check_rounded,
                filled: true,
                onPressed: _save,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _exeRow(
    String label,
    TextEditingController controller,
    Key fieldKey,
    Key findKey,
  ) {
    return Row(
      children: [
        SizedBox(width: 110, child: Text(label, style: PixelText.muted)),
        Expanded(
          child: TextField(
            key: fieldKey,
            controller: controller,
            style: PixelText.body,
            cursorColor: PixelColors.ink,
            decoration: const InputDecoration(
              isDense: true,
              filled: true,
              fillColor: PixelColors.paperLight,
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(6)),
                borderSide: BorderSide(
                  color: PixelColors.paperEdge,
                  width: 1.5,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(6)),
                borderSide: BorderSide(color: PixelColors.ink, width: 2),
              ),
            ),
          ),
        ),
        const SizedBox(width: 6),
        SheetButton(
          key: findKey,
          label: Tr.find,
          onPressed: () => _find(controller),
        ),
      ],
    );
  }

  /// A labelled dropdown; a saved value outside [choices] stays selectable.
  Widget _choiceRow(
    String label,
    Key key,
    String value,
    List<String> choices,
    String Function(String) labelOf,
    ValueChanged<String> onChanged,
  ) {
    final items = [...choices, if (!choices.contains(value)) value];
    return Row(
      children: [
        Expanded(child: Text(label, style: PixelText.muted)),
        DropdownButton<String>(
          key: key,
          value: value,
          isDense: true,
          style: PixelText.body,
          dropdownColor: PixelColors.paperLight,
          items: [
            for (final choice in items)
              DropdownMenuItem(value: choice, child: Text(labelOf(choice))),
          ],
          onChanged: (choice) {
            if (choice != null) onChanged(choice);
          },
        ),
      ],
    );
  }

  Widget _switchRow(
    String label,
    bool value,
    Key key,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Expanded(child: Text(label, style: PixelText.muted)),
        Switch(
          key: key,
          value: value,
          onChanged: onChanged,
          activeThumbColor: PixelColors.ink,
          activeTrackColor: PixelColors.tab,
          inactiveThumbColor: PixelColors.inkMuted,
          inactiveTrackColor: PixelColors.paperEdge,
        ),
      ],
    );
  }
}
