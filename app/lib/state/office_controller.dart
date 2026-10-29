import 'dart:async';
import 'dart:io';

import 'package:office_core/office_core.dart';

import 'office_model.dart';
import 'seat_state.dart';

/// Display name of a desk, as the status bar says it.
String seatDisplayName(Seat seat) => switch (seat) {
  Seat.claude => 'Claude',
  Seat.gpt => 'GPT',
  Seat.gemini => 'Gemini',
};

/// Bubble text shown while a seat compacts its context.
const String compactingBubbleText = 'Notları topluyor';

/// Exit code carried by a `processExited` event: `raw['exitCode']` or
/// `raw['exit_code']` when present, else the number in "exited with code N".
/// Null when the event does not say.
int? exitCodeOf(AgentEvent event) {
  final raw = event.raw['exitCode'] ?? event.raw['exit_code'];
  if (raw is int) return raw;
  if (raw is String) return int.tryParse(raw);
  final match = RegExp(r'code\s+(-?\d+)').firstMatch(event.summary);
  return match == null ? null : int.tryParse(match.group(1)!);
}

/// The pose [event] puts its seat in; null keeps the current pose.
///
/// `sessionStarted` only puts the seat in [SeatVisual.arriving]; the
/// controller moves it to a working pose on the next event. `toolFinished`,
/// subagent events and a clean `processExited` (code 0) keep the pose.
SeatVisual? visualForEvent(AgentEvent event) => switch (event.kind) {
  AgentEventKind.sessionStarted => SeatVisual.arriving,
  AgentEventKind.thinking => SeatVisual.thinking,
  AgentEventKind.textDelta => SeatVisual.typing,
  AgentEventKind.toolStarted => switch (event.category) {
    ToolCategory.read => SeatVisual.reading,
    ToolCategory.edit => SeatVisual.editing,
    ToolCategory.shell => SeatVisual.shell,
    ToolCategory.browser => SeatVisual.browsing,
    ToolCategory.mcp || ToolCategory.other || null => SeatVisual.typing,
  },
  AgentEventKind.fileChanged => SeatVisual.editing,
  AgentEventKind.approvalRequested ||
  AgentEventKind.userQuestion => SeatVisual.waitingUser,
  AgentEventKind.rateLimit => SeatVisual.onBreak,
  AgentEventKind.compacting => SeatVisual.reading,
  AgentEventKind.turnCompleted => SeatVisual.celebrating,
  AgentEventKind.turnFailed => SeatVisual.failed,
  AgentEventKind.processExited => switch (exitCodeOf(event)) {
    null || 0 => null,
    _ => SeatVisual.failed,
  },
  AgentEventKind.toolFinished ||
  AgentEventKind.subagentStarted ||
  AgentEventKind.subagentStopped ||
  AgentEventKind.unknown => null,
};

/// The bubble [event] hangs over its seat; null for none.
SeatBubble? bubbleForEvent(AgentEvent event) => switch (event.kind) {
  AgentEventKind.approvalRequested || AgentEventKind.userQuestion => SeatBubble(
    text: _shortLine(event.summary, fallback: '?'),
    kind: BubbleKind.question,
  ),
  AgentEventKind.rateLimit => SeatBubble(
    text: _shortLine(event.summary, fallback: 'Mola'),
    kind: BubbleKind.warning,
  ),
  AgentEventKind.compacting => const SeatBubble(text: compactingBubbleText),
  AgentEventKind.turnCompleted => const SeatBubble(
    text: '✓',
    kind: BubbleKind.success,
  ),
  AgentEventKind.turnFailed => SeatBubble(
    text: _shortLine(event.summary, fallback: 'Hata'),
    kind: BubbleKind.error,
  ),
  AgentEventKind.processExited =>
    visualForEvent(event) == SeatVisual.failed
        ? SeatBubble(
            text: _shortLine(event.summary, fallback: 'Hata'),
            kind: BubbleKind.error,
          )
        : null,
  _ => null,
};

String _shortLine(String text, {required String fallback, int max = 60}) {
  final line = text
      .split(RegExp(r'\r?\n'))
      .map((l) => l.trim())
      .firstWhere((l) => l.isNotEmpty, orElse: () => '');
  if (line.isEmpty) return fallback;
  return line.length <= max ? line : '${line.substring(0, max - 1)}…';
}

enum _Outcome { none, done, failed }

class _PendingIdle {
  _PendingIdle(this.deadline, this.timer);

  final DateTime deadline;
  final Timer timer;
}

