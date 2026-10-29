import '../model/agent_event.dart';
import '../model/task.dart';

/// Result of one agent turn (one `codex exec`, or one Claude turn ending in a
/// `result` message).
class AgentResult {
  const AgentResult({
    required this.success,
    this.text,
    this.sessionRef,
    this.inputTokens,
    this.outputTokens,
    this.error,
    this.exitCode,
  });

  final bool success;

  /// Final assistant text (Claude `result.result`, Codex last agent_message).
  final String? text;
  final String? sessionRef;
  final int? inputTokens;
  final int? outputTokens;
  final String? error;
  final int? exitCode;
}

/// A live agent process bound to one task.
abstract class AgentRun {
  Stream<AgentEvent> get events;

  /// Completes when the current turn ends (Claude) or the process exits
  /// (Codex). A long-lived Claude run can be given further turns with [send].
  Future<AgentResult> get turnDone;

  /// Session/thread id as soon as the vendor reports it; null before init.
  String? get sessionRef;

  /// Send another user message on the same conversation (Claude stream-json
  /// input). Codex runs reject this: start a new run with `resumeRef` instead.
  Future<void> send(String userMessage);

  /// Polite stop (close stdin), then hard kill after [grace].
  Future<void> stop({Duration grace = const Duration(seconds: 20)});
}

/// One vendor CLI behind one desk. Implementations only launch the user's
/// own, already-logged-in binary and never read or forward credentials.
abstract class SeatAdapter {
  Seat get seat;

  /// Start a run for [task]. [resumeRef] continues an earlier conversation
  /// (Claude `--resume`, Codex `exec resume`); [initialMessage] is the first
  /// user message of this run.
  Future<AgentRun> start(
    TaskRecord task, {
    required String initialMessage,
    String? resumeRef,
  });
}

/// A task option when it is a non-empty string, else the adapter's default.
String pickOption(String? override, String fallback) =>
    override != null && override.trim().isNotEmpty ? override.trim() : fallback;
