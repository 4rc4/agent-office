import 'dart:io';

import 'package:office_core/src/board/schema.dart';
import 'package:office_core/src/board/task_board.dart';
import 'package:office_core/src/model/agent_event.dart';
import 'package:office_core/src/model/session.dart';
import 'package:office_core/src/model/task.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

final _uuidPattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// A clock that advances one second per read, so ordering is deterministic.
class _Clock {
  DateTime _now = DateTime.utc(2026, 10, 28, 12);

  DateTime call() => _now = _now.add(const Duration(seconds: 1));
}

void main() {
  late _Clock clock;
  late TaskBoard board;
  final cwd = p.join('work', 'repo');

  setUp(() {
    clock = _Clock();
    board = TaskBoard.inMemory(clock: clock.call);
  });

  tearDown(() => board.close());

  TaskRecord rootWithPlan(List<PlannedTask> plan) {
    final root = board.insertRoot('Do the thing', cwd);
    board.insertSubtasks(root.id, plan);
    return root;
  }

  group('uuidV4', () {
    test('produces well-formed, distinct ids', () {
      final ids = {for (var i = 0; i < 200; i++) uuidV4()};
      expect(ids, hasLength(200));
      for (final id in ids) {
        expect(id, matches(_uuidPattern));
      }
    });
  });

  group('insertRoot', () {
    test('creates a queued root whose rootId is itself', () {
      final root = board.insertRoot('  \nAdd dark mode\nmore detail', cwd);
      expect(root.id, matches(_uuidPattern));
      expect(root.rootId, root.id);
      expect(root.parentId, isNull);
      expect(root.kind, TaskKind.root);
      expect(root.status, TaskStatus.queued);
      expect(root.title, 'Add dark mode');
      expect(root.prompt, '  \nAdd dark mode\nmore detail');
      expect(root.cwd, cwd);
      expect(root.assignee, isNull);
      expect(root.attempt, 0);
      expect(root.dispatchToken, isNull);
      expect(root.dependsOn, isEmpty);
      expect(root.createdAt, root.updatedAt);
      expect(root.createdAt.isUtc, isTrue);
      expect(board.getTask(root.id)!.title, root.title);
    });

    test('truncates long titles to 80 characters', () {
      final root = board.insertRoot('x' * 200, cwd);
      expect(root.title, hasLength(80));
      expect(root.title, endsWith('...'));
    });

    test('getTask returns null and requireTask throws for unknown ids', () {
      expect(board.getTask('nope'), isNull);
      expect(() => board.requireTask('nope'), throwsArgumentError);
    });
  });

  group('insertSubtasks', () {
    test('maps plan-local ids and dependencies to real ids', () {
      final root = board.insertRoot('Do the thing', cwd);
      final subtasks = board.insertSubtasks(root.id, const [
        PlannedTask(
          id: 't1',
          title: 'Implement',
          assignee: Seat.gpt,
          prompt: 'write code',
        ),
        PlannedTask(
          id: 't2',
          title: 'Verify',
          assignee: Seat.claude,
          prompt: 'test it',
          dependsOn: ['t1'],
        ),
      ]);
      expect(subtasks, hasLength(2));
      final (first, second) = (subtasks[0], subtasks[1]);
      expect(first.id, matches(_uuidPattern));
      expect(first.id, isNot('t1'));
      expect(first.status, TaskStatus.planned);
      expect(first.kind, TaskKind.subtask);
      expect(first.assignee, Seat.gpt);
      expect(first.parentId, root.id);
      expect(first.rootId, root.id);
      expect(first.cwd, cwd);
      expect(first.dependsOn, isEmpty);
      expect(second.assignee, Seat.claude);
      expect(second.dependsOn, [first.id]);
      expect(board.listByRoot(root.id).map((t) => t.id), [
        root.id,
        first.id,
        second.id,
      ]);
      expect(board.listSubtasks(root.id).map((t) => t.id), [
        first.id,
        second.id,
      ]);
    });

    test('rejects unknown, duplicate and self dependencies atomically', () {
      final root = board.insertRoot('Do the thing', cwd);
      expect(
        () => board.insertSubtasks(root.id, const [
          PlannedTask(id: 't1', title: 'a', assignee: Seat.gpt, prompt: 'p'),
          PlannedTask(
            id: 't2',
            title: 'b',
            assignee: Seat.gpt,
            prompt: 'p',
            dependsOn: ['missing'],
          ),
        ]),
        throwsArgumentError,
      );
      expect(
        () => board.insertSubtasks(root.id, const [
          PlannedTask(id: 't1', title: 'a', assignee: Seat.gpt, prompt: 'p'),
          PlannedTask(id: 't1', title: 'b', assignee: Seat.gpt, prompt: 'p'),
        ]),
        throwsArgumentError,
      );
      expect(
        () => board.insertSubtasks(root.id, const [
          PlannedTask(
            id: 't1',
            title: 'a',
            assignee: Seat.gpt,
            prompt: 'p',
            dependsOn: ['t1'],
          ),
        ]),
        throwsArgumentError,
      );
      expect(board.listSubtasks(root.id), isEmpty);
      expect(() => board.insertSubtasks('nope', const []), throwsArgumentError);
    });
  });

  group('transition', () {
    test('writes the status change and one status event together', () async {
      final root = board.insertRoot('Do the thing', cwd);
      final changes = <TaskRecord>[];
      board.changes.listen(changes.add);
      final before = board.eventCount;

      final updated = board.transition(
        root.id,
        TaskStatus.planned,
        note: 'plan ok',
      );

      expect(updated.status, TaskStatus.planned);
      expect(updated.updatedAt.isAfter(root.updatedAt), isTrue);
      expect(board.getTask(root.id)!.status, TaskStatus.planned);
      expect(board.eventCount, before + 1);
      final event = board.listEvents(taskId: root.id, limit: 1).single;
      expect(event.kind, 'status');
      expect(event.summary, 'queued -> planned (plan ok)');
      expect(event.raw, {'from': 'queued', 'to': 'planned', 'note': 'plan ok'});
      await Future<void>.delayed(Duration.zero);
      expect(changes.single.status, TaskStatus.planned);
    });

    test('throws StateError on an illegal move and writes nothing', () {
      final root = board.insertRoot('Do the thing', cwd);
      final before = board.eventCount;
      expect(
        () => board.transition(root.id, TaskStatus.done),
        throwsStateError,
      );
      expect(board.getTask(root.id)!.status, TaskStatus.queued);
      expect(board.eventCount, before);
      expect(
        () => board.transition('nope', TaskStatus.done),
        throwsArgumentError,
      );
    });
  });

  group('beginDispatch', () {
    test('assigns, bumps the attempt and issues a fresh token', () {
      rootWithPlan(const [
        PlannedTask(id: 't1', title: 'a', assignee: Seat.gpt, prompt: 'p'),
      ]);
      final task = board.listNonTerminal().last;
      expect(task.status, TaskStatus.planned);

      final first = board.beginDispatch(task.id);
      expect(first.status, TaskStatus.assigned);
      expect(first.attempt, 1);
      expect(first.dispatchToken, matches(_uuidPattern));
      expect(
        board.listEvents(taskId: task.id).map((e) => e.kind),
        containsAll(['dispatch', 'status']),
      );

      // Re-dispatching an assigned task is allowed (retry): new attempt+token.
      final second = board.beginDispatch(task.id);
      expect(second.status, TaskStatus.assigned);
      expect(second.attempt, 2);
      expect(second.dispatchToken, isNot(first.dispatchToken));

      board.transition(task.id, TaskStatus.running);
      expect(() => board.beginDispatch(task.id), throwsStateError);
      expect(board.getTask(task.id)!.attempt, 2);

      board.transition(task.id, TaskStatus.review);
      final rework = board.beginDispatch(task.id);
      expect(rework.status, TaskStatus.assigned);
      expect(rework.attempt, 3);
    });
  });

  group('completeIfCurrent', () {
    late TaskRecord task;

    setUp(() {
      rootWithPlan(const [
        PlannedTask(id: 't1', title: 'a', assignee: Seat.gpt, prompt: 'p'),
      ]);
      task = board.beginDispatch(board.listNonTerminal().last.id);
      board.transition(task.id, TaskStatus.running);
    });

    test('accepts the current token and moves the task to review', () {
      final ok = board.completeIfCurrent(
        task.id,
        task.dispatchToken!,
        resultPath: p.join('out', 'a.md'),
        resultSummary: 'did it',
        note: 'worker finished',
      );
      expect(ok, isTrue);
      expect(board.isCurrentDispatch(task.id, task.dispatchToken!), isTrue);
      final after = board.getTask(task.id)!;
      expect(after.status, TaskStatus.review);
      expect(after.resultPath, p.join('out', 'a.md'));
      expect(after.resultSummary, 'did it');
      expect(
        board.listEvents(taskId: task.id, limit: 1).single.summary,
        'running -> review (worker finished)',
      );
    });

    test('ignores a stale token, logs it and changes nothing', () {
      final ok = board.completeIfCurrent(
        task.id,
        'stale-token',
        resultSummary: 'late result',
      );
      expect(ok, isFalse);
      expect(board.isCurrentDispatch(task.id, 'stale-token'), isFalse);
      final after = board.getTask(task.id)!;
      expect(after.status, TaskStatus.running);
      expect(after.resultSummary, isNull);
      final event = board.listEvents(taskId: task.id, limit: 1).single;
      expect(event.kind, 'stale_result');
      expect(event.raw['stale_token'], 'stale-token');
      expect(event.raw['current_token'], task.dispatchToken);
      expect(event.raw['result_summary'], 'late result');
    });

    test('ignores a result when the task cannot enter review', () {
      board.transition(task.id, TaskStatus.done);
      final ok = board.completeIfCurrent(task.id, task.dispatchToken!);
      expect(ok, isFalse);
      expect(board.getTask(task.id)!.status, TaskStatus.done);
      expect(
        board.listEvents(taskId: task.id, limit: 1).single.kind,
        'ignored_result',
      );
    });
  });

  group('sessions', () {
    test('setSession upserts and getSession round-trips', () {
      final root = board.insertRoot('Do the thing', cwd);
      expect(board.getSession(root.id), isNull);
      final at = DateTime.utc(2026, 10, 28, 9, 30);
      board.setSession(
        SessionRecord(
          taskId: root.id,
          seat: Seat.claude,
          sessionRef: 'sess-1',
          launchArgs: const ['-p', '--output-format', 'stream-json'],
          turnState: TurnState.inTurn,
          updatedAt: at,
        ),
      );
      var session = board.getSession(root.id)!;
      expect(session.seat, Seat.claude);
      expect(session.sessionRef, 'sess-1');
      expect(session.launchArgs, ['-p', '--output-format', 'stream-json']);
      expect(session.turnState, TurnState.inTurn);
      expect(session.updatedAt, at);

      board.setTurnState(root.id, TurnState.idle);
      session = board.getSession(root.id)!;
      expect(session.turnState, TurnState.idle);
      expect(session.updatedAt.isAfter(at), isTrue);

      board.setSession(
        SessionRecord(
          taskId: root.id,
          seat: Seat.claude,
          sessionRef: 'sess-2',
          launchArgs: const [],
          turnState: TurnState.idle,
          updatedAt: at,
        ),
      );
      expect(board.getSession(root.id)!.sessionRef, 'sess-2');
      expect(() => board.setTurnState('nope', TurnState.idle), returnsNormally);
    });
  });

  group('events', () {
    test('recordEvent stores every column and listEvents filters', () {
      final root = board.insertRoot('Do the thing', cwd);
      final stamp = DateTime.utc(2026, 10, 28, 10);
      board.recordEvent(
        AgentEvent(
          seat: Seat.gpt,
          kind: AgentEventKind.toolStarted,
          category: ToolCategory.shell,
          summary: 'Bash: flutter test',
          taskId: root.id,
          raw: const {'type': 'item.started', 'n': 1},
          timestamp: stamp,
        ),
      );
      board.recordEvent(
        AgentEvent(
          seat: Seat.claude,
          kind: AgentEventKind.textDelta,
          summary: 'hello',
        ),
      );
      final forTask = board.listEvents(taskId: root.id, kind: 'toolStarted');
      final event = forTask.single;
      expect(event.seat, 'gpt');
      expect(event.category, 'shell');
      expect(event.summary, 'Bash: flutter test');
      expect(event.raw, {'type': 'item.started', 'n': 1});
      expect(event.createdAt, stamp);
      expect(board.listEvents(kind: 'textDelta').single.taskId, isNull);
      expect(board.listEvents(taskId: root.id, kind: 'textDelta'), isEmpty);
      board.recordNote(root.id, 'plan', 'planned', raw: const {'k': 'v'});
      expect(board.listEvents(taskId: root.id, kind: 'plan').single.raw, {
        'k': 'v',
      });
    });

    test('keeps at most $eventRingSize rows, dropping the oldest', () {
      for (var i = 0; i < eventRingSize + 10; i++) {
        board.recordEvent(
          AgentEvent(
            seat: Seat.gpt,
            kind: AgentEventKind.textDelta,
            summary: 'e$i',
          ),
        );
      }
      expect(board.eventCount, eventRingSize);
      final all = board.listEvents(limit: eventRingSize + 100);
      expect(all, hasLength(eventRingSize));
      expect(all.first.summary, 'e${eventRingSize + 9}');
      expect(all.last.summary, 'e10');
    });
  });

  group('markRunningAsInterrupted', () {
    test('interrupts assigned, running and waiting tasks only', () {
      final root = rootWithPlan(const [
        PlannedTask(id: 'a', title: 'a', assignee: Seat.gpt, prompt: 'p'),
        PlannedTask(id: 'b', title: 'b', assignee: Seat.gpt, prompt: 'p'),
        PlannedTask(id: 'c', title: 'c', assignee: Seat.gpt, prompt: 'p'),
        PlannedTask(id: 'd', title: 'd', assignee: Seat.gpt, prompt: 'p'),
        PlannedTask(id: 'e', title: 'e', assignee: Seat.gpt, prompt: 'p'),
        PlannedTask(id: 'f', title: 'f', assignee: Seat.gpt, prompt: 'p'),
        PlannedTask(id: 'g', title: 'g', assignee: Seat.gpt, prompt: 'p'),
      ]);
      final s = board.listSubtasks(root.id);
      board.beginDispatch(s[0].id); // assigned
      for (final i in [1, 2, 3, 4, 6]) {
        board.beginDispatch(s[i].id);
        board.transition(s[i].id, TaskStatus.running);
      }
      board.transition(s[2].id, TaskStatus.waitingApproval);
      board.transition(s[3].id, TaskStatus.waitingUser);
      board.transition(s[4].id, TaskStatus.waitingBudget);
      board.transition(s[6].id, TaskStatus.done);
      // s[5] stays planned, the root stays queued.

      final ids = board.markRunningAsInterrupted();

      expect(
        ids,
        unorderedEquals([
          for (final i in [0, 1, 2, 3, 4]) s[i].id,
        ]),
      );
      for (final i in [0, 1, 2, 3, 4]) {
        expect(board.getTask(s[i].id)!.status, TaskStatus.interrupted);
      }
      expect(board.getTask(s[5].id)!.status, TaskStatus.planned);
      expect(board.getTask(s[6].id)!.status, TaskStatus.done);
      expect(board.getTask(root.id)!.status, TaskStatus.queued);
      expect(board.markRunningAsInterrupted(), isEmpty);
    });
  });

  group('listNonTerminal', () {
    test('excludes done, failed and needsHuman, oldest first', () {
      final root = rootWithPlan(const [
        PlannedTask(id: 'a', title: 'a', assignee: Seat.gpt, prompt: 'p'),
        PlannedTask(id: 'b', title: 'b', assignee: Seat.gpt, prompt: 'p'),
        PlannedTask(id: 'c', title: 'c', assignee: Seat.gpt, prompt: 'p'),
      ]);
      final s = board.listSubtasks(root.id);
      board.transition(s[0].id, TaskStatus.failed);
      board.beginDispatch(s[1].id);
      board.transition(s[1].id, TaskStatus.running);
      board.transition(s[1].id, TaskStatus.waitingUser);
      board.transition(s[1].id, TaskStatus.needsHuman);
      expect(board.listNonTerminal().map((t) => t.id), [root.id, s[2].id]);
    });
  });

  group('nextDispatchable', () {
    late TaskRecord root;
    late TaskRecord a;
    late TaskRecord b;
    late TaskRecord c;

    setUp(() {
      root = rootWithPlan(const [
        PlannedTask(id: 'a', title: 'A', assignee: Seat.gpt, prompt: 'p'),
        PlannedTask(
          id: 'b',
          title: 'B',
          assignee: Seat.claude,
          prompt: 'p',
          dependsOn: ['a'],
        ),
        PlannedTask(id: 'c', title: 'C', assignee: Seat.gpt, prompt: 'p'),
      ]);
      [a, b, c] = board.listSubtasks(root.id);
    });

    test('picks the oldest ready task for a free seat', () {
      final all = {Seat.gpt, Seat.claude};
      expect(board.nextDispatchable(freeSeats: all)!.id, a.id);
      expect(board.nextDispatchable(freeSeats: const {}), isNull);
      expect(board.nextDispatchable(freeSeats: const {Seat.claude}), isNull);
      expect(
        board.nextDispatchable(freeSeats: all, excludeTaskIds: {a.id})!.id,
        c.id,
      );
      expect(
        board.nextDispatchable(freeSeats: all, excludeTaskIds: {a.id, c.id}),
        isNull,
      );
    });

    test('skips running tasks and unlocks dependants when done', () {
      final all = {Seat.gpt, Seat.claude};
      final dispatched = board.beginDispatch(a.id);
      expect(
        board.nextDispatchable(freeSeats: all)!.id,
        a.id,
        reason: 'assigned-but-idle tasks are still dispatchable',
      );
      board.transition(a.id, TaskStatus.running);
      expect(board.nextDispatchable(freeSeats: all)!.id, c.id);
      board.completeIfCurrent(a.id, dispatched.dispatchToken!);
      expect(board.nextDispatchable(freeSeats: const {Seat.claude}), isNull);
      board.transition(a.id, TaskStatus.done);
      expect(board.nextDispatchable(freeSeats: const {Seat.claude})!.id, b.id);
    });

    test('a failed dependency blocks the dependant for good', () {
      board.transition(a.id, TaskStatus.failed);
      expect(board.nextDispatchable(freeSeats: const {Seat.claude}), isNull);
    });

    test('rootId restricts the search to one tree', () {
      final other = rootWithPlan(const [
        PlannedTask(id: 'x', title: 'X', assignee: Seat.gpt, prompt: 'p'),
      ]);
      final x = board.listSubtasks(other.id).single;
      expect(
        board
            .nextDispatchable(freeSeats: const {Seat.gpt}, rootId: other.id)!
            .id,
        x.id,
      );
      expect(
        board
            .nextDispatchable(freeSeats: const {Seat.gpt}, rootId: root.id)!
            .id,
        a.id,
      );
      expect(board.listByRoot(other.id).map((t) => t.id), [other.id, x.id]);
    });
  });

  group('interactions', () {
    test('adds pending balloons and records answers', () {
      final root = board.insertRoot('Do the thing', cwd);
      final asked = board.addInteraction(
        taskId: root.id,
        seat: Seat.claude,
        kind: InteractionKind.approval,
        payload: const {'tool': 'Bash', 'command': 'rm -rf build'},
      );
      expect(asked.pending, isTrue);
      expect(asked.kind, InteractionKind.approval);
      expect(asked.payload['command'], 'rm -rf build');
      board.addInteraction(
        taskId: root.id,
        seat: Seat.gpt,
        kind: InteractionKind.question,
      );
      expect(board.pendingInteractions(), hasLength(2));
      expect(board.pendingInteractions(taskId: 'other'), isEmpty);

      final answered = board.answerInteraction(asked.id, 'allow')!;
      expect(answered.pending, isFalse);
      expect(answered.answer, 'allow');
      expect(board.pendingInteractions().single.kind, InteractionKind.question);
      expect(board.answerInteraction(999, 'x'), isNull);
    });
  });

  group('usage and xp', () {
    test('recordUsage upserts per seat and window', () {
      final at = DateTime.utc(2026, 10, 28, 11);
      board.recordUsage(
        UsageSnapshot(
          seat: Seat.claude,
          window: '5h',
          usedPct: 42.5,
          resetsAt: at.add(const Duration(hours: 2)),
          source: 'rate_limit_event',
          fetchedAt: at,
        ),
      );
      board.recordUsage(
        UsageSnapshot(
          seat: Seat.claude,
          window: 'weekly',
          usedPct: 10,
          source: 'rate_limit_event',
          fetchedAt: at,
        ),
      );
      board.recordUsage(
        UsageSnapshot(
          seat: Seat.claude,
          window: '5h',
          usedPct: 50,
          source: 'rate_limit_event',
          fetchedAt: at.add(const Duration(minutes: 5)),
        ),
      );
      final usage = board.usageFor(Seat.claude);
      expect(usage.map((u) => u.window), ['5h', 'weekly']);
      expect(usage.first.usedPct, 50);
      expect(usage.first.resetsAt, isNull);
      expect(usage.last.usedPct, 10);
      expect(board.usageFor(Seat.gpt), isEmpty);
    });

    test('addXp accumulates per seat', () {
      expect(board.xpFor(Seat.gpt), 0);
      expect(board.addXp(Seat.gpt, 10), 10);
      expect(board.addXp(Seat.gpt, 5), 15);
      expect(board.xpFor(Seat.gpt), 15);
      expect(board.xpFor(Seat.claude), 0);
    });
  });

  group('open', () {
    test('persists to a file that can be reopened', () {
      final dir = Directory.systemTemp.createTempSync('office_core_board_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final path = p.join(dir.path, 'nested', 'office.db');

      final first = TaskBoard.open(path);
      final root = first.insertRoot('Persist me', cwd);
      first.transition(root.id, TaskStatus.planned);
      first.close();
      expect(File(path).existsSync(), isTrue);

      final second = TaskBoard.open(path);
      addTearDown(second.close);
      final reloaded = second.getTask(root.id)!;
      expect(reloaded.title, 'Persist me');
      expect(reloaded.status, TaskStatus.planned);
      expect(second.listEvents(taskId: root.id), hasLength(1));
    });
  });
}
