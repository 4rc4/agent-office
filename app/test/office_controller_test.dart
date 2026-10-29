import 'dart:async';

import 'package:agent_office_app/state/office_controller.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

// ----------------------------------------------------------- scripted seat

/// Events to emit, then the result that ends the turn.
class ScriptedTurn {
  const ScriptedTurn(this.events, this.result);

  factory ScriptedTurn.success(
    String text, [
    List<AgentEvent> events = const [],
  ]) => ScriptedTurn(events, AgentResult(success: true, text: text));

  factory ScriptedTurn.failure(
    String error, [
    List<AgentEvent> events = const [],
  ]) => ScriptedTurn(events, AgentResult(success: false, error: error));

  final List<AgentEvent> events;
  final AgentResult result;
}

/// A [SeatAdapter] that plays one script (a list of turns) per `start`.
class ScriptedAdapter implements SeatAdapter {
  ScriptedAdapter(this.seat, List<List<ScriptedTurn>> scripts)
    : _scripts = List.of(scripts);

  @override
  final Seat seat;

  final List<List<ScriptedTurn>> _scripts;
  int starts = 0;

  @override
  Future<AgentRun> start(
    TaskRecord task, {
    required String initialMessage,
    String? resumeRef,
  }) async {
    if (_scripts.isEmpty) {
      throw StateError('no script left for ${seat.name}');
    }
    starts++;
    final run = ScriptedRun(
      seat,
      _scripts.removeAt(0),
      'session-${seat.name}-$starts',
    );
    unawaited(run.play());
    return run;
  }
}

class ScriptedRun implements AgentRun {
  ScriptedRun(this.seat, this.turns, this.ref);

  final Seat seat;
  final List<ScriptedTurn> turns;
  final String ref;
  final _events = StreamController<AgentEvent>.broadcast();
  var _turn = Completer<AgentResult>();
  var _index = 0;
  var _first = true;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<AgentResult> get turnDone => _turn.future;

  @override
  String? get sessionRef => ref;

  @override
  Future<void> send(String userMessage) async {
    _turn = Completer<AgentResult>();
    unawaited(play());
  }

  @override
  Future<void> stop({Duration grace = const Duration(seconds: 20)}) async {
    if (!_events.isClosed) await _events.close();
  }

  Future<void> play() async {
    // Let the dispatcher attach its listener first.
    await Future<void>.delayed(Duration.zero);
    final turn = _index < turns.length
        ? turns[_index]
        : ScriptedTurn.failure('no scripted turn $_index');
    _index++;
    if (_first) {
      _first = false;
      _emit(
        ev(
          seat,
          AgentEventKind.sessionStarted,
          summary: 'session $ref',
          sessionRef: ref,
        ),
      );
      await Future<void>.delayed(Duration.zero);
    }
    for (final event in turn.events) {
      _emit(event);
      await Future<void>.delayed(Duration.zero);
    }
    final ok = turn.result.success;
    _emit(
      ev(
        seat,
        ok ? AgentEventKind.turnCompleted : AgentEventKind.turnFailed,
        summary: ok ? 'turn completed' : 'turn failed: ${turn.result.error}',
        sessionRef: ref,
      ),
    );
    await Future<void>.delayed(Duration.zero);
    if (!_turn.isCompleted) _turn.complete(turn.result);
  }

  void _emit(AgentEvent event) {
    if (!_events.isClosed) _events.add(event);
  }
}

AgentEvent ev(
  Seat seat,
  AgentEventKind kind, {
  String summary = '',
  ToolCategory? category,
  String? sessionRef,
  int? inputTokens,
  int? outputTokens,
  Map<String, Object?> raw = const {},
}) => AgentEvent(
  seat: seat,
  kind: kind,
  summary: summary,
  category: category,
  sessionRef: sessionRef,
  inputTokens: inputTokens,
  outputTokens: outputTokens,
  raw: raw,
);

// ---------------------------------------------------------------- helpers

Future<PlanOrError> neverPlan(String text) async =>
    PlanOrError.error('no plan expected');

Future<String> noDiff(String cwd) async => '';

Future<void> waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 5),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) fail('timed out waiting');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

