import 'dart:async';
import 'dart:io';

import '../board/schema.dart';
import '../board/task_board.dart';
import '../model/agent_event.dart';
import '../model/task.dart';
import 'office_wiring.dart';
import 'sqlite_windows.dart';

/// Usage text of the `office_core` command.
const String cliUsage = '''
Agent Office core CLI

  office_core run "<prompt>" [--cwd <dir>] [--db <file>] [--claude <exe>]
      [--codex <exe>] [--brain <file>] [--mcp-config <file>]
      [--permission-mode <mode>] [--fake] [--fixtures <dir>]
  office_core ask <claude|gpt> "<prompt>" [same options]
      One desk alone: no planning, no merge; the agent's answer is the report.
  office_core reconcile [--cwd <dir>] [--db <file>] [--claude <exe>]
      [--codex <exe>] [--brain <file>] [--mcp-config <file>]
      [--permission-mode <mode>] [--fake] [--fixtures <dir>]
  office_core help

Options:
  --cwd              Repository the agents work in (default: current folder).
  --db               Board file (default: <cwd>/.agent_office/office.db).
  --claude, --codex  Vendor binaries (default: claude, codex on PATH).
  --brain            Claude --append-system-prompt-file (default: brain.md).
  --mcp-config       Claude --mcp-config file.
  --permission-mode  Claude --permission-mode (default: acceptEdits).
  --fake             Replay test/fixtures through FakeProcessRunner; no CLIs.
  --fixtures         Folder of the fixtures used by --fake.

Prints one line per agent event and board status change, then the report.
Exit code 0 when every root task ended done, 1 otherwise.
''';

/// Options that take a value.
const Set<String> cliValueOptions = {
  'cwd',
  'db',
  'claude',
  'codex',
  'brain',
  'mcp-config',
  'permission-mode',
  'fixtures',
};

/// Options that are switches.
const Set<String> cliFlagOptions = {'fake'};

/// A parsed command line: the command, its prompt (for `run`) and the config.
class CliInvocation {
  const CliInvocation({
    required this.command,
    required this.config,
    this.prompt,
    this.seat,
  });

  /// `run`, `ask`, `reconcile` or `help`.
  final String command;

  /// The user's request; for `run` and `ask`.
  final String? prompt;

  /// The desk to talk to; only for `ask`.
  final Seat? seat;
  final OfficeConfig config;
}

/// Parses [arguments]; throws [FormatException] with a one-line reason on
/// bad input. Accepts both `--name value` and `--name=value`.
CliInvocation parseCliArguments(List<String> arguments) {
  if (arguments.isEmpty) {
    throw const FormatException('missing command: run, ask, reconcile or help');
  }
  final command = arguments.first;
  if (command == 'help' || command == '--help' || command == '-h') {
    return CliInvocation(
      command: 'help',
      config: OfficeConfig(paths: OfficePaths(cwd: Directory.current.path)),
    );
  }
  if (command != 'run' && command != 'ask' && command != 'reconcile') {
    throw FormatException('unknown command "$command"');
  }
  var index = 1;
  String? prompt;
  Seat? seat;
  if (command == 'run') {
    if (arguments.length < 2 || arguments[1].startsWith('--')) {
      throw const FormatException('run needs a prompt as its first argument');
    }
    prompt = arguments[1];
    index = 2;
  } else if (command == 'ask') {
    if (arguments.length < 3 || arguments[2].startsWith('--')) {
      throw const FormatException(
        'ask needs a seat (claude or gpt) and then a prompt',
      );
    }
    seat = switch (arguments[1]) {
      'claude' => Seat.claude,
      'gpt' || 'codex' => Seat.gpt,
      'gemini' => Seat.gemini,
      _ => throw FormatException(
        'unknown seat "${arguments[1]}": use claude or gpt',
      ),
    };
    prompt = arguments[2];
    index = 3;
  }
  final values = <String, String>{};
  final flags = <String>{};
  for (; index < arguments.length; index++) {
    final argument = arguments[index];
    if (!argument.startsWith('--')) {
      throw FormatException('unexpected argument "$argument"');
    }
    var name = argument.substring(2);
    String? inlineValue;
    final equals = name.indexOf('=');
    if (equals >= 0) {
      inlineValue = name.substring(equals + 1);
      name = name.substring(0, equals);
    }
    if (cliFlagOptions.contains(name)) {
      if (inlineValue != null) {
        throw FormatException('--$name takes no value');
      }
      flags.add(name);
      continue;
    }
    if (!cliValueOptions.contains(name)) {
      throw FormatException('unknown option --$name');
    }
    if (inlineValue != null) {
      values[name] = inlineValue;
      continue;
    }
    if (index + 1 >= arguments.length) {
      throw FormatException('--$name needs a value');
    }
    values[name] = arguments[++index];
  }
  final cwd = values['cwd'] ?? Directory.current.path;
  return CliInvocation(
    command: command,
    prompt: prompt,
    seat: seat,
    config: OfficeConfig(
      paths: OfficePaths(cwd: cwd, dbPath: values['db']),
      claudeExecutable: values['claude'] ?? 'claude',
      codexExecutable: values['codex'] ?? 'codex',
      permissionMode: values['permission-mode'] ?? 'acceptEdits',
      brainPromptFile: values['brain'],
      mcpConfigFile: values['mcp-config'],
      fake: flags.contains('fake'),
      fixturesDir: values['fixtures'],
    ),
  );
}

