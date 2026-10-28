import 'task.dart';

enum TurnState { idle, inTurn }

/// Where a vendor CLI keeps the conversation for a task, so it can be resumed:
/// Claude `session_id`, Codex `thread_id`, Antigravity `conversation` id.
class SessionRecord {
  const SessionRecord({
    required this.taskId,
    required this.seat,
    required this.sessionRef,
    required this.launchArgs,
    required this.turnState,
    required this.updatedAt,
  });

  final String taskId;
  final Seat seat;
  final String sessionRef;
  final List<String> launchArgs;
  final TurnState turnState;
  final DateTime updatedAt;
}
