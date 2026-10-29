import 'package:office_core/office_core.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

/// The v1 `tasks` table, before the `options` column existed.
const _v1Tasks = '''
CREATE TABLE tasks (
  id TEXT PRIMARY KEY,
  parent_id TEXT,
  root_id TEXT NOT NULL,
  kind TEXT NOT NULL,
  title TEXT NOT NULL,
  prompt TEXT NOT NULL,
  cwd TEXT NOT NULL,
  assignee TEXT,
  status TEXT NOT NULL,
  attempt INTEGER NOT NULL DEFAULT 0,
  dispatch_token TEXT,
  depends_on TEXT NOT NULL DEFAULT '[]',
  result_path TEXT,
  result_summary TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''';

TaskRecord taskWith(Map<String, String> options) {
  final now = DateTime.utc(2026, 10, 29, 12);
  return TaskRecord(
    id: 't1',
    rootId: 't1',
    kind: TaskKind.root,
    title: 'Fix it',
    prompt: 'Fix it.',
    cwd: r'C:\work\demo',
    status: TaskStatus.assigned,
    createdAt: now,
    updatedAt: now,
    options: options,
  );
}

void main() {
  group('task options on the board', () {
    late TaskBoard board;

    setUp(() => board = TaskBoard.inMemory());
    tearDown(() => board.close());

    test('insertRoot stores options and subtasks inherit them', () {
      final root = board.insertRoot(
        'Do it',
        r'C:\work\repo',
        options: {'model': 'opus', 'effort': 'high'},
      );
      expect(root.options, {'model': 'opus', 'effort': 'high'});
      final subtasks = board.insertSubtasks(root.id, const [
        PlannedTask(
          id: 'a',
          title: 'Part',
          assignee: Seat.gpt,
          prompt: 'Part of it',
        ),
      ]);
      expect(subtasks.single.options, {'model': 'opus', 'effort': 'high'});
      expect(board.requireTask(subtasks.single.id).options, {
        'model': 'opus',
        'effort': 'high',
      });
    });

    test('a root without options reads back an empty map', () {
      final root = board.insertRoot('Do it', r'C:\work\repo');
      expect(root.options, isEmpty);
    });

    test('applySchema adds the options column to a v1 board', () {
      final db = sqlite3.openInMemory();
      addTearDown(db.dispose);
      db.execute(_v1Tasks);
      db.execute('CREATE TABLE schema_version (version INTEGER NOT NULL)');
      db.execute('INSERT INTO schema_version (version) VALUES (1)');
      applySchema(db);
      final columns = [
        for (final row in db.select('PRAGMA table_info(tasks)'))
          row['name'] as String,
      ];
      expect(columns, contains('options'));
      expect(
        db.select('SELECT version FROM schema_version').first['version'],
        schemaVersion,
      );
      expect(schemaVersion, greaterThanOrEqualTo(2));
    });
  });

  group('adapter arguments from task options', () {
    test('claude passes --model and --effort from the options', () {
      final adapter = ClaudeAdapter(
        runner: FakeProcessRunner({}),
        executable: 'claude.cmd',
      );
      final args = adapter.buildArguments(
        sessionId: '00000000-0000-4000-8000-000000000000',
        options: {'model': 'opus', 'effort': 'high'},
      );
      expect(args, containsAllInOrder(['--model', 'opus']));
      expect(args, containsAllInOrder(['--effort', 'high']));
    });

    test('claude falls back to the adapter defaults, empty means none', () {
      final adapter = ClaudeAdapter(
        runner: FakeProcessRunner({}),
        executable: 'claude.cmd',
        model: 'sonnet',
      );
      final defaults = adapter.buildArguments(
        sessionId: '00000000-0000-4000-8000-000000000000',
        options: {'model': '', 'effort': ''},
      );
      expect(defaults, containsAllInOrder(['--model', 'sonnet']));
      expect(defaults, isNot(contains('--effort')));
      final bare = ClaudeAdapter(
        runner: FakeProcessRunner({}),
        executable: 'claude.cmd',
      ).buildArguments(sessionId: '00000000-0000-4000-8000-000000000000');
      expect(bare, isNot(contains('--model')));
    });

    test('codex passes -m and the reasoning effort override', () {
      final adapter = CodexAdapter(
        runner: FakeProcessRunner({}),
        executable: 'codex.cmd',
      );
      final args = adapter.buildArguments(
        prompt: 'hi',
        cwd: r'C:\work\demo',
        taskId: 't1',
        options: {'model': 'gpt-5.1', 'effort': 'low'},
      );
      expect(args, containsAllInOrder(['-m', 'gpt-5.1']));
      expect(args, containsAllInOrder(['-c', 'model_reasoning_effort="low"']));
      expect(args.last, 'hi');
    });

    test('codex uses the adapter defaults when the task has none', () {
      final adapter = CodexAdapter(
        runner: FakeProcessRunner({}),
        executable: 'codex.cmd',
        model: 'gpt-5-codex-mini',
        reasoningEffort: 'medium',
      );
      final args = adapter.buildArguments(
        prompt: 'hi',
        cwd: r'C:\work\demo',
        taskId: 't1',
      );
      expect(args, containsAllInOrder(['-m', 'gpt-5-codex-mini']));
      expect(
        args,
        containsAllInOrder(['-c', 'model_reasoning_effort="medium"']),
      );
    });
  });

  test('TaskRecord.copyWith keeps the options', () {
    final task = taskWith({'model': 'opus'});
    expect(task.copyWith(status: TaskStatus.running).options, {
      'model': 'opus',
    });
  });
}
