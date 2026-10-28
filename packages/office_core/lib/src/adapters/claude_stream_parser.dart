import 'dart:convert';

import '../model/agent_event.dart';
import '../model/task.dart';
import 'seat_adapter.dart';

/// Translates Claude Code `--output-format stream-json` lines (one JSON
/// object per line) into vendor-neutral [AgentEvent]s.
///
/// Use one parser per Claude process. It keeps a little state so that:
///
/// * tool results can be matched to the tool_use that started them,
/// * text is not counted twice when `--include-partial-messages` is on (if a
///   `stream_event` text delta was seen in the current turn, the full text
///   block of the following `assistant` message is skipped),
/// * subagent output (non-null `parent_tool_use_id`) is announced once.
///
/// The parser never throws on bad input: a line that is not a JSON object
/// becomes an [AgentEventKind.unknown] event whose summary is the raw line.
/// Unknown event types, subtypes and fields are tolerated; every event keeps
/// the decoded object in [AgentEvent.raw].
class ClaudeStreamParser {
  ClaudeStreamParser();

  /// Longest tool summary fragment, e.g. the command shown after `Bash: `.
  static const int summaryLimit = 80;

  /// Tools whose successful result means a file on disk changed.
  static const Set<String> editTools = {
    'Edit',
    'Write',
    'MultiEdit',
    'NotebookEdit',
  };

  /// Tools that start a subagent.
  static const Set<String> subagentTools = {'Agent', 'Task'};

  final Map<String, _OpenTool> _openTools = {};
  final Set<String> _activeSubagents = {};
  bool _sawTextDelta = false;
  bool _sawThinkingDelta = false;

  /// Whether a `stream_event` text delta was seen in the current turn.
  bool get partialTextSeenThisTurn => _sawTextDelta;

