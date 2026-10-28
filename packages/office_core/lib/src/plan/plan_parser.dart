import 'dart:convert';

import '../model/task.dart';
import 'planned_task.dart';

/// Outcome of [PlanParser.parse]: either the planned tasks (in plan order)
/// with the optional merge instructions, or one error string that lists
/// every problem found so the brain can fix its plan in a single retry.
class PlanParseResult {
  const PlanParseResult.success(
    List<PlannedTask> this.tasks, {
    this.mergeInstructions,
  }) : error = null;

  const PlanParseResult.failure(String this.error)
    : tasks = null,
      mergeInstructions = null;

  /// The tasks in the order the brain wrote them; null on error.
  final List<PlannedTask>? tasks;

  /// The plan's `merge_instructions`, when the brain gave any.
  final String? mergeInstructions;

  /// Every problem found, joined into one sentence; null on success.
  final String? error;

  bool get isError => error != null;

  @override
  String toString() => isError
      ? 'PlanParseResult.failure($error)'
      : 'PlanParseResult.success(${tasks!.length} task(s))';
}

/// Turns the brain's planning reply into [PlannedTask]s.
///
/// The reply is free text that ends in one fenced ```json block of the shape
///
/// ```json
/// {"tasks":[{"id":"t1","title":"...","assignee":"codex","prompt":"...",
///            "depends_on":[]}],"merge_instructions":"..."}
/// ```
///
/// [parse] takes the LAST fenced json block (the brain sometimes quotes the
/// template first), or the whole text when it is itself a JSON object, and
/// validates it in full: every problem is collected and returned in one
/// error string rather than stopping at the first one.
abstract final class PlanParser {
  /// Default upper bound on the number of tasks in one plan.
  static const int defaultMaxTasks = 3;

  /// Seats a plan may assign work to in v1. Gemini is a manual seat and has
  /// no adapter, so a plan naming it is rejected with a hint.
  static const Set<Seat> defaultAllowedAssignees = {Seat.gpt, Seat.claude};

  /// Longest title derived from a prompt when the brain left `title` out.
  static const int derivedTitleLength = 60;

  static final RegExp _fence = RegExp(
    r'```[ \t]*([A-Za-z0-9_+-]*)[^\n]*\n(.*?)\n[ \t]*```',
    dotAll: true,
  );

