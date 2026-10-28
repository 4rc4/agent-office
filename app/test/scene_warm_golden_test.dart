import 'package:agent_office_app/scene_warm/office_scene.dart';
import 'package:agent_office_app/scene_warm/scene_layout.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

TaskSnapshot _task(String id, TaskStatus status, {bool isRoot = false}) =>
    TaskSnapshot(
      id: id,
      rootId: isRoot ? id : 'root',
      title: 'Task $id',
      status: status,
      isRoot: isRoot,
    );

OfficeSnapshot _snapshot({
  required SeatVisual claude,
  required SeatVisual gpt,
  required SeatVisual gemini,
  SeatBubble? claudeBubble,
  SeatBubble? gptBubble,
  SeatBubble? geminiBubble,
  List<TaskSnapshot> tasks = const [],
  String? lastReport,
}) => OfficeSnapshot(
  seats: [
    SeatSnapshot(seat: Seat.claude, visual: claude, bubble: claudeBubble),
    SeatSnapshot(seat: Seat.gpt, visual: gpt, bubble: gptBubble),
    SeatSnapshot(seat: Seat.gemini, visual: gemini, bubble: geminiBubble),
  ],
  tasks: tasks,
  busy: true,
  lastReport: lastReport,
  statusLine: 'busy',
);

final OfficeSnapshot _busy = _snapshot(
  claude: SeatVisual.typing,
  gpt: SeatVisual.shell,
  gemini: SeatVisual.empty,
  gptBubble: const SeatBubble(text: 'flutter test çalışıyor'),
  tasks: [
    _task('root', TaskStatus.running, isRoot: true),
    _task('a', TaskStatus.done),
    _task('b', TaskStatus.running),
    _task('c', TaskStatus.queued),
  ],
);

final OfficeSnapshot _waiting = _snapshot(
  claude: SeatVisual.waitingUser,
  gpt: SeatVisual.onBreak,
  gemini: SeatVisual.failed,
  claudeBubble: const SeatBubble(
    text: 'Onay gerekli: migration dosyası yazılsın mı?',
    kind: BubbleKind.question,
  ),
  gptBubble: const SeatBubble(text: 'Limit: 5 dk', kind: BubbleKind.warning),
  geminiBubble: const SeatBubble(
    text: 'Hata: test kırmızı',
    kind: BubbleKind.error,
  ),
  tasks: [
    _task('root', TaskStatus.waitingUser, isRoot: true),
    _task('a', TaskStatus.failed),
    _task('b', TaskStatus.waitingBudget),
  ],
  lastReport: '# Rapor',
);

final OfficeSnapshot _quietWork = _snapshot(
  claude: SeatVisual.reading,
  gpt: SeatVisual.browsing,
  gemini: SeatVisual.sleeping,
);

final OfficeSnapshot _creative = _snapshot(
  claude: SeatVisual.thinking,
  gpt: SeatVisual.editing,
  gemini: SeatVisual.celebrating,
  geminiBubble: const SeatBubble(text: 'Bitti!', kind: BubbleKind.success),
  tasks: [
    for (var i = 0; i < 10; i++)
      _task('t$i', TaskStatus.values[i % TaskStatus.values.length]),
  ],
);

Future<SceneFit> _pump(
  WidgetTester tester,
  OfficeSnapshot snapshot,
  int tick,
  Key key, {
  void Function(SceneTarget target)? onTap,
  List<double>? gaugeLevels,
}) async {
  const size = Size(960, 540);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    Directionality(
      textDirection: TextDirection.ltr,
      child: RepaintBoundary(
        key: key,
        child: OfficeScene(
          snapshot: snapshot,
          tick: tick,
          onTap: onTap ?? (_) {},
          gaugeLevels: gaugeLevels ?? const [0, 0, 0],
        ),
      ),
    ),
  );
  return SceneFit.compute(size);
}

