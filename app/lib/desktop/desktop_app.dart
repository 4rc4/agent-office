import 'package:flutter/material.dart';

import '../l10n_tr.dart';
import '../runtime/office_settings.dart';
import '../state/office_model.dart';
import '../widgets/office_theme.dart';
import 'desktop_layer.dart';
import 'desktop_stage.dart';

/// The desktop-mode app: a [MaterialApp] (for the text field, buttons and
/// tooltips) whose only page is the [DesktopStage]. Nothing here paints a
/// background; the stage decides between the colour key and the dark
/// `--window` surface.
class DesktopApp extends StatelessWidget {
  const DesktopApp({
    super.key,
    required this.model,
    required this.layer,
    required this.settings,
    this.onSettingsChanged,
    this.windowed = false,
    this.animate = true,
  });

  final OfficeModel model;
  final DesktopLayer layer;
  final OfficeSettings settings;
  final ValueChanged<OfficeSettings>? onSettingsChanged;
  final bool windowed;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = officeTheme();
    return MaterialApp(
      title: Tr.appTitle,
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      color: const Color(0x00000000),
      home: DesktopStage(
        model: model,
        layer: layer,
        settings: settings,
        onSettingsChanged: onSettingsChanged,
        windowed: windowed,
        animate: animate,
      ),
    );
  }
}