List<T> dedupe<T>(Iterable<T> items) {
  final out = <T>[];
  for (final item in items) {
    if (out.isEmpty || out.last != item) out.add(item);
  }
  return out;
}

/// A board, a supervisor over [adapters] and a controller with a clock the
/// test moves by hand. Everything is torn down in the right order.
class Harness {
  Harness(
    Map<Seat, SeatAdapter> adapters, {
    PlanParserFn? parsePlan,
    int maxAttempts = 2,
    Duration celebrateFor = const Duration(seconds: 3),
    int maxRecentEvents = 200,
  }) {
    board = TaskBoard.inMemory(clock: () => now);
    supervisor = Supervisor(
      board: board,
      adapters: adapters,
      parsePlan: parsePlan ?? neverPlan,
      collectDiffStat: noDiff,
      maxAttempts: maxAttempts,
    );
    controller = OfficeController(
      supervisor: supervisor,
      board: board,
      cwd: '/repo',
      clock: () => now,
      celebrateFor: celebrateFor,
      maxRecentEvents: maxRecentEvents,
    );
    controller.addListener(() {
      final snapshot = controller.snapshot;
      statuses.add(snapshot.statusLine);
      busyLog.add(snapshot.busy);
      for (final seat in Seat.values) {
        visuals[seat]!.add(snapshot.seat(seat).visual);
        bubbles[seat]!.add(snapshot.seat(seat).bubble);
      }
      notifications++;
    });
    addTearDown(() async {
      controller.dispose();
      await supervisor.dispose();
      closeBoard();
    });
  }

  bool boardClosed = false;

  /// Closes the board once; tests that close it early call this too.
  void closeBoard() {
    if (boardClosed) return;
    boardClosed = true;
    board.close();
  }

  DateTime now = DateTime(2026, 10, 28, 12);
  late final TaskBoard board;
  late final Supervisor supervisor;
  late final OfficeController controller;
  final statuses = <String>[];
  final busyLog = <bool>[];
  final visuals = {for (final s in Seat.values) s: <SeatVisual>[]};
  final bubbles = {for (final s in Seat.values) s: <SeatBubble?>[]};
  int notifications = 0;

  SeatSnapshot seat(Seat seat) => controller.snapshot.seat(seat);

  Future<void> waitIdle() => waitUntil(() => !controller.snapshot.busy);
}

