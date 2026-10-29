import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';

import '../model/agent_event.dart';
import '../model/session.dart';
import '../model/task.dart';
import '../plan/planned_task.dart';
import 'schema.dart';
import 'transitions.dart';

export '../plan/planned_task.dart' show PlannedTask;

/// One row of the `events` table. [kind] is an [AgentEventKind] name for
/// adapter events, or one of the board's own kinds: `status`, `dispatch`,
/// `stale_result`, `ignored_result`, `plan`.
class BoardEvent {
  const BoardEvent({
    required this.id,
    required this.kind,
    required this.summary,
    required this.createdAt,
    this.taskId,
    this.seat,
    this.category,
    this.raw = const {},
  });

  final int id;
  final String? taskId;
  final String? seat;
  final String kind;
  final String? category;
  final String summary;
  final Map<String, Object?> raw;
  final DateTime createdAt;
}

/// Kind of a pending balloon: a permission request or a question for the user.
enum InteractionKind { approval, question }

/// One approval or question balloon, pending until the user answers.
class Interaction {
  const Interaction({
    required this.id,
    required this.taskId,
    required this.seat,
    required this.kind,
    required this.payload,
    required this.pending,
    required this.createdAt,
    this.answer,
  });

  final int id;
  final String taskId;
  final Seat seat;
  final InteractionKind kind;
  final Map<String, Object?> payload;
  final bool pending;
  final String? answer;
  final DateTime createdAt;
}

/// Latest known usage for one seat and one window (`5h`, `weekly`...).
class UsageSnapshot {
  const UsageSnapshot({
    required this.seat,
    required this.window,
    required this.usedPct,
    required this.source,
    required this.fetchedAt,
    this.resetsAt,
  });

  final Seat seat;
  final String window;
  final double usedPct;
  final DateTime? resetsAt;
  final String source;
  final DateTime fetchedAt;
}

/// Returns a random RFC 4122 version-4 UUID built from `Random.secure`.
String uuidV4() {
  final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}

final Random _random = Random.secure();

/// The SQLite task board: tasks, sessions, events, interactions, usage and XP.
///
/// One [TaskBoard] owns one `Database`. All methods are synchronous (sqlite3
/// is), and every mutation that touches more than one row runs in a single
/// transaction. Status changes are validated against [canTransition] and
/// always leave an event row behind.
class TaskBoard {
  TaskBoard._(this._db, DateTime Function()? clock)
    : _clock = clock ?? DateTime.now {
    applySchema(_db);
  }

  /// Opens (or creates) the board file at [path], creating parent folders.
  factory TaskBoard.open(String path, {DateTime Function()? clock}) {
    Directory(p.dirname(path)).createSync(recursive: true);
    return TaskBoard._(sqlite3.open(path), clock);
  }

  /// A fresh in-memory board, for tests. [clock] overrides `DateTime.now`.
  factory TaskBoard.inMemory({DateTime Function()? clock}) =>
      TaskBoard._(sqlite3.openInMemory(), clock);

  final Database _db;
  final DateTime Function() _clock;
  final _changes = StreamController<TaskRecord>.broadcast();
  final List<TaskRecord> _pendingChanges = [];
  bool _inTransaction = false;

  /// Every task whose status changed, emitted after the transaction commits.
  Stream<TaskRecord> get changes => _changes.stream;

  /// Closes the database. The board must not be used afterwards.
  void close() {
    _changes.close();
    _db.dispose();
  }

  // ---------------------------------------------------------------- tasks

  /// Inserts the user's request as a `queued` root task and returns it.
  TaskRecord insertRoot(
    String prompt,
    String cwd, {
    Map<String, String> options = const {},
  }) {
    final id = uuidV4();
    final now = _now();
    _db.execute(
      '''
INSERT INTO tasks (id, parent_id, root_id, kind, title, prompt, cwd, assignee,
  status, attempt, dispatch_token, depends_on, result_path, result_summary,
  created_at, updated_at, options)
VALUES (?, NULL, ?, ?, ?, ?, ?, NULL, ?, 0, NULL, '[]', NULL, NULL, ?, ?, ?)''',
      [
        id,
        id,
        TaskKind.root.name,
        _titleFor(prompt),
        prompt,
        cwd,
        TaskStatus.queued.name,
        now,
        now,
        jsonEncode(options),
      ],
    );
    return requireTask(id);
  }

