import 'dart:async';
import 'dart:convert';

import 'package:office_core/src/adapters/seat_adapter.dart';
import 'package:office_core/src/board/task_board.dart';
import 'package:office_core/src/model/task.dart';
import 'package:office_core/src/supervisor/supervisor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fakes/fake_seat_adapter.dart';

Future<PlanOrError> parseFencedPlan(String text) async {
  final match = RegExp(r'```json\s*([\s\S]*?)```').firstMatch(text);
  if (match == null) return const PlanOrError.error('no fenced json block');
  final map = jsonDecode(match.group(1)!) as Map<String, dynamic>;
  final tasks = (map['tasks'] as List).map((raw) {
    final t = raw as Map<String, dynamic>;
    return PlannedTask(
      id: t['id'] as String,
      title: t['title'] as String,
      assignee: t['assignee'] == 'codex' ? Seat.gpt : Seat.claude,
      prompt: t['prompt'] as String,
    );
  }).toList();
  return PlanOrError.plan(ParsedPlan(tasks: tasks, mergeInstructions: null));
}

const _plan =
    'Plan:\n```json\n{"tasks":[{"id":"t1","title":"Fix tests","assignee":"codex","prompt":"Fix the tests."}]}\n```\n';

/// Polls the board until [predicate] holds, or fails after two seconds.
Future<TaskRecord> waitFor(
  TaskBoard board,
  bool Function(TaskRecord) predicate, {
  TaskKind kind = TaskKind.subtask,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (DateTime.now().isBefore(deadline)) {
    for (final task in board.listNonTerminal()) {
      if (task.kind == kind && predicate(task)) return task;
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('no task matched in time');
}

void main() {
  final cwd = p.join('work', 'repo');
  late TaskBoard board;

  setUp(() => board = TaskBoard.inMemory());
  tearDown(() => board.close());

  Supervisor supervisor(FakeSeatAdapter claude, FakeSeatAdapter gpt) =>
      Supervisor(
        board: board,
        adapters: {Seat.claude: claude, Seat.gpt: gpt},
        parsePlan: parseFencedPlan,
        collectDiffStat: (_) async => '',
      );

  test('stopTask fails the subtask without a retry', () async {
    final gpt = FakeSeatAdapter(
      Seat.gpt,
      scripts: const [
        FakeRunScript(sessionRef: 'thread-1', turns: [ScriptedTurn.hang()]),
      ],
    );
    final sup = supervisor(FakeSeatAdapter(Seat.claude), gpt);
    final rootFuture = sup.runDirect(Seat.gpt, 'Fix the tests.', cwd);
    final worker = await waitFor(board, (t) => t.status == TaskStatus.running);

    expect(await sup.stopTask(worker.id), isTrue);

    final root = await rootFuture;
    final stopped = board.requireTask(worker.id);
    expect(stopped.status, TaskStatus.failed);
    expect(stopped.attempt, 1);
    expect(gpt.starts, hasLength(1));
    final notes = board.listEvents(taskId: worker.id, kind: 'status');
    expect(notes.map((e) => e.summary).join('\n'), contains('stopped by user'));
    expect(root.status, TaskStatus.failed);
  });

  test('steerTask restarts the task in its session with the note', () async {
    final gpt = FakeSeatAdapter(
      Seat.gpt,
      scripts: const [
        FakeRunScript(sessionRef: 'thread-1', turns: [ScriptedTurn.hang()]),
        FakeRunScript(
          sessionRef: 'thread-1',
          turns: [ScriptedTurn(result: AgentResult(success: true, text: 'ok'))],
        ),
      ],
    );
    final sup = supervisor(FakeSeatAdapter(Seat.claude), gpt);
    final rootFuture = sup.runDirect(Seat.gpt, 'Fix the tests.', cwd);
    final worker = await waitFor(board, (t) => t.status == TaskStatus.running);

    expect(await sup.steerTask(worker.id, 'Use pnpm, not npm'), isTrue);

    final root = await rootFuture;
    expect(root.status, TaskStatus.done);
    expect(gpt.starts, hasLength(2));
    expect(gpt.starts.last.resumeRef, 'thread-1');
    expect(gpt.starts.last.initialMessage, contains('Use pnpm, not npm'));
    expect(gpt.starts.last.initialMessage, isNot(contains('Fix the tests.')));
  });

  test('a steer does not spend a retry attempt', () async {
    // Steer once (restart 1), then a real failure (restart 2) still gets its
    // retry, which succeeds: three starts with maxAttempts = 2.
    final gpt = FakeSeatAdapter(
      Seat.gpt,
      scripts: const [
        FakeRunScript(sessionRef: 'thread-1', turns: [ScriptedTurn.hang()]),
        FakeRunScript(
          sessionRef: 'thread-1',
          turns: [
            ScriptedTurn(result: AgentResult(success: false, error: 'boom')),
          ],
        ),
        FakeRunScript(
          sessionRef: 'thread-1',
          turns: [ScriptedTurn(result: AgentResult(success: true, text: 'ok'))],
        ),
      ],
    );
    final sup = supervisor(FakeSeatAdapter(Seat.claude), gpt);
    final rootFuture = sup.runDirect(Seat.gpt, 'Fix the tests.', cwd);
    final worker = await waitFor(board, (t) => t.status == TaskStatus.running);
    await sup.steerTask(worker.id, 'Try harder');
    final root = await rootFuture;
    expect(root.status, TaskStatus.done);
    expect(gpt.starts, hasLength(3));
  });

  test(
    'steerTask without a session restarts with the prompt and note',
    () async {
      final gpt = FakeSeatAdapter(
        Seat.gpt,
        scripts: const [
          FakeRunScript(sessionRef: '', turns: [ScriptedTurn.hang()]),
          FakeRunScript(
            sessionRef: 'thread-2',
            turns: [
              ScriptedTurn(result: AgentResult(success: true, text: 'ok')),
            ],
          ),
        ],
      );
      final sup = supervisor(FakeSeatAdapter(Seat.claude), gpt);
      final rootFuture = sup.runDirect(Seat.gpt, 'Fix the tests.', cwd);
      final worker = await waitFor(
        board,
        (t) => t.status == TaskStatus.running,
      );
      await sup.steerTask(worker.id, 'Use pnpm');
      await rootFuture;
      expect(gpt.starts.last.resumeRef, isNull);
      expect(gpt.starts.last.initialMessage, contains('Fix the tests.'));
      expect(gpt.starts.last.initialMessage, contains('Use pnpm'));
    },
  );

  test('steerTask on a planned root reaches the next brain turn', () async {
    final claude = FakeSeatAdapter(
      Seat.claude,
      scripts: const [
        FakeRunScript(
          sessionRef: 'brain',
          turns: [
            ScriptedTurn(result: AgentResult(success: true, text: _plan)),
            ScriptedTurn(
              result: AgentResult(success: true, text: '# Report\n\nDone.'),
            ),
          ],
        ),
      ],
    );
    final gpt = FakeSeatAdapter(
      Seat.gpt,
      scripts: const [
        FakeRunScript(sessionRef: 'thread-1', turns: [ScriptedTurn.hang()]),
      ],
    );
    final sup = supervisor(claude, gpt);
    final rootFuture = sup.run('Make the tests pass', cwd);
    final worker = await waitFor(board, (t) => t.status == TaskStatus.running);
    expect(await sup.steerTask(worker.rootId, 'Also update the docs'), isTrue);
    await sup.stopTask(worker.id);
    final root = await rootFuture;
    expect(root.status, TaskStatus.done);
    final brainRun = claude.runs.single;
    expect(brainRun.sent.single, contains('Also update the docs'));
  });

  test('stopTask on a planned root stops its workers and the brain', () async {
    final claude = FakeSeatAdapter(
      Seat.claude,
      scripts: const [
        FakeRunScript(
          sessionRef: 'brain',
          turns: [
            ScriptedTurn(result: AgentResult(success: true, text: _plan)),
            ScriptedTurn(
              result: AgentResult(success: true, text: 'should not be sent'),
            ),
          ],
        ),
      ],
    );
    final gpt = FakeSeatAdapter(
      Seat.gpt,
      scripts: const [
        FakeRunScript(sessionRef: 'thread-1', turns: [ScriptedTurn.hang()]),
      ],
    );
    final sup = supervisor(claude, gpt);
    final rootFuture = sup.run('Make the tests pass', cwd);
    final worker = await waitFor(board, (t) => t.status == TaskStatus.running);
    expect(await sup.stopTask(worker.rootId), isTrue);
    final root = await rootFuture;
    expect(root.status, TaskStatus.failed);
    expect(board.requireTask(worker.id).status, TaskStatus.failed);
    expect(claude.runs.single.sent, isEmpty);
    final notes = board.listEvents(taskId: root.id, kind: 'root_failed');
    expect(notes.single.summary, contains('stopped by user'));
  });

  test(
    'stopTask and steerTask return false for unknown or finished tasks',
    () async {
      final sup = supervisor(
        FakeSeatAdapter(Seat.claude),
        FakeSeatAdapter(Seat.gpt),
      );
      expect(await sup.stopTask('nope'), isFalse);
      expect(await sup.steerTask('nope', 'x'), isFalse);
    },
  );
}