/// The whole CLI: parses [arguments], runs the command, writes progress and
/// the report to [out] (errors and usage to [err]) and returns the exit code:
/// 0 when every root task is done, 1 otherwise. Never throws.
Future<int> runCli(
  List<String> arguments, {
  required StringSink out,
  required StringSink err,
}) async {
  final CliInvocation invocation;
  try {
    invocation = parseCliArguments(arguments);
  } on FormatException catch (error) {
    err
      ..writeln('office_core: ${error.message}')
      ..writeln()
      ..write(cliUsage);
    return 1;
  }
  if (invocation.command == 'help') {
    out.write(cliUsage);
    return 0;
  }
  try {
    return await runOffice(invocation, out: out);
  } on Object catch (error, stack) {
    err
      ..writeln('office_core: $error')
      ..writeln(stack);
    return 1;
  }
}

/// Builds the office for [invocation], runs or reconciles, streams every
/// event and status change to [out] as one line each, prints a report per
/// root and returns 0 when every root is done (1 otherwise). The board is
/// closed before returning.
Future<int> runOffice(
  CliInvocation invocation, {
  required StringSink out,
  TaskBoard? board,
}) async {
  final config = invocation.config;
  final sqliteDll = configureSqliteLibrary();
  if (sqliteDll != null) out.writeln('office: sqlite3 from $sqliteDll');
  final office = await buildOffice(config, board: board);
  out
    ..writeln('office: cwd ${config.paths.cwd}')
    ..writeln('office: board ${config.paths.dbPath}')
    ..writeln(
      'office: ${config.fake ? 'FAKE vendors (fixtures)' : 'claude='
                '${config.claudeExecutable} codex=${config.codexExecutable}'}',
    );
  final events = office.supervisor.events.listen(
    (event) => out.writeln(formatEvent(event)),
  );
  final changes = office.board.changes.listen(
    (task) => out.writeln(formatStatusChange(task)),
  );
  try {
    final List<TaskRecord> roots;
    if (invocation.command == 'run') {
      roots = [
        await office.supervisor.run(invocation.prompt!, config.paths.cwd),
      ];
    } else if (invocation.command == 'ask') {
      roots = [
        await office.supervisor.runDirect(
          invocation.seat!,
          invocation.prompt!,
          config.paths.cwd,
        ),
      ];
    } else {
      roots = await office.supervisor.reconcile();
      if (roots.isEmpty) out.writeln('office: nothing to reconcile');
    }
    for (final root in roots) {
      out.write(formatReport(office.board, root));
    }
    return roots.every((root) => root.status == TaskStatus.done) ? 0 : 1;
  } finally {
    await events.cancel();
    await changes.cancel();
    await office.close();
  }
}