/// The live [OfficeModel]: listens to a [Supervisor]'s events and a
/// [TaskBoard]'s changes and publishes one [OfficeSnapshot] per burst.
///
/// Rebuilds are coalesced through a microtask, so a flood of events causes
/// one `notifyListeners`. [settle] applies due celebrate-to-idle timeouts
/// synchronously, which tests use together with an injected [clock].
class OfficeController extends OfficeModel {
  OfficeController({
    required this.supervisor,
    required this.board,
    String? cwd,
    DateTime Function()? clock,
    this.celebrateFor = const Duration(seconds: 3),
    this.maxRecentEvents = 200,
    this.maxRecentTerminal = 10,
    this.onStopAll,
  }) : _cwd = cwd ?? Directory.current.path,
       _clock = clock ?? DateTime.now {
    for (final seat in Seat.values) {
      _seats[seat] = SeatSnapshot(
        seat: seat,
        visual: supervisor.adapters.containsKey(seat)
            ? SeatVisual.idle
            : SeatVisual.empty,
      );
    }
    _snapshot = _build();
    _eventSubscription = supervisor.events.listen(_onEvent);
    _changeSubscription = board.changes.listen(_onTaskChanged);
  }

  final Supervisor supervisor;
  final TaskBoard board;

  /// How long a seat celebrates a finished turn before sitting idle.
  final Duration celebrateFor;

  /// Cap of [OfficeSnapshot.recentEvents].
  final int maxRecentEvents;

  /// How many finished tasks stay on the whiteboard next to the open ones.
  final int maxRecentTerminal;

  /// How many reports the mailbox keeps.
  static const int maxReports = 20;

  /// Stops the office; injected by the runtime (it closes the `Office`).
  /// Without it [stopAll] is a no-op.
  Future<void> Function()? onStopAll;

  final DateTime Function() _clock;
  final Map<Seat, SeatSnapshot> _seats = {};
  final Map<Seat, _PendingIdle> _pendingIdle = {};
  final List<AgentEvent> _recentEvents = [];

  /// Every task record seen through `board.changes`, by id. The board has no
  /// "recent terminal" query, so finished tasks come from here.
  final Map<String, TaskRecord> _seen = {};

  late StreamSubscription<AgentEvent> _eventSubscription;
  late StreamSubscription<TaskRecord> _changeSubscription;
  late OfficeSnapshot _snapshot;
  String _cwd;
  String? _lastReport;
  final List<OfficeReport> _reports = [];
  int _unreadReports = 0;
  String? _errorLine;
  _Outcome _lastOutcome = _Outcome.none;
  Seat? _selectedSeat;
  bool _dirty = false;
  bool _stopped = false;
  bool _disposed = false;

  @override
  OfficeSnapshot get snapshot => _snapshot;

  @override
  String get cwd => _cwd;

  @override
  set cwd(String value) {
    if (value == _cwd) return;
    _cwd = value;
    _markDirty();
  }

  @override
  Seat? get selectedSeat => _selectedSeat;

  @override
  void selectSeat(Seat? seat) {
    if (seat == _selectedSeat) return;
    _selectedSeat = seat;
    if (!_disposed) notifyListeners();
  }

  /// Whether a root task is open on the board right now. False once the
  /// office is stopped or its board closed.
  bool get isBusy {
    if (_stopped) return false;
    try {
      return _hasOpenRoot(board.listNonTerminal());
    } on StateError {
      return false;
    }
  }

  /// Starts a root in [cwd] (default: the controller's [OfficeModel.cwd]).
  /// Several roots may run at once, each in its own folder; a seat that is
  /// taken makes the new subtask wait on the board. A failure to start is
  /// not thrown: it lands in [OfficeSnapshot.statusLine] and marks the seat
  /// that should have started as [SeatVisual.failed]. Returns once the board
  /// holds the new root; the run itself continues in the background.
  @override
  Future<void> submit(String prompt, {Seat? directSeat, String? cwd}) async {
    if (_disposed) throw StateError('office controller is disposed');
    _errorLine = null;
    _lastOutcome = _Outcome.none;
    final folder = cwd ?? _cwd;
    final seat = directSeat ?? supervisor.brainSeat;
    final Future<TaskRecord> run;
    try {
      run = directSeat == null
          ? supervisor.run(prompt, folder)
          : supervisor.runDirect(directSeat, prompt, folder);
    } on Object catch (error) {
      _failToStart(seat, error);
      _flush(force: true);
      return;
    }
    unawaited(
      run.then<void>(
        (_) => _markDirty(),
        onError: (Object error) => _failToStart(seat, error),
      ),
    );
    _flush(force: true);
    await Future<void>.microtask(() {});
  }

  /// Calls [onStopAll] (best effort) and parks every seat. The office is not
  /// usable afterwards until the runtime starts a new one.
  @override
  Future<void> stopAll() async {
    final hook = onStopAll;
    if (hook == null || _stopped) return;
    _stopped = true;
    _cancelAllIdle();
    for (final seat in Seat.values) {
      _seats[seat] = _seats[seat]!.copyWith(
        visual: supervisor.adapters.containsKey(seat)
            ? SeatVisual.idle
            : SeatVisual.empty,
        clearBubble: true,
        clearTask: true,
      );
    }
    _errorLine = null;
    try {
      await hook();
    } on Object catch (error) {
      _errorLine = 'Durdurma hatası: ${_shortLine('$error', fallback: '?')}';
    }
    _flush(force: true);
  }

