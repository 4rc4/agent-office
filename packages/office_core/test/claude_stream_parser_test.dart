import 'dart:convert';
import 'dart:io';

import 'package:office_core/office_core.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

const _session = 'b7d1f3c2-5a4e-4c8b-9d2e-1f0a2b3c4d5e';

List<String> fixtureLines(String name) {
  final file = File(p.join('test', 'fixtures', name));
  return const LineSplitter().convert(file.readAsStringSync());
}

String assistantLine(List<Map<String, Object?>> content, {String? parent}) {
  return jsonEncode({
    'type': 'assistant',
    'message': {
      'id': 'msg_x',
      'type': 'message',
      'role': 'assistant',
      'model': 'claude-opus-4-1',
      'content': content,
      'usage': {'input_tokens': 1, 'output_tokens': 1},
    },
    'parent_tool_use_id': parent,
    'session_id': _session,
  });
}

String toolUseLine(
  String id,
  String name,
  Map<String, Object?> input, {
  String? parent,
}) {
  return assistantLine([
    {'type': 'tool_use', 'id': id, 'name': name, 'input': input},
  ], parent: parent);
}

String toolResultLine(
  String toolUseId, {
  Object? content = 'ok',
  bool isError = false,
  String? parent,
}) {
  return jsonEncode({
    'type': 'user',
    'message': {
      'role': 'user',
      'content': [
        {
          'type': 'tool_result',
          'tool_use_id': toolUseId,
          'content': content,
          'is_error': isError,
        },
      ],
    },
    'parent_tool_use_id': parent,
    'session_id': _session,
  });
}

String textDeltaLine(String text) {
  return jsonEncode({
    'type': 'stream_event',
    'event': {
      'type': 'content_block_delta',
      'index': 0,
      'delta': {'type': 'text_delta', 'text': text},
    },
    'parent_tool_use_id': null,
    'session_id': _session,
  });
}

String resultLine({
  String subtype = 'success',
  bool isError = false,
  String result = 'pong',
  Map<String, Object?>? usage,
  List<String>? errors,
}) {
  return jsonEncode({
    'type': 'result',
    'subtype': subtype,
    'is_error': isError,
    'duration_ms': 10,
    'num_turns': 1,
    'result': result,
    'session_id': _session,
    'total_cost_usd': 0.0,
    'usage':
        usage ??
        {
          'input_tokens': 10,
          'cache_creation_input_tokens': 100,
          'cache_read_input_tokens': 1000,
          'output_tokens': 7,
        },
    'errors': ?errors,
  });
}

