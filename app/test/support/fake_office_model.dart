import 'package:agent_office_app/state/office_model.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter/foundation.dart';
import 'package:office_core/office_core.dart';

/// One recorded [OfficeModel.submit] call.
class Submission {
  const Submission(this.prompt, this.directSeat);

  final String prompt;
  final Seat? directSeat;
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
  Future<void> submit(String prompt, {Seat? directSeat}) async {
    if (submitError != null) throw submitError!;
    submissions.add(Submission(prompt, directSeat));
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
}
