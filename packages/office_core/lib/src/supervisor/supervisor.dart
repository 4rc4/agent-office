import 'dart:async';

import '../adapters/seat_adapter.dart';
import '../board/task_board.dart';
import '../board/transitions.dart';
import '../model/agent_event.dart';
import '../model/session.dart';
import '../model/task.dart';
import 'brain_protocol.dart';
import 'dispatcher.dart';

/// A plan extracted from the brain's reply.
class ParsedPlan {
  const ParsedPlan({required this.tasks, this.mergeInstructions});

  final List<PlannedTask> tasks;
  final String? mergeInstructions;
}

/// Either a [ParsedPlan] or the reason the reply could not be used.
class PlanOrError {
  const PlanOrError.plan(ParsedPlan this.plan) : error = null;

  const PlanOrError.error(String this.error) : plan = null;

  final ParsedPlan? plan;
  final String? error;

  bool get isError => error != null;
}

/// Turns the brain's reply text into a plan. The plan module provides the
/// real implementation (`PlanParser.parse`, adapted by `parsePlanText`); the
/// supervisor only depends on this signature.
typedef PlanParserFn = Future<PlanOrError> Function(String text);

/// Drives one user request from prompt to final report.
///
/// Flow: insert the root task, let the brain plan it (one retry on a parse
/// error), insert the subtasks, run them through the [Dispatcher], hand the
/// outcomes back to the brain and store its final report on the root.
/// [reconcile] rebuilds that flow from the board after a restart.
class Supervisor {
  Supervisor({
    required this.board,
    required this.adapters,
    required this.parsePlan,
    int maxParallelPerSeat = 1,
    int maxAttempts = 2,
    DiffStatCollector? collectDiffStat,
    String? artifactsDir,
    this.brainSeat = Seat.claude,
  }) {
    dispatcher = Dispatcher(
      board: board,
      adapters: adapters,
      onEvent: _emit,
      maxParallelPerSeat: maxParallelPerSeat,
      maxAttempts: maxAttempts,
      collectDiffStat: collectDiffStat,
      artifactsDir: artifactsDir,
    );
  }

  final TaskBoard board;
  final Map<Seat, SeatAdapter> adapters;
  final PlanParserFn parsePlan;

  /// The seat that plans, reviews and merges (Claude Code in v1).
  final Seat brainSeat;

  /// Runs the worker side; exposed for tests and resume hints.
  late final Dispatcher dispatcher;

  final _events = StreamController<AgentEvent>.broadcast();

  /// The brain of every root being driven, for [stopTask].
  final Map<String, _Brain> _brains = {};

  /// Roots the user stopped; their drive ends with `stopped by user`.
  final Set<String> _stoppedRoots = {};

  /// Notes from [steerTask] on a planned root, handed to the brain at its
  /// next turn.
  final Map<String, List<String>> _rootNotes = {};

  /// Every event from the brain and the workers, stamped with its task id.
  Stream<AgentEvent> get events => _events.stream;

  /// Runs [prompt] against the repository at [cwd] to completion and returns
  /// the final root task (`done` with the report in `resultSummary`, or
  /// `failed`). Never throws for agent failures; they land on the root.
  Future<TaskRecord> run(
    String prompt,
    String cwd, {
    Map<String, String> options = const {},
  }) {
    final root = board.insertRoot(prompt, cwd, options: options);
    return _driveRoot(root.id);
  }

  /// Runs [prompt] on one [seat] with no planning and no merge turn: one
  /// subtask whose result becomes the root's report. This is the desk-level
  /// "ask" of the office (talk to GPT alone, or to Claude alone).
  Future<TaskRecord> runDirect(
    Seat seat,
    String prompt,
    String cwd, {
    Map<String, String> options = const {},
  }) {
    final root = board.insertRoot(prompt, cwd, options: options);
    board.insertSubtasks(root.id, [
      PlannedTask(
        id: 'direct',
        title: directTitle(prompt),
        assignee: seat,
        prompt: prompt,
      ),
    ]);
    board.recordNote(root.id, 'direct', seat.name);
    return _driveRoot(root.id);
  }

  /// Stops [taskId]. A subtask fails with `stopped by user` and never
  /// retries; a direct root stops its worker; a planned root stops every
  /// open subtask and its brain, so the root fails with `stopped by user`.
  /// False when the task is unknown or already finished.
  Future<bool> stopTask(String taskId) async {
    final task = board.getTask(taskId);
    if (task == null || task.status.isTerminal) return false;
    if (task.kind == TaskKind.subtask) return dispatcher.stopTask(taskId);
    if (!_isDirect(taskId)) _stoppedRoots.add(taskId);
    for (final sub in board.listSubtasks(taskId)) {
      if (!sub.status.isTerminal) await dispatcher.stopTask(sub.id);
    }
    final brain = _brains[taskId];
    if (brain != null) {
      await brain.close(byUser: true);
    } else if (!_isDirect(taskId)) {
      _failRoot(taskId, 'stopped by user');
    }
    return true;
  }

