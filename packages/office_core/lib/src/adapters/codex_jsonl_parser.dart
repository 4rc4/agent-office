import 'dart:convert';

import '../model/agent_event.dart';
import '../model/task.dart';

/// Translates `codex exec --json` output (one JSON object per line) into
/// vendor-neutral [AgentEvent]s.
///
/// Use one parser per Codex process. It keeps a little state so that:
///
/// * the `thread_id` from `thread.started` is stamped on every later event
///   (Codex lines do not repeat it) and exposed as [threadId],
/// * streamed `agent_message` / `reasoning` text is emitted once, whichever
///   of `item.updated` deltas or the final `item.completed` carries it,
/// * a tool item's `item.completed` can name what started it,
/// * the last `agent_message` text ([lastAgentMessage]), the failure message
///   ([failureMessage]) and the token usage are available to the adapter for
///   its [AgentResult].
///
/// The parser never throws on bad input: a line that is not a JSON object
/// becomes an [AgentEventKind.unknown] event whose summary is the raw line.
/// Unknown event types, item types and fields are tolerated; every event
/// keeps the decoded object in [AgentEvent.raw].
class CodexJsonlParser {
  CodexJsonlParser();

  /// Longest summary fragment, e.g. the command shown after `codex: `.
  static const int summaryLimit = 80;

  /// MCP server names containing one of these are shown as browser work.
  static const List<String> browserServerHints = [
    'chrome',
    'playwright',
    'browser',
  ];

  final Map<String, _OpenItem> _openItems = {};
  final Map<String, String> _streamedText = {};
  String? _threadId;
  String? _lastAgentMessage;
  String? _failureMessage;
  bool _turnCompleted = false;
  int? _inputTokens;
  int? _outputTokens;

  /// The Codex thread id, once `thread.started` has been seen.
  String? get threadId => _threadId;

  /// Text of the last completed `agent_message` item, if any.
  String? get lastAgentMessage => _lastAgentMessage;

  /// The `turn.failed` / `error` message, if one was seen.
  String? get failureMessage => _failureMessage;

  /// Whether a `turn.failed` or top-level `error` event was seen.
  bool get turnFailed => _failureMessage != null;

  /// Whether `turn.completed` was seen.
  bool get turnCompleted => _turnCompleted;

  /// `usage.input_tokens` of the last `turn.completed`. Codex counts cached
  /// tokens inside `input_tokens`, so this already includes them.
  int? get inputTokens => _inputTokens;

  /// `usage.output_tokens` of the last `turn.completed`.
  int? get outputTokens => _outputTokens;

  /// Parses one stdout line and returns its first event, or null when the
  /// line carries nothing worth reporting (blank line, streaming noise).
  ///
  /// A `file_change` item yields one event per changed path and a lone
  /// `item.completed` of a tool yields a start and a finish, so adapters
  /// should use [parseLineAll] to keep every event.
  AgentEvent? parseLine(String line, {required Seat seat, String? taskId}) {
    final events = parseLineAll(line, seat: seat, taskId: taskId);
    return events.isEmpty ? null : events.first;
  }

  /// Parses one stdout line into zero or more events, in order.
  List<AgentEvent> parseLineAll(
    String line, {
    required Seat seat,
    String? taskId,
  }) {
    final trimmed = line.trim();
    if (trimmed.isEmpty) return const [];
    Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException {
      decoded = null;
    }
    if (decoded is! Map) {
      return [
        AgentEvent(
          seat: seat,
          taskId: taskId,
          kind: AgentEventKind.unknown,
          summary: trimmed,
          sessionRef: _threadId,
          raw: {'line': trimmed},
        ),
      ];
    }
    final raw = Map<String, Object?>.from(decoded);
    final type = _string(raw['type']);
    if (type == 'thread.started') {
      _threadId = _string(raw['thread_id']) ?? _threadId;
    }
    final line0 = _Line(seat, taskId, _threadId, raw);
    switch (type) {
      case 'thread.started':
        return [
          line0.event(
            AgentEventKind.sessionStarted,
            summary: 'thread started: ${_threadId ?? 'no thread_id'}',
          ),
        ];
      case 'turn.started':
        return [line0.event(AgentEventKind.unknown, summary: 'turn started')];
      case 'item.started' || 'item.updated' || 'item.completed':
        return _item(line0, type!.substring('item.'.length));
      case 'turn.completed':
        return [_turnCompletedEvent(line0)];
      case 'turn.failed':
        final error = _map(raw['error']);
        return [_turnFailedEvent(line0, _string(error?['message']))];
      case 'error':
        return [_turnFailedEvent(line0, _string(raw['message']))];
      default:
        return [
          line0.event(
            AgentEventKind.unknown,
            summary: type ?? 'event without type',
          ),
        ];
    }
  }

