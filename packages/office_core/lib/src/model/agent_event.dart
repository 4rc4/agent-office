import 'task.dart';

/// Vendor-neutral event. Adapters translate stream-json / exec JSONL into
/// these; the board stores them and the pixel office animates them.
enum AgentEventKind {
  sessionStarted,
  textDelta,
  thinking,
  toolStarted,
  toolFinished,
  fileChanged,
  approvalRequested,
  userQuestion,
  turnCompleted,
  turnFailed,
  rateLimit,
  compacting,
  subagentStarted,
  subagentStopped,
  processExited,
  unknown,
}

enum ToolCategory { read, edit, shell, browser, mcp, other }

class AgentEvent {
  AgentEvent({
    required this.seat,
    required this.kind,
    required this.summary,
    this.taskId,
    this.category,
    this.sessionRef,
    this.inputTokens,
    this.outputTokens,
    this.raw = const {},
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  final Seat seat;
  final String? taskId;
  final AgentEventKind kind;
  final ToolCategory? category;

  /// One short human line, e.g. `Bash: flutter test` or `edit lib/a.dart`.
  final String summary;
  final String? sessionRef;
  final int? inputTokens;
  final int? outputTokens;

  /// The vendor JSON object this event came from, for forensics.
  final Map<String, Object?> raw;
  final DateTime timestamp;

  @override
  String toString() => '[$seat] ${kind.name}: $summary';
}
