import 'package:flutter/material.dart';

import '../l10n_tr.dart';
import '../runtime/office_settings.dart';
import 'office_theme.dart';

/// Shown instead of the office when the runtime could not start (fake
/// fixtures missing, board file locked, bad settings). Names the folder and
/// the error so the user can fix `settings.json` or the command line.
class StartupErrorScreen extends StatelessWidget {
  const StartupErrorScreen({
    super.key,
    required this.settings,
    required this.error,
  });

  final OfficeSettings settings;
  final Object error;

  @override
  Widget build(BuildContext context) {
    final theme = officeTheme();
    const muted = TextStyle(fontSize: 13, color: OfficeColors.textMuted);
    return MaterialApp(
      title: Tr.appTitle,
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: Scaffold(
        backgroundColor: OfficeColors.background,
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.power_off_rounded,
                    size: 40,
                    color: OfficeColors.orange,
                  ),
                  const SizedBox(height: 12),
                  Text(Tr.startupFailed, style: theme.textTheme.titleLarge),
                  const SizedBox(height: 12),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: OfficeColors.surfaceSunken,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: OfficeColors.outline,
                        width: 1.5,
                      ),
                    ),
                    child: SelectableText(
                      '$error',
                      style: const TextStyle(
                        fontSize: 13,
                        color: OfficeColors.text,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('${Tr.folder}: ${settings.cwd}', style: muted),
                  const SizedBox(height: 4),
                  Text(Tr.startupHint, style: muted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
