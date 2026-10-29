import 'dart:io';
import 'dart:ui' show AppLifecycleState;

import 'package:agent_office_app/desktop/model_choices.dart';
import 'package:agent_office_app/runtime/office_runtime.dart';
import 'package:agent_office_app/runtime/office_settings.dart';
import 'package:agent_office_app/state/office_model.dart';
import 'package:agent_office_app/state/office_ticker.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;

/// A model whose snapshot the test sets by hand, with or without notifying.
class FakeModel extends OfficeModel {
  OfficeSnapshot _snapshot = OfficeSnapshot.initial();
  Seat? _selected;

  @override
  OfficeSnapshot get snapshot => _snapshot;

  /// Replaces the snapshot silently (no listener call).
  set snapshot(OfficeSnapshot value) => _snapshot = value;

  /// Replaces the snapshot and notifies, as the controller would.
  void publish(OfficeSnapshot value) {
    _snapshot = value;
    notifyListeners();
  }

  @override
  String cwd = '/repo';

  @override
  Future<void> submit(
    String prompt, {
    Seat? directSeat,
    String? cwd,
    PromptOptions options = const PromptOptions(),
  }) async {}

  @override
  Seat? get selectedSeat => _selected;

  @override
  void selectSeat(Seat? seat) => _selected = seat;

  @override
  Future<void> stopAll() async {}
}

OfficeSnapshot animated() => OfficeSnapshot(
  seats: [
    const SeatSnapshot(seat: Seat.claude, visual: SeatVisual.typing),
    const SeatSnapshot(seat: Seat.gpt, visual: SeatVisual.idle),
    const SeatSnapshot(seat: Seat.gemini, visual: SeatVisual.empty),
  ],
);

/// office_core's `test/fixtures`, relative to the app package (the cwd of
/// `flutter test`), since the package root cannot be resolved here.
String coreFixturesDir() => p.normalize(
  p.join(
    Directory.current.path,
    '..',
    'packages',
    'office_core',
    'test',
    'fixtures',
  ),
);