  /// Inserts the brain's plan under [rootId] as `planned` subtasks in one
  /// transaction. Plan-local ids in `dependsOn` are mapped to the new task
  /// ids; an unknown reference throws [ArgumentError] and inserts nothing.
  List<TaskRecord> insertSubtasks(String rootId, List<PlannedTask> planned) {
    return _tx(() {
      final root = requireTask(rootId);
      final idMap = {for (final t in planned) t.id: uuidV4()};
      if (idMap.length != planned.length) {
        throw ArgumentError('plan contains duplicate task ids');
      }
      final now = _now();
      final inserted = <TaskRecord>[];
      for (final task in planned) {
        final deps = task.dependsOn.map((dep) {
          final mapped = idMap[dep];
          if (mapped == null) {
            throw ArgumentError('task ${task.id} depends on unknown id $dep');
          }
          if (mapped == idMap[task.id]) {
            throw ArgumentError('task ${task.id} depends on itself');
          }
          return mapped;
        }).toList();
        _db.execute(
          '''
INSERT INTO tasks (id, parent_id, root_id, kind, title, prompt, cwd, assignee,
  status, attempt, dispatch_token, depends_on, result_path, result_summary,
  created_at, updated_at, options)
VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, NULL, ?, NULL, NULL, ?, ?, ?)''',
          [
            idMap[task.id],
            root.id,
            root.id,
            TaskKind.subtask.name,
            task.title,
            task.prompt,
            root.cwd,
            task.assignee.name,
            TaskStatus.planned.name,
            jsonEncode(deps),
            now,
            now,
            jsonEncode(root.options),
          ],
        );
        inserted.add(requireTask(idMap[task.id]!));
      }
      return inserted;
    });
  }

  /// The task with [id], or null.
  TaskRecord? getTask(String id) {
    final rows = _db.select('SELECT * FROM tasks WHERE id = ?', [id]);
    return rows.isEmpty ? null : _taskFromRow(rows.first);
  }

  /// The task with [id]; throws [ArgumentError] when it does not exist.
  TaskRecord requireTask(String id) {
    final task = getTask(id);
    if (task == null) throw ArgumentError.value(id, 'id', 'unknown task');
    return task;
  }

  /// Every task of the tree rooted at [rootId], root first, oldest first.
  List<TaskRecord> listByRoot(String rootId) => _select(
    'SELECT * FROM tasks WHERE root_id = ? ORDER BY created_at, rowid',
    [rootId],
  );

  /// The subtasks of [rootId] (everything in the tree but the root).
  List<TaskRecord> listSubtasks(String rootId) =>
      listByRoot(rootId).where((t) => t.kind != TaskKind.root).toList();

  /// Every task (roots and subtasks) that is not in a terminal state.
  List<TaskRecord> listNonTerminal() {
    final terminal = TaskStatus.values
        .where((s) => s.isTerminal)
        .map((s) => "'${s.name}'")
        .join(', ');
    return _select(
      'SELECT * FROM tasks WHERE status NOT IN ($terminal) '
      'ORDER BY created_at, rowid',
    );
  }

  /// Moves [taskId] to [to], validating against [canTransition], and writes
  /// the status change plus one `status` event row in ONE transaction.
  ///
  /// Throws [StateError] on an illegal move and leaves the row untouched.
  TaskRecord transition(String taskId, TaskStatus to, {String? note}) {
    return _tx(() {
      final task = requireTask(taskId);
      if (!canTransition(task.status, to)) {
        throw StateError(
          'illegal transition ${task.status.name} -> ${to.name} '
          'for task $taskId',
        );
      }
      return _transition(task, to, note);
    });
  }

