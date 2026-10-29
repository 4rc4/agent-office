import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../model/agent_event.dart';
import '../model/task.dart';
import '../process/process_runner.dart';
import 'claude_stream_parser.dart';
import 'seat_adapter.dart';

/// The Claude Code seat: launches the user's own, already-logged-in `claude`
/// binary headless (`-p --output-format stream-json --input-format
/// stream-json`) and keeps the process alive so further turns can be sent on
/// the same conversation with [AgentRun.send].
///
/// Credentials are never read or forwarded. `ANTHROPIC_API_KEY`,
/// `CLAUDE_CODE_USE_BEDROCK` and `CLAUDE_CODE_USE_VERTEX` are removed from the
/// environment handed to the child so the CLI falls back to the subscription
/// login. If the CLI still reports an `apiKeySource` other than `none`, the
/// run emits a warning event (kind [AgentEventKind.unknown], summary starting
/// with `WARNING: apiKeySource=`) but does not abort; the desktop app decides.
///
/// `--bare` is never passed (it drops the subscription login) and `--resume`
/// does not restore `--mcp-config` / `--append-system-prompt-file`, so both
/// are passed on every start.
class ClaudeAdapter implements SeatAdapter {
  ClaudeAdapter({
    required ProcessRunner runner,
    required this.executable,
    this.permissionMode = 'acceptEdits',
    this.systemPromptFile,
    this.mcpConfigFile,
    this.maxTurns,
    this.model = '',
    this.effort = '',
    this.baseEnvironment = const {},
    String Function()? sessionIdFactory,
  }) : _runner = runner,
       _sessionIdFactory = sessionIdFactory ?? newSessionId;

  /// Environment variables that must never reach the child (compared
  /// case-insensitively, since Windows variable names are).
  static const Set<String> scrubbedEnvironmentKeys = {
    'ANTHROPIC_API_KEY',
    'CLAUDE_CODE_USE_BEDROCK',
    'CLAUDE_CODE_USE_VERTEX',
  };

  /// Set to `1` on every `--resume` so an interrupted turn is picked up.
  static const String resumeInterruptedTurnKey =
      'CLAUDE_CODE_RESUME_INTERRUPTED_TURN';

  final ProcessRunner _runner;
  final String Function() _sessionIdFactory;

  /// Absolute path of the `claude` binary (or its `.cmd` shim on Windows).
  final String executable;

  /// Value for `--permission-mode`, e.g. `acceptEdits` or `auto`.
  final String permissionMode;

  /// File passed with `--append-system-prompt-file`, if any.
  final String? systemPromptFile;

  /// File passed with `--mcp-config`, if any.
  final String? mcpConfigFile;

  /// Value for `--max-turns`, if any.
  final int? maxTurns;

  /// Default `--model` (empty: the CLI's own default). A task's
  /// `options['model']` overrides it.
  final String model;

  /// Default `--effort` (empty: none). A task's `options['effort']`
  /// overrides it.
  final String effort;

  /// Environment the child starts from, before scrubbing.
  final Map<String, String> baseEnvironment;

  List<String> _lastArguments = const [];
  Map<String, String> _lastEnvironment = const {};

  /// Arguments of the most recent [start], for tests and session records.
  List<String> get lastArguments => List.unmodifiable(_lastArguments);

  /// Environment of the most recent [start], after scrubbing.
  Map<String, String> get lastEnvironment => Map.unmodifiable(_lastEnvironment);

  @override
  Seat get seat => Seat.claude;

  /// The exact argument list for one start. A new session gets
  /// `--session-id [sessionId]` (generated when null), a resume gets
  /// `--resume [resumeRef]`.
  List<String> buildArguments({
    String? resumeRef,
    String? sessionId,
    Map<String, String> options = const {},
  }) {
    final systemPrompt = systemPromptFile;
    final mcpConfig = mcpConfigFile;
    final turns = maxTurns;
    final chosenModel = pickOption(options['model'], model);
    final chosenEffort = pickOption(options['effort'], effort);
    return [
      '-p',
      '--output-format',
      'stream-json',
      '--input-format',
      'stream-json',
      '--verbose',
      '--include-partial-messages',
      '--permission-mode',
      permissionMode,
      '--permission-prompt-tool',
      'stdio',
      if (resumeRef != null) ...['--resume', resumeRef],
      if (resumeRef == null) ...[
        '--session-id',
        sessionId ?? _sessionIdFactory(),
      ],
      if (systemPrompt != null) ...[
        '--append-system-prompt-file',
        systemPrompt,
      ],
      if (mcpConfig != null) ...['--mcp-config', mcpConfig],
      if (turns != null) ...['--max-turns', '$turns'],
      if (chosenModel.isNotEmpty) ...['--model', chosenModel],
      if (chosenEffort.isNotEmpty) ...['--effort', chosenEffort],
    ];
  }

