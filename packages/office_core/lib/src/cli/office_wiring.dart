import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:path/path.dart' as p;

import '../adapters/claude_adapter.dart';
import '../adapters/codex_adapter.dart';
import '../adapters/seat_adapter.dart';
import '../board/task_board.dart';
import '../model/task.dart';
import '../plan/plan_parser.dart';
import '../process/process_runner.dart';
import '../supervisor/dispatcher.dart';
import '../supervisor/supervisor.dart';

/// Adapts [PlanParser.parse] to the [PlanParserFn] the [Supervisor] expects.
Future<PlanOrError> parsePlanText(String text) async {
  final result = PlanParser.parse(text);
  if (result.isError) return PlanOrError.error(result.error!);
  return PlanOrError.plan(
    ParsedPlan(
      tasks: result.tasks!,
      mergeInstructions: result.mergeInstructions,
    ),
  );
}

/// Where one working directory keeps its office state. Everything lives under
/// the folder of [dbPath] (by default `<cwd>/.agent_office/`).
class OfficePaths {
  OfficePaths({required String cwd, String? dbPath})
    : cwd = p.normalize(p.absolute(cwd)),
      dbPath = p.normalize(p.absolute(dbPath ?? defaultDbPath(cwd)));

  /// The repository the agents work in.
  final String cwd;

  /// The SQLite board file.
  final String dbPath;

  /// Folder holding the board and every derived file.
  String get stateDir => p.dirname(dbPath);

  /// Per-attempt result files written by the dispatcher.
  String get artifactsDir => p.join(stateDir, 'artifacts');

  /// `codex exec -o` output files.
  String get resultsDir => p.join(stateDir, 'results');

  /// `<cwd>/.agent_office/office.db`.
  static String defaultDbPath(String cwd) =>
      p.join(cwd, '.agent_office', 'office.db');

  /// Creates [stateDir] (and parents) when missing.
  void ensureDirectories() => Directory(stateDir).createSync(recursive: true);
}

/// Everything needed to build one office: where it works, which binaries it
/// launches, and whether vendor output is faked from fixtures.
class OfficeConfig {
  const OfficeConfig({
    required this.paths,
    this.claudeExecutable = 'claude',
    this.codexExecutable = 'codex',
    this.permissionMode = 'acceptEdits',
    this.brainPromptFile,
    this.mcpConfigFile,
    this.fake = false,
    this.fixturesDir,
    this.claudeModel = '',
    this.claudeEffort = '',
    this.codexModel = '',
    this.codexEffort = '',
  });

  final OfficePaths paths;

  /// The `claude` binary (or `.cmd` shim); a bare name is looked up on PATH.
  final String claudeExecutable;

  /// The `codex` binary (or `.cmd` shim).
  final String codexExecutable;

  /// Claude `--permission-mode` for brain and worker runs.
  final String permissionMode;

  /// `--append-system-prompt-file` for Claude; null resolves to the repo's
  /// `agent_office/brain/brain.md` when it exists, else nothing is appended.
  final String? brainPromptFile;

  /// `--mcp-config` for Claude, if any.
  final String? mcpConfigFile;

  /// Replace both vendor CLIs with [FakeProcessRunner] scripts built from
  /// the `test/fixtures/` files, so the whole loop runs without a login.
  final bool fake;

  /// Overrides where [FakeOffice] looks for its fixtures.
  final String? fixturesDir;

  /// Default Claude `--model` / `--effort` and Codex `-m` /
  /// `model_reasoning_effort`; empty strings leave the CLI defaults. A
  /// root task's options override them.
  final String claudeModel;
  final String claudeEffort;
  final String codexModel;
  final String codexEffort;
}

/// A built office: the board, the supervisor driving it and the runner the
/// adapters launch processes with. [close] releases all three.
class Office {
  Office({
    required this.config,
    required this.board,
    required this.supervisor,
    required this.runner,
    required this.adapters,
  });

  final OfficeConfig config;
  final TaskBoard board;
  final Supervisor supervisor;
  final ProcessRunner runner;
  final Map<Seat, SeatAdapter> adapters;

  /// Closes the supervisor's event stream and the board.
  Future<void> close() async {
    await supervisor.dispose();
    board.close();
  }
}

/// Wires board, adapters, plan parser and supervisor for [config]. Pass
/// [board] to reuse an open board (tests use an in-memory one).
Future<Office> buildOffice(OfficeConfig config, {TaskBoard? board}) async {
  config.paths.ensureDirectories();
  final ProcessRunner runner;
  final DiffStatCollector? collectDiffStat;
  final Map<String, String> claudeEnvironment;
  final Map<String, String>? codexEnvironment;
  if (config.fake) {
    runner = await FakeOffice.runner(
      claudeExecutable: config.claudeExecutable,
      codexExecutable: config.codexExecutable,
      fixturesDir: config.fixturesDir,
    );
    collectDiffStat = FakeOffice.diffStat;
    claudeEnvironment = const {};
    codexEnvironment = const {};
  } else {
    runner = const DartProcessRunner();
    collectDiffStat = null;
    claudeEnvironment = Platform.environment;
    codexEnvironment = null;
  }
  final claude = ClaudeAdapter(
    runner: runner,
    executable: config.claudeExecutable,
    permissionMode: config.permissionMode,
    systemPromptFile:
        config.brainPromptFile ??
        (config.fake ? null : await defaultBrainPromptFile()),
    mcpConfigFile: config.mcpConfigFile,
    model: config.claudeModel,
    effort: config.claudeEffort,
    baseEnvironment: claudeEnvironment,
  );
  final codex = CodexAdapter(
    runner: runner,
    executable: config.codexExecutable,
    outputDirectory: config.paths.resultsDir,
    model: config.codexModel,
    reasoningEffort: config.codexEffort,
    baseEnvironment: codexEnvironment,
  );
  final adapters = <Seat, SeatAdapter>{Seat.claude: claude, Seat.gpt: codex};
  final openBoard = board ?? TaskBoard.open(config.paths.dbPath);
  final supervisor = Supervisor(
    board: openBoard,
    adapters: adapters,
    parsePlan: parsePlanText,
    collectDiffStat: collectDiffStat,
    artifactsDir: config.paths.artifactsDir,
  );
  return Office(
    config: config,
    board: openBoard,
    supervisor: supervisor,
    runner: runner,
    adapters: adapters,
  );
}