  /// Starts a new attempt: the task becomes `assigned` (if it is not
  /// already), `attempt` is incremented and a fresh `dispatchToken` is
  /// issued. Throws [StateError] when the current status cannot reach
  /// `assigned` (for example while it is still `running`).
  TaskRecord beginDispatch(String taskId) {
    return _tx(() {
      var task = requireTask(taskId);
      if (task.status != TaskStatus.assigned) {
        if (!canTransition(task.status, TaskStatus.assigned)) {
          throw StateError(
            'cannot dispatch task $taskId from ${task.status.name}',
          );
        }
        task = _transition(task, TaskStatus.assigned, 'dispatch');
      }
      final attempt = task.attempt + 1;
      final token = uuidV4();
      _db.execute(
        'UPDATE tasks SET attempt = ?, dispatch_token = ?, updated_at = ? '
        'WHERE id = ?',
        [attempt, token, _now(), taskId],
      );
      _insertEvent(
        taskId: taskId,
        seat: task.assignee?.name,
        kind: 'dispatch',
        summary: 'attempt $attempt started',
        raw: {'attempt': attempt, 'dispatch_token': token},
      );
      return requireTask(taskId);
    });
  }

  /// Whether [token] is the dispatch token of the task's current attempt.
  bool isCurrentDispatch(String taskId, String token) =>
      getTask(taskId)?.dispatchToken == token;

  /// Records the result of the attempt identified by [token] and moves the
  /// task to `review`. Returns false, after writing a `stale_result` event,
  /// when [token] is not the current attempt's token; returns false with an
  /// `ignored_result` event when the task cannot move to `review` from its
  /// current status. Nothing else is written in either case.
  bool completeIfCurrent(
    String taskId,
    String token, {
    String? resultPath,
    String? resultSummary,
    String? note,
  }) {
    return _tx(() {
      final task = requireTask(taskId);
      if (task.dispatchToken != token) {
        _insertEvent(
          taskId: taskId,
          seat: task.assignee?.name,
          kind: 'stale_result',
          summary:
              'result for an old attempt ignored '
              '(current attempt ${task.attempt})',
          raw: {
            'stale_token': token,
            'current_token': task.dispatchToken,
            'result_summary': resultSummary,
          },
        );
        return false;
      }
      if (!canTransition(task.status, TaskStatus.review)) {
        _insertEvent(
          taskId: taskId,
          seat: task.assignee?.name,
          kind: 'ignored_result',
          summary: 'result ignored: task is ${task.status.name}',
          raw: {'result_summary': resultSummary},
        );
        return false;
      }
      _db.execute(
        'UPDATE tasks SET result_path = COALESCE(?, result_path), '
        'result_summary = COALESCE(?, result_summary), updated_at = ? '
        'WHERE id = ?',
        [resultPath, resultSummary, _now(), taskId],
      );
      _transition(requireTask(taskId), TaskStatus.review, note);
      return true;
    });
  }

  /// Boot step: every task that was `assigned`, `running` or waiting when the
  /// previous process died becomes `interrupted`. Returns the affected ids.
  List<String> markRunningAsInterrupted() {
    return _tx(() {
      final live = _select(
        'SELECT * FROM tasks WHERE status IN (?, ?, ?, ?, ?) '
        'ORDER BY created_at, rowid',
        [
          TaskStatus.assigned.name,
          TaskStatus.running.name,
          TaskStatus.waitingApproval.name,
          TaskStatus.waitingUser.name,
          TaskStatus.waitingBudget.name,
        ],
      );
      for (final task in live) {
        _transition(task, TaskStatus.interrupted, 'process restarted');
      }
      return live.map((t) => t.id).toList();
    });
  }

  /// The oldest `queued`, `planned` or `assigned` subtask whose dependencies
  /// are all `done` and whose assignee is in [freeSeats]; null when nothing
  /// can start. [excludeTaskIds] skips tasks the caller is already running;
  /// [rootId] restricts the search to one tree.
  TaskRecord? nextDispatchable({
    required Set<Seat> freeSeats,
    Set<String> excludeTaskIds = const {},
    String? rootId,
  }) {
    if (freeSeats.isEmpty) return null;
    final candidates = _select(
      'SELECT * FROM tasks WHERE kind != ? AND status IN (?, ?, ?) '
      '${rootId == null ? '' : 'AND root_id = ? '}'
      'ORDER BY created_at, rowid',
      [
        TaskKind.root.name,
        TaskStatus.queued.name,
        TaskStatus.planned.name,
        TaskStatus.assigned.name,
        ?rootId,
      ],
    );
    for (final task in candidates) {
      if (excludeTaskIds.contains(task.id)) continue;
      final seat = task.assignee;
      if (seat == null || !freeSeats.contains(seat)) continue;
      if (_dependenciesDone(task)) return task;
    }
    return null;
  }

