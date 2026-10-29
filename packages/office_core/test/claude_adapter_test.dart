import 'dart:convert';
import 'dart:io';

import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _fixedSessionId = '00000000-0000-4000-8000-000000000000';
const _pongSession = 'b7d1f3c2-5a4e-4c8b-9d2e-1f0a2b3c4d5e';

const _baseArguments = [
  '-p',
  '--output-format',
  'stream-json',
  '--input-format',
  'stream-json',
  '--verbose',
  '--include-partial-messages',
  '--permission-mode',
  'acceptEdits',
  '--permission-prompt-tool',
  'stdio',
];

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

TaskRecord task({String cwd = r'C:\work\demo'}) {
  final now = DateTime.utc(2026, 10, 28, 12);
  return TaskRecord(
    id: 'task-1',
    rootId: 'task-1',
    kind: TaskKind.root,
    title: 'Fix the failing test',
    prompt: 'Make the test pass.',
    cwd: cwd,
    status: TaskStatus.assigned,
    createdAt: now,
    updatedAt: now,
  );
}

String secondTurnResult(String text) => jsonEncode({
  'type': 'result',
  'subtype': 'success',
  'is_error': false,
  'num_turns': 1,
  'result': text,
  'session_id': _pongSession,
  'usage': {
    'input_tokens': 1,
    'cache_creation_input_tokens': 0,
    'cache_read_input_tokens': 500,
    'output_tokens': 3,
  },
});

