import 'package:sqlite3/sqlite3.dart';

/// Version written to `schema_version` by [applySchema].
const int schemaVersion = 2;

/// Maximum rows kept in `events`; the oldest rows are trimmed on every insert.
const int eventRingSize = 5000;

/// DDL for every table, in creation order. Every statement is idempotent so
/// [applySchema] can run on each open.
///
/// Timestamps are ISO-8601 UTC strings; `depends_on` and `launch_args` are
/// JSON arrays; `raw` and `payload` are JSON objects.
const List<String> schemaStatements = [
  '''
CREATE TABLE IF NOT EXISTS schema_version (
  version INTEGER NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS tasks (
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
  updated_at TEXT NOT NULL,
  options TEXT NOT NULL DEFAULT '{}'
)''',
  'CREATE INDEX IF NOT EXISTS tasks_root_idx ON tasks(root_id)',
  'CREATE INDEX IF NOT EXISTS tasks_status_idx ON tasks(status)',
  '''
CREATE TABLE IF NOT EXISTS sessions (
  task_id TEXT PRIMARY KEY,
  seat TEXT NOT NULL,
  session_ref TEXT NOT NULL,
  launch_args TEXT NOT NULL DEFAULT '[]',
  turn_state TEXT NOT NULL,
  updated_at TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT,
  seat TEXT,
  kind TEXT NOT NULL,
  category TEXT,
  summary TEXT NOT NULL,
  raw TEXT NOT NULL DEFAULT '{}',
  created_at TEXT NOT NULL
)''',
  'CREATE INDEX IF NOT EXISTS events_task_idx ON events(task_id)',
  '''
CREATE TABLE IF NOT EXISTS interactions (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  task_id TEXT NOT NULL,
  seat TEXT NOT NULL,
  kind TEXT NOT NULL,
  payload TEXT NOT NULL DEFAULT '{}',
  status TEXT NOT NULL DEFAULT 'pending',
  answer TEXT,
  created_at TEXT NOT NULL
)''',
  '''
CREATE TABLE IF NOT EXISTS usage_snapshots (
  seat TEXT NOT NULL,
  window TEXT NOT NULL,
  used_pct REAL NOT NULL,
  resets_at TEXT,
  source TEXT NOT NULL,
  fetched_at TEXT NOT NULL,
  PRIMARY KEY (seat, window)
)''',
  '''
CREATE TABLE IF NOT EXISTS xp (
  seat TEXT PRIMARY KEY,
  points INTEGER NOT NULL DEFAULT 0,
  updated_at TEXT NOT NULL
)''',
];

/// Switches [db] to WAL journaling (a no-op for in-memory databases), creates
/// any missing table and records [schemaVersion].
///
/// Future schema changes go here as `if (current < n)` migration steps.
void applySchema(Database db) {
  db.execute('PRAGMA journal_mode=WAL');
  db.execute('PRAGMA foreign_keys=ON');
  for (final statement in schemaStatements) {
    db.execute(statement);
  }
  // v2: per-root run options (a v1 board has no such column).
  if (!_hasColumn(db, 'tasks', 'options')) {
    db.execute(
      "ALTER TABLE tasks ADD COLUMN options TEXT NOT NULL DEFAULT '{}'",
    );
  }
  final rows = db.select('SELECT version FROM schema_version LIMIT 1');
  if (rows.isEmpty) {
    db.execute('INSERT INTO schema_version (version) VALUES (?)', [
      schemaVersion,
    ]);
  } else if ((rows.first['version'] as int) < schemaVersion) {
    db.execute('UPDATE schema_version SET version = ?', [schemaVersion]);
  }
}

bool _hasColumn(Database db, String table, String column) {
  for (final row in db.select('PRAGMA table_info($table)')) {
    if (row['name'] == column) return true;
  }
  return false;
}
