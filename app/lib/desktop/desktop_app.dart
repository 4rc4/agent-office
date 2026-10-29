import 'package:flutter/material.dart';

import '../l10n_tr.dart';
import '../runtime/office_settings.dart';
import '../state/office_model.dart';
import '../widgets/office_theme.dart';
import 'autostart.dart';
import 'desktop_layer.dart';
import 'desktop_stage.dart';
import 'open_external.dart';
import 'wallpaper.dart';

/// The desktop-mode app: a [MaterialApp] (for the text field, buttons and
/// tooltips) whose only page is the [DesktopStage]. Nothing here paints a
/// background; the stage decides between the wallpaper copy and the dark
/// `--window` surface.
class DesktopApp extends StatelessWidget {
  const DesktopApp({
    super.key,
    required this.model,
    required this.layer,
    required this.settings,
    this.onSettingsChanged,
    this.commands,
    this.autostart = const NoAutostart(),
    this.wallpaper,
    this.pickFiles,
    this.openExternal,
    this.windowed = false,
    this.animate = true,
  });

  final OfficeModel model;
  final DesktopLayer layer;
  final OfficeSettings settings;
  final ValueChanged<OfficeSettings>? onSettingsChanged;
  final DesktopCommands? commands;
  final Autostart autostart;

  /// The wallpaper copy for the first frame, see
  /// [DesktopStage.initialWallpaper].
  final DesktopWallpaper? wallpaper;

  /// Replaces the native file picker, see [DesktopStage.pickFiles].
  final Future<List<String>> Function()? pickFiles;

  /// Opens report folders; null builds the real launcher.
  final OpenExternal? openExternal;
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
        commands: commands,
        autostart: autostart,
        initialWallpaper: wallpaper,
        pickFiles: pickFiles,
        openExternal: openExternal,
        windowed: windowed,
        animate: animate,
      ),
    );
  }
}