  /// Vendor-neutral category of an MCP call on [server]: browser when the
  /// server name hints at one, mcp otherwise.
  static ToolCategory mcpCategory(String server) {
    final lower = server.toLowerCase();
    return browserServerHints.any(lower.contains)
        ? ToolCategory.browser
        : ToolCategory.mcp;
  }

  /// Collapses whitespace to single spaces and cuts at [limit] characters.
  static String clip(String text, [int limit = summaryLimit]) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= limit ? oneLine : oneLine.substring(0, limit);
  }

  // ----------------------------------------------------------------- items

  List<AgentEvent> _item(_Line line, String phase) {
    final item = _map(line.raw['item']);
    if (item == null) {
      return [
        line.event(AgentEventKind.unknown, summary: 'item.$phase without item'),
      ];
    }
    final type = _string(item['type']) ?? 'item';
    final id = _string(item['id']) ?? '';
    switch (type) {
      case 'agent_message':
        return _streamed(line, phase, item, id, AgentEventKind.textDelta);
      case 'reasoning':
        return _streamed(line, phase, item, id, AgentEventKind.thinking);
      case 'command_execution':
        final command = clip(_commandText(item['command']));
        return _tool(
          line,
          phase,
          id,
          summary: 'codex: $command',
          category: ToolCategory.shell,
          status: _string(item['status']),
          exitCode: _int(item['exit_code']),
        );
      case 'mcp_tool_call':
        final server = _string(item['server']) ?? 'mcp';
        final tool = _string(item['tool']) ?? 'tool';
        return _tool(
          line,
          phase,
          id,
          summary: 'MCP $server/$tool',
          category: mcpCategory(server),
          status: _string(item['status']),
        );
      case 'web_search':
        final query = clip(_string(item['query']) ?? '');
        return _tool(
          line,
          phase,
          id,
          summary: 'web search: $query',
          category: ToolCategory.browser,
          status: _string(item['status']),
        );
      case 'file_change':
        return _fileChange(line, phase, item);
      case 'todo_list':
        final items = item['items'];
        final count = items is List ? items.length : 0;
        return [
          line.event(
            AgentEventKind.unknown,
            summary: 'todo list: $count item${count == 1 ? '' : 's'}',
          ),
        ];
      case 'error':
        final message = _string(item['message']) ?? '';
        return [
          line.event(
            AgentEventKind.unknown,
            summary: 'error: ${clip(message)}',
          ),
        ];
      default:
        return [
          line.event(AgentEventKind.unknown, summary: 'item $type ($phase)'),
        ];
    }
  }

  /// Emits only the text not yet shown for a streamed item, whether Codex
  /// sends `delta`s, growing `text` snapshots, or just the completed item.
  List<AgentEvent> _streamed(
    _Line line,
    String phase,
    Map<String, Object?> item,
    String id,
    AgentEventKind kind,
  ) {
    final tracked = id.isNotEmpty;
    final previous = tracked ? (_streamedText[id] ?? '') : '';
    final delta = _string(item['delta']);
    final text = _string(item['text']);
    final full = delta != null ? previous + delta : (text ?? previous);
    final suffix = full.startsWith(previous)
        ? full.substring(previous.length)
        : full;
    if (phase == 'completed') {
      if (tracked) _streamedText.remove(id);
      if (kind == AgentEventKind.textDelta && full.isNotEmpty) {
        _lastAgentMessage = full;
      }
    } else if (tracked) {
      _streamedText[id] = full;
    } else {
      // Untracked partial: the completed item will carry the whole text.
      return const [];
    }
    if (suffix.isEmpty) return const [];
    return [line.event(kind, summary: suffix)];
  }

  List<AgentEvent> _tool(
    _Line line,
    String phase,
    String id, {
    required String summary,
    required ToolCategory category,
    String? status,
    int? exitCode,
  }) {
    switch (phase) {
      case 'started':
        if (id.isNotEmpty) _openItems[id] = _OpenItem(summary, category);
        return [
          line.event(
            AgentEventKind.toolStarted,
            summary: summary,
            category: category,
          ),
        ];
      case 'completed':
        final open = id.isEmpty ? null : _openItems.remove(id);
        final events = <AgentEvent>[];
        if (open == null) {
          // Never announced: say it started so the office sees both ends.
          events.add(
            line.event(
              AgentEventKind.toolStarted,
              summary: summary,
              category: category,
            ),
          );
        }
        final failed =
            status == 'failed' || (exitCode != null && exitCode != 0);
        final buffer = StringBuffer(failed ? 'failed: ' : 'done: ')
          ..write(open?.summary ?? summary);
        if (exitCode != null) buffer.write(' (exit $exitCode)');
        events.add(
          line.event(
            AgentEventKind.toolFinished,
            summary: buffer.toString(),
            category: open?.category ?? category,
          ),
        );
        return events;
      default:
        // item.updated streams aggregated output: nothing new to show.
        return const [];
    }
  }

  List<AgentEvent> _fileChange(
    _Line line,
    String phase,
    Map<String, Object?> item,
  ) {
    if (phase != 'completed') return const [];
    final changes = item['changes'];
    if (changes is! List) return const [];
    return [
      for (final change in changes)
        if (change is Map && change['path'] is String)
          line.event(
            AgentEventKind.fileChanged,
            summary: change['path'] as String,
            category: ToolCategory.edit,
          ),
    ];
  }

  // ------------------------------------------------------------------ turn

  AgentEvent _turnCompletedEvent(_Line line) {
    _turnCompleted = true;
    final usage = _map(line.raw['usage']);
    _inputTokens = _int(usage?['input_tokens']) ?? _inputTokens;
    _outputTokens = _int(usage?['output_tokens']) ?? _outputTokens;
    final text = _lastAgentMessage;
    return line.event(
      AgentEventKind.turnCompleted,
      summary: text == null || text.isEmpty ? 'turn completed' : text,
      inputTokens: _inputTokens,
      outputTokens: _outputTokens,
    );
  }

  AgentEvent _turnFailedEvent(_Line line, String? message) {
    final text = message == null || message.trim().isEmpty
        ? 'turn failed'
        : message.trim();
    _failureMessage = text;
    return line.event(AgentEventKind.turnFailed, summary: text);
  }

  // --------------------------------------------------------------- helpers

  static String _commandText(Object? command) {
    if (command is String) return command;
    if (command is List) return command.whereType<String>().join(' ');
    return '';
  }

  static String? _string(Object? value) => value is String ? value : null;

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : null;
}

/// A tool item whose `item.completed` is still pending.
class _OpenItem {
  const _OpenItem(this.summary, this.category);

  final String summary;
  final ToolCategory category;
}

/// One decoded stdout line plus the identity every event from it carries.
class _Line {
  const _Line(this.seat, this.taskId, this.threadId, this.raw);

  final Seat seat;
  final String? taskId;
  final String? threadId;
  final Map<String, Object?> raw;

  AgentEvent event(
    AgentEventKind kind, {
    required String summary,
    ToolCategory? category,
    int? inputTokens,
    int? outputTokens,
  }) {
    return AgentEvent(
      seat: seat,
      taskId: taskId,
      kind: kind,
      summary: summary,
      category: category,
      sessionRef: threadId,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      raw: raw,
    );
  }
}
