import 'dart:io';

import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Session ids inside the fixtures.
const _brainSession = 'a1b2c3d4-0001-4aaa-8bbb-000000000001';
const _codexThread = '0199c8e2-7f3a-7b2c-9d4e-5f6a7b8c9d0e';
const _workerSession = 'b7d1f3c2-5a4e-4c8b-9d2e-1f0a2b3c4d5e';

void main() {
  final fixtures = p.join(Directory.current.path, 'test', 'fixtures');

  late Directory temp;
  setUp(() => temp = Directory.systemTemp.createTempSync('office_integ_'));
  tearDown(() => temp.deleteSync(recursive: true));

  group('Supervisor with real adapters over FakeProcessRunner', () {
    test('plan -> codex -> claude worker -> resumed report', () async {
      final board = TaskBoard.inMemory();
      addTearDown(board.close);
      final runner = FakeProcessRunner({
        'claude': [
          FakeOffice.script(fixtures, FakeOffice.brainPlanFixture),
          FakeOffice.script(fixtures, FakeOffice.claudeWorkerFixture),
          FakeOffice.script(fixtures, FakeOffice.brainReportFixture),
        ],
        'codex': [FakeOffice.script(fixtures, FakeOffice.codexWorkerFixture)],
      });
      final claude = ClaudeAdapter(
        runner: runner,
        executable: 'claude',
        baseEnvironment: {'PATH': 'bin', 'ANTHROPIC_API_KEY': 'must-not-leak'},
      );
      final codex = CodexAdapter(
        runner: runner,
        executable: 'codex',
        outputDirectory: p.join(temp.path, 'results'),
        baseEnvironment: {'PATH': 'bin', 'OPENAI_API_KEY': 'must-not-leak'},
      );
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.claude: claude, Seat.gpt: codex},
        parsePlan: parsePlanText,
        collectDiffStat: FakeOffice.diffStat,
        artifactsDir: p.join(temp.path, 'artifacts'),
      );
      addTearDown(supervisor.dispose);
      final streamed = <AgentEvent>[];
      supervisor.events.listen(streamed.add);
      final cwd = p.join(temp.path, 'repo');

      final root = await supervisor.run('Fix the failing test', cwd);

      // Root: done, with the brain's final report stored on it.
      expect(root.status, TaskStatus.done);
      expect(root.attempt, 1);
      expect(root.resultSummary, startsWith('## Summary'));
      expect(root.resultSummary, contains('## Changed files'));
      expect(board.listNonTerminal(), isEmpty);

      // Subtasks: codex first, claude depending on it, both done.
      final subtasks = board.listSubtasks(root.id);
      expect(subtasks, hasLength(2));
      final (gptTask, claudeTask) = (subtasks[0], subtasks[1]);
      expect(gptTask.title, 'Fix off-by-one');
      expect(gptTask.assignee, Seat.gpt);
      expect(gptTask.dependsOn, isEmpty);
      expect(claudeTask.title, 'Review and extend test');
      expect(claudeTask.assignee, Seat.claude);
      expect(claudeTask.dependsOn, [gptTask.id]);
      expect(subtasks.map((t) => t.status), everyElement(TaskStatus.done));
      expect(subtasks.map((t) => t.attempt), everyElement(1));
      expect(gptTask.resultSummary, startsWith('Fixed the off-by-one'));
      expect(claudeTask.resultSummary, 'pong');
      expect(gptTask.cwd, cwd);

      // Sessions: brain, codex thread and worker session recorded.
      final brainSession = board.getSession(root.id);
      expect(brainSession, isNotNull);
      expect(brainSession!.seat, Seat.claude);
      expect(brainSession.sessionRef, _brainSession);
      expect(brainSession.turnState, TurnState.idle);
      expect(board.getSession(gptTask.id)?.sessionRef, _codexThread);
      expect(board.getSession(gptTask.id)?.seat, Seat.gpt);
      expect(board.getSession(claudeTask.id)?.sessionRef, _workerSession);

      // Events: adapter events and board status trail are on the board.
      expect(board.eventCount, greaterThan(20));
      final kinds = board
          .listEvents(limit: eventRingSize)
          .map((e) => e.kind)
          .toSet();
      expect(
        kinds,
        containsAll([
          AgentEventKind.sessionStarted.name,
          AgentEventKind.toolStarted.name,
          AgentEventKind.toolFinished.name,
          AgentEventKind.fileChanged.name,
          AgentEventKind.turnCompleted.name,
          AgentEventKind.processExited.name,
          'status',
          'dispatch',
          'plan',
        ]),
      );
      expect(board.listEvents(kind: 'stale_result'), isEmpty);
      expect(board.listEvents(kind: 'root_failed'), isEmpty);
      final fileChanges = board.listEvents(
        taskId: gptTask.id,
        kind: AgentEventKind.fileChanged.name,
      );
      expect(
        fileChanges.map((e) => e.summary),
        containsAll(['lib/a.dart', 'lib/b.dart']),
      );
      expect(streamed, isNotEmpty);
      expect(streamed.every((e) => e.taskId != null), isTrue);
      expect(streamed.map((e) => e.taskId).toSet(), {
        root.id,
        gptTask.id,
        claudeTask.id,
      });

      // Processes: plan, codex, claude worker, resumed brain; in that order.
      expect(runner.starts.map((s) => s.executable), [
        'claude',
        'codex',
        'claude',
        'claude',
      ]);
      final plan = runner.starts[0];
      expect(plan.arguments, contains('--session-id'));
      expect(plan.arguments, isNot(contains('--bare')));
      expect(plan.workingDirectory, cwd);
      expect(plan.environment, {'PATH': 'bin'});
      expect(plan.process.stdinLines.single, contains('USER REQUEST'));
      expect(plan.process.stdinLines.single, contains('Fix the failing test'));

      final codexStart = runner.starts[1];
      expect(codexStart.arguments.take(4), ['exec', '--json', '-C', cwd]);
      expect(codexStart.arguments.last, gptTask.prompt);
      expect(codexStart.environment, {'PATH': 'bin'});

      final worker = runner.starts[2];
      expect(worker.process.stdinLines.single, contains(claudeTask.prompt));

      final report = runner.starts[3];
      expect(report.arguments, containsAllInOrder(['--resume', _brainSession]));
      expect(report.environment?['CLAUDE_CODE_RESUME_INTERRUPTED_TURN'], '1');
      final resultsTurn = report.process.stdinLines.single;
      expect(resultsTurn, contains('You were restarted'));
      expect(resultsTurn, contains('All subtasks have finished'));
      expect(resultsTurn, contains('Fix off-by-one'));
      expect(resultsTurn, contains('lib/a.dart'));
      expect(resultsTurn, contains('Run `dart test`'));

      // Artifacts and XP.
      expect(
        File(
          p.join(temp.path, 'artifacts', gptTask.id, 'attempt-1.md'),
        ).existsSync(),
        isTrue,
      );
      expect(gptTask.resultPath, isNotNull);
      expect(board.xpFor(Seat.gpt), 10);
      expect(board.xpFor(Seat.claude), 10);
    });
  });

  group('CLI wiring (--fake)', () {
    test('runCli run --fake drives the loop and exits 0', () async {
      final out = StringBuffer();
      final err = StringBuffer();
      final code = await runCli(
        ['run', 'demo request', '--cwd', temp.path, '--fake'],
        out: out,
        err: err,
      );

      expect(err.toString(), isEmpty);
      expect(code, 0, reason: out.toString());
      final text = out.toString();
      expect(text, contains('FAKE vendors'));
      expect(text, contains('sessionStarted'));
      expect(text, contains('fileChanged/edit: lib/a.dart'));
      expect(text, contains('status root -> done'));
      expect(text, contains('==== Agent Office report ===='));
      expect(text, contains('subtasks: 2'));
      expect(text, contains('## Summary'));
      expect(text, contains('---- end of report ----'));

      final dbPath = p.join(temp.path, '.agent_office', 'office.db');
      expect(File(dbPath).existsSync(), isTrue);
      final board = TaskBoard.open(dbPath);
      addTearDown(board.close);
      expect(board.listNonTerminal(), isEmpty);
      final roots = board
          .listEvents(kind: 'plan', limit: 10)
          .map((e) => e.taskId)
          .toSet();
      expect(roots, hasLength(1));
      final root = board.requireTask(roots.single!);
      expect(root.status, TaskStatus.done);
      expect(root.prompt, 'demo request');
      expect(root.cwd, p.normalize(p.absolute(temp.path)));
      expect(board.listSubtasks(root.id), hasLength(2));
      expect(board.getSession(root.id)?.sessionRef, _brainSession);
    });

    test('reconcile on a finished board reports nothing to do', () async {
      final dbPath = p.join(temp.path, 'state', 'office.db');
      final out = StringBuffer();
      final first = await runCli(
        ['run', 'first', '--cwd', temp.path, '--db', dbPath, '--fake'],
        out: out,
        err: out,
      );
      expect(first, 0, reason: out.toString());

      final again = StringBuffer();
      final code = await runCli(
        ['reconcile', '--db', dbPath, '--fake'],
        out: again,
        err: again,
      );
      expect(code, 0, reason: again.toString());
      expect(again.toString(), contains('nothing to reconcile'));
    });

    test('reconcile resumes an interrupted root from the board', () async {
      final dbPath = p.join(temp.path, 'office.db');
      final board = TaskBoard.open(dbPath);
      final root = board.insertRoot('resume me', temp.path);
      board.beginDispatch(root.id);
      board.transition(root.id, TaskStatus.running, note: 'brain started');
      board.setSession(
        SessionRecord(
          taskId: root.id,
          seat: Seat.claude,
          sessionRef: 'old-brain-session',
          launchArgs: const [],
          turnState: TurnState.inTurn,
          updatedAt: DateTime.now(),
        ),
      );
      board.close();

      final out = StringBuffer();
      final code = await runCli(
        ['reconcile', '--db', dbPath, '--fake'],
        out: out,
        err: out,
      );
      expect(code, 0, reason: out.toString());
      expect(out.toString(), contains('status root -> interrupted'));
      expect(out.toString(), contains('status root -> done'));

      final reopened = TaskBoard.open(dbPath);
      addTearDown(reopened.close);
      expect(reopened.requireTask(root.id).status, TaskStatus.done);
      expect(reopened.listSubtasks(root.id), hasLength(2));
    });

    test('argument parsing', () {
      final run = parseCliArguments([
        'run',
        'hello',
        '--cwd',
        p.join('work', 'repo'),
        '--claude=/opt/claude',
        '--codex',
        r'C:\npm\codex.cmd',
        '--fake',
        '--permission-mode',
        'auto',
      ]);
      expect(run.command, 'run');
      expect(run.prompt, 'hello');
      expect(run.config.paths.cwd, p.normalize(p.absolute('work', 'repo')));
      expect(
        run.config.paths.dbPath,
        p.join(run.config.paths.cwd, '.agent_office', 'office.db'),
      );
      expect(run.config.claudeExecutable, '/opt/claude');
      expect(run.config.codexExecutable, r'C:\npm\codex.cmd');
      expect(run.config.fake, isTrue);
      expect(run.config.permissionMode, 'auto');

      final reconcile = parseCliArguments([
        'reconcile',
        '--db',
        p.join('x', 'office.db'),
      ]);
      expect(reconcile.command, 'reconcile');
      expect(reconcile.prompt, isNull);
      expect(reconcile.config.paths.dbPath, p.absolute('x', 'office.db'));
      expect(reconcile.config.fake, isFalse);

      expect(parseCliArguments(['help']).command, 'help');
      expect(() => parseCliArguments([]), throwsFormatException);
      expect(() => parseCliArguments(['run']), throwsFormatException);
      expect(() => parseCliArguments(['run', '--fake']), throwsFormatException);
      expect(() => parseCliArguments(['dance']), throwsFormatException);
      expect(
        () => parseCliArguments(['run', 'x', '--nope', '1']),
        throwsFormatException,
      );
      expect(
        () => parseCliArguments(['run', 'x', '--db']),
        throwsFormatException,
      );
      expect(
        () => parseCliArguments(['run', 'x', '--fake=1']),
        throwsFormatException,
      );
    });

    test(
      'usage errors and help go to the right sink with exit codes',
      () async {
        final out = StringBuffer();
        final err = StringBuffer();
        expect(await runCli([], out: out, err: err), 1);
        expect(err.toString(), contains('missing command'));
        expect(err.toString(), contains('office_core run'));
        expect(out.toString(), isEmpty);

        final help = StringBuffer();
        expect(await runCli(['help'], out: help, err: err), 0);
        expect(help.toString(), contains('--fake'));
      },
    );

    test(
      'a seat that cannot start fails after two attempts; brain still reports',
      () async {
        final board = TaskBoard.inMemory();
        addTearDown(board.close);
        // No codex script at all: every codex start throws in the runner.
        final runner = FakeProcessRunner({
          'claude': [
            FakeOffice.script(fixtures, FakeOffice.brainPlanFixture),
            FakeOffice.script(fixtures, FakeOffice.brainReportFixture),
          ],
        });
        final supervisor = Supervisor(
          board: board,
          adapters: {
            Seat.claude: ClaudeAdapter(runner: runner, executable: 'claude'),
            Seat.gpt: CodexAdapter(
              runner: runner,
              executable: 'codex',
              baseEnvironment: const {},
            ),
          },
          parsePlan: parsePlanText,
          collectDiffStat: FakeOffice.diffStat,
        );
        addTearDown(supervisor.dispose);

        final root = await supervisor.run('broken seat', temp.path);

        final subtasks = board.listSubtasks(root.id);
        final (gptTask, claudeTask) = (subtasks[0], subtasks[1]);
        expect(gptTask.status, TaskStatus.failed);
        expect(gptTask.attempt, 2);
        expect(
          board.listEvents(taskId: gptTask.id, kind: 'start_failed'),
          hasLength(2),
        );
        expect(claudeTask.status, TaskStatus.failed);
        expect(claudeTask.attempt, 0);
        expect(
          board.listEvents(taskId: claudeTask.id, kind: 'status').first.summary,
          contains('blocked'),
        );
        // The brain still receives the outcomes and writes the report.
        expect(root.status, TaskStatus.done);
        expect(root.resultSummary, startsWith('## Summary'));
        expect(runner.starts, hasLength(2));
        final resultsTurn = runner.starts.last.process.stdinLines.single;
        expect(resultsTurn, contains('failed, 2 attempts'));
        expect(resultsTurn, contains('failed, 0 attempts'));
      },
    );
  });

  test('parsePlanText adapts PlanParser to the supervisor', () async {
    final good = await parsePlanText(
      '```json\n{"tasks":[{"id":"t1","title":"A","assignee":"codex",'
      '"prompt":"do it","depends_on":[]}],"merge_instructions":"run tests"}'
      '\n```',
    );
    expect(good.isError, isFalse);
    expect(good.plan!.tasks.single.assignee, Seat.gpt);
    expect(good.plan!.mergeInstructions, 'run tests');

    final bad = await parsePlanText('no plan here');
    expect(bad.isError, isTrue);
    expect(bad.error, contains('json'));
  });
}