  @override
  void markReportsRead() {
    if (_unreadReports == 0) return;
    _unreadReports = 0;
    _markDirty();
  }

  /// Puts [message] on the status line until the next [submit].
  void reportError(String message) {
    _errorLine = message;
    _markDirty();
  }

  /// Applies every celebrate-to-idle timeout whose deadline (per the injected
  /// clock) has passed, then rebuilds the snapshot synchronously.
  void settle() {
    final now = _clock();
    for (final seat in _pendingIdle.keys.toList()) {
      final pending = _pendingIdle[seat]!;
      if (pending.deadline.isAfter(now)) continue;
      pending.timer.cancel();
      _applyIdle(seat);
    }
    _flush(force: true);
  }

  @override
  void dispose() {
    _disposed = true;
    _dirty = false;
    _eventSubscription.cancel();
    _changeSubscription.cancel();
    _cancelAllIdle();
    super.dispose();
  }

  // --------------------------------------------------------------- events

  void _onEvent(AgentEvent event) {
    if (_disposed) return;
    _recentEvents.add(event);
    if (_recentEvents.length > maxRecentEvents) {
      _recentEvents.removeRange(0, _recentEvents.length - maxRecentEvents);
    }
    final seat = event.seat;
    final current = _seats[seat]!;
    final mapped = visualForEvent(event);
    final bubble = bubbleForEvent(event);
    final SeatVisual next;
    if (mapped != null) {
      next = mapped;
      _cancelIdle(seat);
    } else if (current.visual == SeatVisual.arriving) {
      // First event after sitting down: at work.
      next = SeatVisual.typing;
    } else {
      next = current.visual;
    }
    final taskId = event.taskId;
    _seats[seat] = current.copyWith(
      visual: next,
      bubble: bubble,
      clearBubble: mapped != null && bubble == null,
      currentTaskId: taskId,
      currentTaskTitle: taskId == null ? null : _titleOf(taskId),
      lastSummary: event.summary.trim().isEmpty ? null : event.summary.trim(),
      tokensIn: current.tokensIn + (event.inputTokens ?? 0),
      tokensOut: current.tokensOut + (event.outputTokens ?? 0),
      sessionRef: event.sessionRef,
    );
    if (next == SeatVisual.celebrating) _scheduleIdle(seat);
    _markDirty();
  }

  void _onTaskChanged(TaskRecord task) {
    if (_disposed) return;
    _seen[task.id] = task;
    _pruneSeen();
    if (task.kind == TaskKind.root &&
        task.status.isTerminal &&
        !_reports.any((r) => r.rootId == task.id)) {
      final done = task.status == TaskStatus.done;
      _lastReport = done ? task.resultSummary : _failureReport(task);
      _lastOutcome = done ? _Outcome.done : _Outcome.failed;
      _reports.insert(
        0,
        OfficeReport(
          rootId: task.id,
          title: task.title,
          cwd: task.cwd,
          text: _lastReport ?? '',
          finishedAt: task.updatedAt,
          failed: !done,
        ),
      );
      if (_reports.length > maxReports) _reports.removeLast();
      _unreadReports++;
    }
    _markDirty();
  }

  void _failToStart(Seat seat, Object error) {
    if (_disposed) return;
    _errorLine = 'Başlatılamadı: ${_shortLine('$error', fallback: 'hata')}';
    _cancelIdle(seat);
    _seats[seat] = _seats[seat]!.copyWith(
      visual: SeatVisual.failed,
      bubble: SeatBubble(
        text: _shortLine('$error', fallback: 'Hata'),
        kind: BubbleKind.error,
      ),
    );
    _markDirty();
  }

  // ------------------------------------------------------------- timeouts

  void _scheduleIdle(Seat seat) {
    _cancelIdle(seat);
    _pendingIdle[seat] = _PendingIdle(
      _clock().add(celebrateFor),
      Timer(celebrateFor, () {
        _applyIdle(seat);
        _markDirty();
      }),
    );
  }

  void _applyIdle(Seat seat) {
    _pendingIdle.remove(seat);
    final current = _seats[seat]!;
    if (current.visual != SeatVisual.celebrating) return;
    final taskId = current.currentTaskId;
    _seats[seat] = current.copyWith(
      visual: SeatVisual.idle,
      clearBubble: true,
      clearTask: taskId == null || _isTerminal(taskId),
    );
  }

  void _cancelIdle(Seat seat) => _pendingIdle.remove(seat)?.timer.cancel();

