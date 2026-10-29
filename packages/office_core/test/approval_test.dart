import 'dart:convert';

import 'package:office_core/src/adapters/claude_adapter.dart';
import 'package:office_core/src/adapters/seat_adapter.dart';
import 'package:office_core/src/board/task_board.dart';
import 'package:office_core/src/model/agent_event.dart';
import 'package:office_core/src/model/task.dart';
import 'package:office_core/src/process/process_runner.dart';
import 'package:office_core/src/supervisor/supervisor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fakes/fake_seat_adapter.dart';

const _request = {
  'type': 'control_request',
  'request_id': 'r1',
  'request': {
    'subtype': 'can_use_tool',
    'tool_name': 'Bash',
    'input': {'command': 'rm -rf build'},
  },
};

TaskRecord task() {
  final now = DateTime.utc(2026, 10, 29, 12);
  return TaskRecord(
    id: 'task-1',
    rootId: 'task-1',
    kind: TaskKind.root,
    title: 'Clean',
    prompt: 'Clean the build folder.',
    cwd: r'C:\work\demo',
    status: TaskStatus.assigned,
    createdAt: now,
    updatedAt: now,
  );
}

Future<PlanOrError> noPlan(String text) async =>
    const PlanOrError.error('unused');

void main() {
  group('ClaudeAdapter permission prompts', () {
    test('every start routes permission prompts to stdio', () {
      final adapter = ClaudeAdapter(
        runner: FakeProcessRunner({}),
        executable: 'claude.cmd',
      );
      final args = adapter.buildArguments(sessionId: 'abc');
      expect(args, containsAllInOrder(['--permission-prompt-tool', 'stdio']));
    });

    test(
      'encodeControlResponse allows with the input and denies with a message',
      () {
        final allow = jsonDecode(
          ClaudeAdapter.encodeControlResponse(
            'r1',
            allow: true,
            input: {'command': 'ls'},
          ),
        );
        expect(allow, {
          'type': 'control_response',
          'response': {
            'subtype': 'success',
            'request_id': 'r1',
            'response': {
              'behavior': 'allow',
              'updatedInput': {'command': 'ls'},
            },
          },
        });
        final deny = jsonDecode(
          ClaudeAdapter.encodeControlResponse(
            'r1',
            allow: false,
            message: 'no',
          ),
        );
        expect(deny['response']['response'], {
          'behavior': 'deny',
          'message': 'no',
        });
      },
    );

    test('answerApproval writes the response for a pending request', () async {
      final runner = FakeProcessRunner({
        'claude.cmd': [
          FakeScript(['', jsonEncode(_request)]),
        ],
      });
      final adapter = ClaudeAdapter(runner: runner, executable: 'claude.cmd');
      final run = await adapter.start(task(), initialMessage: 'go');
      final event = await run.events.firstWhere(
        (e) => e.kind == AgentEventKind.approvalRequested,
      );
      expect(event.raw['request_id'], 'r1');
      await run.answerApproval('r1', allow: true);
      final written = jsonDecode(runner.starts.single.process.stdinLines.last);
      expect(written['response']['request_id'], 'r1');
      expect(written['response']['response']['updatedInput'], {
        'command': 'rm -rf build',
      });
    });
  });

  group('approvals on the board', () {
    final cwd = p.join('work', 'repo');
    late TaskBoard board;

    setUp(() => board = TaskBoard.inMemory());
    tearDown(() => board.close());

    AgentEvent approval() => AgentEvent(
      seat: Seat.gpt,
      kind: AgentEventKind.approvalRequested,
      summary: 'approval: Bash: rm -rf build',
      raw: _request,
    );

    Future<Interaction> pendingOne() async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        final pending = board.pendingInteractions();
        if (pending.isNotEmpty) return pending.single;
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      fail('no pending interaction');
    }

    test(
      'a request becomes a pending interaction and the answer reaches the run',
      () async {
        final gpt = FakeSeatAdapter(
          Seat.gpt,
          scripts: [
            FakeRunScript(
              sessionRef: 'thread-1',
              turns: [
                ScriptedTurn.hang(events: [approval()]),
              ],
            ),
          ],
        );
        final sup = Supervisor(
          board: board,
          adapters: {Seat.claude: FakeSeatAdapter(Seat.claude), Seat.gpt: gpt},
          parsePlan: noPlan,
          collectDiffStat: (_) async => '',
        );
        final rootFuture = sup.runDirect(
          Seat.gpt,
          'Clean the build folder',
          cwd,
        );
        final pending = await pendingOne();
        expect(pending.kind, InteractionKind.approval);
        expect(pending.payload['request_id'], 'r1');
        expect(pending.payload['tool_name'], 'Bash');
        expect(
          board.requireTask(pending.taskId).status,
          TaskStatus.waitingApproval,
        );

        expect(await sup.answerApproval(pending.id, allow: true), isTrue);

        expect(gpt.runs.single.answers, [('r1', true)]);
        expect(board.pendingInteractions(), isEmpty);
        expect(board.requireTask(pending.taskId).status, TaskStatus.running);
        await sup.stopTask(pending.taskId);
        await rootFuture;
      },
    );

    test('a request nobody answered expires when the attempt ends', () async {
      final gpt = FakeSeatAdapter(
        Seat.gpt,
        scripts: [
          FakeRunScript(
            sessionRef: 'thread-1',
            turns: [
              ScriptedTurn(
                result: const AgentResult(success: true, text: 'done'),
                events: [approval()],
              ),
            ],
          ),
        ],
      );
      final sup = Supervisor(
        board: board,
        adapters: {Seat.claude: FakeSeatAdapter(Seat.claude), Seat.gpt: gpt},
        parsePlan: noPlan,
        collectDiffStat: (_) async => '',
      );
      final root = await sup.runDirect(Seat.gpt, 'Clean the build folder', cwd);
      expect(root.status, TaskStatus.done);
      expect(board.pendingInteractions(), isEmpty);
    });

    test('answerApproval returns false for an unknown interaction', () async {
      final sup = Supervisor(
        board: board,
        adapters: {Seat.gpt: FakeSeatAdapter(Seat.gpt)},
        parsePlan: noPlan,
      );
      expect(await sup.answerApproval(99, allow: false), isFalse);
    });
  });
}
