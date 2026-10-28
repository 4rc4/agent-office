import 'dart:convert';
import 'dart:io';

import 'package:office_core/src/board/task_board.dart';
import 'package:office_core/src/model/agent_event.dart';
import 'package:office_core/src/model/session.dart';
import 'package:office_core/src/model/task.dart';
import 'package:office_core/src/supervisor/brain_protocol.dart';
import 'package:office_core/src/supervisor/dispatcher.dart';
import 'package:office_core/src/supervisor/supervisor.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'fakes/fake_seat_adapter.dart';

/// A minimal parser for tests: the first fenced json block, decoded.
Future<PlanOrError> parseFencedPlan(String text) async {
  final match = RegExp(r'```json\s*([\s\S]*?)```').firstMatch(text);
  if (match == null) return const PlanOrError.error('no fenced json block');
  try {
    final map = jsonDecode(match.group(1)!) as Map<String, dynamic>;
    final tasks = (map['tasks'] as List).map((raw) {
      final t = raw as Map<String, dynamic>;
      return PlannedTask(
        id: t['id'] as String,
        title: t['title'] as String,
        assignee: t['assignee'] == 'codex' ? Seat.gpt : Seat.claude,
        prompt: t['prompt'] as String,
        dependsOn: (t['depends_on'] as List? ?? const []).cast<String>(),
      );
    }).toList();
    return PlanOrError.plan(
      ParsedPlan(
        tasks: tasks,
        mergeInstructions: map['merge_instructions'] as String?,
      ),
    );
  } on FormatException catch (error) {
    return PlanOrError.error('bad json: ${error.message}');
  }
}

String fencedPlan(List<Map<String, Object?>> tasks, {String? merge}) =>
    'Plan:\n```json\n${jsonEncode({'tasks': tasks, 'merge_instructions': merge})}\n```\n';

const diffStatText =
    ' lib/settings/settings_screen.dart | 12 ++++++++++--\n'
    ' 1 file changed, 10 insertions(+), 2 deletions(-)\n';

Future<String> fakeDiffStat(String cwd) async => diffStatText;

