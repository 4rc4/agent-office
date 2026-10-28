import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'l10n_tr.dart';
import 'scene/office_scene.dart';
import 'state/office_model.dart';
import 'state/seat_state.dart';
import 'widgets/office_screen.dart';
import 'widgets/office_theme.dart';

/// The Agent Office window: a dark [MaterialApp] whose home is [OfficeScreen]
/// with the real pixel [OfficeScene].
///
/// [model] is the live office (an `OfficeController` from the runtime) and
/// [tick] its animation clock (`OfficeTicker.tick`). Both are owned by the
/// caller; this widget only listens.
class AgentOfficeApp extends StatelessWidget {
  const AgentOfficeApp({super.key, required this.model, required this.tick});

  final OfficeModel model;
  final ValueListenable<int> tick;

  Widget _buildScene(
    BuildContext context,
    OfficeSnapshot snapshot,
    int tick,
    void Function(Object target) onTap,
  ) {
    return OfficeScene(
      snapshot: snapshot,
      tick: tick,
      onTap: onTap,
      onTapEmpty: () => model.selectSeat(null),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = officeTheme();
    return MaterialApp(
      title: Tr.appTitle,
      debugShowCheckedModeBanner: false,
      theme: theme,
      darkTheme: theme,
      themeMode: ThemeMode.dark,
      home: OfficeScreen(model: model, tick: tick, sceneBuilder: _buildScene),
    );
  }
}