  void _cancelAllIdle() {
    for (final pending in _pendingIdle.values) {
      pending.timer.cancel();
    }
    _pendingIdle.clear();
  }

  // ------------------------------------------------------------- snapshot

  void _markDirty() {
    if (_dirty || _disposed) return;
    _dirty = true;
    scheduleMicrotask(_flush);
  }

  void _flush({bool force = false}) {
    if (_disposed || !(_dirty || force)) return;
    _dirty = false;
    _snapshot = _build();
    notifyListeners();
  }

  OfficeSnapshot _build() {
    if (_stopped) return _parkedSnapshot();
    try {
      return _liveSnapshot();
    } on StateError {
      // The board was closed under us: show what we have, nothing live.
      return _parkedSnapshot();
    }
  }

  OfficeSnapshot _parkedSnapshot() => OfficeSnapshot(
    seats: [for (final seat in Seat.values) _seats[seat]!],
    recentEvents: List.unmodifiable(_recentEvents),
    lastReport: _lastReport,
    reports: List.unmodifiable(_reports),
    unreadReports: _unreadReports,
    statusLine: _errorLine ?? 'Ofis durduruldu.',
  );

  OfficeSnapshot _liveSnapshot() {
    final seats = <SeatSnapshot>[];
    for (final seat in Seat.values) {
      final refreshed = _seats[seat]!.copyWith(xp: board.xpFor(seat));
      _seats[seat] = refreshed;
      seats.add(refreshed);
    }
    final open = board.listNonTerminal();
    final openIds = {for (final task in open) task.id};
    final finished =
        _seen.values
            .where((t) => t.status.isTerminal && !openIds.contains(t.id))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return OfficeSnapshot(
      seats: seats,
      tasks: [
        for (final task in open) TaskSnapshot.fromRecord(task),
        for (final task in finished.take(maxRecentTerminal))
          TaskSnapshot.fromRecord(task),
      ],
      recentEvents: List.unmodifiable(_recentEvents),
      busy: _hasOpenRoot(open),
      lastReport: _lastReport,
      reports: List.unmodifiable(_reports),
      unreadReports: _unreadReports,
      statusLine: _statusLine(open, seats),
    );
  }

  String _statusLine(List<TaskRecord> open, List<SeatSnapshot> seats) {
    if (seats.any((s) => s.visual == SeatVisual.waitingUser)) {
      return 'Onay bekleniyor';
    }
    if (_errorLine != null) return _errorLine!;
    final roots = open.where((t) => t.kind == TaskKind.root).toList();
    if (roots.isEmpty) {
      return switch (_lastOutcome) {
        _Outcome.none => 'Ofis sessiz.',
        _Outcome.done => 'Rapor hazır',
        _Outcome.failed => 'Görev başarısız',
      };
    }
    final root = roots.last;
    final subtasks = board.listSubtasks(root.id);
    final direct = board
        .listEvents(taskId: root.id, kind: 'direct', limit: 1)
        .isNotEmpty;
    final active = subtasks.where((t) => !t.status.isTerminal).toList();
    if (!direct && subtasks.isEmpty) return 'Claude planlıyor…';
    if (!direct && active.isEmpty) return 'Claude birleştiriyor…';
    if (active.isEmpty) return 'Ofis çalışıyor…';
    final working = active.firstWhere(
      (t) => t.status == TaskStatus.running,
      orElse: () => active.first,
    );
    final who = working.assignee;
    return '${who == null ? 'Ofis' : seatDisplayName(who)} çalışıyor: '
        '${working.title}';
  }

  static bool _hasOpenRoot(List<TaskRecord> open) =>
      open.any((t) => t.kind == TaskKind.root);

  String _failureReport(TaskRecord root) {
    var reason = root.status.name;
    if (!_stopped) {
      final notes = board.listEvents(
        taskId: root.id,
        kind: 'root_failed',
        limit: 1,
      );
      if (notes.isNotEmpty) reason = notes.first.summary;
    }
    return 'Görev başarısız: $reason';
  }

  String? _titleOf(String taskId) {
    final cached = _seen[taskId];
    if (cached != null) return cached.title;
    if (_stopped) return null;
    final record = board.getTask(taskId);
    if (record != null) _seen[taskId] = record;
    return record?.title;
  }

  bool _isTerminal(String taskId) {
    final record = _seen[taskId] ?? (_stopped ? null : board.getTask(taskId));
    return record?.status.isTerminal ?? true;
  }

  /// Keeps the cache bounded: when it grows past 300 records, only the 50
  /// most recently updated finished tasks stay (open ones are always kept).
  void _pruneSeen() {
    if (_seen.length <= 300) return;
    final finished = _seen.values.where((t) => t.status.isTerminal).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    for (final task in finished.skip(50)) {
      _seen.remove(task.id);
    }
  }
}
