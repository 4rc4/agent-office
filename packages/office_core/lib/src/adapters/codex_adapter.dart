import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../model/agent_event.dart';
import '../model/task.dart';
import '../process/process_runner.dart';
import 'codex_jsonl_parser.dart';
import 'seat_adapter.dart';

/// The Codex (GPT) seat: launches the user's own, already-logged-in `codex`
/// binary as `codex exec --json ...`, one process per turn.
///
/// Credentials are never read or forwarded. `OPENAI_API_KEY` and
/// `CODEX_API_KEY` are removed from the environment handed to the child so
/// the CLI uses the ChatGPT subscription login (`codex login`) and not an API
/// key. `exec` never prompts, so no approval flags are passed.
///
/// A run ends when the process exits; there is no second turn on the same
/// process. To continue a conversation, start a new run with `resumeRef` set
/// to the thread id of the earlier one (`codex exec resume <thread_id>`).
/// The flag order of that resume form is unverified against the vendor
/// binary and is kept in [buildArguments] only; [resumeFlagsAfterSubcommand]
/// flips between `exec resume ID --json ...` and `exec --json ... resume ID`
/// without a code change.
class CodexAdapter implements SeatAdapter {
  CodexAdapter({
    required ProcessRunner runner,
    required this.executable,
    this.sandbox = 'workspace-write',
    this.skipGitRepoCheck = true,
    this.outputDirectory,
    this.resumeFlagsAfterSubcommand = true,
    this.model = '',
    this.reasoningEffort = '',
    Map<String, String>? baseEnvironment,
  }) : _runner = runner,
       _baseEnvironment = baseEnvironment;

  /// Environment variables that must never reach the child (compared
  /// case-insensitively, since Windows variable names are).
  static const Set<String> scrubbedEnvironmentKeys = {
    'OPENAI_API_KEY',
    'CODEX_API_KEY',
  };

  final ProcessRunner _runner;
  final Map<String, String>? _baseEnvironment;

  /// Absolute path of the `codex` binary (or its `.cmd` shim on Windows).
  final String executable;

  /// Value for `-s` / `--sandbox`, e.g. `workspace-write`.
  final String sandbox;

  /// Whether `--skip-git-repo-check` is passed, so a task can run in a
  /// folder that is not a git repository.
  final bool skipGitRepoCheck;

  /// Directory for `-o` files. When set, each run gets
  /// `<outputDirectory>/<task.id>.md` holding the final agent message, which
  /// [AgentResult.text] prefers over the text parsed from the stream.
  final String? outputDirectory;

  /// Where the exec flags go on a resume: after `resume <thread_id>` (true,
  /// the documented form) or before `resume` (false).
  final bool resumeFlagsAfterSubcommand;

  /// Default `-m` model (empty: the CLI's own). `options['model']` of a
  /// task overrides it.
  final String model;

  /// Default `model_reasoning_effort` config override (empty: none).
  /// `options['effort']` of a task overrides it.
  final String reasoningEffort;

  List<String> _lastArguments = const [];
  Map<String, String> _lastEnvironment = const {};

  /// Arguments of the most recent [start], for tests and session records.
  List<String> get lastArguments => List.unmodifiable(_lastArguments);

  /// Environment of the most recent [start], after scrubbing.
  Map<String, String> get lastEnvironment => Map.unmodifiable(_lastEnvironment);

  @override
  Seat get seat => Seat.gpt;

  /// The exact argument list for one start.
  ///
  /// New thread:
  /// `exec --json -C CWD -s SANDBOX [--skip-git-repo-check] [-o FILE] PROMPT`.
  ///
  /// Resume: `exec resume RESUME_REF --json -s SANDBOX [--skip-git-repo-check]
  /// [-o FILE] PROMPT` (no `-C`: the process already runs in the task's
  /// directory and the thread remembers it).
  List<String> buildArguments({
    required String prompt,
    required String cwd,
    required String taskId,
    String? resumeRef,
    Map<String, String> options = const {},
  }) {
    final outputFile = outputFileFor(taskId);
    final chosenModel = pickOption(options['model'], model);
    final chosenEffort = pickOption(options['effort'], reasoningEffort);
    final flags = [
      '--json',
      if (resumeRef == null) ...['-C', cwd],
      '-s',
      sandbox,
      if (skipGitRepoCheck) '--skip-git-repo-check',
      if (outputFile != null) ...['-o', outputFile],
      if (chosenModel.isNotEmpty) ...['-m', chosenModel],
      if (chosenEffort.isNotEmpty) ...[
        '-c',
        'model_reasoning_effort="$chosenEffort"',
      ],
    ];
    if (resumeRef == null) return ['exec', ...flags, prompt];
    if (resumeFlagsAfterSubcommand) {
      return ['exec', 'resume', resumeRef, ...flags, prompt];
    }
    return ['exec', ...flags, 'resume', resumeRef, prompt];
  }

