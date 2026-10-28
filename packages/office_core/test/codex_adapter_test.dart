import 'dart:convert';
import 'dart:io';

import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _executable = r'C:\Users\me\AppData\Roaming\npm\codex.cmd';
const _thread = '0199c8e2-7f3a-7b2c-9d4e-5f6a7b8c9d0e';
const _failedThread = '0199c8e2-aaaa-7b2c-9d4e-5f6a7b8c9d0e';

List<String> fixtureLines(String name) {
  final file = File(p.join('test', 'fixtures', name));
  return const LineSplitter().convert(file.readAsStringSync());
}

/// FakeRunningProcess emits its first stdout line (and all stderr lines) in a
/// microtask scheduled by its constructor, before the adapter can subscribe
/// to its broadcast streams, so that first line is always lost. Scripts here
/// start with a blank line, which the parser ignores, to absorb that.
FakeScript script(List<String> lines, {int exitCode = 0}) =>
    FakeScript(['', ...lines], exitCode: exitCode);

TaskRecord task({String id = 'task-1', String cwd = r'C:\work\demo'}) {
  final now = DateTime.utc(2026, 10, 28, 12);
  return TaskRecord(
    id: id,
    rootId: 'root-1',
    kind: TaskKind.subtask,
    title: 'Fix the failing test',
    prompt: 'Make the test pass.',
    cwd: cwd,
    status: TaskStatus.assigned,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late FakeProcessRunner runner;

  CodexAdapter adapter({
    Map<String, String>? baseEnvironment = const {},
    String? outputDirectory,
    String sandbox = 'workspace-write',
    bool skipGitRepoCheck = true,
    bool resumeFlagsAfterSubcommand = true,
  }) {
    return CodexAdapter(
      runner: runner,
      executable: _executable,
      sandbox: sandbox,
      skipGitRepoCheck: skipGitRepoCheck,
      outputDirectory: outputDirectory,
      resumeFlagsAfterSubcommand: resumeFlagsAfterSubcommand,
      baseEnvironment: baseEnvironment,
    );
  }

  group('arguments and environment', () {
    setUp(() {
      runner = FakeProcessRunner({
        'codex.cmd': [script(fixtureLines('codex_success.jsonl'))],
      });
    });

    test('a new thread passes the exact exec argument list', () async {
      final codex = adapter(
        baseEnvironment: {
          'PATH': r'C:\Windows',
          'OPENAI_API_KEY': 'sk-should-not-leak',
          'CODEX_API_KEY': 'sk-should-not-leak-either',
        },
      );
      final run = await codex.start(
        task(),
        initialMessage: 'Fix the test in lib/a.dart',
      );

      expect(codex.lastArguments, [
        'exec',
        '--json',
        '-C',
        r'C:\work\demo',
        '-s',
        'workspace-write',
        '--skip-git-repo-check',
        'Fix the test in lib/a.dart',
      ]);
      final start = runner.starts.single;
      expect(start.executable, _executable);
      expect(start.arguments, codex.lastArguments);
      expect(start.workingDirectory, r'C:\work\demo');
      expect(start.environment, {'PATH': r'C:\Windows'});
      expect(codex.lastEnvironment, {'PATH': r'C:\Windows'});
      expect(codex.seat, Seat.gpt);
      expect(codex.lastArguments, isNot(contains('--full-auto')));
      expect(codex.lastArguments, isNot(contains('--ask-for-approval')));
      expect((run as CodexRun).requestedSessionRef, isNull);
      await run.turnDone;
    });

    test('a resume passes exec resume <thread_id> then the flags', () async {
      final codex = adapter();
      final run = await codex.start(
        task(),
        initialMessage: 'You were interrupted; check git status and go on.',
        resumeRef: _thread,
      );
      expect(codex.lastArguments, [
        'exec',
        'resume',
        _thread,
        '--json',
        '-s',
        'workspace-write',
        '--skip-git-repo-check',
        'You were interrupted; check git status and go on.',
      ]);
      expect(codex.lastArguments, isNot(contains('-C')));
      expect(runner.starts.single.workingDirectory, r'C:\work\demo');
      expect((run as CodexRun).requestedSessionRef, _thread);
      expect(run.sessionRef, _thread, reason: 'known before thread.started');
      await run.turnDone;
    });

    test('resumeFlagsAfterSubcommand=false puts the flags first', () {
      final codex = adapter(resumeFlagsAfterSubcommand: false);
      expect(
        codex.buildArguments(
          prompt: 'go',
          cwd: r'C:\work\demo',
          taskId: 'task-1',
          resumeRef: _thread,
        ),
        [
          'exec',
          '--json',
          '-s',
          'workspace-write',
          '--skip-git-repo-check',
          'resume',
          _thread,
          'go',
        ],
      );
    });

    test('outputDirectory adds -o <dir>/<task.id>.md joined for the OS', () {
      final dir = p.join('C:', 'office', 'results');
      final codex = adapter(outputDirectory: dir);
      final file = p.join(dir, 'task-1.md');
      expect(codex.outputFileFor('task-1'), file);
      expect(codex.buildArguments(prompt: 'go', cwd: 'x', taskId: 'task-1'), [
        'exec',
        '--json',
        '-C',
        'x',
        '-s',
        'workspace-write',
        '--skip-git-repo-check',
        '-o',
        file,
        'go',
      ]);
      expect(
        codex.buildArguments(
          prompt: 'go',
          cwd: 'x',
          taskId: 'task-1',
          resumeRef: _thread,
        ),
        [
          'exec',
          'resume',
          _thread,
          '--json',
          '-s',
          'workspace-write',
          '--skip-git-repo-check',
          '-o',
          file,
          'go',
        ],
      );
      expect(adapter().outputFileFor('task-1'), isNull);
    });

    test('task ids are made safe for file names', () {
      final codex = adapter(outputDirectory: 'out');
      expect(codex.outputFileFor('a/b:c d'), p.join('out', 'a_b_c_d.md'));
    });

    test('sandbox and skipGitRepoCheck are honoured', () {
      final codex = adapter(sandbox: 'read-only', skipGitRepoCheck: false);
      expect(codex.buildArguments(prompt: 'p', cwd: 'c', taskId: 't'), [
        'exec',
        '--json',
        '-C',
        'c',
        '-s',
        'read-only',
        'p',
      ]);
    });

    test('environment scrubbing ignores case, as Windows does', () {
      final codex = adapter(
        baseEnvironment: {
          'openai_api_key': 'x',
          'Codex_Api_Key': 'y',
          'Path': 'z',
        },
      );
      expect(codex.buildEnvironment(), {'Path': 'z'});
    });

    test('without a base environment the process environment is used', () {
      final codex = adapter(baseEnvironment: null);
      final environment = codex.buildEnvironment();
      for (final key in environment.keys) {
        expect(
          CodexAdapter.scrubbedEnvironmentKeys.contains(key.toUpperCase()),
          isFalse,
          reason: key,
        );
      }
      final expectedLength = Platform.environment.keys
          .where(
            (k) =>
                !CodexAdapter.scrubbedEnvironmentKeys.contains(k.toUpperCase()),
          )
          .length;
      expect(environment, hasLength(expectedLength));
    });
  });

  group('results and events', () {
    test(
      'turnDone completes on exit with text, tokens and thread id',
      () async {
        runner = FakeProcessRunner({
          'codex.cmd': [script(fixtureLines('codex_success.jsonl'))],
        });
        final run = await adapter().start(task(), initialMessage: 'go');
        final events = <AgentEvent>[];
        run.events.listen(events.add);

        final result = await run.turnDone;
        expect(result.success, isTrue);
        expect(result.text, startsWith('Fixed the off-by-one in lib/a.dart'));
        expect(result.sessionRef, _thread);
        expect(result.inputTokens, 4321);
        expect(result.outputTokens, 256);
        expect(result.error, isNull);
        expect(result.exitCode, 0);
        expect(run.sessionRef, _thread);

        await (run as CodexRun).finished;
        final kinds = events.map((e) => e.kind).toList();
        expect(kinds.first, AgentEventKind.sessionStarted);
        expect(kinds, contains(AgentEventKind.thinking));
        expect(kinds, contains(AgentEventKind.toolStarted));
        expect(kinds, contains(AgentEventKind.toolFinished));
        expect(kinds, contains(AgentEventKind.fileChanged));
        expect(kinds, contains(AgentEventKind.textDelta));
        expect(kinds, contains(AgentEventKind.turnCompleted));
        expect(kinds, isNot(contains(AgentEventKind.turnFailed)));
        expect(kinds.last, AgentEventKind.processExited);
        expect(events.last.summary, 'exited with code 0');
        expect(events.every((e) => e.taskId == 'task-1'), isTrue);
        expect(events.every((e) => e.seat == Seat.gpt), isTrue);
        expect(run.exited, isTrue);
        expect(run.exitCode, 0);
      },
    );

    test('events emitted before the first listener are replayed', () async {
      runner = FakeProcessRunner({
        'codex.cmd': [script(fixtureLines('codex_success.jsonl'))],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      await run.turnDone;
      final late = await run.events.toList();
      expect(late.first.kind, AgentEventKind.sessionStarted);
      expect(late.map((e) => e.kind), contains(AgentEventKind.turnCompleted));
      expect(late.last.kind, AgentEventKind.processExited);
    });

    test('the -o file wins over the streamed agent_message', () async {
      final dir = await Directory.systemTemp.createTemp('office_codex_');
      addTearDown(() => dir.delete(recursive: true));
      runner = FakeProcessRunner({
        'codex.cmd': [script(fixtureLines('codex_success.jsonl'))],
      });
      final codex = adapter(outputDirectory: p.join(dir.path, 'results'));
      final file = File(codex.outputFileFor('task-1')!);
      // Codex writes the -o file right before it exits; the fake has no hook
      // for that, so the file is written while the scripted lines still flow.
      // start() creates the directory first.
      final run = await codex.start(task(), initialMessage: 'go');
      expect(file.parent.existsSync(), isTrue);
      file.writeAsStringSync('Final message from the -o file.\n');
      final result = await run.turnDone;
      expect(result.success, isTrue);
      expect(result.text, 'Final message from the -o file.');
      expect(result.sessionRef, _thread);
    });

    test('a missing or empty -o file falls back to the stream text', () async {
      final dir = await Directory.systemTemp.createTemp('office_codex_');
      addTearDown(() => dir.delete(recursive: true));
      runner = FakeProcessRunner({
        'codex.cmd': [
          script(fixtureLines('codex_success.jsonl')),
          script(fixtureLines('codex_success.jsonl')),
        ],
      });
      final codex = adapter(outputDirectory: dir.path);
      final missing = await codex.start(task(), initialMessage: 'go');
      expect((await missing.turnDone).text, startsWith('Fixed the off-by-one'));

      File(codex.outputFileFor('task-2')!).writeAsStringSync('  \n');
      final empty = await codex.start(task(id: 'task-2'), initialMessage: 'go');
      expect((await empty.turnDone).text, startsWith('Fixed the off-by-one'));
    });

    test('exit 1 after turn.failed is a failure with the message', () async {
      runner = FakeProcessRunner({
        'codex.cmd': [script(fixtureLines('codex_failed.jsonl'), exitCode: 1)],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      final events = <AgentEvent>[];
      run.events.listen(events.add);
      final result = await run.turnDone;
      expect(result.success, isFalse);
      expect(result.exitCode, 1);
      expect(
        result.error,
        'stream disconnected before completion: transport error',
      );
      expect(result.text, 'Starting with the failing widget test.');
      expect(result.sessionRef, _failedThread);
      expect(result.inputTokens, isNull);

      await (run as CodexRun).finished;
      final kinds = events.map((e) => e.kind).toList();
      expect(kinds.where((k) => k == AgentEventKind.turnFailed), hasLength(1));
      expect(kinds.last, AgentEventKind.processExited);
    });

    test('turn.failed with exit 0 is still a failure', () async {
      runner = FakeProcessRunner({
        'codex.cmd': [script(fixtureLines('codex_failed.jsonl'))],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      final result = await run.turnDone;
      expect(result.success, isFalse);
      expect(result.exitCode, 0);
      expect(result.error, contains('stream disconnected'));
    });

    test('a non-zero exit without turn.failed names the code', () async {
      runner = FakeProcessRunner({
        'codex.cmd': [
          script(
            fixtureLines('codex_success.jsonl').take(4).toList(),
            exitCode: 2,
          ),
        ],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      final events = <AgentEvent>[];
      run.events.listen(events.add);
      final result = await run.turnDone;
      expect(result.success, isFalse);
      expect(result.exitCode, 2);
      expect(result.error, 'exited with code 2');
      expect(result.text, isNull);
      expect(result.sessionRef, _thread);

      await (run as CodexRun).finished;
      expect(events.map((e) => e.kind).toList().sublist(events.length - 2), [
        AgentEventKind.turnFailed,
        AgentEventKind.processExited,
      ]);
      expect(events[events.length - 2].summary, 'exited with code 2');
    });

    test('exit 143 is reported as killed', () async {
      runner = FakeProcessRunner({
        'codex.cmd': [
          script(
            fixtureLines('codex_success.jsonl').take(2).toList(),
            exitCode: 143,
          ),
        ],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      final result = await run.turnDone;
      expect(result.success, isFalse);
      expect(result.exitCode, 143);
      expect(result.error, 'killed before the turn ended');
    });

    test(
      'a run that never saw thread.started keeps the requested ref',
      () async {
        runner = FakeProcessRunner({
          'codex.cmd': [script(const [], exitCode: 1)],
        });
        final run = await adapter().start(
          task(),
          initialMessage: 'go',
          resumeRef: _thread,
        );
        final result = await run.turnDone;
        expect(result.success, isFalse);
        expect(result.sessionRef, _thread);
        expect(run.sessionRef, _thread);
      },
    );

    test('send() is unsupported: start a new run with resumeRef', () async {
      runner = FakeProcessRunner({
        'codex.cmd': [script(fixtureLines('codex_success.jsonl'))],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      await expectLater(
        run.send('more'),
        throwsA(
          isA<UnsupportedError>().having(
            (e) => e.message,
            'message',
            contains('start a new run with resumeRef'),
          ),
        ),
      );
      expect(runner.starts.single.process.stdinLines, isEmpty);
      await run.turnDone;
    });

    test('stop() closes stdin and waits for the process to end', () async {
      runner = FakeProcessRunner({
        'codex.cmd': [script(fixtureLines('codex_success.jsonl'))],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      await run.stop(grace: const Duration(seconds: 5));
      final process = runner.starts.single.process;
      expect(process.stdinClosed || (run as CodexRun).exited, isTrue);
      expect((run as CodexRun).exited, isTrue);
      expect(process.killed, isFalse);
      final result = await run.turnDone;
      expect(result.success, isTrue);
    });

    test('a missing executable surfaces as the runner error', () async {
      runner = FakeProcessRunner({});
      expect(
        () => adapter().start(task(), initialMessage: 'go'),
        throwsStateError,
      );
    });
  });
}