  /// [baseEnvironment] without [scrubbedEnvironmentKeys], plus
  /// [resumeInterruptedTurnKey] when [resuming].
  Map<String, String> buildEnvironment({required bool resuming}) {
    final environment = Map<String, String>.of(baseEnvironment)
      ..removeWhere(
        (key, _) => scrubbedEnvironmentKeys.contains(key.toUpperCase()),
      );
    if (resuming) environment[resumeInterruptedTurnKey] = '1';
    return environment;
  }

  @override
  Future<AgentRun> start(
    TaskRecord task, {
    required String initialMessage,
    String? resumeRef,
  }) async {
    final sessionId = resumeRef == null ? _sessionIdFactory() : null;
    final arguments = buildArguments(
      resumeRef: resumeRef,
      sessionId: sessionId,
      options: task.options,
    );
    final environment = buildEnvironment(resuming: resumeRef != null);
    _lastArguments = arguments;
    _lastEnvironment = environment;
    final process = await _runner.start(
      executable,
      arguments,
      workingDirectory: task.cwd,
      environment: environment,
    );
    final run = ClaudeRun._(
      process: process,
      taskId: task.id,
      requestedSessionRef: sessionId ?? resumeRef,
    );
    run._beginTurn(initialMessage);
    return run;
  }

  /// One stream-json input line carrying a user text message.
  static String encodeUserMessage(String text) {
    return jsonEncode({
      'type': 'user',
      'message': {
        'role': 'user',
        'content': [
          {'type': 'text', 'text': text},
        ],
      },
    });
  }

  /// One stream-json input line answering `control_request` [requestId]:
  /// allow (echoing [input] as `updatedInput`, the shape the CLI expects)
  /// or deny with [message].
  static String encodeControlResponse(
    String requestId, {
    required bool allow,
    Map<String, Object?> input = const {},
    String? message,
  }) {
    return jsonEncode({
      'type': 'control_response',
      'response': {
        'subtype': 'success',
        'request_id': requestId,
        'response': allow
            ? {'behavior': 'allow', 'updatedInput': input}
            : {'behavior': 'deny', 'message': message ?? 'Denied by the user'},
      },
    });
  }