  /// Hands [note] to [taskId]: a subtask restarts in its session with the
  /// note (see [Dispatcher.steerTask]); a direct root steers its worker; a
  /// planned root keeps the note for the brain's next turn. False when the
  /// task is unknown or finished.
  Future<bool> steerTask(String taskId, String note) async {
    final task = board.getTask(taskId);
    if (task == null || task.status.isTerminal) return false;
    if (task.kind == TaskKind.subtask) {
      return dispatcher.steerTask(taskId, note);
    }
    if (_isDirect(taskId)) {
      final worker = board
          .listSubtasks(taskId)
          .where((t) => !t.status.isTerminal)
          .firstOrNull;
      return worker != null && await dispatcher.steerTask(worker.id, note);
    }
    (_rootNotes[taskId] ??= []).add(note);
    return true;
  }

  /// Answers the pending approval [interactionId] (see
  /// `TaskBoard.pendingInteractions`): the run that asked gets the
  /// response and the balloon closes. False when nothing is pending under
  /// that id or its run is gone.
  Future<bool> answerApproval(int interactionId, {required bool allow}) async {
    final interaction = board
        .pendingInteractions()
        .where((i) => i.id == interactionId)
        .firstOrNull;
    if (interaction == null) return false;
    final run =
        _brains[interaction.taskId]?.run ??
        dispatcher.runFor(interaction.taskId);
    if (run == null) return false;
    return answerApprovalOn(board, run, interaction, allow: allow);
  }

  /// First line of [prompt], at most 60 characters.
  static String directTitle(String prompt) {
    final line = prompt.trim().split(RegExp(r'\r?\n')).first.trim();
    return line.length <= 60 ? line : '${line.substring(0, 57)}...';
  }

  /// Boot step. Marks whatever was in flight as interrupted, re-arms every
  /// interrupted subtask (resuming its vendor session when one is stored),
  /// then drives every unfinished root to completion. The board is consistent
  /// as soon as this method returns its future; awaiting it waits for the
  /// resumed work to finish.
  Future<List<TaskRecord>> reconcile() {
    board.markRunningAsInterrupted();
    final open = board.listNonTerminal();
    final rootIds = {
      for (final t in open)
        if (t.kind == TaskKind.root) t.id,
    };
    for (final task in open) {
      if (task.kind == TaskKind.root || !rootIds.contains(task.rootId)) {
        continue;
      }
      if (task.status != TaskStatus.interrupted) continue;
      final session = board.getSession(task.id);
      if (session != null) {
        dispatcher.addResumeHint(
          task.id,
          ResumeHint(
            sessionRef: session.sessionRef,
            message: BrainProtocol.resumeTurn(_subtaskCheckpoint(task)),
          ),
        );
      }
      board.transition(
        task.id,
        TaskStatus.assigned,
        note: session == null
            ? 'restart: no session to resume'
            : 'resume session ${session.sessionRef}',
      );
    }
    return Future.wait(rootIds.map(_driveRoot));
  }

  /// Closes the [events] stream. Running roots are not stopped.
  Future<void> dispose() => _events.close();

