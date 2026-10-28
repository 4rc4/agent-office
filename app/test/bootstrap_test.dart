import 'dart:io';
import 'dart:ui' show AppExitResponse, AppLifecycleState;

import 'package:agent_office_app/bootstrap.dart';
import 'package:agent_office_app/runtime/office_settings.dart';
import 'package:agent_office_app/state/office_ticker.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;

import 'support/fake_office_model.dart';

Directory _tempDir(String prefix) {
  final dir = Directory.systemTemp.createTempSync(prefix);
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

/// Writes the fixtures marker under [root]/[parts] and returns that folder.
String _fixturesUnder(String root, List<String> parts) {
  final dir = p.joinAll([root, ...parts]);
  File(p.join(dir, Bootstrap.fixturesMarker)).createSync(recursive: true);
  return p.normalize(dir);
}

OfficeSnapshot _animated() => OfficeSnapshot(
  seats: const [
    SeatSnapshot(seat: Seat.claude, visual: SeatVisual.typing),
    SeatSnapshot(seat: Seat.gpt, visual: SeatVisual.idle),
    SeatSnapshot(seat: Seat.gemini, visual: SeatVisual.empty),
  ],
  busy: true,
);

void main() {
  group('Bootstrap.wantsFakeMode', () {
    test('reads the --fake flag', () {
      expect(Bootstrap.wantsFakeMode(['--fake'], const {}), isTrue);
      expect(Bootstrap.wantsFakeMode(['--other', '--fake'], const {}), isTrue);
      expect(Bootstrap.wantsFakeMode(const [], const {}), isFalse);
      expect(Bootstrap.wantsFakeMode(['--fakes'], const {}), isFalse);
    });

    test('reads AGENT_OFFICE_FAKE', () {
      for (final on in ['1', 'true', 'YES', ' on ']) {
        expect(
          Bootstrap.wantsFakeMode(const [], {Bootstrap.fakeEnv: on}),
          isTrue,
          reason: on,
        );
      }
      for (final off in ['0', 'false', '', 'no']) {
        expect(
          Bootstrap.wantsFakeMode(const [], {Bootstrap.fakeEnv: off}),
          isFalse,
          reason: off,
        );
      }
    });
  });

  group('Bootstrap fixtures', () {
    test('finds the repository layout under cwd', () {
      final root = _tempDir('office_boot_');
      final expected = _fixturesUnder(root.path, [
        'agent_office',
        'packages',
        'office_core',
        'test',
        'fixtures',
      ]);
      expect(
        Bootstrap.resolveFixturesDir(root.path, executableDir: root.path),
        expected,
      );
    });

    test('finds a fixtures folder next to the executable', () {
      final root = _tempDir('office_boot_');
      final exe = Directory(p.join(root.path, 'bin'))..createSync();
      final expected = _fixturesUnder(exe.path, ['fixtures']);
      expect(
        Bootstrap.resolveFixturesDir(
          p.join(root.path, 'repo'),
          executableDir: exe.path,
        ),
        expected,
      );
    });

    test('returns null when nothing is found', () {
      final root = _tempDir('office_boot_');
      expect(
        Bootstrap.resolveFixturesDir(root.path, executableDir: root.path),
        isNull,
      );
    });

    test('applyFakeMode fills the fixtures folder only when asked', () {
      final root = _tempDir('office_boot_');
      final found = _fixturesUnder(root.path, [
        'packages',
        'office_core',
        'test',
        'fixtures',
      ]);
      final settings = OfficeSettings(cwd: root.path);
      expect(Bootstrap.applyFakeMode(settings, fake: false), same(settings));

      final fake = Bootstrap.applyFakeMode(
        settings,
        fake: true,
        executableDir: root.path,
      );
      expect(fake.fake, isTrue);
      expect(fake.fixturesDir, found);
      expect(fake.cwd, root.path);

      final explicit = Bootstrap.applyFakeMode(
        settings.copyWith(fixturesDir: '/my/fixtures'),
        fake: true,
        executableDir: root.path,
      );
      expect(explicit.fixturesDir, '/my/fixtures');
    });
  });

  group('Bootstrap.loadSettingsOrDefaults', () {
    test('never throws', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final settings = await Bootstrap.loadSettingsOrDefaults();
      expect(settings.cwd, isNotEmpty);
    });
  });

  group('OfficeLifecycleObserver', () {
    testWidgets('pauses and resumes the ticker, closes on exit', (
      tester,
    ) async {
      final model = FakeOfficeModel(snapshot: _animated());
      final ticker = OfficeTicker(model);
      addTearDown(ticker.dispose);
      var closes = 0;
      final observer = OfficeLifecycleObserver(
        ticker: ticker,
        closeRuntime: () async => closes++,
      );
      expect(ticker.isRunning, isTrue);

      observer.didChangeAppLifecycleState(AppLifecycleState.hidden);
      expect(ticker.isPaused, isTrue);
      expect(ticker.isRunning, isFalse);
      observer.didChangeAppLifecycleState(AppLifecycleState.paused);
      expect(ticker.isPaused, isTrue);
      observer.didChangeAppLifecycleState(AppLifecycleState.resumed);
      expect(ticker.isPaused, isFalse);
      expect(ticker.isRunning, isTrue);
      expect(closes, 0);

      expect(await observer.didRequestAppExit(), AppExitResponse.exit);
      expect(closes, 1);

      observer.didChangeAppLifecycleState(AppLifecycleState.detached);
      await tester.pump();
      expect(closes, 2);
      expect(ticker.isPaused, isTrue);
    });
  });
}
