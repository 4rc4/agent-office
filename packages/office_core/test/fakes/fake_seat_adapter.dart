import 'dart:async';

import 'package:office_core/src/adapters/seat_adapter.dart';
import 'package:office_core/src/model/agent_event.dart';
import 'package:office_core/src/model/task.dart';

/// One scripted turn: [events] are emitted in order, then [result] completes
/// `turnDone`. A `turnCompleted` or `turnFailed` event is appended by the run.
class ScriptedTurn {
  const ScriptedTurn({
    required this.result,
    this.events = const [],
    this.hangs = false,
  });

  /// A turn that never ends on its own: the events play, then `turnDone`
  /// stays pending until [FakeAgentRun.stop] fails it (a process kill).
  const ScriptedTurn.hang({this.events = const []})
    : result = const AgentResult(success: false, error: 'hung'),
      hangs = true;

  factory ScriptedTurn.success(
    String text, {
    List<AgentEvent> events = const [],
  }) => ScriptedTurn(
    result: AgentResult(success: true, text: text),
    events: events,
  );

  factory ScriptedTurn.failure(
    String error, {
    List<AgentEvent> events = const [],
  }) => ScriptedTurn(
    result: AgentResult(success: false, error: error),
    events: events,
  );

  final List<AgentEvent> events;
  final AgentResult result;
  final bool hangs;
}

/// How one fake run behaves: it announces [sessionRef] on start, then plays
/// one [ScriptedTurn] per message (the initial one, then each `send`).
class FakeRunScript {
  const FakeRunScript({
    required this.sessionRef,
    required this.turns,
    this.startError,
  });

  final String sessionRef;
  final List<ScriptedTurn> turns;

  /// When set, `start` throws a [StateError] with this text instead.
  final String? startError;
}

/// One recorded `start` call.
class StartCall {
  const StartCall({
    required this.task,
    required this.initialMessage,
    required this.resumeRef,
    required this.order,
  });

  final TaskRecord task;
  final String initialMessage;
  final String? resumeRef;

  /// Global start sequence number across every [FakeSeatAdapter] in the test.
  final int order;
}

/// A [SeatAdapter] that plays scripts instead of launching a CLI.
///
/// Scripts come from [scriptFor] (chosen per call) or from a queue consumed
/// in order. Every start and every run is recorded for assertions.
class FakeSeatAdapter implements SeatAdapter {
  FakeSeatAdapter(
    this.seat, {
    List<FakeRunScript> scripts = const [],
    this.scriptFor,
  }) : _queue = List.of(scripts);

  static int _nextOrder = 0;

  @override
  final Seat seat;

  final List<FakeRunScript> _queue;
  final FakeRunScript Function(StartCall call)? scriptFor;
  final List<StartCall> starts = [];
  final List<FakeAgentRun> runs = [];

  @override
  Future<AgentRun> start(
    TaskRecord task, {
    required String initialMessage,
    String? resumeRef,
  }) async {
    final call = StartCall(
      task: task,
      initialMessage: initialMessage,
      resumeRef: resumeRef,
      order: _nextOrder++,
    );
    starts.add(call);
    final script = scriptFor?.call(call) ?? _dequeue();
    if (script.startError != null) throw StateError(script.startError!);
    final run = FakeAgentRun(seat, task, script);
    runs.add(run);
    run._play(first: true);
    return run;
  }

  FakeRunScript _dequeue() {
    if (_queue.isEmpty) {
      throw StateError('FakeSeatAdapter(${seat.name}): no script left');
    }
    return _queue.removeAt(0);
  }
}

/// A scripted [AgentRun]. Events are delivered asynchronously so the caller
/// can attach a listener right after `start` returns; `turnDone` completes
/// only after every event of the turn has been delivered.
class FakeAgentRun implements AgentRun {
  FakeAgentRun(this.seat, this.task, this.script);

  final Seat seat;
  final TaskRecord task;
  final FakeRunScript script;
  final _events = StreamController<AgentEvent>.broadcast();
  final List<String> sent = [];
  var _turn = Completer<AgentResult>();
  var _turnIndex = 0;
  bool stopped = false;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<AgentResult> get turnDone => _turn.future;

  @override
  String? get sessionRef => script.sessionRef;

  @override
  Future<void> send(String userMessage) async {
    if (stopped) throw StateError('run is stopped');
    sent.add(userMessage);
    _turn = Completer<AgentResult>();
    _play();
  }

  @override
  Future<void> stop({Duration grace = const Duration(seconds: 20)}) async {
    stopped = true;
    if (!_turn.isCompleted) {
      // Like a killed CLI: the pending turn ends without a result.
      _turn.complete(
        const AgentResult(success: false, error: 'process stopped'),
      );
    }
    if (!_events.isClosed) await _events.close();
  }

  Future<void> _play({bool first = false}) async {
    // Let the caller attach its listener before the first event.
    await Future<void>.delayed(Duration.zero);
    final turn = _turnIndex < script.turns.length
        ? script.turns[_turnIndex]
        : ScriptedTurn.failure('fake run has no scripted turn $_turnIndex');
    _turnIndex++;
    if (first) {
      _emit(
        AgentEvent(
          seat: seat,
          kind: AgentEventKind.sessionStarted,
          summary: 'session ${script.sessionRef}',
          sessionRef: script.sessionRef,
        ),
      );
    }
    for (final event in turn.events) {
      _emit(event);
      await Future<void>.delayed(Duration.zero);
    }
    if (turn.hangs) return;
    _emit(
      AgentEvent(
        seat: seat,
        kind: turn.result.success
            ? AgentEventKind.turnCompleted
            : AgentEventKind.turnFailed,
        summary: turn.result.success
            ? 'turn completed'
            : 'turn failed: ${turn.result.error}',
        sessionRef: script.sessionRef,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    if (!_turn.isCompleted) {
      _turn.complete(
        AgentResult(
          success: turn.result.success,
          text: turn.result.text,
          error: turn.result.error,
          sessionRef: script.sessionRef,
          inputTokens: turn.result.inputTokens,
          outputTokens: turn.result.outputTokens,
        ),
      );
    }
  }

  void _emit(AgentEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}