  /// A random RFC 4122 version 4 UUID, the format `--session-id` requires.
  static String newSessionId([Random? random]) {
    final rng = random ?? _secureRandom();
    final bytes = List<int>.generate(16, (_) => rng.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  static Random _secureRandom() {
    try {
      return Random.secure();
    } on UnsupportedError {
      return Random();
    }
  }
}

/// A live `claude -p` process bound to one task.
///
/// [events] is a broadcast stream. Events produced before the first listener
/// subscribes are buffered and replayed to it, so nothing is lost between
/// [ClaudeAdapter.start] returning and the caller listening. Later listeners
/// only see new events.
class ClaudeRun implements AgentRun {
  ClaudeRun._({
    required RunningProcess process,
    required this.taskId,
    this.requestedSessionRef,
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

  /// How many stderr lines are kept for the error text of a failed turn.
  static const int stderrTailLength = 8;

  /// How long to wait for stdout to drain after the exit code arrives.
  static const Duration stdoutDrainTimeout = Duration(seconds: 5);

  final RunningProcess _process;
  final ClaudeStreamParser _parser = ClaudeStreamParser();
  final Completer<void> _stdoutDone = Completer<void>();
  final Completer<void> _finished = Completer<void>();
  final List<AgentEvent> _pending = [];
  final List<String> _stderrTail = [];
  late final StreamController<AgentEvent> _events;
  Completer<AgentResult> _turn = Completer<AgentResult>();
  bool _hadListener = false;
  bool _exited = false;
  int? _exitCode;
  String? _sessionRef;

  /// Tool inputs of the permission requests still waiting for an answer,
  /// by request id (`updatedInput` echoes them back on allow).
  final Map<String, Map<String, Object?>> _pendingApprovals = {};

  /// The task this run works on.
  final String taskId;

  /// The session id we asked for (`--session-id` or `--resume` value), known
  /// before the CLI confirms it in `system/init`.
  final String? requestedSessionRef;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<AgentResult> get turnDone => _turn.future;

  @override
  String? get sessionRef => _sessionRef;

  /// Whether a turn is in progress (a user message was sent and no `result`
  /// has arrived yet).
  bool get inTurn => !_turn.isCompleted;

  /// Whether the process has exited.
  bool get exited => _exited;

  /// Exit code once the process has exited, else null.
  int? get exitCode => _exitCode;

  /// Completes when the process has exited and [events] is closed.
  Future<void> get finished => _finished.future;

  @override
  Future<void> send(String userMessage) async {
    if (!_turn.isCompleted) await _turn.future;
    if (_exited) {
      throw StateError(
        'Claude process already exited (code $_exitCode); '
        'start a new run with resumeRef instead.',
      );
    }
    _turn = Completer<AgentResult>();
    _process.writeLine(ClaudeAdapter.encodeUserMessage(userMessage));
  }

  @override
  Future<void> answerApproval(
    String requestId, {
    required bool allow,
    String? message,
  }) async {
    final input = _pendingApprovals.remove(requestId);
    if (input == null) {
      throw StateError('no pending permission request $requestId');
    }
    if (_exited) {
      throw StateError('Claude process already exited (code $_exitCode)');
    }
    _process.writeLine(
      ClaudeAdapter.encodeControlResponse(
        requestId,
        allow: allow,
        input: input,
        message: message,
      ),
    );
  }

  @override
  Future<void> stop({Duration grace = const Duration(seconds: 20)}) async {
    if (!_exited) {
      try {
        await _process.closeStdin();
      } catch (_) {
        // stdin may already be closed; the exit code tells the rest.
      }
      try {
        await _process.exitCode.timeout(grace);
      } on TimeoutException {
        _process.kill();
      }
    }
    await _finished.future;
  }

  void _beginTurn(String userMessage) {
    _process.writeLine(ClaudeAdapter.encodeUserMessage(userMessage));
  }

  void _onStdoutLine(String line) {
    final events = _parser.parseLineAll(
      line,
      seat: Seat.claude,
      taskId: taskId,
    );
    for (final event in events) {
      _emit(event);
      switch (event.kind) {
        case AgentEventKind.sessionStarted:
          _sessionRef = event.sessionRef ?? _sessionRef;
          final apiKeySource = event.raw['apiKeySource'];
          if (apiKeySource != null && apiKeySource != 'none') {
            _emit(
              _localEvent(
                AgentEventKind.unknown,
                'WARNING: apiKeySource=$apiKeySource; the Office expects the '
                'subscription login (apiKeySource=none)',
                raw: event.raw,
              ),
            );
          }
        case AgentEventKind.turnCompleted || AgentEventKind.turnFailed:
          _completeTurn(_parser.resultFrom(event.raw));
        case AgentEventKind.approvalRequested:
          final id = event.raw['request_id'];
          final request = event.raw['request'];
          if (id is String && request is Map) {
            final input = request['input'];
            _pendingApprovals[id] = input is Map
                ? Map<String, Object?>.from(input)
                : const {};
          }
        default:
          break;
      }
    }
  }

  void _onStderrLine(String line) {
    if (line.trim().isEmpty) return;
    _stderrTail.add(line);
    if (_stderrTail.length > stderrTailLength) _stderrTail.removeAt(0);
    _emit(
      _localEvent(
        AgentEventKind.unknown,
        'stderr: ${ClaudeStreamParser.clip(line, 200)}',
        raw: {'stderr': line},
      ),
    );
  }

  Future<void> _watchExit() async {
    final code = await _process.exitCode;
    await _stdoutDone.future.timeout(stdoutDrainTimeout, onTimeout: () {});
    _exited = true;
    _exitCode = code;
    if (!_turn.isCompleted) {
      final summary = code == 143
          ? 'killed before the turn ended'
          : 'exited with code $code before the turn ended';
      _emit(_localEvent(AgentEventKind.turnFailed, summary));
      final stderr = _stderrTail.isEmpty ? '' : ': ${_stderrTail.join(' | ')}';
      _completeTurn(
        AgentResult(
          success: false,
          sessionRef: _sessionRef,
          error: '$summary$stderr',
          exitCode: code,
        ),
      );
    }
    _emit(_localEvent(AgentEventKind.processExited, 'exited with code $code'));
    await _events.close();
    _finished.complete();
  }

  void _completeTurn(AgentResult result) {
    if (_turn.isCompleted) return;
    if (result.sessionRef == null && _sessionRef != null) {
      result = AgentResult(
        success: result.success,
        text: result.text,
        sessionRef: _sessionRef,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
        error: result.error,
        exitCode: result.exitCode,
      );
    }
    _turn.complete(result);
  }

  AgentEvent _localEvent(
    AgentEventKind kind,
    String summary, {
    Map<String, Object?> raw = const {},
  }) {
    return AgentEvent(
      seat: Seat.claude,
      taskId: taskId,
      kind: kind,
      summary: summary,
      sessionRef: _sessionRef,
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
    for (final event in _pending) {
      _events.add(event);
    }
    _pending.clear();
  }
}