void main() {
  late FakeProcessRunner runner;

  ClaudeAdapter adapter({
    Map<String, String> baseEnvironment = const {},
    String? systemPromptFile,
    String? mcpConfigFile,
    int? maxTurns,
    String permissionMode = 'acceptEdits',
  }) {
    return ClaudeAdapter(
      runner: runner,
      executable: r'C:\Users\me\AppData\Roaming\npm\claude.cmd',
      permissionMode: permissionMode,
      systemPromptFile: systemPromptFile,
      mcpConfigFile: mcpConfigFile,
      maxTurns: maxTurns,
      baseEnvironment: baseEnvironment,
      sessionIdFactory: () => _fixedSessionId,
    );
  }

  group('arguments and environment', () {
    setUp(() {
      runner = FakeProcessRunner({
        'claude.cmd': [script(fixtureLines('claude_pong.jsonl'))],
      });
    });

    test(
      'a new session passes the exact argument list with --session-id',
      () async {
        final claude = adapter(
          baseEnvironment: {
            'PATH': r'C:\Windows',
            'ANTHROPIC_API_KEY': 'sk-should-not-leak',
            'CLAUDE_CODE_USE_BEDROCK': '1',
            'CLAUDE_CODE_USE_VERTEX': '1',
          },
        );
        final run = await claude.start(task(), initialMessage: 'hello');

        expect(claude.lastArguments, [
          ..._baseArguments,
          '--session-id',
          _fixedSessionId,
        ]);
        final start = runner.starts.single;
        expect(start.executable, r'C:\Users\me\AppData\Roaming\npm\claude.cmd');
        expect(start.arguments, claude.lastArguments);
        expect(start.workingDirectory, r'C:\work\demo');
        expect(start.environment, {'PATH': r'C:\Windows'});
        expect(claude.lastEnvironment, {'PATH': r'C:\Windows'});
        expect(claude.seat, Seat.claude);
        expect((run as ClaudeRun).requestedSessionRef, _fixedSessionId);
        await run.turnDone;
      },
    );

    test('a resume passes --resume and the interrupted-turn flag', () async {
      final claude = adapter(baseEnvironment: {'HOME': r'C:\Users\me'});
      final run = await claude.start(
        task(),
        initialMessage: 'You were restarted; check git status.',
        resumeRef: _pongSession,
      );

      expect(claude.lastArguments, [
        ..._baseArguments,
        '--resume',
        _pongSession,
      ]);
      expect(runner.starts.single.environment, {
        'HOME': r'C:\Users\me',
        'CLAUDE_CODE_RESUME_INTERRUPTED_TURN': '1',
      });
      expect((run as ClaudeRun).requestedSessionRef, _pongSession);
      await run.turnDone;
    });

    test('optional flags follow in the documented order', () async {
      final claude = adapter(
        permissionMode: 'auto',
        systemPromptFile: r'C:\office\brain.md',
        mcpConfigFile: r'C:\office\office-mcp.json',
        maxTurns: 40,
      );
      final run = await claude.start(task(), initialMessage: 'plan');
      expect(claude.lastArguments, [
        '-p',
        '--output-format',
        'stream-json',
        '--input-format',
        'stream-json',
        '--verbose',
        '--include-partial-messages',
        '--permission-mode',
        'auto',
        '--permission-prompt-tool',
        'stdio',
        '--session-id',
        _fixedSessionId,
        '--append-system-prompt-file',
        r'C:\office\brain.md',
        '--mcp-config',
        r'C:\office\office-mcp.json',
        '--max-turns',
        '40',
      ]);
      expect(claude.lastArguments, isNot(contains('--bare')));
      await run.turnDone;
    });

    test('environment scrubbing ignores case, as Windows does', () {
      final claude = adapter(
        baseEnvironment: {'anthropic_api_key': 'x', 'Path': 'y'},
      );
      expect(claude.buildEnvironment(resuming: false), {'Path': 'y'});
    });

    test('newSessionId yields distinct RFC 4122 v4 ids', () {
      final a = ClaudeAdapter.newSessionId();
      final b = ClaudeAdapter.newSessionId();
      final v4 = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      expect(a, matches(v4));
      expect(b, matches(v4));
      expect(a, isNot(b));
    });
  });

  group('stdin', () {
    test('the initial message is one stream-json user line', () async {
      runner = FakeProcessRunner({
        'claude.cmd': [script(fixtureLines('claude_pong.jsonl'))],
      });
      final run = await adapter().start(
        task(),
        initialMessage: 'Fix the test in lib/a.dart\nthen stop.',
      );
      final process = runner.starts.single.process;
      expect(process.stdinLines, hasLength(1));
      expect(
        process.stdinLines.single,
        '{"type":"user","message":{"role":"user","content":[{"type":"text",'
        '"text":"Fix the test in lib/a.dart\\nthen stop."}]}}',
      );
      expect(process.stdinLines.single, isNot(contains('\n')));
      await run.turnDone;
    });

    test('send() writes another user line and resets turnDone', () async {
      runner = FakeProcessRunner({
        'claude.cmd': [
          script([
            ...fixtureLines('claude_pong.jsonl'),
            secondTurnResult('second answer'),
          ]),
        ],
      });
      final run = await adapter().start(task(), initialMessage: 'first');
      final first = await run.turnDone;
      expect(first.text, 'pong');

      await run.send('second');
      final process = runner.starts.single.process;
      expect(process.stdinLines, [
        ClaudeAdapter.encodeUserMessage('first'),
        '{"type":"user","message":{"role":"user","content":[{"type":"text","text":"second"}]}}',
      ]);
      expect((run as ClaudeRun).inTurn, isTrue);

      final second = await run.turnDone;
      expect(second.success, isTrue);
      expect(second.text, 'second answer');
      expect(second.inputTokens, 501);
      expect(second.outputTokens, 3);
      expect(second.sessionRef, _pongSession);
    });

    test('send() after the process exited throws instead of writing', () async {
      runner = FakeProcessRunner({
        'claude.cmd': [script(fixtureLines('claude_pong.jsonl'))],
      });
      final run = await adapter().start(task(), initialMessage: 'first');
      await run.turnDone;
      await (run as ClaudeRun).finished;
      expect(run.exited, isTrue);
      expect(() => run.send('late'), throwsStateError);
      expect(runner.starts.single.process.stdinLines, hasLength(1));
    });
  });

  group('turn results and events', () {
    test(
      'turnDone completes with the result text, tokens and session',
      () async {
        runner = FakeProcessRunner({
          'claude.cmd': [script(fixtureLines('claude_pong.jsonl'))],
        });
        final run = await adapter().start(task(), initialMessage: 'go');
        final events = <AgentEvent>[];
        run.events.listen(events.add);

        final result = await run.turnDone;
        expect(result.success, isTrue);
        expect(result.text, 'pong');
        expect(result.inputTokens, 12 + 1200 + 34000);
        expect(result.outputTokens, 48);
        expect(result.sessionRef, _pongSession);
        expect(result.error, isNull);
        expect(result.exitCode, isNull);
        expect(run.sessionRef, _pongSession);

        await (run as ClaudeRun).finished;
        final kinds = events.map((e) => e.kind).toList();
        expect(kinds.first, AgentEventKind.sessionStarted);
        expect(kinds, contains(AgentEventKind.toolStarted));
        expect(kinds, contains(AgentEventKind.fileChanged));
        expect(kinds, contains(AgentEventKind.rateLimit));
        expect(kinds, contains(AgentEventKind.turnCompleted));
        expect(kinds.last, AgentEventKind.processExited);
        expect(events.last.summary, 'exited with code 0');
        expect(events.where((e) => e.summary.startsWith('WARNING:')), isEmpty);
        expect(events.every((e) => e.taskId == 'task-1'), isTrue);
        expect(run.exitCode, 0);
      },
    );

    test(
      'events emitted before the first listener are replayed to it',
      () async {
        runner = FakeProcessRunner({
          'claude.cmd': [script(fixtureLines('claude_pong.jsonl'))],
        });
        final run = await adapter().start(task(), initialMessage: 'go');
        await run.turnDone;
        final late = await run.events.toList();
        expect(late.first.kind, AgentEventKind.sessionStarted);
        expect(late.map((e) => e.kind), contains(AgentEventKind.turnCompleted));
        expect(late.last.kind, AgentEventKind.processExited);
      },
    );

    test(
      'an apiKeySource other than none produces a warning, not a stop',
      () async {
        final init =
            jsonDecode(fixtureLines('claude_pong.jsonl').first)
                as Map<String, Object?>;
        init['apiKeySource'] = 'ANTHROPIC_API_KEY';
        final lines = [
          jsonEncode(init),
          ...fixtureLines('claude_pong.jsonl').skip(1),
        ];
        runner = FakeProcessRunner({
          'claude.cmd': [script(lines)],
        });
        final run = await adapter().start(task(), initialMessage: 'go');
        final events = <AgentEvent>[];
        run.events.listen(events.add);
        final result = await run.turnDone;
        expect(result.success, isTrue);
        final warning = events.firstWhere(
          (e) => e.summary.startsWith('WARNING: apiKeySource='),
        );
        expect(warning.kind, AgentEventKind.unknown);
        expect(
          warning.summary,
          startsWith('WARNING: apiKeySource=ANTHROPIC_API_KEY'),
        );
        expect(events.indexOf(warning), 1);
      },
    );

    test('exit 143 without a result fails the turn as killed', () async {
      runner = FakeProcessRunner({
        'claude.cmd': [
          script(fixtureLines('claude_killed.jsonl'), exitCode: 143),
        ],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      final events = <AgentEvent>[];
      run.events.listen(events.add);

      final result = await run.turnDone;
      expect(result.success, isFalse);
      expect(result.exitCode, 143);
      expect(result.error, 'killed before the turn ended');
      expect(result.text, isNull);
      expect(result.sessionRef, 'c8e2a4d3-6b5f-4d9c-8e3f-2a1b3c4d5e6f');

      await (run as ClaudeRun).finished;
      expect(events.map((e) => e.kind), [
        AgentEventKind.sessionStarted,
        AgentEventKind.textDelta,
        AgentEventKind.turnFailed,
        AgentEventKind.processExited,
      ]);
      expect(events[2].summary, 'killed before the turn ended');
      expect(events[3].summary, 'exited with code 143');
      expect(run.exited, isTrue);
      expect(run.exitCode, 143);
    });

    test('another exit code without a result names the code', () async {
      runner = FakeProcessRunner({
        'claude.cmd': [
          script(fixtureLines('claude_killed.jsonl'), exitCode: 1),
        ],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      final result = await run.turnDone;
      expect(result.success, isFalse);
      expect(result.exitCode, 1);
      expect(result.error, 'exited with code 1 before the turn ended');
    });

    test('a result with is_error fails the turn with the subtype', () async {
      final failed = jsonEncode({
        'type': 'result',
        'subtype': 'error_max_turns',
        'is_error': true,
        'num_turns': 1,
        'result': '',
        'session_id': _pongSession,
        'usage': {'input_tokens': 5, 'output_tokens': 2},
      });
      runner = FakeProcessRunner({
        'claude.cmd': [
          script([...fixtureLines('claude_killed.jsonl'), failed]),
        ],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      final result = await run.turnDone;
      expect(result.success, isFalse);
      expect(result.error, 'error_max_turns');
      expect(result.inputTokens, 5);
      expect(result.outputTokens, 2);
      expect(result.exitCode, isNull);
    });

    test('stop() closes stdin and waits for the process to end', () async {
      runner = FakeProcessRunner({
        'claude.cmd': [script(fixtureLines('claude_pong.jsonl'))],
      });
      final run = await adapter().start(task(), initialMessage: 'go');
      await run.turnDone;
      await run.stop(grace: const Duration(seconds: 5));
      final process = runner.starts.single.process;
      expect(
        process.stdinClosed || process.killed || (run as ClaudeRun).exited,
        isTrue,
      );
      expect((run as ClaudeRun).exited, isTrue);
      expect(process.killed, isFalse);
    });
  });
}