  /// The child's environment: the base environment (the constructor's, else
  /// [Platform.environment]) without [scrubbedEnvironmentKeys].
  Map<String, String> buildEnvironment() {
    return Map<String, String>.of(_baseEnvironment ?? Platform.environment)
      ..removeWhere(
        (key, _) => scrubbedEnvironmentKeys.contains(key.toUpperCase()),
      );
  }

  /// The `-o` file for [taskId], or null when [outputDirectory] is unset.
  String? outputFileFor(String taskId) {
    final directory = outputDirectory;
    if (directory == null) return null;
    final safe = taskId.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    return p.join(directory, '$safe.md');
  }

  @override
  Future<AgentRun> start(
    TaskRecord task, {
    required String initialMessage,
    String? resumeRef,
  }) async {
    final arguments = buildArguments(
      prompt: initialMessage,
      cwd: task.cwd,
      taskId: task.id,
      resumeRef: resumeRef,
      options: task.options,
    );
    final environment = buildEnvironment();
    _lastArguments = arguments;
    _lastEnvironment = environment;
    _ensureOutputDirectory();
    final process = await _runner.start(
      executable,
      arguments,
      workingDirectory: task.cwd,
      environment: environment,
    );
    return CodexRun._(
      process: process,
      taskId: task.id,
      requestedSessionRef: resumeRef,
      outputFile: outputFileFor(task.id),
    );
  }

  void _ensureOutputDirectory() {
    final directory = outputDirectory;
    if (directory == null) return;
    try {
      Directory(directory).createSync(recursive: true);
    } on FileSystemException {
      // Codex reports the unwritable -o path itself; the stream still works.
    }
  }
}

/// A live `codex exec` process bound to one task.
///
/// [events] is a broadcast stream. Events produced before the first listener
/// subscribes are buffered and replayed to it, so nothing is lost between
/// [CodexAdapter.start] returning and the caller listening. Later listeners
/// only see new events. [turnDone] completes when the process exits.
class CodexRun implements AgentRun {
  CodexRun._({
    required RunningProcess process,
    required this.taskId,
    this.requestedSessionRef,
    this.outputFile,
  }) : _process = process {
    _events = StreamController<AgentEvent>.broadcast(
      onListen: _onFirstListener,
    );
    _process.stdoutLines.listen(
      _onStdoutLine,
      onDone: _stdoutDone.complete,
      onError: (Object error, StackTrace _) {
        _emit(_localEvent(AgentEventKind.unknown, 'stdout error: $error'));
      },
      cancelOnError: false,
    );
    _process.stderrLines.listen(
      _onStderrLine,
      onError: (Object _, StackTrace _) {},
      cancelOnError: false,
    );
    unawaited(_watchExit());
  }

  /// How many stderr lines are kept for the error text of a failed run.
  static const int stderrTailLength = 8;

  /// How long to wait for stdout to drain after the exit code arrives.
  static const Duration stdoutDrainTimeout = Duration(seconds: 5);

  final RunningProcess _process;
  final CodexJsonlParser _parser = CodexJsonlParser();
  final Completer<void> _stdoutDone = Completer<void>();
  final Completer<void> _finished = Completer<void>();
  final Completer<AgentResult> _turn = Completer<AgentResult>();
  final List<AgentEvent> _pending = [];
  final List<String> _stderrTail = [];
  late final StreamController<AgentEvent> _events;
  bool _hadListener = false;
  bool _exited = false;
  int? _exitCode;

  /// The task this run works on.
  final String taskId;

  /// The thread id we asked to resume, known before Codex confirms it in
  /// `thread.started`; null for a new thread.
  final String? requestedSessionRef;

  /// The `-o` file Codex writes the final message to, if any.
  final String? outputFile;

