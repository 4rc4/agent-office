/// Agent Office core: task board, supervisor and CLI adapters. Pure Dart.
library;

export 'src/adapters/claude_adapter.dart';
export 'src/adapters/claude_stream_parser.dart';
export 'src/adapters/codex_adapter.dart';
export 'src/adapters/codex_jsonl_parser.dart';
export 'src/adapters/seat_adapter.dart';
export 'src/board/schema.dart';
export 'src/board/task_board.dart';
export 'src/board/transitions.dart';
export 'src/cli/office_cli.dart';
export 'src/cli/office_wiring.dart';
export 'src/model/agent_event.dart';
export 'src/model/session.dart';
export 'src/model/task.dart';
export 'src/plan/plan_parser.dart';
export 'src/plan/planned_task.dart';
export 'src/process/process_runner.dart';
export 'src/supervisor/brain_protocol.dart';
export 'src/supervisor/dispatcher.dart';
export 'src/supervisor/supervisor.dart';
