import 'dart:async';
import 'dart:io';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:path/path.dart' as p;

import 'runtime/office_settings.dart';
import 'state/office_ticker.dart';

/// Start-up helpers for `main.dart`, kept free of `runApp` so they can be
/// unit-tested: fake-mode detection, settings loading with a safe fallback,
/// and the fixtures lookup a built app needs for fake mode.
abstract final class Bootstrap {
  /// Process argument that starts the office in fake mode.
  static const String fakeFlag = '--fake';

  /// Environment variable that does the same (`1`, `true`, `yes` or `on`).
  static const String fakeEnv = 'AGENT_OFFICE_FAKE';

  /// Process argument that shows the desktop stage in a plain dark window
  /// instead of the wallpaper layer (no WorkerW trick; for testing).
  static const String windowFlag = '--window';

  /// Process argument that opens the old pixel-room window (`OfficeScreen`).
  static const String roomFlag = '--room';

  /// The file office_core's fake runner needs; its presence marks a fixtures
  /// folder.
  static const String fixturesMarker = 'claude_brain_plan.jsonl';

  /// Whether [args] or [environment] ask for fake mode: canned vendor output,
  /// no `claude` or `codex` binary needed.
  static bool wantsFakeMode(
    List<String> args,
    Map<String, String> environment,
  ) {
    if (args.contains(fakeFlag)) return true;
    final value = environment[fakeEnv]?.trim().toLowerCase();
    return value != null && const {'1', 'true', 'yes', 'on'}.contains(value);
  }

  /// Loads the saved settings; any failure (no platform channel, unwritable
  /// support folder, corrupt file) yields [OfficeSettings.defaults], whose
  /// `cwd` is the current folder.
  static Future<OfficeSettings> loadSettingsOrDefaults() async {
    try {
      return await OfficeSettings.load();
    } on Object {
      return OfficeSettings.defaults();
    }
  }

  /// office_core's `test/fixtures` for fake mode when the package root cannot
  /// be resolved (a built app): looks for the repository layout under [cwd]
  /// and for a `fixtures` folder next to the executable. Null when nothing is
  /// found; office_core then tries its own candidates and reports the failure.
  static String? resolveFixturesDir(String cwd, {String? executableDir}) {
    final exeDir = executableDir ?? p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(
        cwd,
        'agent_office',
        'packages',
        'office_core',
        'test',
        'fixtures',
      ),
      p.join(cwd, 'packages', 'office_core', 'test', 'fixtures'),
      p.join(cwd, '..', 'packages', 'office_core', 'test', 'fixtures'),
      p.join(exeDir, 'fixtures'),
    ];
    for (final dir in candidates) {
      if (File(p.join(dir, fixturesMarker)).existsSync()) {
        return p.normalize(dir);
      }
    }
    return null;
  }

  /// [settings] with fake mode switched on when [fake] is set, filling in a
  /// fixtures folder when the settings name none. Unchanged otherwise.
  static OfficeSettings applyFakeMode(
    OfficeSettings settings, {
    required bool fake,
    String? executableDir,
  }) {
    if (!fake) return settings;
    return settings.copyWith(
      fake: true,
      fixturesDir:
          settings.fixturesDir ??
          resolveFixturesDir(settings.cwd, executableDir: executableDir),
    );
  }
}

/// Binds the window lifecycle to the animation clock and the runtime: a
/// hidden, paused or detached window pauses the [ticker], a resumed one
/// restarts it, and an exit request (the user closing the window) runs
/// [closeRuntime] before the process ends. Detaching closes it too, so the
/// board is released whichever signal arrives first; [closeRuntime] must be
/// safe to call twice.
class OfficeLifecycleObserver with WidgetsBindingObserver {
  OfficeLifecycleObserver({this.ticker, required this.closeRuntime});

  /// The room's animation clock; the desktop stage owns its own and passes
  /// none.
  final OfficeTicker? ticker;
  final Future<void> Function() closeRuntime;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    ticker?.onLifecycleChanged(state);
    if (state == AppLifecycleState.detached) unawaited(closeRuntime());
  }

  @override
  Future<AppExitResponse> didRequestAppExit() async {
    await closeRuntime();
    return AppExitResponse.exit;
  }
}
