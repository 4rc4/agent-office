import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../adapters/seat_adapter.dart';
import '../board/task_board.dart';
import '../model/agent_event.dart';
import '../model/session.dart';
import '../model/task.dart';
import 'brain_protocol.dart';

/// Collects `git diff --stat` (or any change summary) for a working tree.
typedef DiffStatCollector = Future<String> Function(String cwd);

/// Receives every event the dispatcher forwards from worker runs.
typedef AgentEventSink = void Function(AgentEvent event);

/// Continue [sessionRef] with [message] instead of starting the task afresh.
class ResumeHint {
  const ResumeHint({required this.sessionRef, required this.message});

  final String sessionRef;
  final String message;
}

/// Runs `git diff --stat` in [cwd]; empty when git is missing or fails.
Future<String> gitDiffStat(String cwd) async {
  try {
    final result = await Process.run('git', [
      'diff',
      '--stat',
    ], workingDirectory: cwd);
    return result.exitCode == 0 ? result.stdout as String : '';
  } on Object {
    return '';
  }
}

/// Starts worker runs for dispatchable subtasks, forwards their events to the
/// board and to [onEvent], and settles each attempt through the board's
/// dispatch token so results from stale attempts are ignored.
///
/// v1 policy: a successful attempt is auto-accepted (`review -> done`); a
/// failed attempt is retried from scratch until [maxAttempts] is reached,
/// then the task fails and anything depending on it fails as blocked.
class Dispatcher {
  Dispatcher({
    required this.board,
    required this.adapters,
    required this.onEvent,
    this.maxParallelPerSeat = 1,
    this.maxAttempts = 2,
    DiffStatCollector? collectDiffStat,
    this.artifactsDir,
    this.xpPerSubtask = 10,
  }) : collectDiffStat = collectDiffStat ?? gitDiffStat;

  final TaskBoard board;
  final Map<Seat, SeatAdapter> adapters;
  final AgentEventSink onEvent;
  final int maxParallelPerSeat;
  final int maxAttempts;
  final DiffStatCollector collectDiffStat;

  /// Folder for per-attempt result files; null keeps results in the board only.
  final String? artifactsDir;
  final int xpPerSubtask;

  final Map<String, _ActiveRun> _active = {};
  final Map<String, ResumeHint> _resumeHints = {};
  final Map<String, String> _diffStats = {};

  /// Task ids with a run in flight right now.
  Set<String> get activeTaskIds => _active.keys.toSet();

  /// Makes the next dispatch of [taskId] resume an earlier conversation.
  void addResumeHint(String taskId, ResumeHint hint) =>
      _resumeHints[taskId] = hint;

  /// Seats that have an adapter and spare capacity.
  Set<Seat> freeSeats() {
    final busy = <Seat, int>{};
    for (final run in _active.values) {
      busy.update(run.seat, (n) => n + 1, ifAbsent: () => 1);
    }
    return adapters.keys
        .where((seat) => (busy[seat] ?? 0) < maxParallelPerSeat)
        .toSet();
  }

  /// Dispatches the subtasks of [rootId] in dependency order until every one
  /// is terminal, then returns their outcomes in board order.
  Future<List<SubtaskOutcome>> runSubtasks(String rootId) async {
    while (true) {
      final pending = board
          .listSubtasks(rootId)
          .where((t) => !t.status.isTerminal)
          .toList();
      if (pending.isEmpty) break;
      _fillSeats(rootId);
      final blocked = pending
          .where((t) => !_active.containsKey(t.id) && _isBlocked(t))
          .toList();
      if (blocked.isNotEmpty) {
        for (final task in blocked) {
          _fail(
            task,
            'blocked: a dependency failed or the seat has no adapter',
          );
        }
        continue;
      }
      if (_active.isEmpty) {
        for (final task in pending) {
          _fail(task, 'not dispatchable from ${task.status.name}');
        }
        continue;
      }
      await Future.any(_active.values.map((run) => run.done));
    }
    return outcomesFor(rootId);
  }

