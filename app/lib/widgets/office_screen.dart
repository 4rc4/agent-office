import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:office_core/office_core.dart';

import '../l10n_tr.dart';
import '../state/office_model.dart';
import '../state/seat_state.dart';
import 'event_log_sheet.dart';
import 'mailbox_dialog.dart';
import 'office_theme.dart';
import 'prompt_bar.dart';
import 'scene_tap_router.dart';
import 'seat_panel.dart';
import 'whiteboard_panel.dart';

/// Builds the pixel scene for a snapshot and animation tick. [onTap] takes
/// the scene's own target object; [SceneTapRouter] classifies it. The real
/// scene (lib/scene/office_scene.dart) is plugged in by app.dart, tests pass
/// a placeholder.
typedef SceneBuilder =
    Widget Function(
      BuildContext context,
      OfficeSnapshot snapshot,
      int tick,
      void Function(Object target) onTap,
    );

/// The window: the scene on top, the prompt bar at the bottom, and the
/// selected desk's [SeatPanel] on the right (wide) or over the scene's lower
/// half as a sheet (narrower than [wideBreakpoint]).
///
/// Rebuilds on every [model] notification and, for the scene only, on every
/// [tick]. Scene taps: a desk selects its seat (again closes), the
/// whiteboard and the mailbox open dialogs, the cabinet and the coffee
/// corner open the event log sheet; all keep following the model while open.
class OfficeScreen extends StatelessWidget {
  const OfficeScreen({
    super.key,
    required this.model,
    required this.tick,
    required this.sceneBuilder,
  });

  /// Below this width the seat panel becomes a bottom sheet.
  static const double wideBreakpoint = 900;

  /// Width of the right-hand seat panel.
  static const double panelWidth = 320;

  static const Key sidePanelKey = Key('officeScreen.sidePanel');
  static const Key bottomSheetKey = Key('officeScreen.bottomSheet');
  static const Key sceneKey = Key('officeScreen.scene');

  final OfficeModel model;
  final ValueListenable<int> tick;
  final SceneBuilder sceneBuilder;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OfficeColors.background,
      body: ListenableBuilder(
        listenable: model,
        builder: (context, _) {
          final snapshot = model.snapshot;
          final selected = model.selectedSeat;
          return LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= wideBreakpoint;
              final column = Column(
                children: [
                  Expanded(
                    child: wide || selected == null
                        ? _scene(context, snapshot)
                        : _sceneWithSheet(context, snapshot, selected),
                  ),
                  _promptBar(context, snapshot),
                ],
              );
              if (!wide || selected == null) return column;
              return Row(
                children: [
                  Expanded(child: column),
                  Container(
                    key: sidePanelKey,
                    width: panelWidth,
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: OfficeColors.outline, width: 2),
                      ),
                    ),
                    child: _seatPanel(snapshot, selected),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  Widget _scene(BuildContext context, OfficeSnapshot snapshot) {
    return ValueListenableBuilder<int>(
      key: sceneKey,
      valueListenable: tick,
      builder: (context, tick, _) => sceneBuilder(
        context,
        snapshot,
        tick,
        (target) => _onTap(context, target),
      ),
    );
  }

  Widget _sceneWithSheet(
    BuildContext context,
    OfficeSnapshot snapshot,
    Seat selected,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final height = math.min(380.0, constraints.maxHeight * 0.6);
        return Stack(
          children: [
            Positioned.fill(child: _scene(context, snapshot)),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: height,
              child: Container(
                key: bottomSheetKey,
                decoration: const BoxDecoration(
                  color: OfficeColors.surface,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  border: Border(
                    top: BorderSide(color: OfficeColors.outline, width: 2),
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _seatPanel(snapshot, selected),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _seatPanel(OfficeSnapshot snapshot, Seat selected) {
    return SeatPanel(
      seat: snapshot.seat(selected),
      events: snapshot.recentEvents,
      onClose: () => model.selectSeat(null),
    );
  }

  Widget _promptBar(BuildContext context, OfficeSnapshot snapshot) {
    return PromptBar(
      busy: snapshot.busy,
      cwd: model.cwd,
      statusLine: snapshot.statusLine,
      onCwdChanged: (value) => model.cwd = value,
      onStop: () => _stop(context),
      onSubmit: (prompt, mode) => _submit(context, prompt, mode),
    );
  }

  Future<bool> _submit(
    BuildContext context,
    String prompt,
    PromptMode mode,
  ) async {
    try {
      await model.submit(prompt, directSeat: mode.directSeat);
      return true;
    } on Object catch (error) {
      if (context.mounted) _toast(context, '${Tr.submitFailed}: $error');
      return false;
    }
  }

  Future<void> _stop(BuildContext context) async {
    try {
      await model.stopAll();
    } on Object catch (error) {
      if (context.mounted) _toast(context, '$error');
    }
  }

  void _onTap(BuildContext context, Object target) {
    final tap = SceneTapRouter.classify(target);
    switch (tap.kind) {
      case SceneTapKind.seat:
        model.selectSeat(tap.seat == model.selectedSeat ? null : tap.seat);
      case SceneTapKind.whiteboard:
        showWhiteboardDialog(context, model);
      case SceneTapKind.mailbox:
        showMailboxDialog(context, model);
      case SceneTapKind.cabinet:
      case SceneTapKind.coffee:
        showEventLogSheet(context, model);
      case SceneTapKind.unknown:
        break;
    }
  }

  void _toast(BuildContext context, String text) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
      );
  }
}
