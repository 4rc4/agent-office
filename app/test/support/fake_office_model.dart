import 'package:agent_office_app/desktop/model_choices.dart';
import 'package:agent_office_app/state/office_model.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter/foundation.dart';
import 'package:office_core/office_core.dart';

/// One recorded [OfficeModel.submit] call.
class Submission {
  const Submission(
    this.prompt,
    this.directSeat, [
    this.cwd,
    this.options = const PromptOptions(),
  ]);

  final String prompt;
  final Seat? directSeat;
  final String? cwd;
  final PromptOptions options;
}

/// Hand-rolled [OfficeModel] for widget tests and goldens: records calls and
/// exposes a settable snapshot that notifies on change.
class FakeOfficeModel extends ChangeNotifier implements OfficeModel {
  FakeOfficeModel({OfficeSnapshot? snapshot, this.cwdValue = r'C:\work\repo'})
    : _snapshot = snapshot ?? OfficeSnapshot.initial();

  OfficeSnapshot _snapshot;
  String cwdValue;
  Seat? _selected;
  final submissions = <Submission>[];
  int stopCalls = 0;

  /// When set, [submit] throws it instead of recording the prompt.
  Object? submitError;

  @override
  OfficeSnapshot get snapshot => _snapshot;

  set snapshot(OfficeSnapshot value) {
    _snapshot = value;
    notifyListeners();
  }

  @override
  String get cwd => cwdValue;

  @override
  set cwd(String value) {
    cwdValue = value;
    notifyListeners();
  }

  @override
  Future<void> submit(
    String prompt, {
    Seat? directSeat,
    String? cwd,
    PromptOptions options = const PromptOptions(),
  }) async {
    if (submitError != null) throw submitError!;
    submissions.add(Submission(prompt, directSeat, cwd, options));
  }

  int markReadCalls = 0;
  bool pausedValue = false;

  @override
  bool get paused => pausedValue;

  @override
  Future<void> setPaused(bool value) async {
    pausedValue = value;
    notifyListeners();
  }

  @override
  void markReportsRead() {
    markReadCalls++;
  }

  @override
  Seat? get selectedSeat => _selected;

  @override
  void selectSeat(Seat? seat) {
    _selected = seat;
    notifyListeners();
  }

  @override
  Future<void> stopAll() async {
    stopCalls++;
  }

  final stopped = <String>[];
  final steered = <(String, String)>[];

  @override
  Future<bool> stopTask(String taskId) async {
    stopped.add(taskId);
    return true;
  }

  @override
  Future<bool> steerTask(String taskId, String note) async {
    steered.add((taskId, note));
    return true;
  }
}