  bool _dependenciesDone(TaskRecord task) {
    for (final dep in task.dependsOn) {
      if (getTask(dep)?.status != TaskStatus.done) return false;
    }
    return true;
  }

  // ------------------------------------------------------------- sessions

  /// Upserts the vendor session of a task (one session per task).
  void setSession(SessionRecord session) {
    _db.execute(
      '''
INSERT INTO sessions (task_id, seat, session_ref, launch_args, turn_state,
  updated_at)
VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(task_id) DO UPDATE SET seat = excluded.seat,
  session_ref = excluded.session_ref, launch_args = excluded.launch_args,
  turn_state = excluded.turn_state, updated_at = excluded.updated_at''',
      [
        session.taskId,
        session.seat.name,
        session.sessionRef,
        jsonEncode(session.launchArgs),
        session.turnState.name,
        _toIso(session.updatedAt),
      ],
    );
  }

  /// The stored session of [taskId], or null.
  SessionRecord? getSession(String taskId) {
    final rows = _db.select('SELECT * FROM sessions WHERE task_id = ?', [
      taskId,
    ]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return SessionRecord(
      taskId: row['task_id'] as String,
      seat: Seat.parse(row['seat'] as String),
      sessionRef: row['session_ref'] as String,
      launchArgs: (jsonDecode(row['launch_args'] as String) as List)
          .cast<String>(),
      turnState: TurnState.values.byName(row['turn_state'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }

  /// Updates the turn state of the stored session; a no-op without one.
  void setTurnState(String taskId, TurnState state) {
    _db.execute(
      'UPDATE sessions SET turn_state = ?, updated_at = ? WHERE task_id = ?',
      [state.name, _now(), taskId],
    );
  }

  // --------------------------------------------------------------- events

  /// Appends an adapter event and trims the table to [eventRingSize] rows.
  void recordEvent(AgentEvent event) {
    _insertEvent(
      taskId: event.taskId,
      seat: event.seat.name,
      kind: event.kind.name,
      category: event.category?.name,
      summary: event.summary,
      raw: event.raw,
      createdAt: event.timestamp,
    );
  }

  /// Stores a board-level note on [taskId] as an event row of [kind].
  void recordNote(
    String taskId,
    String kind,
    String summary, {
    Map<String, Object?> raw = const {},
  }) {
    _insertEvent(
      taskId: taskId,
      seat: getTask(taskId)?.assignee?.name,
      kind: kind,
      summary: summary,
      raw: raw,
    );
  }

  /// Newest events first, optionally filtered by task and kind.
  List<BoardEvent> listEvents({String? taskId, String? kind, int limit = 100}) {
    final where = <String>[];
    final args = <Object?>[];
    if (taskId != null) {
      where.add('task_id = ?');
      args.add(taskId);
    }
    if (kind != null) {
      where.add('kind = ?');
      args.add(kind);
    }
    final clause = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')} ';
    args.add(limit);
    final rows = _db.select(
      'SELECT * FROM events ${clause}ORDER BY id DESC LIMIT ?',
      args,
    );
    return rows.map(_eventFromRow).toList();
  }

  /// Number of rows currently in `events`.
  int get eventCount =>
      _db.select('SELECT COUNT(*) AS n FROM events').first['n'] as int;

  void _insertEvent({
    required String? taskId,
    required String? seat,
    required String kind,
    required String summary,
    String? category,
    Map<String, Object?> raw = const {},
    DateTime? createdAt,
  }) {
    _db.execute(
      'INSERT INTO events (task_id, seat, kind, category, summary, raw, '
      'created_at) VALUES (?, ?, ?, ?, ?, ?, ?)',
      [
        taskId,
        seat,
        kind,
        category,
        summary,
        _encodeJson(raw),
        createdAt == null ? _now() : _toIso(createdAt),
      ],
    );
    _db.execute(
      'DELETE FROM events WHERE id <= '
      '(SELECT id FROM events ORDER BY id DESC LIMIT 1 OFFSET ?)',
      [eventRingSize],
    );
  }

  // --------------------------------------------------------- interactions

  /// Adds a pending approval or question balloon for [taskId].
  Interaction addInteraction({
    required String taskId,
    required Seat seat,
    required InteractionKind kind,
    Map<String, Object?> payload = const {},
  }) {
    _db.execute(
      'INSERT INTO interactions (task_id, seat, kind, payload, status, '
      "answer, created_at) VALUES (?, ?, ?, ?, 'pending', NULL, ?)",
      [taskId, seat.name, kind.name, _encodeJson(payload), _now()],
    );
    return _interactionById(_db.lastInsertRowId)!;
  }

  /// Marks interaction [id] as answered with [answer].
  Interaction? answerInteraction(int id, String answer) {
    _db.execute(
      "UPDATE interactions SET status = 'answered', answer = ? WHERE id = ?",
      [answer, id],
    );
    return _interactionById(id);
  }

  /// Marks every pending balloon of [taskId] `expired` (the attempt ended
  /// without an answer). Returns how many were closed.
  int expireInteractions(String taskId) {
    _db.execute(
      "UPDATE interactions SET status = 'expired' "
      "WHERE task_id = ? AND status = 'pending'",
      [taskId],
    );
    return _db.updatedRows;
  }

  /// Every balloon still waiting for the user, oldest first.
  List<Interaction> pendingInteractions({String? taskId}) {
    final rows = _db.select(
      "SELECT * FROM interactions WHERE status = 'pending' "
      '${taskId == null ? '' : 'AND task_id = ? '}ORDER BY id',
      [?taskId],
    );
    return rows.map(_interactionFromRow).toList();
  }

  Interaction? _interactionById(int id) {
    final rows = _db.select('SELECT * FROM interactions WHERE id = ?', [id]);
    return rows.isEmpty ? null : _interactionFromRow(rows.first);
  }

  // ----------------------------------------------------------- usage / xp

  /// Upserts the latest usage reading for one seat and window.
  void recordUsage(UsageSnapshot snapshot) {
    _db.execute(
      '''
INSERT INTO usage_snapshots (seat, window, used_pct, resets_at, source,
  fetched_at)
VALUES (?, ?, ?, ?, ?, ?)
ON CONFLICT(seat, window) DO UPDATE SET used_pct = excluded.used_pct,
  resets_at = excluded.resets_at, source = excluded.source,
  fetched_at = excluded.fetched_at''',
      [
        snapshot.seat.name,
        snapshot.window,
        snapshot.usedPct,
        snapshot.resetsAt == null ? null : _toIso(snapshot.resetsAt!),
        snapshot.source,
        _toIso(snapshot.fetchedAt),
      ],
    );
  }

  /// The latest reading per window for [seat].
  List<UsageSnapshot> usageFor(Seat seat) {
    final rows = _db.select(
      'SELECT * FROM usage_snapshots WHERE seat = ? ORDER BY window',
      [seat.name],
    );
    return rows
        .map(
          (row) => UsageSnapshot(
            seat: Seat.parse(row['seat'] as String),
            window: row['window'] as String,
            usedPct: (row['used_pct'] as num).toDouble(),
            resetsAt: row['resets_at'] == null
                ? null
                : DateTime.parse(row['resets_at'] as String),
            source: row['source'] as String,
            fetchedAt: DateTime.parse(row['fetched_at'] as String),
          ),
        )
        .toList();
  }

  /// Adds [points] to [seat]'s XP and returns the new total.
  int addXp(Seat seat, int points) {
    _db.execute(
      '''
INSERT INTO xp (seat, points, updated_at) VALUES (?, ?, ?)
ON CONFLICT(seat) DO UPDATE SET points = points + excluded.points,
  updated_at = excluded.updated_at''',
      [seat.name, points, _now()],
    );
    return xpFor(seat);
  }

  /// Current XP of [seat]; 0 when it never earned any.
  int xpFor(Seat seat) {
    final rows = _db.select('SELECT points FROM xp WHERE seat = ?', [
      seat.name,
    ]);
    return rows.isEmpty ? 0 : rows.first['points'] as int;
  }

  // ------------------------------------------------------------ internals

  TaskRecord _transition(TaskRecord task, TaskStatus to, String? note) {
    _db.execute('UPDATE tasks SET status = ?, updated_at = ? WHERE id = ?', [
      to.name,
      _now(),
      task.id,
    ]);
    _insertEvent(
      taskId: task.id,
      seat: task.assignee?.name,
      kind: 'status',
      summary:
          '${task.status.name} -> ${to.name}'
          '${note == null || note.isEmpty ? '' : ' ($note)'}',
      raw: {'from': task.status.name, 'to': to.name, 'note': note},
    );
    final updated = requireTask(task.id);
    _pendingChanges.add(updated);
    if (!_inTransaction) _flushChanges();
    return updated;
  }

  T _tx<T>(T Function() body) {
    if (_inTransaction) return body();
    _db.execute('BEGIN IMMEDIATE');
    _inTransaction = true;
    try {
      final result = body();
      _db.execute('COMMIT');
      _inTransaction = false;
      _flushChanges();
      return result;
    } catch (_) {
      _inTransaction = false;
      _pendingChanges.clear();
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void _flushChanges() {
    if (_changes.isClosed) {
      _pendingChanges.clear();
      return;
    }
    for (final change in _pendingChanges) {
      _changes.add(change);
    }
    _pendingChanges.clear();
  }

  List<TaskRecord> _select(String sql, [List<Object?> args = const []]) =>
      _db.select(sql, args).map(_taskFromRow).toList();

  TaskRecord _taskFromRow(Row row) {
    final assignee = row['assignee'] as String?;
    return TaskRecord(
      id: row['id'] as String,
      parentId: row['parent_id'] as String?,
      rootId: row['root_id'] as String,
      kind: TaskKind.values.byName(row['kind'] as String),
      title: row['title'] as String,
      prompt: row['prompt'] as String,
      cwd: row['cwd'] as String,
      assignee: assignee == null ? null : Seat.parse(assignee),
      status: TaskStatus.values.byName(row['status'] as String),
      attempt: row['attempt'] as int,
      dispatchToken: row['dispatch_token'] as String?,
      dependsOn: (jsonDecode(row['depends_on'] as String) as List)
          .cast<String>(),
      resultPath: row['result_path'] as String?,
      resultSummary: row['result_summary'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      options: _decodeOptions(row['options']),
    );
  }

  static Map<String, String> _decodeOptions(Object? raw) {
    if (raw is! String || raw.isEmpty) return const {};
    final decoded = _decodeJson(raw);
    return {
      for (final e in decoded.entries)
        if (e.value is String) e.key: e.value as String,
    };
  }

  BoardEvent _eventFromRow(Row row) => BoardEvent(
    id: row['id'] as int,
    taskId: row['task_id'] as String?,
    seat: row['seat'] as String?,
    kind: row['kind'] as String,
    category: row['category'] as String?,
    summary: row['summary'] as String,
    raw: _decodeJson(row['raw'] as String),
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  Interaction _interactionFromRow(Row row) => Interaction(
    id: row['id'] as int,
    taskId: row['task_id'] as String,
    seat: Seat.parse(row['seat'] as String),
    kind: InteractionKind.values.byName(row['kind'] as String),
    payload: _decodeJson(row['payload'] as String),
    pending: row['status'] == 'pending',
    answer: row['answer'] as String?,
    createdAt: DateTime.parse(row['created_at'] as String),
  );

  String _now() => _toIso(_clock());

  static String _toIso(DateTime time) => time.toUtc().toIso8601String();

  static String _titleFor(String prompt) {
    final firstLine = prompt
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => 'Untitled request');
    return firstLine.length <= 80
        ? firstLine
        : '${firstLine.substring(0, 77)}...';
  }

  static String _encodeJson(Map<String, Object?> value) {
    try {
      return jsonEncode(value);
    } on Object {
      return jsonEncode({'unencodable': value.toString()});
    }
  }

  static Map<String, Object?> _decodeJson(String text) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) return decoded.cast<String, Object?>();
    } on FormatException {
      // Fall through: a corrupt row must not break listing.
    }
    return const {};
  }
}
