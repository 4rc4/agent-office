import 'package:flutter/foundation.dart';
import 'package:office_core/office_core.dart';

import 'seat_state.dart';

/// What the widgets talk to. The real implementation (OfficeController) wraps
/// office_core's Supervisor; tests use a hand-rolled fake. Widgets never
/// import office_core process classes directly.
abstract class OfficeModel extends ChangeNotifier {
  /// Current state of every desk, the whiteboard, the log and the mailbox.
  OfficeSnapshot get snapshot;

  /// Repository the agents work in; editable from the prompt bar.
  String get cwd;
  set cwd(String value);

  /// Starts a root task in [cwd] (default: [OfficeModel.cwd]). With
  /// [directSeat] the prompt goes to that desk alone (no planning, no merge);
  /// without it Claude plans and delegates. Several roots may be open at
  /// once, each in its own folder. Returns when the task has been accepted
  /// by the board, not when it ends.
  Future<void> submit(String prompt, {Seat? directSeat, String? cwd});

  /// Clears [OfficeSnapshot.unreadReports] (the mailbox was opened).
  void markReportsRead() {}

  /// Whether new prompts are held back (the tray's "Duraklat").
  bool get paused => false;

  /// Holds new prompts while paused; resuming submits the held ones.
  Future<void> setPaused(bool value) async {}

  /// Desk the user tapped; the side panel shows it. Null closes the panel.
  Seat? get selectedSeat;
  void selectSeat(Seat? seat);

  /// Stops every running agent politely (close stdin, then kill).
  Future<void> stopAll();
}