  Future<TaskRecord> _driveRoot(String rootId) async {
    if (_isDirect(rootId)) return _driveDirect(rootId);
    final adapter = adapters[brainSeat];
    if (adapter == null) {
      return _failRoot(rootId, 'no adapter for brain seat ${brainSeat.name}');
    }
    final _Brain brain;
    final String token;
    try {
      final root = board.beginDispatch(rootId);
      token = root.dispatchToken!;
      brain = _Brain(this, root, adapter);
    } on Object catch (error) {
      return _failRoot(rootId, 'cannot start root: $error');
    }
    _brains[rootId] = brain;
    try {
      var mergeInstructions = _storedMergeInstructions(rootId);
      if (board.listSubtasks(rootId).isEmpty) {
        final planned = await _obtainPlan(brain, rootId);
        if (planned.isError) return _failRoot(rootId, planned.error!);
        final plan = planned.plan!;
        board.insertSubtasks(rootId, plan.tasks);
        mergeInstructions = plan.mergeInstructions;
        board.recordNote(
          rootId,
          'plan',
          '${plan.tasks.length} subtask(s) planned',
          raw: {
            'merge_instructions': plan.mergeInstructions,
            'tasks': [
              for (final t in plan.tasks)
                {
                  'id': t.id,
                  'title': t.title,
                  'assignee': t.assignee.name,
                  'depends_on': t.dependsOn,
                },
            ],
          },
        );
      }
      final outcomes = await dispatcher.runSubtasks(rootId);
      if (_stoppedRoots.contains(rootId)) {
        return _failRoot(rootId, 'stopped by user');
      }
      var results = BrainProtocol.resultsTurn(
        outcomes,
        mergeInstructions: mergeInstructions,
      );
      final notes = _rootNotes.remove(rootId);
      if (notes != null && notes.isNotEmpty) {
        results = '${BrainProtocol.userNote(notes.join('\n'))}\n\n$results';
      }
      final reply = await brain.ask(results);
      if (!reply.success) {
        return _failRoot(rootId, 'final brain turn failed: ${reply.error}');
      }
      final accepted = board.completeIfCurrent(
        rootId,
        token,
        resultSummary: reply.text ?? '',
        note: 'final report received',
      );
      if (accepted) {
        board.transition(rootId, TaskStatus.done, note: 'completed');
      }
      return board.requireTask(rootId);
    } on Object catch (error) {
      return _failRoot(rootId, 'supervisor error: $error');
    } finally {
      _brains.remove(rootId);
      await brain.close();
    }
  }

  bool _isDirect(String rootId) =>
      board.listEvents(taskId: rootId, kind: 'direct', limit: 1).isNotEmpty;

  /// A direct root has exactly one worker subtask and no brain: its result
  /// text is the report. Resume after a restart goes through the same path.
  Future<TaskRecord> _driveDirect(String rootId) async {
    final String token;
    try {
      token = board.beginDispatch(rootId).dispatchToken!;
      board.transition(rootId, TaskStatus.running, note: 'direct run');
    } on Object catch (error) {
      return _failRoot(rootId, 'cannot start root: $error');
    }
    try {
      await dispatcher.runSubtasks(rootId);
      final subtasks = board.listSubtasks(rootId);
      final worker = subtasks.isEmpty ? null : subtasks.first;
      if (worker == null || worker.status != TaskStatus.done) {
        return _failRoot(
          rootId,
          'direct task ended ${worker?.status.name ?? 'without a subtask'}',
        );
      }
      final accepted = board.completeIfCurrent(
        rootId,
        token,
        resultSummary: worker.resultSummary ?? '',
        note: 'direct result received',
      );
      if (accepted) {
        board.transition(rootId, TaskStatus.done, note: 'completed');
      }
      return board.requireTask(rootId);
    } on Object catch (error) {
      return _failRoot(rootId, 'supervisor error: $error');
    }
  }

  Future<PlanOrError> _obtainPlan(_Brain brain, String rootId) async {
    final root = board.requireTask(rootId);
    var reply = await brain.ask(BrainProtocol.firstTurn(root));
    if (!reply.success) {
      return PlanOrError.error('brain turn failed: ${reply.error}');
    }
    var parsed = await parsePlan(reply.text ?? '');
    if (!parsed.isError) return parsed;
    board.recordNote(rootId, 'plan_rejected', parsed.error!);
    reply = await brain.ask(BrainProtocol.retryTurn(parsed.error!));
    if (!reply.success) {
      return PlanOrError.error('brain turn failed: ${reply.error}');
    }
    parsed = await parsePlan(reply.text ?? '');
    if (parsed.isError) {
      return PlanOrError.error('plan rejected twice: ${parsed.error}');
    }
    return parsed;
  }

  TaskRecord _failRoot(String rootId, String reason) {
    final root = board.requireTask(rootId);
    if (_stoppedRoots.remove(rootId)) reason = 'stopped by user';
    _rootNotes.remove(rootId);
    board.recordNote(rootId, 'root_failed', reason);
    if (canTransition(root.status, TaskStatus.failed)) {
      board.transition(rootId, TaskStatus.failed, note: reason);
    }
    return board.requireTask(rootId);
  }

  String? _storedMergeInstructions(String rootId) {
    final events = board.listEvents(taskId: rootId, kind: 'plan', limit: 1);
    if (events.isEmpty) return null;
    return events.first.raw['merge_instructions'] as String?;
  }

