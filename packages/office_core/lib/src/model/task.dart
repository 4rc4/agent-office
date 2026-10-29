/// Which desk an agent sits at. One seat = one vendor CLI.
enum Seat {
  claude,
  gpt,
  gemini;

  static Seat parse(String value) => Seat.values.byName(value);
}

enum TaskKind { root, subtask, followUp }

/// Lifecycle of a task row. Terminal states: done, failed, needsHuman.
enum TaskStatus {
  queued,
  planned,
  assigned,
  running,
  waitingApproval,
  waitingUser,
  waitingBudget,
  review,
  interrupted,
  done,
  failed,
  needsHuman;

  bool get isTerminal =>
      this == TaskStatus.done ||
      this == TaskStatus.failed ||
      this == TaskStatus.needsHuman;
}

/// One row of the `tasks` table. Immutable; the board returns fresh copies.
class TaskRecord {
  const TaskRecord({
    required this.id,
    required this.rootId,
    required this.kind,
    required this.title,
    required this.prompt,
    required this.cwd,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.parentId,
    this.assignee,
    this.attempt = 0,
    this.dispatchToken,
    this.dependsOn = const [],
    this.resultPath,
    this.resultSummary,
    this.options = const {},
  });

  final String id;
  final String? parentId;
  final String rootId;
  final TaskKind kind;
  final String title;
  final String prompt;
  final String cwd;
  final Seat? assignee;
  final TaskStatus status;
  final int attempt;
  final String? dispatchToken;
  final List<String> dependsOn;
  final String? resultPath;
  final String? resultSummary;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Per-root run options the adapters read: `model` and `effort`
  /// (empty or missing = the adapter's default). Subtasks inherit them.
  final Map<String, String> options;

  TaskRecord copyWith({
    TaskStatus? status,
    Seat? assignee,
    int? attempt,
    String? dispatchToken,
    String? resultPath,
    String? resultSummary,
    DateTime? updatedAt,
  }) {
    return TaskRecord(
      id: id,
      parentId: parentId,
      rootId: rootId,
      kind: kind,
      title: title,
      prompt: prompt,
      cwd: cwd,
      assignee: assignee ?? this.assignee,
      status: status ?? this.status,
      attempt: attempt ?? this.attempt,
      dispatchToken: dispatchToken ?? this.dispatchToken,
      dependsOn: dependsOn,
      resultPath: resultPath ?? this.resultPath,
      resultSummary: resultSummary ?? this.resultSummary,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      options: options,
    );
  }
}