  /// Outcomes for every subtask of [rootId], built from the board plus the
  /// diff stats collected in this process (or read back from result files).
  List<SubtaskOutcome> outcomesFor(String rootId) {
    return board.listSubtasks(rootId).map((task) {
      final diff = _diffStats[task.id] ?? _readDiffStat(task.resultPath);
      return SubtaskOutcome(
        taskId: task.id,
        title: task.title,
        assignee: task.assignee,
        status: task.status,
        attempts: task.attempt,
        summary: task.resultSummary,
        files: parseDiffStatFiles(diff ?? ''),
        diffStatPath: task.resultPath,
        diffStat: diff,
      );
    }).toList();
  }

  /// File paths named in `git diff --stat` output.
  static List<String> parseDiffStatFiles(String diffStat) {
    final files = <String>[];
    for (final line in diffStat.split(RegExp(r'\r?\n'))) {
      final bar = line.indexOf(' | ');
      if (bar <= 0) continue;
      var path = line.substring(0, bar).trim();
      // Renames: `lib/{old => new}.dart` or `old.dart => new.dart`.
      path = path.replaceAllMapped(_braceRename, (m) => m.group(2)!);
      final arrow = path.indexOf(' => ');
      if (arrow >= 0) path = path.substring(arrow + 4);
      if (path.isNotEmpty) files.add(path);
    }
    return files;
  }

  static final RegExp _braceRename = RegExp(r'\{([^{}]*) => ([^{}]*)\}');

  void _fillSeats(String rootId) {
    while (true) {
      final next = board.nextDispatchable(
        freeSeats: freeSeats(),
        excludeTaskIds: _active.keys.toSet(),
        rootId: rootId,
      );
      if (next == null) return;
      final seat = next.assignee!;
      final run = _ActiveRun(seat, _runAttempt(next));
      _active[next.id] = run;
      run.done.whenComplete(() => _active.remove(next.id));
    }
  }

  bool _isBlocked(TaskRecord task) {
    final seat = task.assignee;
    if (seat == null || !adapters.containsKey(seat)) return true;
    for (final dep in task.dependsOn) {
      final status = board.getTask(dep)?.status;
      if (status == null) return true;
      if (status.isTerminal && status != TaskStatus.done) return true;
    }
    return false;
  }

  Future<void> _runAttempt(TaskRecord task) async {
    final hint = _resumeHints.remove(task.id);
    final dispatched = board.beginDispatch(task.id);
    final seat = dispatched.assignee!;
    final token = dispatched.dispatchToken!;
    final adapter = adapters[seat]!;

    final AgentRun run;
    try {
      run = await adapter.start(
        dispatched,
        initialMessage: hint?.message ?? dispatched.prompt,
        resumeRef: hint?.sessionRef,
      );
    } on Object catch (error) {
      _startFailed(dispatched, 'could not start ${seat.name}: $error');
      return;
    }
    board.transition(
      dispatched.id,
      TaskStatus.running,
      note: 'attempt ${dispatched.attempt}',
    );
    final subscription = run.events.listen(
      (event) => _forward(dispatched, event, run),
    );
    AgentResult result;
    try {
      result = await run.turnDone;
    } on Object catch (error) {
      result = AgentResult(success: false, error: '$error');
    }
    try {
      await run.stop();
    } on Object {
      // The process is already gone; nothing to clean up.
    }
    await subscription.cancel();
    if (result.success) {
      await _succeeded(dispatched, token, result);
    } else {
      _failedAttempt(dispatched, token, result.error ?? 'unknown error');
    }
  }