Directory tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 10),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  group('OfficeSettings', () {
    test('defaults use the current folder', () {
      final s = OfficeSettings.defaults();
      expect(s.cwd, Directory.current.path);
      expect(s.claudeExecutable, 'claude');
      expect(s.codexExecutable, 'codex');
      expect(s.permissionMode, 'acceptEdits');
      expect(s.fake, isFalse);
      expect(s.brainFile, isNull);
    });

    test('round trip through a file', () async {
      final dir = tempDir('office_settings_');
      const settings = OfficeSettings(
        cwd: r'C:\work\repo',
        claudeExecutable: r'C:\Users\me\AppData\Roaming\npm\claude.cmd',
        codexExecutable: 'codex.cmd',
        permissionMode: 'plan',
        fake: true,
        brainFile: r'C:\work\brain.md',
        fixturesDir: r'C:\work\fixtures',
      );
      final file = await settings.save(directory: dir.path);
      expect(file.path, p.join(dir.path, OfficeSettings.fileName));
      expect(file.existsSync(), isTrue);
      final loaded = await OfficeSettings.load(directory: dir.path);
      expect(loaded, settings);
      expect(loaded.hashCode, settings.hashCode);
    });

    test('missing, corrupt and partial files fall back to defaults', () async {
      final dir = tempDir('office_settings_');
      expect(
        await OfficeSettings.load(directory: dir.path),
        OfficeSettings.defaults(),
      );

      final file = File(p.join(dir.path, OfficeSettings.fileName));
      file.writeAsStringSync('{not json');
      expect(
        await OfficeSettings.load(directory: dir.path),
        OfficeSettings.defaults(),
      );

      file.writeAsStringSync(
        '{"cwd": "/x", "fake": "yes", "brainFile": "", "fixturesDir": 7}',
      );
      final partial = await OfficeSettings.load(directory: dir.path);
      expect(partial.cwd, '/x');
      expect(partial.fake, isFalse);
      expect(partial.brainFile, isNull);
      expect(partial.fixturesDir, isNull);
      expect(partial.claudeExecutable, 'claude');
    });

    test('copyWith can clear the brain file', () {
      const s = OfficeSettings(cwd: '/r', brainFile: '/b.md');
      expect(s.copyWith(fake: true).brainFile, '/b.md');
      expect(s.copyWith(clearBrainFile: true).brainFile, isNull);
      expect(s.copyWith(cwd: '/other').cwd, '/other');
    });
  });

  group('OfficeTicker', () {
    testWidgets(
      'no timer while idle; ticks while animated; stops within one period',
      (tester) async {
        final model = FakeModel();
        final ticker = OfficeTicker(model);
        addTearDown(ticker.dispose);

        expect(ticker.isRunning, isFalse);
        await tester.pump(const Duration(seconds: 1));
        expect(ticker.tick.value, 0);

        model.publish(animated());
        expect(ticker.isRunning, isTrue);
        await tester.pump(const Duration(milliseconds: 350));
        expect(ticker.tick.value, 3);

        // Animation ends without a notification: the next period stops it.
        model.snapshot = OfficeSnapshot.initial();
        expect(ticker.isRunning, isTrue);
        await tester.pump(const Duration(milliseconds: 100));
        expect(ticker.isRunning, isFalse);
        final ticks = ticker.tick.value;
        await tester.pump(const Duration(seconds: 2));
        expect(ticker.tick.value, ticks);
      },
    );

    testWidgets('a notification that parks the last seat stops it at once', (
      tester,
    ) async {
      final model = FakeModel();
      final ticker = OfficeTicker(model);
      addTearDown(ticker.dispose);
      model.publish(animated());
      await tester.pump(const Duration(milliseconds: 100));
      expect(ticker.tick.value, 1);
      model.publish(OfficeSnapshot.initial());
      expect(ticker.isRunning, isFalse);
    });

    testWidgets('pause and resume follow the window lifecycle', (tester) async {
      final model = FakeModel();
      final ticker = OfficeTicker(model);
      addTearDown(ticker.dispose);
      model.publish(animated());
      expect(ticker.isRunning, isTrue);

      ticker.onLifecycleChanged(AppLifecycleState.hidden);
      expect(ticker.isPaused, isTrue);
      expect(ticker.isRunning, isFalse);
      await tester.pump(const Duration(seconds: 1));
      expect(ticker.tick.value, 0);

      // A notification while paused does not restart the timer.
      model.publish(animated());
      expect(ticker.isRunning, isFalse);

      ticker.onLifecycleChanged(AppLifecycleState.inactive);
      expect(ticker.isPaused, isFalse);
      expect(ticker.isRunning, isTrue);
      await tester.pump(const Duration(milliseconds: 200));
      expect(ticker.tick.value, 2);

      ticker.onLifecycleChanged(AppLifecycleState.resumed);
      expect(ticker.isRunning, isTrue);
      ticker.dispose();
      expect(ticker.isRunning, isFalse);
    });
  });

  group('OfficeRuntime', () {
    test('resolveBrainFile: explicit first, then a copy in the repo', () async {
      final dir = tempDir('office_brain_');
      const explicit = OfficeSettings(cwd: '/r', brainFile: '/my/brain.md');
      expect(
        await OfficeRuntime.resolveBrainFile(explicit, executableDir: dir.path),
        '/my/brain.md',
      );
      final inRepo = File(p.join(dir.path, 'agent_office', 'brain', 'brain.md'))
        ..createSync(recursive: true);
      final found = await OfficeRuntime.resolveBrainFile(
        OfficeSettings(cwd: dir.path),
        executableDir: dir.path,
      );
      expect(found, isNotNull);
      expect(found, endsWith(p.join('brain', 'brain.md')));
      if (await defaultBrainPromptFile() == null) {
        expect(found, p.normalize(inRepo.path));
      }
    });

    test(
      'fake office: starts, runs a direct GPT task, stops, closes',
      () async {
        final dir = tempDir('office_runtime_');
        final runtime = await OfficeRuntime.start(
          OfficeSettings(
            cwd: dir.path,
            fake: true,
            fixturesDir: coreFixturesDir(),
          ),
          board: TaskBoard.inMemory(),
        );
        addTearDown(runtime.close);
        final controller = runtime.controller;
        expect(runtime.isClosed, isFalse);
        expect(runtime.office.config.fake, isTrue);
        expect(controller.cwd, p.normalize(p.absolute(dir.path)));
        expect(controller.snapshot.busy, isFalse);
        expect(controller.snapshot.statusLine, 'Ofis sessiz.');
        expect(
          Directory(runtime.office.config.paths.stateDir).existsSync(),
          isTrue,
        );

        await controller.submit('ping', directSeat: Seat.gpt);
        expect(controller.snapshot.busy, isTrue);
        await waitUntil(() => !controller.snapshot.busy);
        expect(controller.snapshot.statusLine, 'Rapor hazır');
        expect(controller.snapshot.lastReport, isNotEmpty);
        final root = controller.snapshot.tasks.singleWhere((t) => t.isRoot);
        expect(root.status, TaskStatus.done);
        expect(controller.snapshot.seat(Seat.gpt).xp, 10);
        expect(controller.snapshot.recentEvents, isNotEmpty);

        await controller.stopAll();
        expect(runtime.isClosed, isTrue);
        expect(controller.snapshot.statusLine, 'Ofis durduruldu.');
        await runtime.close();
        await runtime.close();
      },
    );
  });
}