/// One line for an agent event:
/// `HH:MM:SS task.... seat   kind/category: summary`.
String formatEvent(AgentEvent event) {
  final category = event.category == null ? '' : '/${event.category!.name}';
  final tokens = event.inputTokens == null && event.outputTokens == null
      ? ''
      : ' [in ${event.inputTokens ?? 0} out ${event.outputTokens ?? 0}]';
  return '${formatClock(event.timestamp)} ${shortTaskId(event.taskId)} '
      '${event.seat.name.padRight(6)} ${event.kind.name}$category: '
      '${oneLine(event.summary)}$tokens';
}

/// One line for a board status change.
String formatStatusChange(TaskRecord task) =>
    '${formatClock(task.updatedAt)} ${shortTaskId(task.id)} board  '
    'status ${task.kind.name} -> ${task.status.name}'
    '${task.attempt == 0 ? '' : ' (attempt ${task.attempt})'}: '
    '${oneLine(task.title, 80)}';

/// The final report for [root]: the task tree, sessions, event count and the
/// brain's markdown report (or the failure reason).
String formatReport(TaskBoard board, TaskRecord root) {
  final buffer = StringBuffer()
    ..writeln()
    ..writeln('==== Agent Office report ====')
    ..writeln('root ${root.id}: ${root.status.name} (attempt ${root.attempt})')
    ..writeln('title: ${root.title}')
    ..writeln('cwd: ${root.cwd}');
  final brainSession = board.getSession(root.id);
  if (brainSession != null) {
    buffer.writeln(
      'brain session: ${brainSession.sessionRef} '
      '(${brainSession.seat.name}, ${brainSession.turnState.name})',
    );
  }
  final subtasks = board.listSubtasks(root.id);
  buffer.writeln('subtasks: ${subtasks.length}');
  for (final task in subtasks) {
    final session = board.getSession(task.id);
    buffer.writeln(
      '  [${task.status.name}] ${shortTaskId(task.id)} '
      '${task.assignee?.name ?? 'unassigned'} attempt ${task.attempt}: '
      '${task.title}'
      '${session == null ? '' : ' (session ${session.sessionRef})'}',
    );
    final summary = task.resultSummary;
    if (summary != null && summary.isNotEmpty) {
      buffer.writeln('      ${oneLine(summary, 120)}');
    }
  }
  buffer.writeln(
    'events recorded: ${board.listEvents(limit: eventRingSize).length} '
    '(board total ${board.eventCount})',
  );
  buffer.writeln(
    'xp: ${Seat.values.map((s) => '${s.name}=${board.xpFor(s)}').join(' ')}',
  );
  if (root.status == TaskStatus.done) {
    buffer
      ..writeln()
      ..writeln('---- brain report ----')
      ..writeln((root.resultSummary ?? '').trim())
      ..writeln('---- end of report ----');
  } else {
    final reason = board.listEvents(
      taskId: root.id,
      kind: 'root_failed',
      limit: 1,
    );
    buffer.writeln(
      'failure: ${reason.isEmpty ? 'root is ${root.status.name}' : reason.first.summary}',
    );
  }
  return buffer.toString();
}

/// `HH:MM:SS` in local time.
String formatClock(DateTime time) {
  final local = time.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(local.hour)}:${two(local.minute)}:${two(local.second)}';
}

/// The first 8 characters of a task id, or dashes when there is none.
String shortTaskId(String? id) => id == null
    ? '--------'
    : (id.length <= 8 ? id.padRight(8) : id.substring(0, 8));

/// [text] on one line, whitespace collapsed, cut at [limit] characters.
String oneLine(String text, [int limit = 160]) {
  final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.length <= limit) return collapsed;
  return '${collapsed.substring(0, limit - 3)}...';
}