void main() {
  group('warm OfficeScene goldens', () {
    testWidgets('initial office', (tester) async {
      const key = Key('scene');
      await _pump(tester, OfficeSnapshot.initial(), 0, key);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/scene_warm_initial.png'),
      );
    }, tags: ['golden']);

    testWidgets('busy office', (tester) async {
      const key = Key('scene');
      await _pump(tester, _busy, 1, key, gaugeLevels: const [0.6, 0.3, 0.0]);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/scene_warm_busy.png'),
      );
    }, tags: ['golden']);

    testWidgets('waiting, break and failure', (tester) async {
      const key = Key('scene');
      await _pump(tester, _waiting, 2, key, gaugeLevels: const [0.9, 1.0, 0.4]);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/scene_warm_waiting.png'),
      );
    }, tags: ['golden']);

    testWidgets('reading, browsing, sleeping', (tester) async {
      const key = Key('scene');
      await _pump(tester, _quietWork, 3, key);
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/scene_warm_quiet.png'),
      );
    }, tags: ['golden']);

    testWidgets('thinking, editing, celebrating', (tester) async {
      const key = Key('scene');
      await _pump(
        tester,
        _creative,
        2,
        key,
        gaugeLevels: const [0.2, 0.5, 0.8],
      );
      await expectLater(
        find.byKey(key),
        matchesGoldenFile('goldens/scene_warm_creative.png'),
      );
    }, tags: ['golden']);
  });

  group('warm SceneLayout.hitTest', () {
    Offset center(IRect r) => Offset(r.x + r.w / 2, r.y + r.h / 2);

    test('each desk reports its seat', () {
      for (final seat in Seat.values) {
        final rect = SceneLayout.placement(seat).hitRect;
        expect(SceneLayout.hitTest(center(rect)), SceneTarget.seat(seat));
      }
    });

    test('furniture targets', () {
      expect(
        SceneLayout.hitTest(center(SceneLayout.whiteboard)),
        SceneTarget.whiteboard,
      );
      expect(
        SceneLayout.hitTest(center(SceneLayout.mailboxArea)),
        SceneTarget.mailbox,
      );
      expect(
        SceneLayout.hitTest(center(SceneLayout.coffeeMachine)),
        SceneTarget.coffee,
      );
      expect(
        SceneLayout.hitTest(center(SceneLayout.cabinet)),
        SceneTarget.cabinet,
      );
    });

    test('floor, wall and outside report nothing', () {
      expect(SceneLayout.hitTest(const Offset(240, 262)), isNull);
      expect(SceneLayout.hitTest(const Offset(176, 110)), isNull);
      expect(SceneLayout.hitTest(const Offset(-1, 10)), isNull);
      expect(SceneLayout.hitTest(const Offset(10, 300)), isNull);
    });

    test('seat rects do not overlap each other or the furniture', () {
      final rects = <IRect>[
        for (final p in SceneLayout.placements) p.hitRect,
        SceneLayout.whiteboard,
        SceneLayout.mailboxArea,
        SceneLayout.coffeeArea,
        SceneLayout.cabinet,
      ];
      for (var i = 0; i < rects.length; i++) {
        for (var j = i + 1; j < rects.length; j++) {
          expect(
            rects[i].rect.overlaps(rects[j].rect),
            isFalse,
            reason: '${rects[i]} overlaps ${rects[j]}',
          );
        }
      }
    });
  });

  group('warm OfficeScene taps', () {
    testWidgets('map widget taps back to scene targets', (tester) async {
      final taps = <SceneTarget>[];
      final fit = await _pump(
        tester,
        OfficeSnapshot.initial(),
        0,
        const Key('scene'),
        onTap: taps.add,
      );
      expect(fit.scale, 2);
      expect(fit.origin, Offset.zero);

      Offset at(IRect r) => fit.fromScene(Offset(r.x + r.w / 2, r.y + r.h / 2));
      await tester.tapAt(at(SceneLayout.claude.hitRect));
      await tester.tapAt(at(SceneLayout.gpt.hitRect));
      await tester.tapAt(at(SceneLayout.gemini.hitRect));
      await tester.tapAt(at(SceneLayout.whiteboard));
      await tester.tapAt(at(SceneLayout.mailboxArea));
      await tester.tapAt(at(SceneLayout.coffeeCounter));
      await tester.tapAt(at(SceneLayout.cabinet));
      await tester.tapAt(fit.fromScene(const Offset(240, 262)));
      expect(taps, const [
        SceneTarget.seat(Seat.claude),
        SceneTarget.seat(Seat.gpt),
        SceneTarget.seat(Seat.gemini),
        SceneTarget.whiteboard,
        SceneTarget.mailbox,
        SceneTarget.coffee,
        SceneTarget.cabinet,
      ]);
    });

    testWidgets('empty taps reach onTapEmpty', (tester) async {
      var empty = 0;
      const size = Size(960, 540);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: OfficeScene(
            snapshot: OfficeSnapshot.initial(),
            tick: 0,
            onTap: (_) => fail('floor tap reported a target'),
            onTapEmpty: () => empty++,
          ),
        ),
      );
      final fit = SceneFit.compute(size);
      await tester.tapAt(fit.fromScene(const Offset(240, 262)));
      expect(empty, 1);
    });

    test('SceneFit picks the largest integer scale and centres', () {
      final fit = SceneFit.compute(const Size(1000, 600));
      expect(fit.scale, 2);
      expect(fit.origin, const Offset(20, 30));
      expect(SceneFit.compute(const Size(200, 100)).scale, 1);
      expect(SceneFit.compute(const Size(640, 360)).scale, 1);
      expect(SceneFit.compute(const Size(1440, 810)).scale, 3);
      expect(
        fit.toScene(fit.fromScene(const Offset(12, 34))),
        const Offset(12, 34),
      );
    });
  });
}