  /// Board state for the brain after a restart.
  String _checkpoint(String rootId) {
    final root = board.requireTask(rootId);
    final subtasks = board.listSubtasks(rootId);
    final buffer = StringBuffer(
      'Root task "${root.title}" is ${root.status.name}.',
    );
    if (subtasks.isEmpty) {
      buffer.write(
        ' No plan has been recorded yet; the request below asks for it again.',
      );
      return buffer.toString();
    }
    buffer.writeln(' Subtasks:');
    for (final task in subtasks) {
      final summary = task.resultSummary?.trim().split(RegExp(r'\r?\n')).first;
      buffer.writeln(
        '- [${task.status.name}] ${task.title} '
        '(${task.assignee?.name ?? 'unassigned'}, attempt ${task.attempt})'
        '${summary == null || summary.isEmpty ? '' : ': $summary'}',
      );
    }
    return buffer.toString();
  }

  String _subtaskCheckpoint(TaskRecord task) =>
      'Subtask "${task.title}" (attempt ${task.attempt}) was interrupted '
      'mid-work. The original task was:\n\n${task.prompt}';

  void _emit(AgentEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

/// The brain's live run for one root: starts it (resuming the stored session
/// when there is one), sends turns, and records its session id first thing.
class _Brain {
  _Brain(this.supervisor, this.root, this.adapter);

  final Supervisor supervisor;
  final TaskRecord root;
  final SeatAdapter adapter;
  AgentRun? _run;
  StreamSubscription<AgentEvent>? _subscription;
  bool _closedByUser = false;

  TaskBoard get _board => supervisor.board;

  /// The live run, for permission answers.
  AgentRun? get run => _run;

  /// Sends [message] as the next turn and waits for the reply. A run whose
  /// `send` fails, or whose process exits under the turn without a result
  /// (idle close, kill, crash), is replaced once by a new run that resumes
  /// the stored session with the same message.
  Future<AgentResult> ask(String message) async {
    var resumed = false;
    if (_run == null) {
      await _start(message);
    } else {
      try {
        await _run!.send(message);
      } on Object {
        resumed = true;
        await close();
        await _start(message);
      }
    }
    var result = await _awaitTurn();
    if (!result.success &&
        result.exitCode != null &&
        !resumed &&
        !_closedByUser) {
      _board.recordNote(
        root.id,
        'brain_resumed',
        'brain process exited (code ${result.exitCode}) before the turn '
            'ended; resuming the session once',
      );
      await close();
      await _start(message);
      result = await _awaitTurn();
    }
    return result;
  }

  Future<AgentResult> _awaitTurn() async {
    _board.setTurnState(root.id, TurnState.inTurn);
    AgentResult result;
    try {
      result = await _run!.turnDone;
    } on Object catch (error) {
      result = AgentResult(success: false, error: '$error');
    }
    _board.setTurnState(root.id, TurnState.idle);
    _board.expireInteractions(root.id);
    if (_board.requireTask(root.id).status == TaskStatus.waitingApproval) {
      _board.transition(
        root.id,
        TaskStatus.running,
        note: 'permission request lapsed with the turn',
      );
    }
    return result;
  }

  /// Stops the run (closing stdin) and drops the event subscription. With
  /// [byUser] the run is killed after a short grace and never resumed.
  Future<void> close({bool byUser = false}) async {
    if (byUser) _closedByUser = true;
    await _subscription?.cancel();
    _subscription = null;
    final run = _run;
    _run = null;
    if (run == null) return;
    _board.expireInteractions(root.id);
    try {
      await run.stop(
        grace: byUser ? Dispatcher.userStopGrace : const Duration(seconds: 20),
      );
    } on Object {
      // Already gone.
    }
  }

  Future<void> _start(String message) async {
    final session = _board.getSession(root.id);
    final resumeRef = session?.sessionRef;
    final text = resumeRef == null
        ? message
        : '${BrainProtocol.resumeTurn(supervisor._checkpoint(root.id))}\n'
              '$message';
    final run = await adapter.start(
      _board.requireTask(root.id),
      initialMessage: text,
      resumeRef: resumeRef,
    );
    _run = run;
    _subscription = run.events.listen((event) => _onEvent(event, run));
    if (_board.requireTask(root.id).status == TaskStatus.assigned) {
      _board.transition(root.id, TaskStatus.running, note: 'brain started');
    }
  }

  void _onEvent(AgentEvent event, AgentRun run) {
    if (event.kind == AgentEventKind.sessionStarted) {
      final ref = event.sessionRef ?? run.sessionRef;
      if (ref != null) {
        _board.setSession(
          SessionRecord(
            taskId: root.id,
            seat: adapter.seat,
            sessionRef: ref,
            launchArgs: const [],
            turnState: TurnState.inTurn,
            updatedAt: event.timestamp,
          ),
        );
      }
    }
    final stamped = withTaskId(event, root.id);
    _board.recordEvent(stamped);
    recordApprovalRequest(_board, root.id, stamped);
    supervisor._emit(stamped);
  }
}