void main() {
  late ClaudeStreamParser parser;

  List<AgentEvent> parseAll(String line) =>
      parser.parseLineAll(line, seat: Seat.claude, taskId: 't1');

  AgentEvent? parse(String line) =>
      parser.parseLine(line, seat: Seat.claude, taskId: 't1');

  setUp(() => parser = ClaudeStreamParser());

  group('system events', () {
    test(
      'init becomes sessionStarted with sessionRef and raw apiKeySource',
      () {
        final event = parse(fixtureLines('claude_pong.jsonl').first)!;
        expect(event.kind, AgentEventKind.sessionStarted);
        expect(event.seat, Seat.claude);
        expect(event.taskId, 't1');
        expect(event.sessionRef, _session);
        expect(event.raw['apiKeySource'], 'none');
        expect(event.summary, contains('apiKeySource=none'));
        expect(event.summary, contains('claude-opus-4-1'));
      },
    );

    test('status compacting becomes compacting', () {
      final event = parse(
        '{"type":"system","subtype":"status","status":"compacting"}',
      )!;
      expect(event.kind, AgentEventKind.compacting);
    });

    test('other status and hook subtypes become unknown without throwing', () {
      expect(
        parse('{"type":"system","subtype":"status","status":"idle"}')!.kind,
        AgentEventKind.unknown,
      );
      final hook = parse(
        '{"type":"system","subtype":"hook_response","hook_name":"SessionStart:startup","outcome":"success"}',
      )!;
      expect(hook.kind, AgentEventKind.unknown);
      expect(hook.summary, 'hook SessionStart:startup: success');
    });
  });

  group('text and thinking', () {
    test('assistant text block becomes textDelta when no partials flow', () {
      final events = parseAll(
        assistantLine([
          {'type': 'text', 'text': 'Hello there'},
        ]),
      );
      expect(events, hasLength(1));
      expect(events.single.kind, AgentEventKind.textDelta);
      expect(events.single.summary, 'Hello there');
    });

    test('stream_event text deltas become textDelta', () {
      final event = parse(textDeltaLine('pon'))!;
      expect(event.kind, AgentEventKind.textDelta);
      expect(event.summary, 'pon');
      expect(parser.partialTextSeenThisTurn, isTrue);
    });

    test('assistant text block is skipped once a delta was seen this turn', () {
      parse(textDeltaLine('po'));
      parse(textDeltaLine('ng'));
      final skipped = parseAll(
        assistantLine([
          {'type': 'text', 'text': 'pong'},
        ]),
      );
      expect(skipped, isEmpty);

      // The result ends the turn; the next turn starts counting afresh.
      parse(resultLine());
      expect(parser.partialTextSeenThisTurn, isFalse);
      final again = parseAll(
        assistantLine([
          {'type': 'text', 'text': 'next turn'},
        ]),
      );
      expect(again.single.kind, AgentEventKind.textDelta);
    });

    test('streaming plumbing events produce nothing', () {
      expect(
        parseAll(
          '{"type":"stream_event","event":{"type":"message_start","message":{}}}',
        ),
        isEmpty,
      );
      expect(
        parseAll(
          '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"input_json_delta","partial_json":"{"}}}',
        ),
        isEmpty,
      );
    });

    test('thinking block becomes thinking', () {
      final event = parse(
        assistantLine([
          {'type': 'thinking', 'thinking': 'Let me think.', 'signature': 'x'},
        ]),
      )!;
      expect(event.kind, AgentEventKind.thinking);
      expect(event.summary, 'Let me think.');
    });

    test('thinking deltas become thinking and suppress the full block', () {
      final delta = parse(
        '{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"Hmm"}}}',
      )!;
      expect(delta.kind, AgentEventKind.thinking);
      expect(delta.summary, 'Hmm');
      expect(
        parseAll(
          assistantLine([
            {'type': 'thinking', 'thinking': 'Hmm'},
          ]),
        ),
        isEmpty,
      );
    });
  });

  group('tools', () {
    test(
      'Bash tool_use becomes toolStarted (shell) with a clipped command',
      () {
        final longCommand = 'echo ${'x' * 120}';
        final event = parse(
          toolUseLine('toolu_1', 'Bash', {'command': longCommand}),
        )!;
        expect(event.kind, AgentEventKind.toolStarted);
        expect(event.category, ToolCategory.shell);
        expect(event.summary, startsWith('Bash: echo xxxx'));
        expect(event.summary.length, 'Bash: '.length + 80);
      },
    );

    test('multi-line commands are shown on one line', () {
      final event = parse(
        toolUseLine('toolu_1', 'Bash', {'command': 'cd lib\n  && dart test'}),
      )!;
      expect(event.summary, 'Bash: cd lib && dart test');
    });

    test('Edit tool_use becomes toolStarted (edit) naming the file', () {
      final event = parse(
        toolUseLine('toolu_2', 'Edit', {
          'file_path': r'C:\work\demo\lib\a.dart',
          'old_string': 'a',
          'new_string': 'b',
        }),
      )!;
      expect(event.kind, AgentEventKind.toolStarted);
      expect(event.category, ToolCategory.edit);
      expect(event.summary, r'Edit C:\work\demo\lib\a.dart');
    });

    test('successful edit result yields toolFinished then fileChanged', () {
      parse(toolUseLine('toolu_2', 'Write', {'file_path': 'lib/new.dart'}));
      final events = parseAll(toolResultLine('toolu_2'));
      expect(events.map((e) => e.kind), [
        AgentEventKind.toolFinished,
        AgentEventKind.fileChanged,
      ]);
      expect(events[0].summary, 'done: Write lib/new.dart');
      expect(events[0].category, ToolCategory.edit);
      expect(events[1].summary, 'lib/new.dart');
    });

    test(
      'failed edit result yields toolFinished "failed" and no fileChanged',
      () {
        parse(toolUseLine('toolu_3', 'Edit', {'file_path': 'lib/a.dart'}));
        final events = parseAll(
          toolResultLine(
            'toolu_3',
            isError: true,
            content: 'String to replace not found in file.',
          ),
        );
        expect(events, hasLength(1));
        expect(events.single.kind, AgentEventKind.toolFinished);
        expect(events.single.summary, startsWith('failed'));
        expect(events.single.summary, contains('Edit lib/a.dart'));
        expect(events.single.summary, contains('not found'));
      },
    );

    test('tool_result for an unknown id still becomes toolFinished', () {
      final event = parse(toolResultLine('toolu_unknown', isError: true))!;
      expect(event.kind, AgentEventKind.toolFinished);
      expect(event.summary, startsWith('failed'));
      expect(event.category, ToolCategory.other);
    });

    test('tool_result content given as blocks is previewed on failure', () {
      parse(toolUseLine('toolu_4', 'Bash', {'command': 'false'}));
      final event = parse(
        toolResultLine(
          'toolu_4',
          isError: true,
          content: [
            {'type': 'text', 'text': 'exit 1'},
          ],
        ),
      )!;
      expect(event.summary, 'failed: Bash: false (exit 1)');
    });

    test('NotebookEdit uses notebook_path', () {
      parse(
        toolUseLine('toolu_5', 'NotebookEdit', {'notebook_path': 'n.ipynb'}),
      );
      final events = parseAll(toolResultLine('toolu_5'));
      expect(events.last.kind, AgentEventKind.fileChanged);
      expect(events.last.summary, 'n.ipynb');
    });

    test('categories follow the vendor tool names', () {
      expect(ClaudeStreamParser.categoryFor('Read'), ToolCategory.read);
      expect(ClaudeStreamParser.categoryFor('Grep'), ToolCategory.read);
      expect(ClaudeStreamParser.categoryFor('Glob'), ToolCategory.read);
      expect(ClaudeStreamParser.categoryFor('LS'), ToolCategory.read);
      expect(ClaudeStreamParser.categoryFor('WebFetch'), ToolCategory.browser);
      expect(ClaudeStreamParser.categoryFor('WebSearch'), ToolCategory.browser);
      expect(ClaudeStreamParser.categoryFor('MultiEdit'), ToolCategory.edit);
      expect(ClaudeStreamParser.categoryFor('PowerShell'), ToolCategory.shell);
      expect(
        ClaudeStreamParser.categoryFor('mcp__office__plan_submit'),
        ToolCategory.mcp,
      );
      expect(
        ClaudeStreamParser.categoryFor('mcp__chrome-devtools__take_snapshot'),
        ToolCategory.browser,
      );
      expect(
        ClaudeStreamParser.categoryFor('mcp__playwright__browser_click'),
        ToolCategory.browser,
      );
      expect(ClaudeStreamParser.categoryFor('Agent'), ToolCategory.other);
      expect(
        ClaudeStreamParser.categoryFor('SomethingNew'),
        ToolCategory.other,
      );
    });

    test('summaries name what the tool touches', () {
      expect(
        ClaudeStreamParser.toolSummary('Read', {'file_path': 'lib/a.dart'}),
        'Read lib/a.dart',
      );
      expect(
        ClaudeStreamParser.toolSummary('Grep', {
          'pattern': 'TODO',
          'path': 'lib',
        }),
        'Grep TODO in lib',
      );
      expect(
        ClaudeStreamParser.toolSummary('Glob', {'pattern': '**/*.dart'}),
        'Glob **/*.dart',
      );
      expect(
        ClaudeStreamParser.toolSummary('WebFetch', {'url': 'https://x.test/a'}),
        'WebFetch https://x.test/a',
      );
      expect(
        ClaudeStreamParser.toolSummary('WebSearch', {'query': 'dart ffi'}),
        'WebSearch: dart ffi',
      );
      expect(
        ClaudeStreamParser.toolSummary('mcp__office__plan_submit', {
          'plan': 'x',
        }),
        'MCP office/plan_submit',
      );
      expect(
        ClaudeStreamParser.toolSummary('Mystery', {
          'count': 3,
          'target': 'abc',
        }),
        'Mystery: abc',
      );
      expect(
        ClaudeStreamParser.toolSummary('Mystery', {'count': 3}),
        'Mystery',
      );
    });

    test('mcp tool_use becomes toolStarted (mcp)', () {
      final event = parse(
        toolUseLine('toolu_6', 'mcp__office__plan_submit', {'plan': '...'}),
      )!;
      expect(event.kind, AgentEventKind.toolStarted);
      expect(event.category, ToolCategory.mcp);
      expect(event.summary, 'MCP office/plan_submit');
    });

    test('AskUserQuestion becomes userQuestion', () {
      final event = parse(
        toolUseLine('toolu_7', 'AskUserQuestion', {
          'questions': [
            {'question': 'Which database?', 'header': 'DB'},
          ],
        }),
      )!;
      expect(event.kind, AgentEventKind.userQuestion);
      expect(event.summary, 'question: Which database?');
    });

    test('control_request can_use_tool becomes approvalRequested', () {
      final event = parse(
        jsonEncode({
          'type': 'control_request',
          'request_id': 'r1',
          'request': {
            'subtype': 'can_use_tool',
            'tool_name': 'Bash',
            'input': {'command': 'rm -rf build'},
          },
        }),
      )!;
      expect(event.kind, AgentEventKind.approvalRequested);
      expect(event.category, ToolCategory.shell);
      expect(event.summary, 'approval: Bash: rm -rf build');
    });
  });

  group('subagents', () {
    test('Agent tool_use starts a subagent and its result stops it', () {
      final started = parse(
        toolUseLine('toolu_a', 'Agent', {
          'description': 'Explore the repo',
          'prompt': 'long prompt',
        }),
      )!;
      expect(started.kind, AgentEventKind.subagentStarted);
      expect(started.summary, 'subagent: Explore the repo');

      // Output from inside the subagent carries parent_tool_use_id; the
      // subagent is already known, so no second start is announced.
      final inner = parseAll(
        toolUseLine('toolu_b', 'Read', {
          'file_path': 'README.md',
        }, parent: 'toolu_a'),
      );
      expect(inner.map((e) => e.kind), [AgentEventKind.toolStarted]);
      expect(inner.single.raw['parent_tool_use_id'], 'toolu_a');

      final stopped = parseAll(toolResultLine('toolu_a', content: 'summary'));
      expect(stopped.map((e) => e.kind), [AgentEventKind.subagentStopped]);
      expect(stopped.single.summary, 'subagent done');
    });

    test('Task is treated like Agent', () {
      final event = parse(
        toolUseLine('toolu_t', 'Task', {'subagent_type': 'x'}),
      )!;
      expect(event.kind, AgentEventKind.subagentStarted);
    });

    test('an unseen parent_tool_use_id announces the subagent once', () {
      final first = parseAll(
        assistantLine([
          {'type': 'text', 'text': 'inside'},
        ], parent: 'toolu_p'),
      );
      expect(first.map((e) => e.kind), [
        AgentEventKind.subagentStarted,
        AgentEventKind.textDelta,
      ]);
      expect(first.first.summary, 'subagent toolu_p');

      final second = parseAll(
        toolUseLine('toolu_q', 'Bash', {'command': 'ls'}, parent: 'toolu_p'),
      );
      expect(second.map((e) => e.kind), [AgentEventKind.toolStarted]);

      final stop = parseAll(toolResultLine('toolu_p', isError: true));
      expect(stop.single.kind, AgentEventKind.subagentStopped);
      expect(stop.single.summary, 'subagent failed');
    });
  });

  group('rate limit and result', () {
    test(
      'rate_limit_event becomes rateLimit with the status in the summary',
      () {
        final line = fixtureLines(
          'claude_pong.jsonl',
        ).firstWhere((l) => l.contains('"rate_limit_event"'));
        final event = parse(line)!;
        expect(event.kind, AgentEventKind.rateLimit);
        expect(event.summary, contains('allowed_warning'));
        expect(event.summary, contains('seven_day'));
        expect(event.summary, contains('86% used'));
        expect(event.summary, contains('resets 2026-10-29T00:00:00.000Z'));
      },
    );

    test('rate_limit_event with sparse info still parses', () {
      final event = parse(
        '{"type":"rate_limit_event","rate_limit_info":{"status":"rejected"}}',
      )!;
      expect(event.kind, AgentEventKind.rateLimit);
      expect(event.summary, 'rate limit rejected');
    });

    test(
      'successful result becomes turnCompleted with summed input tokens',
      () {
        final event = parse(resultLine())!;
        expect(event.kind, AgentEventKind.turnCompleted);
        expect(event.summary, 'pong');
        expect(event.inputTokens, 1110);
        expect(event.outputTokens, 7);
        expect(event.sessionRef, _session);
      },
    );

    test('resultFrom builds a successful AgentResult', () {
      final result = parser.resultFrom(
        jsonDecode(resultLine()) as Map<String, Object?>,
      );
      expect(result.success, isTrue);
      expect(result.text, 'pong');
      expect(result.sessionRef, _session);
      expect(result.inputTokens, 1110);
      expect(result.outputTokens, 7);
      expect(result.error, isNull);
    });

    test('error_max_turns becomes turnFailed with the subtype as error', () {
      final line = resultLine(
        subtype: 'error_max_turns',
        isError: true,
        result: '',
      );
      final event = parse(line)!;
      expect(event.kind, AgentEventKind.turnFailed);
      expect(event.summary, 'error_max_turns');
      final result = parser.resultFrom(
        jsonDecode(line) as Map<String, Object?>,
      );
      expect(result.success, isFalse);
      expect(result.error, 'error_max_turns');
    });

    test('error_during_execution carries the errors list', () {
      final result = parser.resultFrom(
        jsonDecode(
              resultLine(
                subtype: 'error_during_execution',
                isError: true,
                result: '',
                errors: ['boom', 'bang'],
              ),
            )
            as Map<String, Object?>,
      );
      expect(result.success, isFalse);
      expect(result.error, 'error_during_execution: boom; bang');
    });

    test('result without usage has null tokens', () {
      final result = parser.resultFrom({
        'type': 'result',
        'subtype': 'success',
        'is_error': false,
        'result': 'x',
      });
      expect(result.success, isTrue);
      expect(result.inputTokens, isNull);
      expect(result.outputTokens, isNull);
    });
  });

  group('robustness', () {
    test('malformed JSON becomes unknown with the raw line as summary', () {
      const bad = '{"type":"assistant", "message":';
      final event = parse(bad)!;
      expect(event.kind, AgentEventKind.unknown);
      expect(event.summary, bad);
      expect(event.raw['line'], bad);
    });

    test('non-object JSON becomes unknown', () {
      expect(parse('42')!.kind, AgentEventKind.unknown);
      expect(parse('[1,2]')!.kind, AgentEventKind.unknown);
      expect(parse('"str"')!.kind, AgentEventKind.unknown);
    });

    test('blank lines produce nothing', () {
      expect(parse(''), isNull);
      expect(parse('   \r'), isNull);
    });

    test('unknown top-level types become unknown', () {
      final event = parse(
        '{"type":"autocompact_state","value":{"enabled":true},"session_id":"s"}',
      )!;
      expect(event.kind, AgentEventKind.unknown);
      expect(event.summary, 'autocompact_state');
      expect(event.sessionRef, 's');
      expect(parse('{"no":"type"}')!.kind, AgentEventKind.unknown);
    });

    test('messages with odd content shapes never throw', () {
      expect(
        parseAll('{"type":"assistant","message":{"content":"plain"}}'),
        isEmpty,
      );
      final user = parseAll('{"type":"user","message":{"content":"typed"}}');
      expect(user.single.kind, AgentEventKind.unknown);
      expect(user.single.summary, 'user: typed');
      expect(parseAll('{"type":"assistant"}'), isEmpty);
      expect(
        parseAll('{"type":"user","message":{"content":[7,null]}}'),
        isEmpty,
      );
      final odd = parseAll(
        '{"type":"assistant","message":{"content":[{"type":"redacted_thinking"}]}}',
      );
      expect(odd.single.kind, AgentEventKind.unknown);
    });
  });

  group('fixtures', () {
    test('claude_pong.jsonl plays through as one coherent turn', () {
      final events = [
        for (final line in fixtureLines('claude_pong.jsonl')) ...parseAll(line),
      ];
      final kinds = events.map((e) => e.kind).toList();
      expect(kinds, [
        AgentEventKind.sessionStarted,
        AgentEventKind.textDelta, // "I'll run the "
        AgentEventKind.textDelta, // "tests first."
        AgentEventKind.toolStarted, // Bash
        AgentEventKind.toolFinished, // failed
        AgentEventKind.toolStarted, // Edit
        AgentEventKind.toolFinished,
        AgentEventKind.fileChanged,
        AgentEventKind.textDelta, // "pong" delta; the text block is skipped
        AgentEventKind.rateLimit,
        AgentEventKind.turnCompleted,
      ]);
      final text = events
          .where((e) => e.kind == AgentEventKind.textDelta)
          .map((e) => e.summary)
          .join();
      expect(text, "I'll run the tests first.pong");
      expect(events[3].summary, 'Bash: dart test test/a_test.dart');
      expect(events[4].summary, startsWith('failed: Bash: dart test'));
      expect(events[5].summary, r'Edit C:\work\demo\lib\a.dart');
      expect(events[7].summary, r'C:\work\demo\lib\a.dart');
      expect(events.last.inputTokens, 12 + 1200 + 34000);
      expect(events.last.outputTokens, 48);
      expect(events.every((e) => e.sessionRef == _session), isTrue);
    });

    test('claude_killed.jsonl has a session but no turn end', () {
      final events = [
        for (final line in fixtureLines('claude_killed.jsonl'))
          ...parseAll(line),
      ];
      expect(events.map((e) => e.kind), [
        AgentEventKind.sessionStarted,
        AgentEventKind.textDelta,
      ]);
    });

    test(
      'claude_real_pong.jsonl (genuine capture) parses without surprises',
      () {
        final events = [
          for (final line in fixtureLines('claude_real_pong.jsonl'))
            ...parseAll(line),
        ];
        final kinds = events.map((e) => e.kind).toList();
        expect(
          kinds.where((k) => k == AgentEventKind.sessionStarted),
          hasLength(1),
        );
        expect(
          kinds.where((k) => k == AgentEventKind.turnCompleted),
          hasLength(1),
        );
        expect(kinds, contains(AgentEventKind.rateLimit));
        expect(kinds, contains(AgentEventKind.textDelta));
        // hook_started/hook_response/ui_invalidate/active_goal/autocompact_state
        expect(kinds.where((k) => k == AgentEventKind.unknown).length, 7);
        final init = events.firstWhere(
          (e) => e.kind == AgentEventKind.sessionStarted,
        );
        expect(init.sessionRef, '9d4af3e7-0338-5acf-a174-3cdfdb654f1c');
        expect(init.raw['apiKeySource'], 'none');
        final done = events.last;
        expect(done.kind, AgentEventKind.turnCompleted);
        expect(done.summary, 'pong');
        expect(done.inputTokens, 2 + 34623);
        expect(done.outputTokens, 4);
        expect(
          events.every((e) => e.sessionRef == init.sessionRef),
          isTrue,
          reason: 'every line of a real session carries session_id',
        );
      },
    );
  });
}
