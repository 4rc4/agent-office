import 'package:flutter/material.dart';

import '../l10n_tr.dart';
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
    required this.layer,
    this.windowed = false,
    this.animate = true,
    this.initialFolder,
  });

  final DesktopLayer layer;
  final bool windowed;
  final bool animate;
  final String? initialFolder;

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
        layer: layer,
        windowed: windowed,
        animate: animate,
        initialFolder: initialFolder,
      ),
    );
  }
}
