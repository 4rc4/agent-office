import 'dart:convert';
import 'dart:io';

import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _thread = '0199c8e2-7f3a-7b2c-9d4e-5f6a7b8c9d0e';

List<String> fixtureLines(String name) {
  final file = File(p.join('test', 'fixtures', name));
  return const LineSplitter().convert(file.readAsStringSync());
}

String threadStarted([String id = _thread]) =>
    jsonEncode({'type': 'thread.started', 'thread_id': id});

String itemLine(String phase, Map<String, Object?> item) =>
    jsonEncode({'type': 'item.$phase', 'item': item});

String commandLine(
  String phase, {
  String id = 'item_1',
  Object command = 'dart test',
  String status = 'in_progress',
  int? exitCode,
  String output = '',
}) => itemLine(phase, {
  'id': id,
  'type': 'command_execution',
  'command': command,
  'aggregated_output': output,
  'exit_code': exitCode,
  'status': status,
});

void main() {
  late CodexJsonlParser parser;

  List<AgentEvent> parseAll(String line) =>
      parser.parseLineAll(line, seat: Seat.gpt, taskId: 't1');

  AgentEvent? parse(String line) =>
      parser.parseLine(line, seat: Seat.gpt, taskId: 't1');

  setUp(() => parser = CodexJsonlParser());

  group('thread and turn lifecycle', () {
    test('thread.started becomes sessionStarted carrying the thread id', () {
      final event = parse(threadStarted())!;
      expect(event.kind, AgentEventKind.sessionStarted);
      expect(event.seat, Seat.gpt);
      expect(event.taskId, 't1');
      expect(event.sessionRef, _thread);
      expect(event.summary, 'thread started: $_thread');
      expect(event.raw['thread_id'], _thread);
      expect(parser.threadId, _thread);
    });

    test('the thread id is stamped on every later event', () {
      parse(threadStarted());
      final event = parse('{"type":"turn.started"}')!;
      expect(event.kind, AgentEventKind.unknown);
      expect(event.summary, 'turn started');
      expect(event.sessionRef, _thread);
    });

    test('events before thread.started have no sessionRef', () {
      expect(parse('{"type":"turn.started"}')!.sessionRef, isNull);
    });

    test('turn.completed becomes turnCompleted with the token usage', () {
      parse(
        itemLine('completed', {
          'id': 'm1',
          'type': 'agent_message',
          'text': 'All done.',
        }),
      );
      final event = parse(
        '{"type":"turn.completed","usage":{"input_tokens":4321,"cached_input_tokens":1024,"output_tokens":256}}',
      )!;
      expect(event.kind, AgentEventKind.turnCompleted);
      expect(event.summary, 'All done.');
      expect(event.inputTokens, 4321);
      expect(event.outputTokens, 256);
      expect(parser.turnCompleted, isTrue);
      expect(parser.turnFailed, isFalse);
      expect(parser.inputTokens, 4321);
      expect(parser.outputTokens, 256);
    });

    test('turn.completed without usage or message still parses', () {
      final event = parse('{"type":"turn.completed"}')!;
      expect(event.kind, AgentEventKind.turnCompleted);
      expect(event.summary, 'turn completed');
      expect(event.inputTokens, isNull);
      expect(event.outputTokens, isNull);
    });

    test('turn.failed becomes turnFailed with the error message', () {
      final event = parse(
        '{"type":"turn.failed","error":{"message":"stream disconnected"}}',
      )!;
      expect(event.kind, AgentEventKind.turnFailed);
      expect(event.summary, 'stream disconnected');
      expect(parser.turnFailed, isTrue);
      expect(parser.failureMessage, 'stream disconnected');
    });

    test('a top-level error event becomes turnFailed', () {
      final event = parse('{"type":"error","message":"quota exceeded"}')!;
      expect(event.kind, AgentEventKind.turnFailed);
      expect(event.summary, 'quota exceeded');
      expect(parser.failureMessage, 'quota exceeded');
    });

    test('turn.failed without a message still fails the turn', () {
      final event = parse('{"type":"turn.failed"}')!;
      expect(event.kind, AgentEventKind.turnFailed);
      expect(event.summary, 'turn failed');
      expect(parser.turnFailed, isTrue);
    });
  });

  group('agent_message and reasoning', () {
    test('a completed agent_message becomes one textDelta', () {
      final events = parseAll(
        itemLine('completed', {
          'id': 'm1',
          'type': 'agent_message',
          'text': 'Hello there',
        }),
      );
      expect(events, hasLength(1));
      expect(events.single.kind, AgentEventKind.textDelta);
      expect(events.single.summary, 'Hello there');
      expect(parser.lastAgentMessage, 'Hello there');
    });

    test('the last agent_message wins', () {
      parse(
        itemLine('completed', {
          'id': 'm1',
          'type': 'agent_message',
          'text': 'first',
        }),
      );
      parse(
        itemLine('completed', {
          'id': 'm2',
          'type': 'agent_message',
          'text': 'second',
        }),
      );
      expect(parser.lastAgentMessage, 'second');
    });

    test('item.started with empty text produces nothing', () {
      expect(
        parseAll(
          itemLine('started', {
            'id': 'm1',
            'type': 'agent_message',
            'text': '',
          }),
        ),
        isEmpty,
      );
    });

    test('delta updates stream and the completed item adds no duplicate', () {
      final a = parseAll(
        itemLine('updated', {
          'id': 'm1',
          'type': 'agent_message',
          'delta': 'Hel',
        }),
      );
      final b = parseAll(
        itemLine('updated', {
          'id': 'm1',
          'type': 'agent_message',
          'delta': 'lo',
        }),
      );
      final done = parseAll(
        itemLine('completed', {
          'id': 'm1',
          'type': 'agent_message',
          'text': 'Hello',
        }),
      );
      expect(a.single.summary, 'Hel');
      expect(b.single.summary, 'lo');
      expect(done, isEmpty);
      expect(parser.lastAgentMessage, 'Hello');
    });

    test('growing text snapshots are emitted as their new suffix only', () {
      final a = parseAll(
        itemLine('updated', {
          'id': 'm1',
          'type': 'agent_message',
          'text': 'Hel',
        }),
      );
      final b = parseAll(
        itemLine('updated', {
          'id': 'm1',
          'type': 'agent_message',
          'text': 'Hello',
        }),
      );
      final done = parseAll(
        itemLine('completed', {
          'id': 'm1',
          'type': 'agent_message',
          'text': 'Hello world',
        }),
      );
      expect(a.single.summary, 'Hel');
      expect(b.single.summary, 'lo');
      expect(done.single.summary, ' world');
      expect(parser.lastAgentMessage, 'Hello world');
    });

    test('a rewritten text that no longer extends the old one is re-shown', () {
      parse(
        itemLine('updated', {
          'id': 'm1',
          'type': 'agent_message',
          'text': 'draft',
        }),
      );
      final done = parseAll(
        itemLine('completed', {
          'id': 'm1',
          'type': 'agent_message',
          'text': 'final',
        }),
      );
      expect(done.single.summary, 'final');
      expect(parser.lastAgentMessage, 'final');
    });

    test('reasoning becomes thinking and never touches lastAgentMessage', () {
      final event = parse(
        itemLine('completed', {
          'id': 'r1',
          'type': 'reasoning',
          'text': 'Let me check the test.',
        }),
      )!;
      expect(event.kind, AgentEventKind.thinking);
      expect(event.summary, 'Let me check the test.');
      expect(parser.lastAgentMessage, isNull);
    });

    test('an item without id is only shown when completed', () {
      expect(
        parseAll(
          itemLine('updated', {'type': 'agent_message', 'text': 'partial'}),
        ),
        isEmpty,
      );
      final done = parse(
        itemLine('completed', {'type': 'agent_message', 'text': 'whole'}),
      )!;
      expect(done.kind, AgentEventKind.textDelta);
      expect(done.summary, 'whole');
    });
  });

  group('command_execution', () {
    test('started becomes toolStarted (shell) with a clipped command', () {
      final longCommand = 'echo ${'x' * 120}';
      final event = parse(commandLine('started', command: longCommand))!;
      expect(event.kind, AgentEventKind.toolStarted);
      expect(event.category, ToolCategory.shell);
      expect(event.summary, startsWith('codex: echo xxxx'));
      expect(event.summary.length, 'codex: '.length + 80);
    });

    test('multi-line commands are shown on one line', () {
      final event = parse(
        commandLine('started', command: 'cd lib\n  && dart test'),
      )!;
      expect(event.summary, 'codex: cd lib && dart test');
    });

    test('a command given as an argument list is joined', () {
      final event = parse(
        commandLine('started', command: ['bash', '-lc', 'ls -la']),
      )!;
      expect(event.summary, 'codex: bash -lc ls -la');
    });

    test('updated streams output and produces nothing', () {
      parse(commandLine('started'));
      expect(parseAll(commandLine('updated', output: 'partial')), isEmpty);
    });

    test('completed with exit 0 becomes toolFinished done with the code', () {
      parse(commandLine('started'));
      final events = parseAll(
        commandLine('completed', status: 'completed', exitCode: 0),
      );
      expect(events, hasLength(1));
      expect(events.single.kind, AgentEventKind.toolFinished);
      expect(events.single.category, ToolCategory.shell);
      expect(events.single.summary, 'done: codex: dart test (exit 0)');
    });

    test('completed with a non-zero exit becomes toolFinished failed', () {
      parse(commandLine('started'));
      final event = parse(
        commandLine('completed', status: 'failed', exitCode: 1),
      )!;
      expect(event.summary, 'failed: codex: dart test (exit 1)');
    });

    test('status failed without exit code is still a failure', () {
      parse(commandLine('started'));
      final event = parse(commandLine('completed', status: 'failed'))!;
      expect(event.summary, 'failed: codex: dart test');
    });

    test('a completed command that was never started yields both ends', () {
      final events = parseAll(
        commandLine('completed', status: 'completed', exitCode: 0),
      );
      expect(events.map((e) => e.kind), [
        AgentEventKind.toolStarted,
        AgentEventKind.toolFinished,
      ]);
      expect(events[0].summary, 'codex: dart test');
      expect(events[1].summary, 'done: codex: dart test (exit 0)');
    });
  });

  group('file_change, mcp_tool_call, web_search, todo_list', () {
    test('file_change completed yields one fileChanged per path', () {
      final events = parseAll(
        itemLine('completed', {
          'id': 'f1',
          'type': 'file_change',
          'changes': [
            {'path': 'lib/a.dart', 'kind': 'update'},
            {'path': 'lib/b.dart', 'kind': 'add'},
            {'path': 'lib/old.dart', 'kind': 'delete'},
          ],
          'status': 'completed',
        }),
      );
      expect(events, hasLength(3));
      expect(events.every((e) => e.kind == AgentEventKind.fileChanged), isTrue);
      expect(events.every((e) => e.category == ToolCategory.edit), isTrue);
      expect(events.map((e) => e.summary), [
        'lib/a.dart',
        'lib/b.dart',
        'lib/old.dart',
      ]);
      expect(events.first.raw['item'], isA<Map<Object?, Object?>>());
    });

    test('file_change before completion and odd shapes produce nothing', () {
      expect(
        parseAll(
          itemLine('started', {
            'id': 'f1',
            'type': 'file_change',
            'changes': [
              {'path': 'lib/a.dart', 'kind': 'update'},
            ],
          }),
        ),
        isEmpty,
      );
      expect(
        parseAll(
          itemLine('completed', {
            'id': 'f2',
            'type': 'file_change',
            'changes': 'nope',
          }),
        ),
        isEmpty,
      );
      expect(
        parseAll(
          itemLine('completed', {
            'id': 'f3',
            'type': 'file_change',
            'changes': [7, null, {}],
          }),
        ),
        isEmpty,
      );
    });

    test('mcp_tool_call becomes toolStarted (mcp) naming server and tool', () {
      final event = parse(
        itemLine('started', {
          'id': 'c1',
          'type': 'mcp_tool_call',
          'server': 'office',
          'tool': 'plan_submit',
          'status': 'in_progress',
        }),
      )!;
      expect(event.kind, AgentEventKind.toolStarted);
      expect(event.category, ToolCategory.mcp);
      expect(event.summary, 'MCP office/plan_submit');

      final done = parse(
        itemLine('completed', {
          'id': 'c1',
          'type': 'mcp_tool_call',
          'server': 'office',
          'tool': 'plan_submit',
          'status': 'completed',
        }),
      )!;
      expect(done.kind, AgentEventKind.toolFinished);
      expect(done.category, ToolCategory.mcp);
      expect(done.summary, 'done: MCP office/plan_submit');
    });

    test('mcp servers that sound like a browser are browser work', () {
      for (final server in ['chrome-devtools', 'Playwright', 'my-browser']) {
        final event = parse(
          itemLine('started', {
            'id': 'c-$server',
            'type': 'mcp_tool_call',
            'server': server,
            'tool': 'click',
          }),
        )!;
        expect(event.category, ToolCategory.browser, reason: server);
      }
      expect(CodexJsonlParser.mcpCategory('github'), ToolCategory.mcp);
      expect(CodexJsonlParser.mcpCategory('CHROME'), ToolCategory.browser);
    });

    test('a failed mcp call says so', () {
      final event = parse(
        itemLine('completed', {
          'id': 'c9',
          'type': 'mcp_tool_call',
          'server': 'office',
          'tool': 'approve',
          'status': 'failed',
        }),
      )!;
      // Never started: the first event is the synthesized start.
      expect(event.kind, AgentEventKind.toolStarted);
      final events = parseAll(
        itemLine('completed', {
          'id': 'c10',
          'type': 'mcp_tool_call',
          'server': 'office',
          'tool': 'approve',
          'status': 'failed',
        }),
      );
      expect(events.last.kind, AgentEventKind.toolFinished);
      expect(events.last.summary, 'failed: MCP office/approve');
    });

    test('web_search becomes toolStarted (browser) with the query', () {
      final event = parse(
        itemLine('started', {
          'id': 'w1',
          'type': 'web_search',
          'query': 'dart ffi windows',
        }),
      )!;
      expect(event.kind, AgentEventKind.toolStarted);
      expect(event.category, ToolCategory.browser);
      expect(event.summary, 'web search: dart ffi windows');
    });

    test('todo_list and unknown item types become unknown', () {
      final todo = parse(
        itemLine('completed', {
          'id': 'td',
          'type': 'todo_list',
          'items': [
            {'text': 'a', 'completed': true},
            {'text': 'b', 'completed': false},
          ],
        }),
      )!;
      expect(todo.kind, AgentEventKind.unknown);
      expect(todo.summary, 'todo list: 2 items');

      final odd = parse(itemLine('started', {'id': 'x', 'type': 'hologram'}))!;
      expect(odd.kind, AgentEventKind.unknown);
      expect(odd.summary, 'item hologram (started)');

      final error = parse(
        itemLine('completed', {
          'id': 'e',
          'type': 'error',
          'message': 'reconnecting',
        }),
      )!;
      expect(error.kind, AgentEventKind.unknown);
      expect(error.summary, 'error: reconnecting');
      expect(parser.turnFailed, isFalse);
    });
  });

  group('robustness', () {
    test('malformed JSON becomes unknown with the raw line as summary', () {
      const bad = '{"type":"item.completed", "item":';
      final event = parse(bad)!;
      expect(event.kind, AgentEventKind.unknown);
      expect(event.summary, bad);
      expect(event.raw['line'], bad);
    });

    test('non-object JSON becomes unknown', () {
      expect(parse('42')!.kind, AgentEventKind.unknown);
      expect(parse('[1,2]')!.kind, AgentEventKind.unknown);
      expect(parse('"str"')!.kind, AgentEventKind.unknown);
      expect(parse('null')!.kind, AgentEventKind.unknown);
    });

    test('blank lines produce nothing', () {
      expect(parse(''), isNull);
      expect(parse('   \r'), isNull);
      expect(parseAll('\t'), isEmpty);
    });

    test('unknown top-level types and missing fields never throw', () {
      final event = parse('{"type":"session.configured","model":"gpt-5"}')!;
      expect(event.kind, AgentEventKind.unknown);
      expect(event.summary, 'session.configured');
      expect(parse('{"no":"type"}')!.summary, 'event without type');
      expect(
        parse('{"type":"item.completed"}')!.summary,
        'item.completed without item',
      );
      expect(
        parse('{"type":"item.completed","item":7}')!.kind,
        AgentEventKind.unknown,
      );
      expect(
        parse(
          '{"type":"item.started","item":{"type":"command_execution"}}',
        )!.summary,
        'codex: ',
      );
      expect(
        parse('{"type":"thread.started"}')!.summary,
        'thread started: no thread_id',
      );
      expect(
        parse('{"type":"turn.failed","error":"plain"}')!.summary,
        'turn failed',
      );
    });

    test('a non-string thread_id is ignored', () {
      final event = parse('{"type":"thread.started","thread_id":12}')!;
      expect(event.kind, AgentEventKind.sessionStarted);
      expect(parser.threadId, isNull);
    });
  });

  group('fixtures', () {
    test('codex_success.jsonl plays through as one coherent turn', () {
      final events = [
        for (final line in fixtureLines('codex_success.jsonl'))
          ...parseAll(line),
      ];
      expect(events.map((e) => e.kind), [
        AgentEventKind.sessionStarted,
        AgentEventKind.unknown, // turn started
        AgentEventKind.thinking,
        AgentEventKind.toolStarted, // dart test (fails)
        AgentEventKind.toolFinished,
        AgentEventKind.fileChanged, // lib/a.dart
        AgentEventKind.fileChanged, // lib/b.dart
        AgentEventKind.toolStarted, // dart test (passes)
        AgentEventKind.toolFinished,
        AgentEventKind.textDelta,
        AgentEventKind.turnCompleted,
      ]);
      expect(events[3].summary, 'codex: dart test test/a_test.dart');
      expect(
        events[4].summary,
        'failed: codex: dart test test/a_test.dart (exit 1)',
      );
      expect(events[5].summary, 'lib/a.dart');
      expect(events[6].summary, 'lib/b.dart');
      expect(
        events[8].summary,
        'done: codex: dart test test/a_test.dart (exit 0)',
      );
      expect(events[9].summary, startsWith('Fixed the off-by-one'));
      expect(events.last.summary, events[9].summary);
      expect(events.last.inputTokens, 4321);
      expect(events.last.outputTokens, 256);
      expect(events.every((e) => e.sessionRef == _thread), isTrue);
      expect(events.every((e) => e.seat == Seat.gpt), isTrue);
      expect(events.every((e) => e.taskId == 't1'), isTrue);
      expect(parser.threadId, _thread);
      expect(parser.lastAgentMessage, startsWith('Fixed the off-by-one'));
      expect(parser.turnCompleted, isTrue);
      expect(parser.turnFailed, isFalse);
    });

    test('codex_failed.jsonl ends in turnFailed with the message', () {
      final events = [
        for (final line in fixtureLines('codex_failed.jsonl'))
          ...parseAll(line),
      ];
      expect(events.map((e) => e.kind), [
        AgentEventKind.sessionStarted,
        AgentEventKind.unknown,
        AgentEventKind.textDelta,
        AgentEventKind.toolStarted,
        AgentEventKind.turnFailed,
      ]);
      expect(events.last.summary, contains('stream disconnected'));
      expect(parser.turnFailed, isTrue);
      expect(parser.turnCompleted, isFalse);
      expect(parser.threadId, '0199c8e2-aaaa-7b2c-9d4e-5f6a7b8c9d0e');
      expect(parser.lastAgentMessage, 'Starting with the failing widget test.');
    });
  });
}
