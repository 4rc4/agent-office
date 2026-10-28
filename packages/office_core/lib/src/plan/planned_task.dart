import '../model/task.dart';

/// A subtask exactly as the brain planned it, before the board gives it a
/// real task id.
///
/// [id] is the plan-local id the brain chose (`t1`, `t2`, ...) and
/// [dependsOn] refers to those local ids. The board maps both to real task
/// ids when it inserts the plan.
class PlannedTask {
  const PlannedTask({
    required this.id,
    required this.title,
    required this.assignee,
    required this.prompt,
    this.dependsOn = const [],
  });

  /// Plan-local id, unique within one plan.
  final String id;

  /// A few words for the whiteboard.
  final String title;

  /// The desk this task goes to.
  final Seat assignee;

  /// Self-contained instructions for the worker, which never sees the
  /// brain's conversation.
  final String prompt;

  /// Plan-local ids of the tasks that must finish first.
  final List<String> dependsOn;

  /// Every assignee spelling the brain may use, lower-cased, and the seat it
  /// means. `codex`/`gpt` is the OpenAI worker, `claude` the second Claude
  /// seat; the Gemini names are recognised so the error message can say the
  /// seat exists but is not available, rather than "unknown".
  static const Map<String, Seat> assigneeNames = {
    'codex': Seat.gpt,
    'gpt': Seat.gpt,
    'openai': Seat.gpt,
    'claude': Seat.claude,
    'anthropic': Seat.claude,
    'gemini': Seat.gemini,
    'agy': Seat.gemini,
    'antigravity': Seat.gemini,
  };

  /// The seat for an assignee name as the brain wrote it (case and
  /// surrounding whitespace do not matter), or null when it is not a known
  /// name.
  static Seat? parseAssignee(String? name) {
    if (name == null) return null;
    return assigneeNames[name.trim().toLowerCase()];
  }

  /// The canonical name the brain should write for [seat]: `codex`,
  /// `claude` or `gemini`.
  static String assigneeName(Seat seat) => switch (seat) {
    Seat.gpt => 'codex',
    Seat.claude => 'claude',
    Seat.gemini => 'gemini',
  };

  /// The plan JSON shape of this task (`depends_on`, `assignee` as the
  /// canonical name), for board notes and logs.
  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'assignee': assigneeName(assignee),
    'prompt': prompt,
    'depends_on': dependsOn,
  };

  @override
  String toString() =>
      'PlannedTask($id "$title" -> ${assigneeName(assignee)}'
      '${dependsOn.isEmpty ? '' : ', after ${dependsOn.join(', ')}'})';
}
