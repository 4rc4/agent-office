import 'dart:convert';

import 'package:office_core/office_core.dart';
import 'package:test/test.dart';

Map<String, Object?> taskJson(
  String id, {
  String assignee = 'codex',
  String prompt = 'Do the thing in lib/a.dart and run dart test.',
  String? title = 'A title',
  List<String> dependsOn = const [],
}) => {
  'id': id,
  'title': ?title,
  'assignee': assignee,
  'prompt': prompt,
  'depends_on': dependsOn,
};

String fenced(Object plan, {String lang = 'json'}) =>
    '```$lang\n${const JsonEncoder.withIndent('  ').convert(plan)}\n```';

const _reply = '''
I looked at the repository. The settings screen already has a toggle row
widget, so the work splits into an implementation task and a test task.

```json
{
  "tasks": [
    {
      "id": "t1",
      "title": "Add dark mode toggle",
      "assignee": "codex",
      "prompt": "In lib/settings/settings_screen.dart add a 'Dark mode' toggle row. Verify with `flutter analyze`.",
      "depends_on": []
    },
    {
      "id": "t2",
      "title": "Widget test for toggle",
      "assignee": "claude",
      "prompt": "Write test/settings/dark_mode_toggle_test.dart covering the new toggle. Run it with --timeout 60s.",
      "depends_on": ["t1"]
    }
  ],
  "merge_instructions": "Run flutter analyze and the new widget test, then check the toggle at 360x680."
}
```
''';

