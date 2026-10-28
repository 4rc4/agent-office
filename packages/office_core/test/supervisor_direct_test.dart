import 'package:office_core/src/board/task_board.dart';
import 'package:office_core/src/model/task.dart';
import 'package:office_core/src/supervisor/supervisor.dart';
import 'package:test/test.dart';

import 'fakes/fake_seat_adapter.dart';

Future<PlanOrError> neverPlan(String text) async =>
    PlanOrError.error('a direct run must not ask for a plan');

Future<String> fakeDiffStat(String cwd) async => ' 1 file changed';

void main() {
  group('runDirect', () {
    test('runs one seat alone and uses its answer as the report', () async {
      final board = TaskBoard.inMemory();
      addTearDown(board.close);
      final gpt = FakeSeatAdapter(
        Seat.gpt,
        scripts: [
          FakeRunScript(
            sessionRef: 'thread-1',
            turns: [ScriptedTurn.success('42 is the answer')],
          ),
        ],
      );
      final claude = FakeSeatAdapter(Seat.claude);
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.claude: claude, Seat.gpt: gpt},
        parsePlan: neverPlan,
        collectDiffStat: fakeDiffStat,
      );
      addTearDown(supervisor.dispose);

      final root = await supervisor.runDirect(
        Seat.gpt,
        'What is 6*7?\nShow your work.',
        '/tmp',
      );

      expect(root.status, TaskStatus.done);
      expect(root.resultSummary, '42 is the answer');
      expect(claude.starts, isEmpty, reason: 'the brain is not involved');
      final worker = board.listSubtasks(root.id).single;
      expect(worker.assignee, Seat.gpt);
      expect(worker.status, TaskStatus.done);
      expect(worker.title, 'What is 6*7?');
      expect(worker.prompt, 'What is 6*7?\nShow your work.');
      expect(board.getSession(worker.id)?.sessionRef, 'thread-1');
    });

    test('fails the root when the seat keeps failing', () async {
      final board = TaskBoard.inMemory();
      addTearDown(board.close);
      final gpt = FakeSeatAdapter(
        Seat.gpt,
        scripts: [
          FakeRunScript(
            sessionRef: 'thread-1',
            turns: [ScriptedTurn.failure('boom')],
          ),
          FakeRunScript(
            sessionRef: 'thread-2',
            turns: [ScriptedTurn.failure('boom again')],
          ),
        ],
      );
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.gpt: gpt},
        parsePlan: neverPlan,
        collectDiffStat: fakeDiffStat,
        maxAttempts: 2,
      );
      addTearDown(supervisor.dispose);

      final root = await supervisor.runDirect(Seat.gpt, 'Explode', '/tmp');

      expect(root.status, TaskStatus.failed);
      expect(gpt.starts, hasLength(2));
      expect(board.listSubtasks(root.id).single.status, TaskStatus.failed);
    });

    test('directTitle keeps the first line, at most 60 characters', () {
      expect(Supervisor.directTitle('  hello\nworld '), 'hello');
      final long = 'x' * 80;
      expect(Supervisor.directTitle(long), '${'x' * 57}...');
    });
  });
}