void main() {
  concurrentRootTests();
  pauseTests();
  group('visualForEvent', () {
    test('maps every kind', () {
      SeatVisual? of(
        AgentEventKind kind, {
        ToolCategory? category,
        String summary = '',
      }) => visualForEvent(
        ev(Seat.gpt, kind, category: category, summary: summary),
      );

      expect(of(AgentEventKind.sessionStarted), SeatVisual.arriving);
      expect(of(AgentEventKind.thinking), SeatVisual.thinking);
      expect(of(AgentEventKind.textDelta), SeatVisual.typing);
      expect(
        of(AgentEventKind.toolStarted, category: ToolCategory.read),
        SeatVisual.reading,
      );
      expect(
        of(AgentEventKind.toolStarted, category: ToolCategory.edit),
        SeatVisual.editing,
      );
      expect(
        of(AgentEventKind.toolStarted, category: ToolCategory.shell),
        SeatVisual.shell,
      );
      expect(
        of(AgentEventKind.toolStarted, category: ToolCategory.browser),
        SeatVisual.browsing,
      );
      expect(
        of(AgentEventKind.toolStarted, category: ToolCategory.mcp),
        SeatVisual.typing,
      );
      expect(
        of(AgentEventKind.toolStarted, category: ToolCategory.other),
        SeatVisual.typing,
      );
      expect(of(AgentEventKind.toolStarted), SeatVisual.typing);
      expect(of(AgentEventKind.fileChanged), SeatVisual.editing);
      expect(of(AgentEventKind.approvalRequested), SeatVisual.waitingUser);
      expect(of(AgentEventKind.userQuestion), SeatVisual.waitingUser);
      expect(of(AgentEventKind.rateLimit), SeatVisual.onBreak);
      expect(of(AgentEventKind.compacting), SeatVisual.reading);
      expect(of(AgentEventKind.turnCompleted), SeatVisual.celebrating);
      expect(of(AgentEventKind.turnFailed), SeatVisual.failed);
      expect(
        of(AgentEventKind.processExited, summary: 'exited with code 1'),
        SeatVisual.failed,
      );
      expect(
        of(AgentEventKind.processExited, summary: 'exited with code 0'),
        isNull,
      );
      expect(of(AgentEventKind.processExited, summary: 'gone'), isNull);
      for (final keep in [
        AgentEventKind.toolFinished,
        AgentEventKind.subagentStarted,
        AgentEventKind.subagentStopped,
        AgentEventKind.unknown,
      ]) {
        expect(of(keep), isNull, reason: keep.name);
      }
    });

    test('exitCodeOf prefers raw, then the summary', () {
      expect(
        exitCodeOf(
          ev(Seat.gpt, AgentEventKind.processExited, raw: {'exitCode': 3}),
        ),
        3,
      );
      expect(
        exitCodeOf(
          ev(Seat.gpt, AgentEventKind.processExited, raw: {'exit_code': '-1'}),
        ),
        -1,
      );
      expect(
        exitCodeOf(
          ev(
            Seat.gpt,
            AgentEventKind.processExited,
            summary: 'exited with code 137',
          ),
        ),
        137,
      );
      expect(
        exitCodeOf(ev(Seat.gpt, AgentEventKind.processExited, summary: 'bye')),
        isNull,
      );
    });
  });

  group('bubbleForEvent', () {
    test('question, warning, info, success, error', () {
      final q = bubbleForEvent(
        ev(
          Seat.gpt,
          AgentEventKind.approvalRequested,
          summary: 'Allow Bash?\nmore',
        ),
      );
      expect(q?.kind, BubbleKind.question);
      expect(q?.text, 'Allow Bash?');
      expect(
        bubbleForEvent(ev(Seat.gpt, AgentEventKind.userQuestion))?.text,
        '?',
      );
      final w = bubbleForEvent(
        ev(Seat.gpt, AgentEventKind.rateLimit, summary: 'rate limited'),
      );
      expect(w?.kind, BubbleKind.warning);
      final c = bubbleForEvent(ev(Seat.gpt, AgentEventKind.compacting));
      expect(c?.kind, BubbleKind.info);
      expect(c?.text, compactingBubbleText);
      final s = bubbleForEvent(ev(Seat.gpt, AgentEventKind.turnCompleted));
      expect(s?.kind, BubbleKind.success);
      expect(s?.text, '✓');
      final e = bubbleForEvent(
        ev(Seat.gpt, AgentEventKind.turnFailed, summary: 'boom'),
      );
      expect(e?.kind, BubbleKind.error);
      expect(e?.text, 'boom');
      expect(
        bubbleForEvent(
          ev(
            Seat.gpt,
            AgentEventKind.processExited,
            summary: 'exited with code 2',
          ),
        )?.kind,
        BubbleKind.error,
      );
      expect(
        bubbleForEvent(
          ev(
            Seat.gpt,
            AgentEventKind.processExited,
            summary: 'exited with code 0',
          ),
        ),
        isNull,
      );
      expect(bubbleForEvent(ev(Seat.gpt, AgentEventKind.textDelta)), isNull);
    });

    test('long text is cut to one short line', () {
      final b = bubbleForEvent(
        ev(Seat.gpt, AgentEventKind.userQuestion, summary: 'x' * 100),
      );
      expect(b!.text.length, 60);
      expect(b.text.endsWith('…'), isTrue);
    });
  });

  group('OfficeController', () {
    test('initial snapshot: idle seats with adapters, empty without', () {
      final h = Harness({
        Seat.claude: ScriptedAdapter(Seat.claude, []),
        Seat.gpt: ScriptedAdapter(Seat.gpt, []),
      });
      expect(h.seat(Seat.claude).visual, SeatVisual.idle);
      expect(h.seat(Seat.gpt).visual, SeatVisual.idle);
      expect(h.seat(Seat.gemini).visual, SeatVisual.empty);
      expect(h.controller.snapshot.busy, isFalse);
      expect(h.controller.snapshot.statusLine, 'Ofis sessiz.');
      expect(h.controller.snapshot.anyAnimated, isFalse);
      expect(h.controller.cwd, '/repo');
    });

    test('direct run: visuals, busy, status line, report, tasks, xp', () async {
      final h = Harness({
        Seat.claude: ScriptedAdapter(Seat.claude, []),
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [
            ScriptedTurn.success('done', [
              ev(
                Seat.gpt,
                AgentEventKind.toolStarted,
                category: ToolCategory.shell,
                summary: 'Bash: flutter test',
                inputTokens: 100,
                outputTokens: 20,
              ),
              ev(
                Seat.gpt,
                AgentEventKind.toolFinished,
                summary: 'ok',
                inputTokens: 5,
              ),
            ]),
          ],
        ]),
      });

      await h.controller.submit('Run the tests\nplease', directSeat: Seat.gpt);
      expect(h.controller.snapshot.busy, isTrue);
      expect(h.controller.isBusy, isTrue);
      expect(h.controller.snapshot.statusLine, 'GPT çalışıyor: Run the tests');
      expect(h.controller.snapshot.tasks.where((t) => t.isRoot), hasLength(1));

      await h.waitIdle();
      expect(dedupe(h.visuals[Seat.gpt]!), [
        SeatVisual.idle,
        SeatVisual.arriving,
        SeatVisual.shell,
        SeatVisual.celebrating,
      ]);
      expect(dedupe(h.busyLog), [true, false]);
      expect(h.controller.snapshot.statusLine, 'Rapor hazır');
      expect(h.controller.snapshot.lastReport, 'done');

      final gpt = h.seat(Seat.gpt);
      expect(gpt.visual, SeatVisual.celebrating);
      expect(gpt.bubble?.text, '✓');
      expect(gpt.bubble?.kind, BubbleKind.success);
      expect(gpt.tokensIn, 105);
      expect(gpt.tokensOut, 20);
      expect(gpt.sessionRef, 'session-gpt-1');
      expect(gpt.lastSummary, 'turn completed');
      expect(gpt.currentTaskTitle, 'Run the tests');
      expect(gpt.xp, 10);
      expect(h.seat(Seat.claude).visual, SeatVisual.idle);

      final tasks = h.controller.snapshot.tasks;
      expect(tasks, hasLength(2));
      expect(tasks.every((t) => t.status == TaskStatus.done), isTrue);
      final root = tasks.singleWhere((t) => t.isRoot);
      expect(root.resultSummary, 'done');
      expect(tasks.singleWhere((t) => !t.isRoot).assignee, Seat.gpt);
      expect(h.controller.snapshot.recentEvents.map((e) => e.kind), [
        AgentEventKind.sessionStarted,
        AgentEventKind.toolStarted,
        AgentEventKind.toolFinished,
        AgentEventKind.turnCompleted,
      ]);

      // Celebrating ends after celebrateFor, measured on the injected clock.
      h.controller.settle();
      expect(h.seat(Seat.gpt).visual, SeatVisual.celebrating);
      h.now = h.now.add(const Duration(seconds: 3));
      h.controller.settle();
      expect(h.seat(Seat.gpt).visual, SeatVisual.idle);
      expect(h.seat(Seat.gpt).bubble, isNull);
      expect(h.seat(Seat.gpt).currentTaskId, isNull);
      expect(h.controller.snapshot.anyAnimated, isFalse);

      // The office accepts the next request again.
      await h.controller.submit('x', directSeat: Seat.claude);
      expect(h.controller.snapshot.busy, isTrue);
      expect(h.controller.snapshot.statusLine, 'Claude çalışıyor: x');
    });

    test('the real timer parks a celebrating seat', () async {
      final h = Harness({
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [ScriptedTurn.success('ok')],
        ]),
      }, celebrateFor: const Duration(milliseconds: 30));
      await h.controller.submit('hi', directSeat: Seat.gpt);
      await h.waitIdle();
      expect(h.seat(Seat.gpt).visual, SeatVisual.celebrating);
      await waitUntil(() => h.seat(Seat.gpt).visual == SeatVisual.idle);
      expect(h.seat(Seat.gpt).bubble, isNull);
    });

    test('failed run: failed seat, error bubble, failure report', () async {
      final h = Harness({
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [ScriptedTurn.failure('boom')],
          [ScriptedTurn.failure('boom again')],
        ]),
      });
      await h.controller.submit('Explode', directSeat: Seat.gpt);
      await h.waitIdle();
      final gpt = h.seat(Seat.gpt);
      expect(gpt.visual, SeatVisual.failed);
      expect(gpt.bubble?.kind, BubbleKind.error);
      expect(gpt.bubble?.text, 'turn failed: boom again');
      expect(h.controller.snapshot.statusLine, 'Görev başarısız');
      expect(h.controller.snapshot.lastReport, startsWith('Görev başarısız: '));
      expect(
        h.controller.snapshot.lastReport,
        contains('direct task ended failed'),
      );
      final root = h.controller.snapshot.tasks.singleWhere((t) => t.isRoot);
      expect(root.status, TaskStatus.failed);
      expect(h.visuals[Seat.gpt], contains(SeatVisual.arriving));
      expect(h.seat(Seat.gpt).xp, 0);
    });

    test('approval request: waitingUser with a question bubble', () async {
      final h = Harness({
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [
            ScriptedTurn.success('ok', [
              ev(
                Seat.gpt,
                AgentEventKind.approvalRequested,
                summary: 'Allow Bash?',
              ),
              ev(Seat.gpt, AgentEventKind.textDelta, summary: 'Thanks'),
            ]),
          ],
        ]),
      });
      await h.controller.submit('Need approval', directSeat: Seat.gpt);
      await h.waitIdle();
      final seq = h.visuals[Seat.gpt]!;
      final at = seq.indexOf(SeatVisual.waitingUser);
      expect(at, greaterThan(0));
      expect(h.bubbles[Seat.gpt]![at]?.kind, BubbleKind.question);
      expect(h.bubbles[Seat.gpt]![at]?.text, 'Allow Bash?');
      expect(h.statuses[at], 'Onay bekleniyor');
      // The next event clears the question.
      expect(seq[at + 1], SeatVisual.typing);
      expect(h.bubbles[Seat.gpt]![at + 1], isNull);
      expect(h.statuses[at + 1], 'GPT çalışıyor: Need approval');
    });

    test('rate limit and compacting bubbles', () async {
      final h = Harness({
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [
            ScriptedTurn.success('ok', [
              ev(Seat.gpt, AgentEventKind.rateLimit, summary: 'rate limited'),
              ev(Seat.gpt, AgentEventKind.compacting, summary: 'compacting'),
              ev(Seat.gpt, AgentEventKind.toolFinished, summary: 'still here'),
            ]),
          ],
        ]),
      });
      await h.controller.submit('slow', directSeat: Seat.gpt);
      await h.waitIdle();
      final seq = h.visuals[Seat.gpt]!;
      final b = h.bubbles[Seat.gpt]!;
      final onBreak = seq.indexOf(SeatVisual.onBreak);
      expect(b[onBreak]?.kind, BubbleKind.warning);
      final reading = seq.indexOf(SeatVisual.reading);
      expect(b[reading]?.text, compactingBubbleText);
      // toolFinished keeps the pose and the bubble.
      expect(seq[reading + 1], SeatVisual.reading);
      expect(b[reading + 1]?.text, compactingBubbleText);
    });

    test('planned run: planning, worker, merge, report', () async {
      Future<PlanOrError> onePlan(String text) async => PlanOrError.plan(
        ParsedPlan(
          tasks: [
            PlannedTask(
              id: 't1',
              title: 'Fix lint',
              assignee: Seat.gpt,
              prompt: 'fix it',
            ),
          ],
          mergeInstructions: 'merge',
        ),
      );
      final h = Harness({
        Seat.claude: ScriptedAdapter(Seat.claude, [
          [
            ScriptedTurn.success('PLAN', [
              ev(Seat.claude, AgentEventKind.thinking, summary: 'hmm'),
            ]),
            ScriptedTurn.success('# Report', [
              ev(Seat.claude, AgentEventKind.textDelta, summary: 'Rep'),
            ]),
          ],
        ]),
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [
            ScriptedTurn.success('fixed', [
              ev(
                Seat.gpt,
                AgentEventKind.fileChanged,
                summary: 'edit lib/a.dart',
              ),
            ]),
          ],
        ]),
      }, parsePlan: onePlan);
      await h.controller.submit('Make lint pass');
      expect(h.controller.snapshot.statusLine, 'Claude planlıyor…');
      await h.waitIdle();
      expect(
        dedupe(h.statuses),
        containsAllInOrder([
          'Claude planlıyor…',
          'GPT çalışıyor: Fix lint',
          'Claude birleştiriyor…',
          'Rapor hazır',
        ]),
      );
      expect(
        dedupe(h.visuals[Seat.claude]!),
        containsAllInOrder([
          SeatVisual.arriving,
          SeatVisual.thinking,
          SeatVisual.celebrating,
          SeatVisual.typing,
          SeatVisual.celebrating,
        ]),
      );
      expect(
        dedupe(h.visuals[Seat.gpt]!),
        containsAllInOrder([
          SeatVisual.arriving,
          SeatVisual.editing,
          SeatVisual.celebrating,
        ]),
      );
      expect(h.controller.snapshot.lastReport, '# Report');
      expect(h.seat(Seat.gpt).xp, 10);
      expect(h.seat(Seat.claude).xp, 0);
      expect(h.seat(Seat.claude).currentTaskTitle, 'Make lint pass');
      expect(h.seat(Seat.gpt).currentTaskTitle, 'Fix lint');
      expect(h.controller.snapshot.tasks.map((t) => t.title), [
        'Make lint pass',
        'Fix lint',
      ]);
    });

    test('recentEvents is capped, newest last', () async {
      final h = Harness({
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [
            ScriptedTurn.success('ok', [
              for (var i = 0; i < 8; i++)
                ev(Seat.gpt, AgentEventKind.textDelta, summary: 'd$i'),
            ]),
          ],
        ]),
      }, maxRecentEvents: 5);
      await h.controller.submit('talk', directSeat: Seat.gpt);
      await h.waitIdle();
      final recent = h.controller.snapshot.recentEvents;
      expect(recent, hasLength(5));
      expect(recent.first.summary, 'd4');
      expect(recent.last.kind, AgentEventKind.turnCompleted);
    });

    test('synchronous changes coalesce into one notification', () async {
      final h = Harness({Seat.gpt: ScriptedAdapter(Seat.gpt, [])});
      h.controller.cwd = '/a';
      h.controller.cwd = '/b';
      h.controller.reportError('Ayar hatası');
      expect(h.notifications, 0);
      await Future<void>.microtask(() {});
      expect(h.notifications, 1);
      expect(h.controller.cwd, '/b');
      expect(h.controller.snapshot.statusLine, 'Ayar hatası');
    });

    test('a start failure lands on the status line and the seat', () async {
      final h = Harness({Seat.gpt: ScriptedAdapter(Seat.gpt, [])});
      // Gemini has no adapter: the dispatcher fails the subtask as blocked and
      // the root fails without ever throwing to the caller.
      await h.controller.submit('hello', directSeat: Seat.gemini);
      await h.waitIdle();
      expect(h.controller.snapshot.statusLine, 'Görev başarısız');
      expect(
        h.controller.snapshot.lastReport,
        contains('direct task ended failed'),
      );

      // A closed board makes the supervisor throw synchronously; the
      // controller degrades to what it knows instead of throwing.
      h.closeBoard();
      expect(h.controller.isBusy, isFalse);
      await h.controller.submit('again', directSeat: Seat.gpt);
      expect(h.controller.snapshot.statusLine, startsWith('Başlatılamadı: '));
      expect(h.seat(Seat.gpt).visual, SeatVisual.failed);
      expect(h.seat(Seat.gpt).bubble?.kind, BubbleKind.error);
      expect(h.controller.snapshot.busy, isFalse);
      expect(h.controller.snapshot.lastReport, isNotNull);
    });

    test('selectSeat notifies and stopAll runs the hook', () async {
      final h = Harness({Seat.gpt: ScriptedAdapter(Seat.gpt, [])});
      h.controller.selectSeat(Seat.gpt);
      expect(h.controller.selectedSeat, Seat.gpt);
      expect(h.notifications, 1);
      h.controller.selectSeat(null);
      expect(h.controller.selectedSeat, isNull);

      await h.controller.stopAll();
      expect(
        h.controller.snapshot.statusLine,
        'Ofis sessiz.',
        reason: 'no hook: no-op',
      );

      var stops = 0;
      h.controller.onStopAll = () async => stops++;
      await h.controller.stopAll();
      expect(stops, 1);
      expect(h.controller.snapshot.statusLine, 'Ofis durduruldu.');
      expect(h.controller.snapshot.busy, isFalse);
      expect(h.controller.isBusy, isFalse);
      expect(h.seat(Seat.gpt).visual, SeatVisual.idle);
      expect(h.seat(Seat.claude).visual, SeatVisual.empty);
      await h.controller.stopAll();
      expect(stops, 1, reason: 'second stop is a no-op');
    });
  });
}