/// The office_core package folder, resolved through the package config; null
/// when that is impossible (for example in an AOT-compiled executable).
Future<String?> officeCorePackageRoot() async {
  try {
    final uri = await Isolate.resolvePackageUri(
      Uri.parse('package:office_core/office_core.dart'),
    );
    if (uri == null || uri.scheme != 'file') return null;
    return p.dirname(p.dirname(uri.toFilePath()));
  } on Object {
    return null;
  }
}

/// `agent_office/brain/brain.md` next to this package, when it exists.
Future<String?> defaultBrainPromptFile() async {
  final root = await officeCorePackageRoot();
  if (root == null) return null;
  final file = p.normalize(p.join(root, '..', '..', 'brain', 'brain.md'));
  return File(file).existsSync() ? file : null;
}

/// Canned vendor output for demos and tests: the brain plans two subtasks
/// (codex, then claude depending on it), both workers succeed, and the brain
/// writes the final report, all replayed from `test/fixtures/` through a
/// [FakeProcessRunner]. No vendor CLI or login is needed.
///
/// The brain's two turns come from two processes: the first fixture ends
/// after the plan, so the supervisor's `send` finds the process gone and
/// resumes the stored session with the report fixture (`--resume`), which
/// also exercises the restart path.
abstract final class FakeOffice {
  /// Brain turn 1: a fenced json plan with two tasks.
  static const String brainPlanFixture = 'claude_brain_plan.jsonl';

  /// Brain turn 2 (resumed): the final markdown report.
  static const String brainReportFixture = 'claude_brain_report.jsonl';

  /// The Claude worker: one edit, result `pong`.
  static const String claudeWorkerFixture = 'claude_pong.jsonl';

  /// The Codex worker: a fix with two changed files.
  static const String codexWorkerFixture = 'codex_success.jsonl';

  /// What `git diff --stat` returns in fake mode.
  static const String diffStatText =
      ' lib/a.dart | 2 +-\n'
      ' lib/b.dart | 5 +++++\n'
      ' 2 files changed, 6 insertions(+), 1 deletion(-)\n';

  /// A [DiffStatCollector] returning [diffStatText].
  static Future<String> diffStat(String cwd) async => diffStatText;

  /// A runner scripted for one full `run`: Claude starts three times (plan,
  /// worker, resumed report), Codex once. Keys follow the executables'
  /// basenames, as [FakeProcessRunner] does.
  static Future<FakeProcessRunner> runner({
    String claudeExecutable = 'claude',
    String codexExecutable = 'codex',
    String? fixturesDir,
  }) async {
    final dir = await fixturesDirectory(fixturesDir);
    return FakeProcessRunner({
      runnerKey(claudeExecutable): [
        script(dir, brainPlanFixture),
        script(dir, claudeWorkerFixture),
        script(dir, brainReportFixture),
      ],
      runnerKey(codexExecutable): [script(dir, codexWorkerFixture)],
    });
  }

  /// The script map key [FakeProcessRunner] derives from an executable path.
  static String runnerKey(String executable) =>
      executable.split(RegExp(r'[\\/]')).last;

  /// One fixture as a [FakeScript]. A blank first line is prepended because
  /// [FakeRunningProcess] emits its first stdout line before any adapter can
  /// subscribe; the parsers ignore blank lines.
  static FakeScript script(String dir, String name, {int exitCode = 0}) {
    final lines = const LineSplitter().convert(
      File(p.join(dir, name)).readAsStringSync(),
    );
    return FakeScript(['', ...lines], exitCode: exitCode);
  }

  /// The first folder holding [brainPlanFixture]: [override], then
  /// `test/fixtures` under the package root, then under the current folder.
  static Future<String> fixturesDirectory([String? override]) async {
    final candidates = <String>[?override];
    final root = await officeCorePackageRoot();
    if (root != null) candidates.add(p.join(root, 'test', 'fixtures'));
    candidates.add(p.join(Directory.current.path, 'test', 'fixtures'));
    for (final dir in candidates) {
      if (File(p.join(dir, brainPlanFixture)).existsSync()) return dir;
    }
    throw StateError(
      'fake fixtures not found; looked in ${candidates.join(', ')}. '
      'Pass --fixtures <dir>.',
    );
  }
}
