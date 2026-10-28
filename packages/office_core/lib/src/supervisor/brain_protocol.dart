import '../model/task.dart';

/// What one finished (or given-up) subtask looks like to the brain.
class SubtaskOutcome {
  const SubtaskOutcome({
    required this.taskId,
    required this.title,
    required this.status,
    required this.attempts,
    this.assignee,
    this.summary,
    this.files = const [],
    this.diffStatPath,
    this.diffStat,
  });

  final String taskId;
  final String title;
  final Seat? assignee;
  final TaskStatus status;
  final int attempts;

  /// The worker's final text, or `FAILED: ...` for a failed attempt.
  final String? summary;

  /// Paths named by `git diff --stat`, repository-relative.
  final List<String> files;

  /// File holding the result text and the diff stat, when artifacts are kept.
  final String? diffStatPath;

  /// Raw `git diff --stat` output, when it was collected.
  final String? diffStat;

  bool get succeeded => status == TaskStatus.done;
}

/// Builds the brain's user messages as plain English strings.
///
/// The brain is a Claude Code headless run; everything it needs to know about
/// the office protocol travels in these messages, not in tool definitions.
abstract final class BrainProtocol {
  /// Longest diff stat quoted inline in a results turn, in lines.
  static const int maxInlineDiffLines = 40;

  /// The opening message: the user's request wrapped in the planning rules.
  static String firstTurn(TaskRecord rootTask) =>
      '''
You are the brain of Agent Office. You plan work, hand well-defined pieces to
co-workers, then review and merge what comes back. The repository you work in
is: ${rootTask.cwd}

The user asked:

<<<USER REQUEST
${rootTask.prompt.trim()}
USER REQUEST>>>

Plan now; do not implement anything yet. Inspect the repository as much as you
need (read-only), then reply with exactly ONE fenced json block and nothing
after it:

```json
{"tasks":[{"id":"t1","title":"...","assignee":"codex","prompt":"...","depends_on":[]}],"merge_instructions":"..."}
```

Planning rules:
- At most 3 tasks. One task is fine when the request is small.
- "assignee" is "codex" (the GPT worker) or "claude" (a second Claude seat).
- Tasks that touch the same files go to the same assignee; never let two
  workers edit one file.
- Give "codex" only well-specified implementation work with clear acceptance
  criteria. Keep research, design decisions, anything ambiguous and the final
  review for "claude".
- Each "prompt" must be self-contained: which files, what behaviour, how to
  verify. The worker does not see this conversation.
- "depends_on" lists ids of tasks that must be done first; leave it empty
  when tasks are independent.
- "merge_instructions": how you will verify and merge the results at the end
  (tests to run, files to check).
- Short "title": a few words, shown on a whiteboard.
''';

  /// Sent when the plan reply could not be parsed; asks for a clean retry.
  static String retryTurn(String parserError) =>
      '''
Your previous reply could not be used as a plan: $parserError

Reply again with exactly ONE fenced json block, using this exact shape and no
prose outside the block:

```json
{"tasks":[{"id":"t1","title":"...","assignee":"codex","prompt":"...","depends_on":[]}],"merge_instructions":"..."}
```

"assignee" is "codex" or "claude"; at most 3 tasks; "depends_on" holds task
ids from this plan.
''';

  /// Reports every subtask's outcome and asks for merge, verification and the
  /// final markdown report.
  static String resultsTurn(
    List<SubtaskOutcome> outcomes, {
    String? mergeInstructions,
  }) {
    final buffer = StringBuffer()
      ..writeln('All subtasks have finished. Results, in plan order:')
      ..writeln();
    for (var i = 0; i < outcomes.length; i++) {
      _writeOutcome(buffer, i + 1, outcomes[i]);
    }
    if (mergeInstructions != null && mergeInstructions.trim().isNotEmpty) {
      buffer
        ..writeln('Merge instructions from your plan:')
        ..writeln(mergeInstructions.trim())
        ..writeln();
    }
    buffer.writeln('''
Now review the changes in the working tree, merge them if needed, run the
verification you planned, fix small issues yourself, and write the final
report in markdown: what changed, how it was verified, and what is left for
the user (if anything). Mention any subtask that failed and what you did about
it. Reply with the report only.''');
    return buffer.toString();
  }

  /// Sent as the first message after a restart, before the real request.
  static String resumeTurn(String checkpointSummary) =>
      '''
You were restarted: the office process was interrupted and this conversation
is being resumed. Trust nothing you remember about progress. Check the
checkpoint below and `git status` before continuing, and do not redo steps
that are already finished.

Checkpoint:
${checkpointSummary.trim()}

Continue from there.
''';

  static void _writeOutcome(StringBuffer buffer, int index, SubtaskOutcome o) {
    final seat = o.assignee == null ? 'unassigned' : _seatLabel(o.assignee!);
    buffer.writeln(
      '### $index. ${o.title} '
      '($seat, ${o.status.name}, ${o.attempts} attempt'
      '${o.attempts == 1 ? '' : 's'})',
    );
    final summary = o.summary?.trim();
    buffer.writeln(
      'Summary: ${summary == null || summary.isEmpty ? '(none)' : summary}',
    );
    buffer.writeln(
      'Files: ${o.files.isEmpty ? '(none reported)' : o.files.join(', ')}',
    );
    if (o.diffStatPath != null) {
      buffer.writeln('Diff stat file: ${o.diffStatPath}');
    }
    final diff = o.diffStat?.trim();
    if (diff != null && diff.isNotEmpty) {
      final lines = diff.split(RegExp(r'\r?\n'));
      buffer.writeln('```');
      buffer.writeln(lines.take(maxInlineDiffLines).join('\n'));
      if (lines.length > maxInlineDiffLines) {
        buffer.writeln(
          '... (${lines.length - maxInlineDiffLines} more lines in the file)',
        );
      }
      buffer.writeln('```');
    }
    buffer.writeln();
  }

  static String _seatLabel(Seat seat) => switch (seat) {
    Seat.claude => 'claude',
    Seat.gpt => 'codex',
    Seat.gemini => 'antigravity',
  };
}