void main() {
  group('happy path', () {
    test('prose plus one json block yields the tasks in plan order', () {
      final result = PlanParser.parse(_reply);
      expect(result.isError, isFalse, reason: result.error);
      final tasks = result.tasks!;
      expect(tasks, hasLength(2));
      expect(tasks[0].id, 't1');
      expect(tasks[0].title, 'Add dark mode toggle');
      expect(tasks[0].assignee, Seat.gpt);
      expect(tasks[0].prompt, startsWith('In lib/settings/'));
      expect(tasks[0].dependsOn, isEmpty);
      expect(tasks[1].id, 't2');
      expect(tasks[1].assignee, Seat.claude);
      expect(tasks[1].dependsOn, ['t1']);
      expect(
        result.mergeInstructions,
        'Run flutter analyze and the new widget test, then check the toggle '
        'at 360x680.',
      );
    });

    test('the LAST json block wins when the template is quoted first', () {
      final text =
          'The template is:\n'
          '${fenced({
            'tasks': [taskJson('template')],
          })}\n'
          'And my plan:\n'
          '${fenced({
            'tasks': [taskJson('real', assignee: 'gpt')],
          })}\n'
          'Done.';
      final result = PlanParser.parse(text);
      expect(result.isError, isFalse, reason: result.error);
      expect(result.tasks!.single.id, 'real');
      expect(result.tasks!.single.assignee, Seat.gpt);
      expect(result.mergeInstructions, isNull);
    });

    test('a bare JSON object with no fence is accepted', () {
      final result = PlanParser.parse(
        jsonEncode({
          'tasks': [taskJson('t1', assignee: 'claude')],
          'merge_instructions': 'Run the tests.',
        }),
      );
      expect(result.isError, isFalse, reason: result.error);
      expect(result.tasks!.single.assignee, Seat.claude);
      expect(result.mergeInstructions, 'Run the tests.');
    });

    test('a fence without a language tag is used when it holds an object', () {
      final result = PlanParser.parse(
        'Plan:\n${fenced({
          'tasks': [taskJson('t1')],
        }, lang: '')}',
      );
      expect(result.isError, isFalse, reason: result.error);
      expect(result.tasks!.single.id, 't1');
    });

    test('fence tags are case-insensitive and CRLF text is fine', () {
      final text =
          'Here:\r\n```JSON\r\n{"tasks":[${jsonEncode(taskJson('t1'))}]}'
          '\r\n```\r\n';
      final result = PlanParser.parse(text);
      expect(result.isError, isFalse, reason: result.error);
      expect(result.tasks!.single.id, 't1');
    });

    test('assignee spellings are tolerant', () {
      for (final name in ['codex', 'GPT', ' OpenAI ']) {
        expect(PlannedTask.parseAssignee(name), Seat.gpt, reason: name);
      }
      for (final name in ['claude', 'Claude', 'anthropic']) {
        expect(PlannedTask.parseAssignee(name), Seat.claude, reason: name);
      }
      expect(PlannedTask.parseAssignee('gemini'), Seat.gemini);
      expect(PlannedTask.parseAssignee('agy'), Seat.gemini);
      expect(PlannedTask.parseAssignee('copilot'), isNull);
      expect(PlannedTask.parseAssignee(null), isNull);
      expect(PlannedTask.assigneeName(Seat.gpt), 'codex');
      expect(PlannedTask.assigneeName(Seat.claude), 'claude');
    });

    test('a missing title is derived from the prompt', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [
            taskJson(
              't1',
              title: null,
              prompt:
                  'Rename   the widget in lib/a.dart to FooBar and update '
                  'every call site, then run flutter analyze until clean.',
            ),
          ],
        }),
      );
      expect(result.isError, isFalse, reason: result.error);
      final title = result.tasks!.single.title;
      expect(title, startsWith('Rename the widget in lib/a.dart to FooBar'));
      expect(title, endsWith('...'));
      expect(title.length, lessThanOrEqualTo(63));
    });

    test('dependsOn in camelCase and duplicate entries are tolerated', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [
            taskJson('t1'),
            {
              'id': 't2',
              'title': 'x',
              'assignee': 'claude',
              'prompt': 'y',
              'dependsOn': ['t1', 't1'],
            },
          ],
        }),
      );
      expect(result.isError, isFalse, reason: result.error);
      expect(result.tasks![1].dependsOn, ['t1']);
    });

    test('maxTasks and allowedAssignees can be widened', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [
            taskJson('a'),
            taskJson('b'),
            taskJson('c'),
            taskJson('d', assignee: 'gemini'),
          ],
        }),
        maxTasks: 4,
        allowedAssignees: {Seat.gpt, Seat.claude, Seat.gemini},
      );
      expect(result.isError, isFalse, reason: result.error);
      expect(result.tasks, hasLength(4));
      expect(result.tasks!.last.assignee, Seat.gemini);
    });

    test('toJson round-trips through parse', () {
      final task = const PlannedTask(
        id: 't1',
        title: 'T',
        assignee: Seat.gpt,
        prompt: 'P',
        dependsOn: ['t0'],
      );
      expect(task.toJson(), {
        'id': 't1',
        'title': 'T',
        'assignee': 'codex',
        'prompt': 'P',
        'depends_on': ['t0'],
      });
      expect(task.toString(), 'PlannedTask(t1 "T" -> codex, after t0)');
    });
  });

  group('errors', () {
    test('a reply without any json is rejected with guidance', () {
      final result = PlanParser.parse('I would split this into two tasks.');
      expect(result.isError, isTrue);
      expect(result.tasks, isNull);
      expect(result.error, contains('no ```json block'));
      expect(result.error, contains('exactly one fenced json block'));
    });

    test('a fence with broken JSON names the syntax problem', () {
      final result = PlanParser.parse('```json\n{"tasks": [}\n```');
      expect(result.isError, isTrue);
      expect(result.error, startsWith('the json block is not valid JSON'));
    });

    test('a json block that is not an object is rejected', () {
      final result = PlanParser.parse('```json\n[1, 2]\n```');
      expect(result.error, contains('must be an object'));
    });

    test('tasks missing, not an array, or empty', () {
      expect(
        PlanParser.parse('```json\n{"plan": 1}\n```').error,
        contains('"tasks" must be a non-empty array'),
      );
      expect(
        PlanParser.parse('```json\n{"tasks": "t1"}\n```').error,
        contains('"tasks" must be a non-empty array'),
      );
      expect(
        PlanParser.parse('```json\n{"tasks": []}\n```').error,
        contains('"tasks" is empty'),
      );
    });

    test('a bad assignee is named with the allowed choices', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [taskJson('t1', assignee: 'copilot')],
        }),
      );
      expect(result.isError, isTrue);
      expect(
        result.error,
        '1 problem: tasks[0] ("t1"): unknown assignee "copilot"; '
        'use "codex" or "claude"',
      );
    });

    test('a known but unavailable seat gets a different hint', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [taskJson('t1', assignee: 'gemini')],
        }),
      );
      expect(result.error, contains('"gemini" is not available'));
      expect(result.error, contains('use "codex" or "claude"'));
    });

    test('a missing assignee is reported', () {
      final result = PlanParser.parse(
        '```json\n{"tasks":[{"id":"t1","prompt":"p"}]}\n```',
      );
      expect(result.error, contains('tasks[0] ("t1"): assignee is missing'));
    });

    test('an unknown dependency is reported with the id', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [
            taskJson('t1', dependsOn: ['t9']),
          ],
        }),
      );
      expect(result.isError, isTrue);
      expect(
        result.error,
        '1 problem: tasks[0] ("t1"): depends_on references unknown id "t9"',
      );
    });

    test('a cycle is reported as the loop of ids', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [
            taskJson('t1', dependsOn: ['t2']),
            taskJson('t2', dependsOn: ['t3']),
            taskJson('t3', dependsOn: ['t1']),
          ],
        }),
      );
      expect(result.isError, isTrue);
      expect(result.error, '1 problem: dependency cycle: t1 -> t2 -> t3 -> t1');
    });

    test('a self dependency is its own problem, not a cycle', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [
            taskJson('t1', dependsOn: ['t1']),
          ],
        }),
      );
      expect(result.error, '1 problem: tasks[0] ("t1"): depends on itself');
    });

    test('too many tasks', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [taskJson('a'), taskJson('b'), taskJson('c'), taskJson('d')],
        }),
      );
      expect(result.isError, isTrue);
      expect(result.error, '1 problem: too many tasks: 4 (at most 3)');
      expect(
        PlanParser.parse(
          fenced({
            'tasks': [taskJson('a'), taskJson('b')],
          }),
          maxTasks: 1,
        ).error,
        contains('too many tasks: 2 (at most 1)'),
      );
    });

    test('duplicate, missing and empty ids', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [
            taskJson('t1'),
            taskJson('t1'),
            {'title': 'no id', 'assignee': 'codex', 'prompt': 'p'},
          ],
        }),
      );
      expect(result.error, contains('tasks[1] ("t1"): duplicate id "t1"'));
      expect(result.error, contains('tasks[2]: id is missing or empty'));
      expect(
        PlanParser.parse(
          fenced({
            'tasks': [taskJson('  ')],
          }),
        ).error,
        contains('tasks[0]: id is missing or empty'),
      );
    });

    test('an empty prompt and odd depends_on shapes', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [
            taskJson('t1', prompt: '   '),
            {
              'id': 't2',
              'title': 'x',
              'assignee': 'claude',
              'prompt': 'y',
              'depends_on': 't1',
            },
            {
              'id': 't3',
              'title': 'x',
              'assignee': 'claude',
              'prompt': 'y',
              'depends_on': [3, 't1'],
            },
          ],
        }),
      );
      expect(result.error, startsWith('3 problems: '));
      expect(
        result.error,
        contains('tasks[0] ("t1"): prompt is missing or empty'),
      );
      expect(
        result.error,
        contains('tasks[1] ("t2"): depends_on must be an array of task ids'),
      );
      expect(
        result.error,
        contains('tasks[2] ("t3"): depends_on contains a non-id value "3"'),
      );
    });

    test('a task entry that is not an object is reported', () {
      final result = PlanParser.parse('```json\n{"tasks":[7]}\n```');
      expect(result.error, '1 problem: tasks[0] is not an object');
    });

    test('every problem is listed at once so one retry can fix them all', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [
            taskJson('t1', assignee: 'copilot', dependsOn: ['nope']),
            taskJson('t1', prompt: ''),
            taskJson('t3'),
            taskJson('t4'),
          ],
        }),
      );
      expect(result.isError, isTrue);
      final error = result.error!;
      expect(error, startsWith('5 problems: '));
      expect(error, contains('too many tasks: 4 (at most 3)'));
      expect(error, contains('tasks[1] ("t1"): duplicate id "t1"'));
      expect(error, contains('tasks[0] ("t1"): unknown assignee "copilot"'));
      expect(error, contains('depends_on references unknown id "nope"'));
      expect(error, contains('tasks[1] ("t1"): prompt is missing or empty'));
    });

    test('merge_instructions that is not a string is ignored', () {
      final result = PlanParser.parse(
        fenced({
          'tasks': [taskJson('t1')],
          'merge_instructions': ['a', 'b'],
        }),
      );
      expect(result.isError, isFalse, reason: result.error);
      expect(result.mergeInstructions, isNull);
    });

    test('nothing throws on hostile input', () {
      for (final text in [
        '',
        '```json\n\n```',
        '{',
        '```json\n{"tasks":null}\n```',
        '{"tasks":[{"id":null,"assignee":1,"prompt":2,"depends_on":{}}]}',
      ]) {
        final result = PlanParser.parse(text);
        expect(result.isError, isTrue, reason: text);
      }
    });
  });

  group('topologicalOrder', () {
    PlannedTask planned(String id, [List<String> deps = const []]) =>
        PlannedTask(
          id: id,
          title: id,
          assignee: Seat.gpt,
          prompt: id,
          dependsOn: deps,
        );

    test('dependencies come first, plan order otherwise', () {
      final ordered = PlanParser.topologicalOrder([
        planned('review', ['impl', 'test']),
        planned('test', ['impl']),
        planned('impl'),
        planned('docs'),
      ]);
      expect(ordered.map((t) => t.id), ['impl', 'test', 'review', 'docs']);
    });

    test('independent tasks keep their order', () {
      final ordered = PlanParser.topologicalOrder([
        planned('a'),
        planned('b'),
        planned('c'),
      ]);
      expect(ordered.map((t) => t.id), ['a', 'b', 'c']);
      expect(PlanParser.topologicalOrder(const []), isEmpty);
    });

    test('the parsed sample orders the test after the implementation', () {
      final tasks = PlanParser.parse(_reply).tasks!;
      expect(
        PlanParser.topologicalOrder(tasks.reversed.toList()).map((t) => t.id),
        ['t1', 't2'],
      );
    });

    test('cycles and unknown dependencies throw ArgumentError', () {
      expect(
        () => PlanParser.topologicalOrder([
          planned('a', ['b']),
          planned('b', ['a']),
        ]),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            'dependency cycle among a, b',
          ),
        ),
      );
      expect(
        () => PlanParser.topologicalOrder([
          planned('a', ['zzz']),
        ]),
        throwsArgumentError,
      );
    });
  });
}