  /// Parses one stdout line and returns its first event, or null when the
  /// line carries nothing worth reporting (blank line, streaming noise such
  /// as `message_start`).
  ///
  /// A single line can produce several events (an assistant message with a
  /// text block and a tool_use, a tool result that also means a file
  /// changed). Adapters should use [parseLineAll] so none are lost.
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
    if (decoded is! Map<String, Object?>) {
      return [
        AgentEvent(
          seat: seat,
          taskId: taskId,
          kind: AgentEventKind.unknown,
          summary: trimmed,
          raw: {'line': trimmed},
        ),
      ];
    }
    final line0 = _Line(seat, taskId, decoded);
    final type = decoded['type'];
    switch (type) {
      case 'system':
        return _system(line0);
      case 'assistant':
        return _assistant(line0);
      case 'user':
        return _user(line0);
      case 'stream_event':
        return _streamEvent(line0);
      case 'rate_limit_event':
        return [_rateLimit(line0)];
      case 'result':
        return [_result(line0)];
      case 'control_request':
        return _controlRequest(line0);
      default:
        return [
          line0.event(
            AgentEventKind.unknown,
            summary: type is String ? type : trimmed,
          ),
        ];
    }
  }

  /// Builds the [AgentResult] for a `result` event (the last line of a turn).
  ///
  /// `inputTokens` is the sum of `input_tokens`, `cache_creation_input_tokens`
  /// and `cache_read_input_tokens`, i.e. everything the model read, so it is
  /// comparable with other vendors whose input count includes cached tokens.
  AgentResult resultFrom(Map<String, Object?> resultEvent) {
    final subtype = _string(resultEvent['subtype']);
    final isError = resultEvent['is_error'] == true;
    final success = !isError && (subtype == null || subtype == 'success');
    final text = _string(resultEvent['result']);
    final usage = _map(resultEvent['usage']);
    String? error;
    if (!success) {
      final buffer = StringBuffer(subtype ?? 'error');
      final errors = resultEvent['errors'];
      if (errors is List && errors.isNotEmpty) {
        buffer.write(': ${errors.join('; ')}');
      } else if (text != null && text.isNotEmpty) {
        buffer.write(': $text');
      }
      error = buffer.toString();
    }
    return AgentResult(
      success: success,
      text: text,
      sessionRef: _string(resultEvent['session_id']),
      inputTokens: _inputTokens(usage),
      outputTokens: _int(usage?['output_tokens']),
      error: error,
    );
  }

  /// Vendor-neutral category of a Claude Code tool name.
  static ToolCategory categoryFor(String toolName) {
    if (toolName.startsWith('mcp__')) {
      if (toolName.startsWith('mcp__chrome-devtools__') ||
          toolName.startsWith('mcp__playwright__')) {
        return ToolCategory.browser;
      }
      return ToolCategory.mcp;
    }
    return switch (toolName) {
      'Read' || 'Grep' || 'Glob' || 'LS' => ToolCategory.read,
      'WebFetch' || 'WebSearch' => ToolCategory.browser,
      'Edit' || 'Write' || 'MultiEdit' || 'NotebookEdit' => ToolCategory.edit,
      'Bash' || 'PowerShell' => ToolCategory.shell,
      _ => ToolCategory.other,
    };
  }

  /// Whether [toolName] starts a subagent (`Agent`, `Task`).
  static bool isSubagentTool(String toolName) =>
      subagentTools.contains(toolName);

  /// The file an edit tool targets, or null for other tools.
  static String? editedFilePath(String toolName, Map<String, Object?> input) {
    if (!editTools.contains(toolName)) return null;
    return _string(input['file_path']) ?? _string(input['notebook_path']);
  }

  /// One short human line for a tool call, e.g. `Bash: flutter test` or
  /// `Edit C:\work\lib\a.dart`.
  static String toolSummary(String toolName, Map<String, Object?> input) {
    switch (toolName) {
      case 'Bash' || 'PowerShell':
        return '$toolName: ${clip(_string(input['command']) ?? '')}';
      case 'Edit' || 'Write' || 'MultiEdit' || 'Read':
        return _withPath(toolName, input['file_path']);
      case 'NotebookEdit':
        return _withPath(toolName, input['notebook_path']);
      case 'Grep':
        final pattern = clip(_string(input['pattern']) ?? '');
        final path = _string(input['path']);
        return path == null ? 'Grep $pattern' : 'Grep $pattern in $path';
      case 'Glob':
        final pattern = clip(_string(input['pattern']) ?? '');
        final path = _string(input['path']);
        return path == null ? 'Glob $pattern' : 'Glob $pattern in $path';
      case 'LS':
        return _withPath(toolName, input['path']);
      case 'WebFetch':
        return 'WebFetch ${clip(_string(input['url']) ?? '')}';
      case 'WebSearch':
        return 'WebSearch: ${clip(_string(input['query']) ?? '')}';
      case 'Agent' || 'Task':
        final what =
            _string(input['description']) ??
            _string(input['subagent_type']) ??
            _string(input['prompt']) ??
            '';
        return 'subagent: ${clip(what)}';
      case 'AskUserQuestion':
        return 'question: ${clip(_firstQuestion(input) ?? '')}';
    }
    if (toolName.startsWith('mcp__')) {
      final parts = toolName.split('__');
      if (parts.length >= 3) {
        return 'MCP ${parts[1]}/${parts.sublist(2).join('__')}';
      }
      return 'MCP $toolName';
    }
    final firstString = input.values.whereType<String>().firstOrNull;
    return firstString == null ? toolName : '$toolName: ${clip(firstString)}';
  }

  /// Collapses whitespace to single spaces and cuts at [limit] characters.
  static String clip(String text, [int limit = summaryLimit]) {
    final oneLine = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return oneLine.length <= limit ? oneLine : oneLine.substring(0, limit);
  }

  // ---------------------------------------------------------------- system

  List<AgentEvent> _system(_Line line) {
    final subtype = _string(line.raw['subtype']);
    switch (subtype) {
      case 'init':
        _resetTurn();
        _openTools.clear();
        _activeSubagents.clear();
        final model = _string(line.raw['model']) ?? 'unknown model';
        final mode = _string(line.raw['permissionMode']) ?? 'unknown';
        final apiKeySource = _string(line.raw['apiKeySource']) ?? 'unknown';
        return [
          line.event(
            AgentEventKind.sessionStarted,
            summary:
                'session started: model $model, permissionMode $mode, '
                'apiKeySource=$apiKeySource',
          ),
        ];
      case 'status':
        final status = _string(line.raw['status']);
        if (status == 'compacting') {
          return [
            line.event(
              AgentEventKind.compacting,
              summary: 'compacting context',
            ),
          ];
        }
        return [line.event(AgentEventKind.unknown, summary: 'status: $status')];
      case 'hook_started' || 'hook_response':
        final name = _string(line.raw['hook_name']) ?? 'hook';
        final outcome = _string(line.raw['outcome']);
        return [
          line.event(
            AgentEventKind.unknown,
            summary: outcome == null ? 'hook $name' : 'hook $name: $outcome',
          ),
        ];
      default:
        return [
          line.event(
            AgentEventKind.unknown,
            summary: 'system ${subtype ?? ''}',
          ),
        ];
    }
  }

  // ------------------------------------------------------------- assistant

  List<AgentEvent> _assistant(_Line line) {
    final events = _noteParent(line);
    for (final block in _contentBlocks(line.raw['message'])) {
      final type = _string(block['type']);
      switch (type) {
        case 'text':
          final text = _string(block['text']) ?? '';
          if (_sawTextDelta || text.isEmpty) continue;
          events.add(line.event(AgentEventKind.textDelta, summary: text));
        case 'thinking':
          final text = _string(block['thinking']) ?? '';
          if (_sawThinkingDelta || text.isEmpty) continue;
          events.add(line.event(AgentEventKind.thinking, summary: text));
        case 'tool_use':
          events.add(_toolUse(line, block));
        default:
          events.add(
            line.event(
              AgentEventKind.unknown,
              summary: 'assistant block ${type ?? ''}',
            ),
          );
      }
    }
    return events;
  }

  AgentEvent _toolUse(_Line line, Map<String, Object?> block) {
    final id = _string(block['id']) ?? '';
    final name = _string(block['name']) ?? 'tool';
    final input = _map(block['input']) ?? const {};
    final category = categoryFor(name);
    final summary = toolSummary(name, input);
    final subagent = isSubagentTool(name);
    if (id.isNotEmpty) {
      _openTools[id] = _OpenTool(
        name: name,
        summary: summary,
        category: category,
        filePath: editedFilePath(name, input),
        isSubagent: subagent,
      );
    }
    if (subagent) {
      if (id.isNotEmpty) _activeSubagents.add(id);
      return line.event(
        AgentEventKind.subagentStarted,
        summary: summary,
        category: category,
      );
    }
    if (name == 'AskUserQuestion') {
      return line.event(
        AgentEventKind.userQuestion,
        summary: summary,
        category: category,
      );
    }
    return line.event(
      AgentEventKind.toolStarted,
      summary: summary,
      category: category,
    );
  }

  // ------------------------------------------------------------------ user

  List<AgentEvent> _user(_Line line) {
    final events = _noteParent(line);
    final message = _map(line.raw['message']);
    final content = message?['content'];
    if (content is String) {
      events.add(
        line.event(AgentEventKind.unknown, summary: 'user: ${clip(content)}'),
      );
      return events;
    }
    for (final block in _contentBlocks(message)) {
      final type = _string(block['type']);
      switch (type) {
        case 'tool_result':
          events.addAll(_toolResult(line, block));
        case 'text':
          events.add(
            line.event(
              AgentEventKind.unknown,
              summary: 'user: ${clip(_string(block['text']) ?? '')}',
            ),
          );
        default:
          events.add(
            line.event(
              AgentEventKind.unknown,
              summary: 'user block ${type ?? ''}',
            ),
          );
      }
    }
    return events;
  }

  List<AgentEvent> _toolResult(_Line line, Map<String, Object?> block) {
    final id = _string(block['tool_use_id']) ?? '';
    final isError = block['is_error'] == true;
    final open = _openTools.remove(id);
    if ((open?.isSubagent ?? false) || _activeSubagents.contains(id)) {
      _activeSubagents.remove(id);
      return [
        line.event(
          AgentEventKind.subagentStopped,
          summary: isError ? 'subagent failed' : 'subagent done',
          category: ToolCategory.other,
        ),
      ];
    }
    final buffer = StringBuffer(isError ? 'failed' : 'done');
    if (open != null) buffer.write(': ${open.summary}');
    if (isError) {
      final preview = clip(_resultText(block['content']));
      if (preview.isNotEmpty) buffer.write(' ($preview)');
    }
    final events = [
      line.event(
        AgentEventKind.toolFinished,
        summary: buffer.toString(),
        category: open?.category ?? ToolCategory.other,
      ),
    ];
    final filePath = open?.filePath;
    if (!isError && filePath != null) {
      events.add(
        line.event(
          AgentEventKind.fileChanged,
          summary: filePath,
          category: ToolCategory.edit,
        ),
      );
    }
    return events;
  }

  // ---------------------------------------------------------- stream_event

  List<AgentEvent> _streamEvent(_Line line) {
    final event = _map(line.raw['event']);
    if (event == null || event['type'] != 'content_block_delta') {
      // message_start, content_block_start/stop, message_delta, message_stop:
      // streaming plumbing, nothing to show.
      return const [];
    }
    final delta = _map(event['delta']);
    final events = _noteParent(line);
    switch (_string(delta?['type'])) {
      case 'text_delta':
        _sawTextDelta = true;
        final text = _string(delta?['text']) ?? '';
        if (text.isNotEmpty) {
          events.add(line.event(AgentEventKind.textDelta, summary: text));
        }
      case 'thinking_delta':
        _sawThinkingDelta = true;
        final text = _string(delta?['thinking']) ?? '';
        if (text.isNotEmpty) {
          events.add(line.event(AgentEventKind.thinking, summary: text));
        }
      default:
        // input_json_delta, signature_delta: the full tool_use follows in
        // the assistant message.
        break;
    }
    return events;
  }

  // ------------------------------------------------------------ rate limit

  AgentEvent _rateLimit(_Line line) {
    final info = _map(line.raw['rate_limit_info']) ?? const {};
    final status = _string(info['status']) ?? 'unknown';
    final buffer = StringBuffer('rate limit $status');
    final type = _string(info['rateLimitType']);
    if (type != null) buffer.write(' ($type)');
    final utilization = info['utilization'];
    if (utilization is num) {
      buffer.write(', ${(utilization * 100).round()}% used');
    }
    final resetsAt = info['resetsAt'];
    if (resetsAt is num) {
      final when = DateTime.fromMillisecondsSinceEpoch(
        (resetsAt * 1000).round(),
        isUtc: true,
      );
      buffer.write(', resets ${when.toIso8601String()}');
    }
    return line.event(AgentEventKind.rateLimit, summary: buffer.toString());
  }

  // ---------------------------------------------------------------- result

  AgentEvent _result(_Line line) {
    final result = resultFrom(line.raw);
    _resetTurn();
    _openTools.clear();
    _activeSubagents.clear();
    if (result.success) {
      final text = result.text;
      return line.event(
        AgentEventKind.turnCompleted,
        summary: text == null || text.isEmpty ? 'turn completed' : text,
        inputTokens: result.inputTokens,
        outputTokens: result.outputTokens,
      );
    }
    return line.event(
      AgentEventKind.turnFailed,
      summary: result.error ?? 'turn failed',
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
    );
  }

  // ------------------------------------------------------- control_request

  List<AgentEvent> _controlRequest(_Line line) {
    final request = _map(line.raw['request']);
    final subtype = _string(request?['subtype']);
    if (subtype == 'can_use_tool') {
      final name = _string(request?['tool_name']) ?? 'tool';
      final input = _map(request?['input']) ?? const {};
      return [
        line.event(
          AgentEventKind.approvalRequested,
          summary: 'approval: ${toolSummary(name, input)}',
          category: categoryFor(name),
        ),
      ];
    }
    return [
      line.event(
        AgentEventKind.unknown,
        summary: 'control_request ${subtype ?? ''}',
      ),
    ];
  }

  // --------------------------------------------------------------- helpers

  /// Announces a subagent the first time its `parent_tool_use_id` shows up
  /// without a preceding Agent/Task tool_use (e.g. after a resume).
  List<AgentEvent> _noteParent(_Line line) {
    final parent = _string(line.raw['parent_tool_use_id']);
    if (parent == null || parent.isEmpty || _activeSubagents.contains(parent)) {
      return [];
    }
    _activeSubagents.add(parent);
    return [
      line.event(
        AgentEventKind.subagentStarted,
        summary: 'subagent $parent',
        category: ToolCategory.other,
      ),
    ];
  }

  void _resetTurn() {
    _sawTextDelta = false;
    _sawThinkingDelta = false;
  }

  static List<Map<String, Object?>> _contentBlocks(Object? message) {
    final content = _map(message)?['content'];
    if (content is! List) return const [];
    return [
      for (final block in content)
        if (block is Map) Map<String, Object?>.from(block),
    ];
  }

  static String _resultText(Object? content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .map((block) => _string(block['text']) ?? '')
          .where((text) => text.isNotEmpty)
          .join(' ');
    }
    return '';
  }

  static String? _firstQuestion(Map<String, Object?> input) {
    final questions = input['questions'];
    if (questions is List && questions.isNotEmpty) {
      final first = questions.first;
      if (first is Map) return _string(first['question']);
    }
    return _string(input['question']);
  }

  static int? _inputTokens(Map<String, Object?>? usage) {
    if (usage == null) return null;
    final parts = [
      _int(usage['input_tokens']),
      _int(usage['cache_creation_input_tokens']),
      _int(usage['cache_read_input_tokens']),
    ];
    if (parts.every((part) => part == null)) return null;
    return parts.fold<int>(0, (sum, part) => sum + (part ?? 0));
  }

  static String _withPath(String toolName, Object? path) {
    final text = _string(path);
    return text == null ? toolName : '$toolName $text';
  }

  static String? _string(Object? value) => value is String ? value : null;

  static int? _int(Object? value) => value is num ? value.toInt() : null;

  static Map<String, Object?>? _map(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : null;
}

/// A tool_use we have seen and whose tool_result is still pending.
class _OpenTool {
  const _OpenTool({
    required this.name,
    required this.summary,
    required this.category,
    required this.filePath,
    required this.isSubagent,
  });

  final String name;
  final String summary;
  final ToolCategory category;
  final String? filePath;
  final bool isSubagent;
}

/// One decoded stdout line plus the identity every event from it carries.
class _Line {
  _Line(this.seat, this.taskId, this.raw)
    : sessionRef = raw['session_id'] is String
          ? raw['session_id'] as String
          : null;

  final Seat seat;
  final String? taskId;
  final Map<String, Object?> raw;
  final String? sessionRef;

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
      sessionRef: sessionRef,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      raw: raw,
    );
  }
}