  void _forward(TaskRecord task, AgentEvent event, AgentRun run) {
    final stamped = withTaskId(event, task.id);
    board.recordEvent(stamped);
    switch (event.kind) {
      case AgentEventKind.sessionStarted:
        final ref = event.sessionRef ?? run.sessionRef;
        if (ref != null) {
          board.setSession(
            SessionRecord(
              taskId: task.id,
              seat: task.assignee!,
              sessionRef: ref,
              launchArgs: const [],
              turnState: TurnState.inTurn,
              updatedAt: event.timestamp,
            ),
          );
        }
      case AgentEventKind.turnCompleted:
      case AgentEventKind.turnFailed:
      case AgentEventKind.processExited:
        board.setTurnState(task.id, TurnState.idle);
      default:
        break;
    }
    onEvent(stamped);
  }

  Future<void> _succeeded(
    TaskRecord task,
    String token,
    AgentResult result,
  ) async {
    final diff = await _safeDiffStat(task.cwd);
    _diffStats[task.id] = diff;
    final path = _writeArtifact(task, result.text, diff);
    final accepted = board.completeIfCurrent(
      task.id,
      token,
      resultPath: path,
      resultSummary: result.text ?? '',
      note: 'attempt ${task.attempt} succeeded',
    );
    if (!accepted) return;
    board.transition(task.id, TaskStatus.done, note: 'auto-accepted (v1)');
    board.addXp(task.assignee!, xpPerSubtask);
  }

  void _failedAttempt(TaskRecord task, String token, String error) {
    final accepted = board.completeIfCurrent(
      task.id,
      token,
      resultSummary: 'FAILED: $error',
      note: 'attempt ${task.attempt} failed',
    );
    if (!accepted) return;
    if (task.attempt < maxAttempts) {
      board.transition(
        task.id,
        TaskStatus.assigned,
        note: 'retry ${task.attempt + 1}/$maxAttempts',
      );
    } else {
      board.transition(
        task.id,
        TaskStatus.failed,
        note: 'gave up after ${task.attempt} attempts: $error',
      );
    }
  }

  void _startFailed(TaskRecord task, String error) {
    board.recordNote(task.id, 'start_failed', error);
    if (task.attempt >= maxAttempts) {
      board.transition(
        task.id,
        TaskStatus.failed,
        note: 'gave up after ${task.attempt} attempts: $error',
      );
    }
  }

  void _fail(TaskRecord task, String note) {
    final current = board.getTask(task.id);
    if (current == null || current.status.isTerminal) return;
    board.transition(task.id, TaskStatus.failed, note: note);
  }

  Future<String> _safeDiffStat(String cwd) async {
    try {
      return await collectDiffStat(cwd);
    } on Object {
      return '';
    }
  }

  String? _writeArtifact(TaskRecord task, String? text, String diff) {
    final dir = artifactsDir;
    if (dir == null) return null;
    try {
      final file = File(p.join(dir, task.id, 'attempt-${task.attempt}.md'));
      file.parent.createSync(recursive: true);
      file.writeAsStringSync(
        '# ${task.title}\n\n## Result\n\n${text ?? ''}\n\n'
        '## git diff --stat\n\n```\n$diff\n```\n',
      );
      return file.path;
    } on IOException {
      return null;
    }
  }

  String? _readDiffStat(String? path) {
    if (path == null) return null;
    try {
      final text = File(path).readAsStringSync();
      const marker = '## git diff --stat\n\n```\n';
      final start = text.indexOf(marker);
      if (start < 0) return null;
      final body = text.substring(start + marker.length);
      final end = body.lastIndexOf('\n```');
      return end < 0 ? body : body.substring(0, end);
    } on IOException {
      return null;
    }
  }
}

/// A copy of [event] bound to [taskId]; [event] itself when already bound.
AgentEvent withTaskId(AgentEvent event, String taskId) {
  if (event.taskId == taskId) return event;
  return AgentEvent(
    seat: event.seat,
    kind: event.kind,
    summary: event.summary,
    taskId: taskId,
    category: event.category,
    sessionRef: event.sessionRef,
    inputTokens: event.inputTokens,
    outputTokens: event.outputTokens,
    raw: event.raw,
    timestamp: event.timestamp,
  );
}

class _ActiveRun {
  _ActiveRun(this.seat, this.done);

  final Seat seat;
  final Future<void> done;
}