// ---------------------------------------------------- concurrent roots

void concurrentRootTests() {
  group('OfficeController, several roots', () {
    test('two direct roots run at once, each in its own folder', () async {
      final h = Harness({
        Seat.claude: ScriptedAdapter(Seat.claude, [
          [
            ScriptedTurn.success('claude says hi', [
              ev(Seat.claude, AgentEventKind.textDelta, summary: 'hi'),
            ]),
          ],
        ]),
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [
            ScriptedTurn.success('gpt fixed it', [
              ev(Seat.gpt, AgentEventKind.toolStarted, summary: 'bash'),
            ]),
          ],
        ]),
      });
      await h.controller.submit('Fix /a', directSeat: Seat.gpt, cwd: '/a');
      expect(h.controller.snapshot.busy, isTrue);
      // A second root while the first is open: accepted, not refused.
      await h.controller.submit('Fix /b', directSeat: Seat.claude, cwd: '/b');
      final roots = h.controller.snapshot.tasks.where((t) => t.isRoot);
      expect(roots.map((t) => t.cwd).toSet(), {'/a', '/b'});
      expect(
        h.board.listNonTerminal().where((t) => t.kind == TaskKind.root),
        hasLength(2),
      );
      await h.waitIdle();
      final reports = h.controller.snapshot.reports;
      expect(reports, hasLength(2));
      expect(reports.map((r) => r.cwd).toSet(), {'/a', '/b'});
      expect(reports.map((r) => r.text).toSet(), {
        'claude says hi',
        'gpt fixed it',
      });
      expect(reports.every((r) => !r.failed), isTrue);
      expect(h.controller.snapshot.unreadReports, 2);
      expect(h.controller.snapshot.lastReport, reports.first.text);
      h.controller.markReportsRead();
      await Future<void>.delayed(Duration.zero);
      expect(h.controller.snapshot.unreadReports, 0);
      expect(h.controller.snapshot.reports, hasLength(2));
    });

    test('two roots for one desk: the second waits for the seat', () async {
      final h = Harness({
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [ScriptedTurn.success('first')],
          [ScriptedTurn.success('second')],
        ]),
      });
      await h.controller.submit('One', directSeat: Seat.gpt, cwd: '/one');
      await h.controller.submit('Two', directSeat: Seat.gpt, cwd: '/two');
      await h.waitIdle();
      final reports = h.controller.snapshot.reports;
      expect(reports.map((r) => r.title), ['Two', 'One']);
      expect(reports.map((r) => r.text), ['second', 'first']);
      expect(h.seat(Seat.gpt).xp, 20);
    });
  });
}

// -------------------------------------------------------------- pausing

void pauseTests() {
  group('OfficeController, pause', () {
    test('held prompts start when the office resumes', () async {
      final h = Harness({
        Seat.gpt: ScriptedAdapter(Seat.gpt, [
          [ScriptedTurn.success('done')],
        ]),
      });
      await h.controller.setPaused(true);
      expect(h.controller.paused, isTrue);
      expect(h.controller.snapshot.paused, isTrue);
      expect(h.controller.snapshot.statusLine, 'Ofis duraklatıldı');
      await h.controller.submit('Later', directSeat: Seat.gpt, cwd: '/x');
      expect(h.controller.snapshot.busy, isFalse);
      expect(h.board.listNonTerminal(), isEmpty);
      await h.controller.setPaused(false);
      expect(h.controller.snapshot.paused, isFalse);
      expect(h.controller.snapshot.busy, isTrue);
      await h.waitIdle();
      expect(h.controller.snapshot.reports.single.cwd, '/x');
      expect(h.controller.snapshot.reports.single.text, 'done');
    });
  });
}
