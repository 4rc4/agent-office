import 'dart:async';
import 'dart:io';

import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;

import '../state/office_controller.dart';
import 'office_settings.dart';

/// One running office behind the window: the built [Office] from office_core
/// and the [OfficeController] the widgets listen to.
///
/// [start] wires both from [OfficeSettings] and, unless told otherwise,
/// reconciles whatever the board still holds from a previous run. [close]
/// disposes the controller first, then the office, so no rebuild touches a
/// closed board.
class OfficeRuntime {
  OfficeRuntime._(this.settings, this.office, this.controller);

  /// The settings this runtime was built from.
  final OfficeSettings settings;

  /// Board, supervisor, adapters and process runner.
  final Office office;

  /// The live model for the widgets.
  final OfficeController controller;

  bool _officeClosed = false;
  bool _closed = false;

  /// Whether [close] or the controller's `stopAll` has shut the office.
  bool get isClosed => _closed || _officeClosed;

  /// Builds the office for [settings] and its controller.
  ///
  /// [board] replaces the on-disk board (tests pass an in-memory one).
  /// [reconcile] resumes interrupted tasks in the background; a failure there
  /// lands on the controller's status line.
  static Future<OfficeRuntime> start(
    OfficeSettings settings, {
    TaskBoard? board,
    bool reconcile = true,
  }) async {
    final config = OfficeConfig(
      paths: OfficePaths(cwd: settings.cwd),
      claudeExecutable: settings.claudeExecutable,
      codexExecutable: settings.codexExecutable,
      permissionMode: settings.permissionMode,
      brainPromptFile: await resolveBrainFile(settings),
      fake: settings.fake,
      fixturesDir: settings.fixturesDir,
    );
    final office = await buildOffice(config, board: board);
    final controller = OfficeController(
      supervisor: office.supervisor,
      board: office.board,
      cwd: config.paths.cwd,
    );
    final runtime = OfficeRuntime._(settings, office, controller);
    controller.onStopAll = runtime._closeOffice;
    if (reconcile) {
      unawaited(
        office.supervisor.reconcile().then<void>(
          (_) {},
          onError: (Object error) =>
              controller.reportError('Devam ettirilemedi: $error'),
        ),
      );
    }
    return runtime;
  }

  /// The brain prompt file for [settings]: its explicit `brainFile`, else
  /// office_core's `defaultBrainPromptFile()` (found when running from
  /// source), else `agent_office/brain/brain.md` or `brain/brain.md` under the
  /// repository or next to the executable (a built app cannot resolve package
  /// paths). Null when none exists; Claude then runs without the brain prompt.
  static Future<String?> resolveBrainFile(
    OfficeSettings settings, {
    String? executableDir,
  }) async {
    final explicit = settings.brainFile;
    if (explicit != null && explicit.isNotEmpty) return explicit;
    final bundled = await defaultBrainPromptFile();
    if (bundled != null) return bundled;
    final exeDir = executableDir ?? p.dirname(Platform.resolvedExecutable);
    final candidates = [
      p.join(settings.cwd, 'agent_office', 'brain', 'brain.md'),
      p.join(settings.cwd, 'brain', 'brain.md'),
      p.join(exeDir, 'brain', 'brain.md'),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return p.normalize(candidate);
    }
    return null;
  }

  /// Disposes the controller and closes the office. Safe to call twice.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    controller.dispose();
    await _closeOffice();
  }

  Future<void> _closeOffice() async {
    if (_officeClosed) return;
    _officeClosed = true;
    await office.close();
  }
}