void main() {
  final cwd = p.join('work', 'repo');
  final fixture = File(
    p.join('test', 'fixtures', 'supervisor_plan_reply.md'),
  ).readAsStringSync();
  late TaskBoard board;

  setUp(() => board = TaskBoard.inMemory());
  tearDown(() => board.close());

  group('Supervisor.run', () {
    test(
      'plans two subtasks, runs them in dependency order, reports back',
      () async {
        const finalReport = '# Report\n\nDark mode toggle added and tested.';
        final artifacts = Directory.systemTemp.createTempSync('office_sup_');
        addTearDown(() => artifacts.deleteSync(recursive: true));
        final workerOrder = <String>[];
        TaskStatus? firstStatusWhenSecondStarted;

        final claude = FakeSeatAdapter(
          Seat.claude,
          scriptFor: (call) {
            if (call.task.kind == TaskKind.root) {
              return FakeRunScript(
                sessionRef: 'sess-brain',
                turns: [
                  ScriptedTurn.success(fixture),
                  ScriptedTurn.success(finalReport),
                ],
              );
            }
            workerOrder.add('claude:${call.task.title}');
            final dependency = board.getTask(call.task.dependsOn.single)!;
            firstStatusWhenSecondStarted = dependency.status;
            return FakeRunScript(
              sessionRef: 'sess-worker',
              turns: [
                ScriptedTurn.success(
                  'Test written',
                  events: [
                    AgentEvent(
                      seat: Seat.claude,
                      kind: AgentEventKind.toolStarted,
                      category: ToolCategory.edit,
                      summary: 'Write test/settings/dark_mode_toggle_test.dart',
                    ),
                  ],
                ),
              ],
            );
          },
        );
        final gpt = FakeSeatAdapter(
          Seat.gpt,
          scriptFor: (call) {
            workerOrder.add('gpt:${call.task.title}');
            return FakeRunScript(
              sessionRef: 'thread-1',
              turns: [
                ScriptedTurn.success(
                  'Toggle implemented',
                  events: [
                    AgentEvent(
                      seat: Seat.gpt,
                      kind: AgentEventKind.toolStarted,
                      category: ToolCategory.shell,
                      summary: 'flutter analyze',
                      raw: const {'type': 'item.started'},
                    ),
                    AgentEvent(
                      seat: Seat.gpt,
                      kind: AgentEventKind.fileChanged,
                      category: ToolCategory.edit,
                      summary: 'lib/settings/settings_screen.dart',
                    ),
                  ],
                ),
              ],
            );
          },
        );
        final supervisor = Supervisor(
          board: board,
          adapters: {Seat.claude: claude, Seat.gpt: gpt},
          parsePlan: parseFencedPlan,
          collectDiffStat: fakeDiffStat,
          artifactsDir: artifacts.path,
        );
        addTearDown(supervisor.dispose);
        final received = <AgentEvent>[];
        supervisor.events.listen(received.add);

        final root = await supervisor.run(
          'Add a dark mode toggle to settings',
          cwd,
        );

        // Root: done with the brain's final text.
        expect(root.status, TaskStatus.done);
        expect(root.resultSummary, finalReport);
        expect(root.attempt, 1);

        // Subtasks: both done, in dependency order.
        final subtasks = board.listSubtasks(root.id);
        expect(subtasks.map((t) => t.title), [
          'Add dark mode toggle',
          'Widget test for toggle',
        ]);
        final (gptTask, claudeTask) = (subtasks[0], subtasks[1]);
        expect(gptTask.assignee, Seat.gpt);
        expect(claudeTask.assignee, Seat.claude);
        expect(claudeTask.dependsOn, [gptTask.id]);
        expect(subtasks.map((t) => t.status), everyElement(TaskStatus.done));
        expect(subtasks.map((t) => t.attempt), everyElement(1));
        expect(gptTask.resultSummary, 'Toggle implemented');
        expect(claudeTask.resultSummary, 'Test written');
        expect(workerOrder, [
          'gpt:Add dark mode toggle',
          'claude:Widget test for toggle',
        ]);
        expect(firstStatusWhenSecondStarted, TaskStatus.done);

        // Brain conversation: first turn wraps the prompt, one results turn.
        final brainStart = claude.starts.first;
        expect(brainStart.task.id, root.id);
        expect(brainStart.resumeRef, isNull);
        expect(brainStart.initialMessage, contains('USER REQUEST'));
        expect(
          brainStart.initialMessage,
          contains('Add a dark mode toggle to settings'),
        );
        final brain = claude.runs.first;
        expect(brain.sent, hasLength(1));
        final results = brain.sent.single;
        expect(results, contains('All subtasks have finished'));
        expect(results, contains('Add dark mode toggle'));
        expect(results, contains('Widget test for toggle'));
        expect(results, contains('Toggle implemented'));
        expect(results, contains('Test written'));
        expect(results, contains('lib/settings/settings_screen.dart'));
        expect(results, contains('check the toggle renders at 360x680'));
        expect(brain.stopped, isTrue);
        expect(gpt.runs.single.stopped, isTrue);

        // Sessions recorded for the brain and the Codex worker.
        final brainSession = board.getSession(root.id)!;
        expect(brainSession.sessionRef, 'sess-brain');
        expect(brainSession.seat, Seat.claude);
        expect(brainSession.turnState, TurnState.idle);
        expect(board.getSession(gptTask.id)!.sessionRef, 'thread-1');

        // Worker events landed on the board and on the stream with task ids.
        final shell = board
            .listEvents(taskId: gptTask.id, kind: 'toolStarted')
            .single;
        expect(shell.category, 'shell');
        expect(shell.raw, {'type': 'item.started'});
        expect(received.map((e) => e.taskId), everyElement(isNotNull));
        expect(
          received.where(
            (e) =>
                e.kind == AgentEventKind.sessionStarted && e.taskId == root.id,
          ),
          hasLength(1),
        );
        expect(
          received
              .where((e) => e.kind == AgentEventKind.fileChanged)
              .single
              .taskId,
          gptTask.id,
        );

        // Plan event, artifacts and XP.
        final plan = board.listEvents(taskId: root.id, kind: 'plan').single;
        expect(
          plan.raw['merge_instructions'],
          contains('check the toggle renders'),
        );
        final artifact = File(gptTask.resultPath!);
        expect(artifact.existsSync(), isTrue);
        expect(artifact.readAsStringSync(), contains(diffStatText.trim()));
        expect(p.isWithin(artifacts.path, artifact.path), isTrue);
        expect(board.xpFor(Seat.gpt), 10);
        expect(board.xpFor(Seat.claude), 10);
        final outcome = supervisor.dispatcher
            .outcomesFor(root.id)
            .firstWhere((o) => o.taskId == gptTask.id);
        expect(outcome.files, ['lib/settings/settings_screen.dart']);
        expect(outcome.succeeded, isTrue);
      },
    );

    test('retries the plan once when the reply cannot be parsed', () async {
      final claude = FakeSeatAdapter(
        Seat.claude,
        scripts: [
          FakeRunScript(
            sessionRef: 'sess-brain',
            turns: [
              ScriptedTurn.success('Let me think about this first.'),
              ScriptedTurn.success(
                fencedPlan([
                  {
                    'id': 't1',
                    'title': 'Only task',
                    'assignee': 'codex',
                    'prompt': 'do it',
                    'depends_on': <String>[],
                  },
                ]),
              ),
              ScriptedTurn.success('final'),
            ],
          ),
        ],
      );
      final gpt = FakeSeatAdapter(
        Seat.gpt,
        scripts: [
          FakeRunScript(
            sessionRef: 'thread-1',
            turns: [ScriptedTurn.success('done')],
          ),
        ],
      );
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.claude: claude, Seat.gpt: gpt},
        parsePlan: parseFencedPlan,
        collectDiffStat: fakeDiffStat,
      );
      addTearDown(supervisor.dispose);

      final root = await supervisor.run('Small change', cwd);

      expect(root.status, TaskStatus.done);
      expect(root.resultSummary, 'final');
      final brain = claude.runs.single;
      expect(brain.sent, hasLength(2));
      expect(brain.sent[0], contains('could not be used as a plan'));
      expect(brain.sent[0], contains('no fenced json block'));
      expect(brain.sent[1], contains('All subtasks have finished'));
      expect(
        board.listEvents(taskId: root.id, kind: 'plan_rejected'),
        hasLength(1),
      );
      expect(board.listSubtasks(root.id).single.status, TaskStatus.done);
    });

    test('fails the root when the plan is rejected twice', () async {
      final claude = FakeSeatAdapter(
        Seat.claude,
        scripts: [
          FakeRunScript(
            sessionRef: 'sess-brain',
            turns: [
              ScriptedTurn.success('nope'),
              ScriptedTurn.success('still nope'),
            ],
          ),
        ],
      );
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.claude: claude, Seat.gpt: FakeSeatAdapter(Seat.gpt)},
        parsePlan: parseFencedPlan,
        collectDiffStat: fakeDiffStat,
      );
      addTearDown(supervisor.dispose);

      final root = await supervisor.run('Vague request', cwd);

      expect(root.status, TaskStatus.failed);
      expect(root.resultSummary, isNull);
      expect(board.listSubtasks(root.id), isEmpty);
      final failure = board
          .listEvents(taskId: root.id, kind: 'root_failed')
          .single;
      expect(failure.summary, contains('plan rejected twice'));
      expect(claude.runs.single.stopped, isTrue);
    });

    test('fails the root when there is no brain adapter', () async {
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.gpt: FakeSeatAdapter(Seat.gpt)},
        parsePlan: parseFencedPlan,
        collectDiffStat: fakeDiffStat,
      );
      addTearDown(supervisor.dispose);
      final root = await supervisor.run('Anything', cwd);
      expect(root.status, TaskStatus.failed);
      expect(
        board.listEvents(taskId: root.id, kind: 'root_failed').single.summary,
        contains('no adapter for brain seat claude'),
      );
    });

    test('retries a failed worker attempt once, fresh', () async {
      final claude = FakeSeatAdapter(
        Seat.claude,
        scripts: [
          FakeRunScript(
            sessionRef: 'sess-brain',
            turns: [
              ScriptedTurn.success(
                fencedPlan([
                  {
                    'id': 't1',
                    'title': 'Flaky',
                    'assignee': 'codex',
                    'prompt': 'do it',
                    'depends_on': <String>[],
                  },
                ]),
              ),
              ScriptedTurn.success('final'),
            ],
          ),
        ],
      );
      final gpt = FakeSeatAdapter(
        Seat.gpt,
        scripts: [
          FakeRunScript(
            sessionRef: 'thread-a',
            turns: [ScriptedTurn.failure('exit 1')],
          ),
          FakeRunScript(
            sessionRef: 'thread-b',
            turns: [ScriptedTurn.success('ok now')],
          ),
        ],
      );
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.claude: claude, Seat.gpt: gpt},
        parsePlan: parseFencedPlan,
        collectDiffStat: fakeDiffStat,
      );
      addTearDown(supervisor.dispose);

      final root = await supervisor.run('Flaky work', cwd);

      expect(root.status, TaskStatus.done);
      final task = board.listSubtasks(root.id).single;
      expect(task.status, TaskStatus.done);
      expect(task.attempt, 2);
      expect(task.resultSummary, 'ok now');
      expect(gpt.starts, hasLength(2));
      expect(gpt.starts[1].resumeRef, isNull);
      expect(gpt.starts[1].initialMessage, 'do it');
      final trail = board
          .listEvents(taskId: task.id, kind: 'status', limit: 50)
          .map((e) => e.summary)
          .toList()
          .reversed
          .toList();
      expect(trail, [
        'planned -> assigned (dispatch)',
        'assigned -> running (attempt 1)',
        'running -> review (attempt 1 failed)',
        'review -> assigned (retry 2/2)',
        'assigned -> running (attempt 2)',
        'running -> review (attempt 2 succeeded)',
        'review -> done (auto-accepted (v1))',
      ]);
      expect(board.getSession(task.id)!.sessionRef, 'thread-b');
    });

    test('gives up after maxAttempts and fails blocked dependants', () async {
      final claude = FakeSeatAdapter(
        Seat.claude,
        scriptFor: (call) => FakeRunScript(
          sessionRef: 'sess',
          turns: call.task.kind == TaskKind.root
              ? [
                  ScriptedTurn.success(
                    fencedPlan([
                      {
                        'id': 't1',
                        'title': 'Broken',
                        'assignee': 'codex',
                        'prompt': 'do it',
                        'depends_on': <String>[],
                      },
                      {
                        'id': 't2',
                        'title': 'Needs t1',
                        'assignee': 'claude',
                        'prompt': 'verify',
                        'depends_on': ['t1'],
                      },
                    ]),
                  ),
                  ScriptedTurn.success('final with failures'),
                ]
              : [ScriptedTurn.success('should never run')],
        ),
      );
      final gpt = FakeSeatAdapter(
        Seat.gpt,
        scriptFor: (_) => FakeRunScript(
          sessionRef: 'thread',
          turns: [ScriptedTurn.failure('exit 1')],
        ),
      );
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.claude: claude, Seat.gpt: gpt},
        parsePlan: parseFencedPlan,
        collectDiffStat: fakeDiffStat,
      );
      addTearDown(supervisor.dispose);

      final root = await supervisor.run('Doomed work', cwd);

      expect(root.status, TaskStatus.done);
      expect(root.resultSummary, 'final with failures');
      final [broken, dependant] = board.listSubtasks(root.id);
      expect(broken.status, TaskStatus.failed);
      expect(broken.attempt, 2);
      expect(broken.resultSummary, 'FAILED: exit 1');
      expect(dependant.status, TaskStatus.failed);
      expect(dependant.attempt, 0);
      expect(
        board.listEvents(taskId: dependant.id, kind: 'status').single.summary,
        contains('blocked'),
      );
      expect(gpt.starts, hasLength(2));
      expect(claude.starts, hasLength(1), reason: 'only the brain ran');
      final results = claude.runs.single.sent.single;
      expect(results, contains('Broken (codex, failed, 2 attempts)'));
      expect(results, contains('FAILED: exit 1'));
      expect(results, contains('Needs t1 (claude, failed, 0 attempts)'));
      expect(board.xpFor(Seat.gpt), 0);
    });
  });

  group('Supervisor.reconcile', () {
    test('re-dispatches interrupted work, resuming stored sessions', () async {
      // The previous process: a root mid-flight with one worker running on a
      // known Codex thread, one running without a session, one not started.
      final root = board.insertRoot('Refactor settings', cwd);
      board.beginDispatch(root.id);
      board.transition(root.id, TaskStatus.running);
      board.setSession(
        SessionRecord(
          taskId: root.id,
          seat: Seat.claude,
          sessionRef: 'sess-old',
          launchArgs: const [],
          turnState: TurnState.idle,
          updatedAt: DateTime.now(),
        ),
      );
      final subtasks = board.insertSubtasks(root.id, const [
        PlannedTask(
          id: 't1',
          title: 'Implement',
          assignee: Seat.gpt,
          prompt: 'do it',
        ),
        PlannedTask(
          id: 't2',
          title: 'Cleanup',
          assignee: Seat.gpt,
          prompt: 'tidy up',
        ),
        PlannedTask(
          id: 't3',
          title: 'Verify',
          assignee: Seat.claude,
          prompt: 'check it',
          dependsOn: ['t1'],
        ),
      ]);
      final [implement, cleanup, verify] = subtasks;
      board.beginDispatch(implement.id);
      board.transition(implement.id, TaskStatus.running);
      board.setSession(
        SessionRecord(
          taskId: implement.id,
          seat: Seat.gpt,
          sessionRef: 'thread-old',
          launchArgs: const [],
          turnState: TurnState.inTurn,
          updatedAt: DateTime.now(),
        ),
      );
      board.beginDispatch(cleanup.id);
      board.transition(cleanup.id, TaskStatus.running);

      // The new process.
      final gpt = FakeSeatAdapter(
        Seat.gpt,
        scripts: [
          FakeRunScript(
            sessionRef: 'thread-old',
            turns: [ScriptedTurn.success('resumed and finished')],
          ),
          FakeRunScript(
            sessionRef: 'thread-new',
            turns: [ScriptedTurn.success('cleaned')],
          ),
        ],
      );
      final claude = FakeSeatAdapter(
        Seat.claude,
        scriptFor: (call) => call.task.kind == TaskKind.root
            ? FakeRunScript(
                sessionRef: 'sess-old',
                turns: [ScriptedTurn.success('# Final after restart')],
              )
            : FakeRunScript(
                sessionRef: 'sess-w',
                turns: [ScriptedTurn.success('verified')],
              ),
      );
      var parserCalls = 0;
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.claude: claude, Seat.gpt: gpt},
        parsePlan: (_) async {
          parserCalls++;
          return const PlanOrError.error('must not be called');
        },
        collectDiffStat: fakeDiffStat,
      );
      addTearDown(supervisor.dispose);

      final future = supervisor.reconcile();
      // Synchronously after the call the board is already consistent.
      expect(board.getTask(root.id)!.status, TaskStatus.assigned);
      expect(board.getTask(implement.id)!.status, TaskStatus.assigned);
      expect(board.getTask(cleanup.id)!.status, TaskStatus.assigned);
      expect(board.getTask(verify.id)!.status, TaskStatus.planned);
      final results = await future;

      expect(results.single.id, root.id);
      expect(results.single.status, TaskStatus.done);
      expect(results.single.resultSummary, '# Final after restart');
      expect(parserCalls, 0, reason: 'subtasks existed, no re-planning');

      // The worker with a session resumed it with the resume message.
      expect(gpt.starts, hasLength(2));
      final resumed = gpt.starts[0];
      expect(resumed.task.id, implement.id);
      expect(resumed.resumeRef, 'thread-old');
      expect(resumed.initialMessage, contains('You were restarted'));
      expect(resumed.initialMessage, contains('Implement'));
      expect(resumed.initialMessage, contains('do it'));
      // The worker without a session started fresh.
      final fresh = gpt.starts[1];
      expect(fresh.task.id, cleanup.id);
      expect(fresh.resumeRef, isNull);
      expect(fresh.initialMessage, 'tidy up');

      // The brain resumed its stored session and got the results directly.
      final brainStart = claude.starts.firstWhere(
        (s) => s.task.kind == TaskKind.root,
      );
      expect(brainStart.resumeRef, 'sess-old');
      expect(brainStart.initialMessage, contains('You were restarted'));
      expect(brainStart.initialMessage, contains('All subtasks have finished'));
      expect(brainStart.initialMessage, contains('resumed and finished'));
      expect(brainStart.initialMessage, isNot(contains('USER REQUEST')));
      expect(claude.runs.first.sent, isEmpty);

      final after = board.listSubtasks(root.id);
      expect(after.map((t) => t.status), everyElement(TaskStatus.done));
      expect(after[0].attempt, 2);
      expect(after[1].attempt, 2);
      expect(after[2].attempt, 1);
      final trail = board
          .listEvents(taskId: implement.id, kind: 'status', limit: 50)
          .map((e) => e.summary)
          .toList()
          .reversed
          .toList();
      expect(trail, [
        'planned -> assigned (dispatch)',
        'assigned -> running',
        'running -> interrupted (process restarted)',
        'interrupted -> assigned (resume session thread-old)',
        'assigned -> running (attempt 2)',
        'running -> review (attempt 2 succeeded)',
        'review -> done (auto-accepted (v1))',
      ]);
      expect(board.getSession(root.id)!.turnState, TurnState.idle);
    });

    test('does nothing when the board has no open work', () async {
      final root = board.insertRoot('Old', cwd);
      board.transition(root.id, TaskStatus.failed);
      final supervisor = Supervisor(
        board: board,
        adapters: {Seat.claude: FakeSeatAdapter(Seat.claude)},
        parsePlan: parseFencedPlan,
        collectDiffStat: fakeDiffStat,
      );
      addTearDown(supervisor.dispose);
      expect(await supervisor.reconcile(), isEmpty);
    });
  });

  group('BrainProtocol', () {
    test('resultsTurn lists every outcome and truncates long diffs', () {
      final longDiff = List.generate(
        BrainProtocol.maxInlineDiffLines + 5,
        (i) => ' file$i.dart | 1 +',
      ).join('\n');
      final text = BrainProtocol.resultsTurn([
        SubtaskOutcome(
          taskId: 'a',
          title: 'First',
          assignee: Seat.gpt,
          status: TaskStatus.done,
          attempts: 1,
          summary: 'ok',
          files: const ['a.dart'],
          diffStatPath: p.join('out', 'a.md'),
          diffStat: longDiff,
        ),
        const SubtaskOutcome(
          taskId: 'b',
          title: 'Second',
          status: TaskStatus.failed,
          attempts: 2,
        ),
      ], mergeInstructions: 'run the tests');
      expect(text, contains('### 1. First (codex, done, 1 attempt)'));
      expect(text, contains('Files: a.dart'));
      expect(text, contains('Diff stat file: ${p.join('out', 'a.md')}'));
      expect(text, contains('... (5 more lines in the file)'));
      expect(text, contains('### 2. Second (unassigned, failed, 2 attempts)'));
      expect(text, contains('Summary: (none)'));
      expect(text, contains('Files: (none reported)'));
      expect(
        text,
        contains('Merge instructions from your plan:\nrun the tests'),
      );
      expect(text, contains('Reply with the report only.'));
    });

    test('parseDiffStatFiles handles renames and summary lines', () {
      expect(
        Dispatcher.parseDiffStatFiles(
          ' lib/a.dart            | 3 ++-\n'
          ' lib/{old => new}.dart | 1 +\n'
          ' 2 files changed, 3 insertions(+), 1 deletion(-)\n',
        ),
        ['lib/a.dart', 'lib/new.dart'],
      );
      expect(Dispatcher.parseDiffStatFiles(''), isEmpty);
    });
  });
}
