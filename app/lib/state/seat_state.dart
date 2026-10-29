import 'package:office_core/office_core.dart';

/// What a desk looks like right now. The scene maps each value to a sprite
/// pose; the controller derives it from AgentEvents and board changes.
enum SeatVisual {
  /// Nobody at the desk (no adapter configured, or never started).
  empty,

  /// Sitting, monitor off, occasional stretch.
  idle,

  /// Lights dimmed, screen saver; no animation ticker needed.
  sleeping,

  /// Walking in / sitting down (session started).
  arriving,

  /// Cloud over the head.
  thinking,

  /// Typing hands, "..." bubble.
  typing,

  /// Leaning forward, papers shuffle.
  reading,

  /// Pen over the head, sheet flies to the tray.
  editing,

  /// Monitor shows a green terminal.
  shell,

  /// Globe on the monitor.
  browsing,

  /// Standing, hand raised, yellow "?" bubble; waits for the user.
  waitingUser,

  /// At the coffee machine with a clock bubble (rate limit / budget).
  onBreak,

  /// Green check, stretch (turn or task done).
  celebrating,

  /// Red "!" bubble, scratching head.
  failed,
}

/// Speech bubble above a seat.
class SeatBubble {
  const SeatBubble({required this.text, this.kind = BubbleKind.info});

  final String text;
  final BubbleKind kind;
}

enum BubbleKind { info, question, warning, error, success }

/// One desk, as the scene and the side panel see it.
class SeatSnapshot {
  const SeatSnapshot({
    required this.seat,
    required this.visual,
    this.bubble,
    this.currentTaskId,
    this.currentTaskTitle,
    this.lastSummary = '',
    this.xp = 0,
    this.tokensIn = 0,
    this.tokensOut = 0,
    this.sessionRef,
  });

  final Seat seat;
  final SeatVisual visual;
  final SeatBubble? bubble;
  final String? currentTaskId;
  final String? currentTaskTitle;

  /// Last event summary, one line (for the desk tooltip and the panel).
  final String lastSummary;
  final int xp;
  final int tokensIn;
  final int tokensOut;
  final String? sessionRef;

  bool get isAnimated => switch (visual) {
    SeatVisual.empty || SeatVisual.sleeping || SeatVisual.idle => false,
    _ => true,
  };

  SeatSnapshot copyWith({
    SeatVisual? visual,
    SeatBubble? bubble,
    bool clearBubble = false,
    String? currentTaskId,
    String? currentTaskTitle,
    bool clearTask = false,
    String? lastSummary,
    int? xp,
    int? tokensIn,
    int? tokensOut,
    String? sessionRef,
  }) {
    return SeatSnapshot(
      seat: seat,
      visual: visual ?? this.visual,
      bubble: clearBubble ? null : (bubble ?? this.bubble),
      currentTaskId: clearTask ? null : (currentTaskId ?? this.currentTaskId),
      currentTaskTitle: clearTask
          ? null
          : (currentTaskTitle ?? this.currentTaskTitle),
      lastSummary: lastSummary ?? this.lastSummary,
      xp: xp ?? this.xp,
      tokensIn: tokensIn ?? this.tokensIn,
      tokensOut: tokensOut ?? this.tokensOut,
      sessionRef: sessionRef ?? this.sessionRef,
    );
  }
}

/// A sticky note on the whiteboard.
class TaskSnapshot {
  const TaskSnapshot({
    required this.id,
    required this.rootId,
    required this.title,
    required this.status,
    required this.isRoot,
    this.assignee,
    this.attempt = 0,
    this.resultSummary,
    this.cwd = '',
  });

  factory TaskSnapshot.fromRecord(TaskRecord record) => TaskSnapshot(
    id: record.id,
    rootId: record.rootId,
    title: record.title,
    status: record.status,
    isRoot: record.kind == TaskKind.root,
    assignee: record.assignee,
    attempt: record.attempt,
    resultSummary: record.resultSummary,
    cwd: record.cwd,
  );

  final String id;
  final String rootId;
  final String title;
  final TaskStatus status;
  final bool isRoot;
  final Seat? assignee;
  final int attempt;
  final String? resultSummary;

  /// Folder the task's root works in; empty when unknown.
  final String cwd;
}

/// One finished root's report, as the mailbox keeps it.
class OfficeReport {
  const OfficeReport({
    required this.rootId,
    required this.title,
    required this.cwd,
    required this.text,
    required this.finishedAt,
    this.failed = false,
  });

  final String rootId;
  final String title;
  final String cwd;

  /// The report (markdown) or the failure line.
  final String text;
  final DateTime finishedAt;
  final bool failed;
}

/// Everything the scene and the panels render. Immutable; the controller
/// publishes a new one on every change.
class OfficeSnapshot {
  const OfficeSnapshot({
    required this.seats,
    this.tasks = const [],
    this.recentEvents = const [],
    this.busy = false,
    this.lastReport,
    this.reports = const [],
    this.unreadReports = 0,
    this.paused = false,
    this.statusLine = '',
    this.usage = const [],
  });

  /// One entry per [Seat], in Seat.values order.
  final List<SeatSnapshot> seats;
  final List<TaskSnapshot> tasks;

  /// Newest last; capped by the controller (e.g. 200).
  final List<AgentEvent> recentEvents;

  /// A root task is in flight.
  final bool busy;

  /// The last finished root's report (markdown), for the mailbox.
  final String? lastReport;

  /// Every finished root's report the controller still holds, newest first.
  final List<OfficeReport> reports;

  /// How many of [reports] arrived since the mailbox was last opened; the
  /// mailbox flag is up while this is positive.
  final int unreadReports;

  /// New prompts are being held back (tray "Duraklat").
  final bool paused;

  /// One line for the bottom bar ("Claude is planning...", "Office asleep").
  final String statusLine;

  /// Latest rate-limit usage per seat and window, from the CLIs; the TV
  /// shows it.
  final List<UsageSnapshot> usage;

  SeatSnapshot seat(Seat seat) => seats.firstWhere((s) => s.seat == seat);

  bool get anyAnimated => seats.any((s) => s.isAnimated);

  static OfficeSnapshot initial() => OfficeSnapshot(
    seats: [
      for (final seat in Seat.values)
        SeatSnapshot(
          seat: seat,
          visual: seat == Seat.gemini ? SeatVisual.empty : SeatVisual.idle,
        ),
    ],
    statusLine: 'Office is quiet.',
  );
}