  /// Events as they happen. A listener who subscribes only after the process
  /// exited (for example right after awaiting [turnDone]) and when nobody
  /// listened before gets the whole history replayed instead of nothing.
  @override
  Stream<AgentEvent> get events {
    if (_events.isClosed && !_hadListener) {
      return Stream.fromIterable(List.of(_pending));
    }
    return _events.stream;
  }

  @override
  Future<AgentResult> get turnDone => _turn.future;

  @override
  String? get sessionRef => _parser.threadId ?? requestedSessionRef;

  /// Whether the process has exited.
  bool get exited => _exited;

  /// Exit code once the process has exited, else null.
  int? get exitCode => _exitCode;

  /// Completes when the process has exited and [events] is closed.
  Future<void> get finished => _finished.future;

  /// Codex exec takes one prompt per process; a follow-up is a new run.
  @override
  Future<void> send(String userMessage) async {
    throw UnsupportedError(
      'codex exec takes one prompt per process; '
      'start a new run with resumeRef',
    );
  }

  @override
  Future<void> stop({Duration grace = const Duration(seconds: 20)}) async {
    if (!_exited) {
      try {
        await _process.closeStdin();
      } catch (_) {
        // stdin may already be closed; codex exec does not read it anyway.
      }
      try {
        await _process.exitCode.timeout(grace);
      } on TimeoutException {
        _process.kill();
      }
    }
    await _finished.future;
  }

  void _onStdoutLine(String line) {
    final events = _parser.parseLineAll(line, seat: Seat.gpt, taskId: taskId);
    events.forEach(_emit);
  }

  void _onStderrLine(String line) {
    if (line.trim().isEmpty) return;
    _stderrTail.add(line);
    if (_stderrTail.length > stderrTailLength) _stderrTail.removeAt(0);
    _emit(
      _localEvent(
        AgentEventKind.unknown,
        'stderr: ${CodexJsonlParser.clip(line, 200)}',
        raw: {'stderr': line},
      ),
    );
  }

  Future<void> _watchExit() async {
    final code = await _process.exitCode;
    await _stdoutDone.future.timeout(stdoutDrainTimeout, onTimeout: () {});
    _exited = true;
    _exitCode = code;
    final result = _buildResult(code);
    if (!result.success && !_parser.turnFailed) {
      _emit(_localEvent(AgentEventKind.turnFailed, result.error!));
    }
    _emit(_localEvent(AgentEventKind.processExited, 'exited with code $code'));
    _turn.complete(result);
    // Let a caller that was awaiting turnDone subscribe before the close.
    await Future<void>.delayed(Duration.zero);
    await _events.close();
    _finished.complete();
  }

  /// Success is exit 0 without `turn.failed`. The text is the `-o` file when
  /// it exists and is non-empty, else the last `agent_message`.
  AgentResult _buildResult(int code) {
    final success = code == 0 && !_parser.turnFailed;
    String? error;
    if (!success) {
      final stderr = _stderrTail.isEmpty ? '' : ': ${_stderrTail.join(' | ')}';
      error =
          _parser.failureMessage ??
          (code == 143
              ? 'killed before the turn ended$stderr'
              : 'exited with code $code$stderr');
    }
    return AgentResult(
      success: success,
      text: _readOutputFile() ?? _parser.lastAgentMessage,
      sessionRef: sessionRef,
      inputTokens: _parser.inputTokens,
      outputTokens: _parser.outputTokens,
      error: error,
      exitCode: code,
    );
  }

  String? _readOutputFile() {
    final path = outputFile;
    if (path == null) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      final text = file.readAsStringSync().trim();
      return text.isEmpty ? null : text;
    } on FileSystemException {
      return null;
    }
  }

  AgentEvent _localEvent(
    AgentEventKind kind,
    String summary, {
    Map<String, Object?> raw = const {},
  }) {
    return AgentEvent(
      seat: Seat.gpt,
      taskId: taskId,
      kind: kind,
      summary: summary,
      sessionRef: sessionRef,
      raw: raw,
    );
  }

  void _emit(AgentEvent event) {
    if (_events.isClosed) return;
    if (_hadListener) {
      _events.add(event);
    } else {
      _pending.add(event);
    }
  }

  void _onFirstListener() {
    if (_hadListener) return;
    _hadListener = true;
    if (_events.isClosed) return;
    _pending.forEach(_events.add);
    _pending.clear();
  }
}