  /// Parses [brainText] into a plan of at most [maxTasks] tasks whose
  /// assignees are all in [allowedAssignees]. Never throws.
  static PlanParseResult parse(
    String brainText, {
    int maxTasks = defaultMaxTasks,
    Set<Seat> allowedAssignees = defaultAllowedAssignees,
  }) {
    final json = extractJson(brainText);
    if (json == null) {
      return const PlanParseResult.failure(
        'no ```json block found in the reply (and the reply is not itself a '
        'JSON object); end the reply with exactly one fenced json block',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(json);
    } on FormatException catch (e) {
      return PlanParseResult.failure(
        'the json block is not valid JSON: ${e.message}',
      );
    }
    if (decoded is! Map) {
      return const PlanParseResult.failure(
        'the json block must be an object with a "tasks" array',
      );
    }
    final plan = Map<String, Object?>.from(decoded);
    final problems = <String>[];
    final tasks = _tasks(plan, maxTasks, allowedAssignees, problems);
    if (problems.isNotEmpty) {
      final count = problems.length == 1
          ? '1 problem'
          : '${problems.length} '
                'problems';
      return PlanParseResult.failure('$count: ${problems.join('; ')}');
    }
    return PlanParseResult.success(
      tasks,
      mergeInstructions: _optionalText(
        plan['merge_instructions'] ?? plan['mergeInstructions'],
      ),
    );
  }

  /// The JSON text of the plan inside [text]: the content of the last fenced
  /// block tagged `json`, else the whole text when it is a JSON object, else
  /// the content of the last fenced block of any language that decodes to an
  /// object. Null when none of these exist.
  static String? extractJson(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final fences = _fence.allMatches(normalized).toList();
    for (final match in fences.reversed) {
      if (match.group(1)!.toLowerCase() == 'json') return match.group(2);
    }
    final whole = normalized.trim();
    if (whole.startsWith('{') && whole.endsWith('}') && _isObject(whole)) {
      return whole;
    }
    for (final match in fences.reversed) {
      final body = match.group(2)!;
      if (_isObject(body)) return body;
    }
    return null;
  }

  /// [tasks] ordered so that every task comes after the tasks it depends on,
  /// keeping the plan order among tasks that are ready at the same time.
  ///
  /// Throws [ArgumentError] on an unknown dependency or a cycle; [parse]
  /// already rejects both, so this only fires on hand-built lists.
  static List<PlannedTask> topologicalOrder(List<PlannedTask> tasks) {
    final ids = {for (final task in tasks) task.id};
    for (final task in tasks) {
      for (final dep in task.dependsOn) {
        if (!ids.contains(dep)) {
          throw ArgumentError('task ${task.id} depends on unknown id $dep');
        }
      }
    }
    final placed = <String>{};
    final remaining = List.of(tasks);
    final ordered = <PlannedTask>[];
    while (remaining.isNotEmpty) {
      final index = remaining.indexWhere(
        (task) => task.dependsOn.every(placed.contains),
      );
      if (index < 0) {
        throw ArgumentError(
          'dependency cycle among ${remaining.map((t) => t.id).join(', ')}',
        );
      }
      final next = remaining.removeAt(index);
      placed.add(next.id);
      ordered.add(next);
    }
    return ordered;
  }

  // -------------------------------------------------------------- validate

  static List<PlannedTask> _tasks(
    Map<String, Object?> plan,
    int maxTasks,
    Set<Seat> allowedAssignees,
    List<String> problems,
  ) {
    final raw = plan['tasks'];
    if (raw is! List) {
      problems.add('"tasks" must be a non-empty array');
      return const [];
    }
    if (raw.isEmpty) {
      problems.add('"tasks" is empty; plan at least one task');
      return const [];
    }
    if (raw.length > maxTasks) {
      problems.add('too many tasks: ${raw.length} (at most $maxTasks)');
    }
    final entries = <_Entry>[];
    for (var i = 0; i < raw.length; i++) {
      final item = raw[i];
      if (item is! Map) {
        problems.add('tasks[$i] is not an object');
        continue;
      }
      entries.add(_Entry(i, Map<String, Object?>.from(item)));
    }
    final knownIds = <String>{};
    for (final entry in entries) {
      final id = _nonEmptyText(entry.json['id']);
      entry.id = id;
      if (id == null) {
        problems.add('${entry.label}: id is missing or empty');
      } else if (!knownIds.add(id)) {
        problems.add('${entry.label}: duplicate id "$id"');
      }
    }
    final tasks = <PlannedTask>[];
    final edges = <String, List<String>>{};
    for (final entry in entries) {
      final task = _task(entry, knownIds, allowedAssignees, problems);
      if (task != null) {
        tasks.add(task);
        edges[task.id] = task.dependsOn;
      }
    }
    if (tasks.length == entries.length) {
      for (final cycle in _cycles(edges)) {
        problems.add('dependency cycle: ${cycle.join(' -> ')}');
      }
    }
    return tasks;
  }

  static PlannedTask? _task(
    _Entry entry,
    Set<String> knownIds,
    Set<Seat> allowedAssignees,
    List<String> problems,
  ) {
    final label = entry.label;
    final before = problems.length;
    final json = entry.json;

    final assigneeText = _nonEmptyText(json['assignee']);
    final assignee = PlannedTask.parseAssignee(assigneeText);
    final hint = allowedAssignees
        .map((seat) => '"${PlannedTask.assigneeName(seat)}"')
        .join(' or ');
    if (assigneeText == null) {
      problems.add('$label: assignee is missing; use $hint');
    } else if (assignee == null) {
      problems.add('$label: unknown assignee "$assigneeText"; use $hint');
    } else if (!allowedAssignees.contains(assignee)) {
      problems.add(
        '$label: assignee "$assigneeText" is not available in this office; '
        'use $hint',
      );
    }

    final prompt = _nonEmptyText(json['prompt']);
    if (prompt == null) problems.add('$label: prompt is missing or empty');

    final dependsOn = <String>[];
    final rawDeps = json['depends_on'] ?? json['dependsOn'];
    if (rawDeps != null && rawDeps is! List) {
      problems.add('$label: depends_on must be an array of task ids');
    } else if (rawDeps is List) {
      for (final dep in rawDeps) {
        if (dep is! String || dep.trim().isEmpty) {
          problems.add('$label: depends_on contains a non-id value "$dep"');
        } else if (dep == entry.id) {
          problems.add('$label: depends on itself');
        } else if (!knownIds.contains(dep)) {
          problems.add('$label: depends_on references unknown id "$dep"');
        } else if (!dependsOn.contains(dep)) {
          dependsOn.add(dep);
        }
      }
    }

    final id = entry.id;
    if (problems.length > before || id == null) return null;
    final title = _nonEmptyText(json['title']) ?? _derivedTitle(prompt!);
    return PlannedTask(
      id: id,
      title: title,
      assignee: assignee!,
      prompt: prompt!,
      dependsOn: List.unmodifiable(dependsOn),
    );
  }

  /// Every cycle a depth-first walk over [edges] closes, each as the ids on
  /// the loop with the starting id repeated at the end.
  static List<List<String>> _cycles(Map<String, List<String>> edges) {
    final cycles = <List<String>>[];
    final done = <String>{};
    final stack = <String>[];
    final onStack = <String>{};

    void visit(String id) {
      if (done.contains(id)) return;
      stack.add(id);
      onStack.add(id);
      for (final dep in edges[id] ?? const <String>[]) {
        if (onStack.contains(dep)) {
          cycles.add([...stack.sublist(stack.indexOf(dep)), dep]);
        } else {
          visit(dep);
        }
      }
      stack.removeLast();
      onStack.remove(id);
      done.add(id);
    }

    for (final id in edges.keys) {
      visit(id);
    }
    return cycles;
  }

  // --------------------------------------------------------------- helpers

  static bool _isObject(String text) {
    try {
      return jsonDecode(text) is Map;
    } on FormatException {
      return false;
    }
  }

  static String _derivedTitle(String prompt) {
    final oneLine = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (oneLine.length <= derivedTitleLength) return oneLine;
    final cut = oneLine.substring(0, derivedTitleLength);
    final space = cut.lastIndexOf(' ');
    return '${space > derivedTitleLength ~/ 2 ? cut.substring(0, space) : cut}'
        '...';
  }

  static String? _nonEmptyText(Object? value) {
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static String? _optionalText(Object? value) =>
      value is String && value.trim().isNotEmpty ? value.trim() : null;
}

/// One element of the `tasks` array while it is being validated.
class _Entry {
  _Entry(this.index, this.json);

  final int index;
  final Map<String, Object?> json;
  String? id;

  String get label => id == null ? 'tasks[$index]' : 'tasks[$index] ("$id")';
}
