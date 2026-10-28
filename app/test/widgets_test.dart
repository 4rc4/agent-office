import 'package:agent_office_app/app.dart';
import 'package:agent_office_app/l10n_tr.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:agent_office_app/widgets/mailbox_dialog.dart';
import 'package:agent_office_app/widgets/office_screen.dart';
import 'package:agent_office_app/widgets/prompt_bar.dart';
import 'package:agent_office_app/widgets/scene_tap_router.dart';
import 'package:agent_office_app/widgets/seat_panel.dart';
import 'package:agent_office_app/widgets/whiteboard_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

import 'support/fake_office_model.dart';

// ------------------------------------------------------------- fake model

/// Mimics the scene's `SceneTarget` by `toString` only.
class FakeTarget {
  const FakeTarget(this.text);

  final String text;

  @override
  String toString() => text;
}

/// Placeholder scene: one button per tappable thing, plus the tick.
Widget placeholderScene(
  BuildContext context,
  OfficeSnapshot snapshot,
  int tick,
  void Function(Object target) onTap,
) {
  Widget button(String label, Object target) => TextButton(
    key: Key('scene.$label'),
    onPressed: () => onTap(target),
    child: Text('scene:$label'),
  );
  return Column(
    children: [
      Text('tick:$tick'),
      button('claude', const FakeTarget('SceneTarget.seat(claude)')),
      button('gpt', const FakeTarget('SceneTarget.seat(gpt)')),
      button('whiteboard', const FakeTarget('SceneTarget.whiteboard')),
      button('mailbox', const FakeTarget('SceneTarget.mailbox')),
      button('cabinet', const FakeTarget('SceneTarget.cabinet')),
      button('coffee', const FakeTarget('SceneTarget.coffee')),
    ],
  );
}

OfficeSnapshot snapshotWith({
  List<TaskSnapshot> tasks = const [],
  List<AgentEvent> events = const [],
  bool busy = false,
  String? lastReport,
  String statusLine = 'Ofis sakin.',
}) {
  return OfficeSnapshot(
    seats: OfficeSnapshot.initial().seats,
    tasks: tasks,
    recentEvents: events,
    busy: busy,
    lastReport: lastReport,
    statusLine: statusLine,
  );
}

Future<void> pumpScreen(
  WidgetTester tester,
  FakeOfficeModel model, {
  Size size = const Size(1280, 800),
  ValueNotifier<int>? tick,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: OfficeScreen(
        model: model,
        tick: tick ?? ValueNotifier<int>(0),
        sceneBuilder: placeholderScene,
      ),
    ),
  );
}

Future<void> chooseMode(WidgetTester tester, String label) async {
  await tester.tap(find.byKey(PromptBar.modeDropdownKey));
  await tester.pumpAndSettle();
  await tester.tap(find.text(label).last);
  await tester.pumpAndSettle();
}

Future<void> typeAndSend(WidgetTester tester, String prompt) async {
  await tester.enterText(find.byKey(PromptBar.promptFieldKey), prompt);
  await tester.tap(find.byKey(PromptBar.sendButtonKey));
  await tester.pumpAndSettle();
}

// ------------------------------------------------------------------ tests

void main() {
  group('SceneTapRouter', () {
    test('reads seats, furniture and bare Seat values', () {
      expect(
        SceneTapRouter.classify(const FakeTarget('SceneTarget.seat(gpt)')).seat,
        Seat.gpt,
      );
      expect(
        SceneTapRouter.classify(
          const FakeTarget('SceneTarget.whiteboard'),
        ).kind,
        SceneTapKind.whiteboard,
      );
      expect(
        SceneTapRouter.classify(const FakeTarget('SceneTarget.mailbox')).kind,
        SceneTapKind.mailbox,
      );
      expect(
        SceneTapRouter.classify(const FakeTarget('SceneTarget.coffee')).kind,
        SceneTapKind.coffee,
      );
      expect(
        SceneTapRouter.classify(const FakeTarget('SceneTarget.cabinet')).kind,
        SceneTapKind.cabinet,
      );
      expect(SceneTapRouter.classify(Seat.gemini).seat, Seat.gemini);
      expect(
        SceneTapRouter.classify(const FakeTarget('nothing')).kind,
        SceneTapKind.unknown,
      );
    });
  });

  group('PromptBar', () {
    testWidgets('Send submits to the office with no direct seat', (
      tester,
    ) async {
      final model = FakeOfficeModel();
      await pumpScreen(tester, model);
      await typeAndSend(tester, 'Testleri yeşile çevir');
      expect(model.submissions, hasLength(1));
      expect(model.submissions.single.prompt, 'Testleri yeşile çevir');
      expect(model.submissions.single.directSeat, isNull);
      final field = tester.widget<TextField>(
        find.byKey(PromptBar.promptFieldKey),
      );
      expect(field.controller!.text, isEmpty);
    });

    testWidgets('Sadece Claude sends directSeat claude', (tester) async {
      final model = FakeOfficeModel();
      await pumpScreen(tester, model);
      await chooseMode(tester, Tr.modeClaudeOnly);
      await typeAndSend(tester, 'Sadece sen bak');
      expect(model.submissions.single.directSeat, Seat.claude);
    });

    testWidgets('Sadece GPT sends directSeat gpt', (tester) async {
      final model = FakeOfficeModel();
      await pumpScreen(tester, model);
      await chooseMode(tester, Tr.modeGptOnly);
      await typeAndSend(tester, 'GPT yapsın');
      expect(model.submissions.single.directSeat, Seat.gpt);
    });

    testWidgets('Enter sends, Shift+Enter does not', (tester) async {
      final model = FakeOfficeModel();
      await pumpScreen(tester, model);
      await tester.enterText(find.byKey(PromptBar.promptFieldKey), 'Merhaba');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(model.submissions.map((s) => s.prompt), ['Merhaba']);

      await tester.enterText(find.byKey(PromptBar.promptFieldKey), 'İkinci');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pumpAndSettle();
      expect(model.submissions, hasLength(1));
      final field = tester.widget<TextField>(
        find.byKey(PromptBar.promptFieldKey),
      );
      expect(field.controller!.text, contains('İkinci'));
    });

    testWidgets('empty prompt is not sent', (tester) async {
      final model = FakeOfficeModel();
      await pumpScreen(tester, model);
      await typeAndSend(tester, '   ');
      expect(model.submissions, isEmpty);
    });

    testWidgets('Send is disabled while busy and Stop calls stopAll', (
      tester,
    ) async {
      final model = FakeOfficeModel(
        snapshot: snapshotWith(busy: true, statusLine: 'Claude planlıyor…'),
      );
      await pumpScreen(tester, model);
      final send = tester.widget<FilledButton>(
        find.byKey(PromptBar.sendButtonKey),
      );
      expect(send.onPressed, isNull);
      expect(find.text(Tr.working), findsOneWidget);
      expect(find.text('Claude planlıyor…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // The spinner animates forever, so pump a frame instead of settling.
      await tester.tap(find.byKey(PromptBar.stopButtonKey));
      await tester.pump();
      expect(model.stopCalls, 1);

      model.snapshot = snapshotWith(busy: false);
      await tester.pumpAndSettle();
      expect(find.byKey(PromptBar.stopButtonKey), findsNothing);
      expect(
        tester
            .widget<FilledButton>(find.byKey(PromptBar.sendButtonKey))
            .onPressed,
        isNotNull,
      );
    });

    testWidgets('a refused submit keeps the text and shows the error', (
      tester,
    ) async {
      final model = FakeOfficeModel()..submitError = StateError(Tr.busyRefused);
      await pumpScreen(tester, model);
      await typeAndSend(tester, 'Bekle');
      final field = tester.widget<TextField>(
        find.byKey(PromptBar.promptFieldKey),
      );
      expect(field.controller!.text, 'Bekle');
      expect(find.textContaining(Tr.submitFailed), findsOneWidget);
    });

    testWidgets('folder field shows and edits cwd', (tester) async {
      final model = FakeOfficeModel(cwdValue: '/repo/a');
      await pumpScreen(tester, model);
      expect(find.text('/repo/a'), findsOneWidget);
      await tester.enterText(find.byKey(PromptBar.folderFieldKey), '/repo/b');
      await tester.pumpAndSettle();
      expect(model.cwd, '/repo/b');
    });
  });

  group('OfficeScreen panels', () {
    testWidgets('tapping a seat opens the side panel with its name', (
      tester,
    ) async {
      final events = [
        AgentEvent(
          seat: Seat.claude,
          kind: AgentEventKind.toolStarted,
          category: ToolCategory.shell,
          summary: 'Bash: flutter test',
        ),
        AgentEvent(
          seat: Seat.gpt,
          kind: AgentEventKind.textDelta,
          summary: 'GPT writes',
        ),
      ];
      final model = FakeOfficeModel(snapshot: snapshotWith(events: events));
      await pumpScreen(tester, model);
      expect(find.byType(SeatPanel), findsNothing);

      await tester.tap(find.byKey(const Key('scene.claude')));
      await tester.pumpAndSettle();
      expect(model.selectedSeat, Seat.claude);
      expect(find.byKey(OfficeScreen.sidePanelKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SeatPanel),
          matching: find.text('Claude'),
        ),
        findsOneWidget,
      );
      expect(find.text(Tr.visualLabel(SeatVisual.idle)), findsOneWidget);
      expect(find.text('Bash: flutter test'), findsOneWidget);
      expect(find.text('GPT writes'), findsNothing);

      await tester.tap(find.byKey(SeatPanel.closeButtonKey));
      await tester.pumpAndSettle();
      expect(model.selectedSeat, isNull);
      expect(find.byType(SeatPanel), findsNothing);
    });

    testWidgets('tapping the selected seat again closes the panel', (
      tester,
    ) async {
      final model = FakeOfficeModel();
      await pumpScreen(tester, model);
      await tester.tap(find.byKey(const Key('scene.gpt')));
      await tester.pumpAndSettle();
      expect(model.selectedSeat, Seat.gpt);
      await tester.tap(find.byKey(const Key('scene.gpt')));
      await tester.pumpAndSettle();
      expect(model.selectedSeat, isNull);
    });

    testWidgets('narrow windows show the panel as a bottom sheet', (
      tester,
    ) async {
      final model = FakeOfficeModel();
      await pumpScreen(tester, model, size: const Size(800, 600));
      await tester.tap(find.byKey(const Key('scene.claude')));
      await tester.pumpAndSettle();
      expect(find.byKey(OfficeScreen.bottomSheetKey), findsOneWidget);
      expect(find.byKey(OfficeScreen.sidePanelKey), findsNothing);
      expect(find.byType(SeatPanel), findsOneWidget);
    });

    testWidgets('the mailbox dialog shows lastReport and copies it', (
      tester,
    ) async {
      const report = '# Rapor\n\nHer şey yeşil.';
      final model = FakeOfficeModel(snapshot: snapshotWith(lastReport: report));
      await pumpScreen(tester, model);
      await tester.tap(find.byKey(const Key('scene.mailbox')));
      await tester.pumpAndSettle();
      expect(find.byType(MailboxDialog), findsOneWidget);
      expect(find.text(report), findsOneWidget);

      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.byKey(MailboxDialog.copyButtonKey));
      await tester.pumpAndSettle();
      expect(copied, report);
      expect(find.text(Tr.copied), findsOneWidget);

      await tester.tap(find.byKey(MailboxDialog.closeButtonKey));
      await tester.pumpAndSettle();
      expect(find.byType(MailboxDialog), findsNothing);
    });

    testWidgets('an empty mailbox says so', (tester) async {
      final model = FakeOfficeModel();
      await pumpScreen(tester, model);
      await tester.tap(find.byKey(const Key('scene.mailbox')));
      await tester.pumpAndSettle();
      expect(find.text(Tr.noReport), findsOneWidget);
      expect(find.byKey(MailboxDialog.copyButtonKey), findsNothing);
    });

    testWidgets('the whiteboard lists tasks by status with assignees', (
      tester,
    ) async {
      final tasks = [
        const TaskSnapshot(
          id: 'r1',
          rootId: 'r1',
          title: 'Testleri yeşile çevir',
          status: TaskStatus.running,
          isRoot: true,
          assignee: Seat.claude,
        ),
        const TaskSnapshot(
          id: 's1',
          rootId: 'r1',
          title: 'Widget testini düzelt',
          status: TaskStatus.running,
          isRoot: false,
          assignee: Seat.gpt,
          attempt: 2,
        ),
        const TaskSnapshot(
          id: 's2',
          rootId: 'r1',
          title: 'Analyzer uyarısı',
          status: TaskStatus.done,
          isRoot: false,
          resultSummary: 'Temiz.',
        ),
      ];
      final model = FakeOfficeModel(snapshot: snapshotWith(tasks: tasks));
      await pumpScreen(tester, model);
      await tester.tap(find.byKey(const Key('scene.whiteboard')));
      await tester.pumpAndSettle();
      expect(find.byType(WhiteboardPanel), findsOneWidget);
      expect(find.text('Testleri yeşile çevir'), findsOneWidget);
      expect(find.text('Widget testini düzelt'), findsOneWidget);
      expect(find.text('Analyzer uyarısı'), findsOneWidget);
      expect(find.text('Temiz.'), findsOneWidget);
      expect(
        find.text('${Tr.statusLabel(TaskStatus.running)} · 2'),
        findsOneWidget,
      );
      expect(
        find.text('${Tr.statusLabel(TaskStatus.done)} · 1'),
        findsOneWidget,
      );
      expect(find.text('Claude'), findsOneWidget);
      expect(find.text('GPT'), findsOneWidget);
      expect(find.text(Tr.unassigned), findsOneWidget);
      expect(find.text('${Tr.attempt} 2'), findsOneWidget);

      await tester.tap(find.byKey(WhiteboardPanel.closeButtonKey));
      await tester.pumpAndSettle();
      expect(find.byType(WhiteboardPanel), findsNothing);
    });

    testWidgets('the cabinet opens the event log', (tester) async {
      final events = [
        AgentEvent(
          seat: Seat.gpt,
          kind: AgentEventKind.fileChanged,
          summary: 'edit lib/a.dart',
        ),
      ];
      final model = FakeOfficeModel(snapshot: snapshotWith(events: events));
      await pumpScreen(tester, model);
      await tester.tap(find.byKey(const Key('scene.cabinet')));
      await tester.pumpAndSettle();
      expect(find.text('${Tr.events} · 1'), findsOneWidget);
      expect(find.text('edit lib/a.dart'), findsOneWidget);
    });

    testWidgets('the coffee corner opens the event log too', (tester) async {
      final events = [
        AgentEvent(
          seat: Seat.claude,
          kind: AgentEventKind.rateLimit,
          summary: 'limit: 5 dk',
        ),
      ];
      final model = FakeOfficeModel(snapshot: snapshotWith(events: events));
      await pumpScreen(tester, model);
      await tester.tap(find.byKey(const Key('scene.coffee')));
      await tester.pumpAndSettle();
      expect(find.text('${Tr.events} · 1'), findsOneWidget);
      expect(find.text('limit: 5 dk'), findsOneWidget);
    });

    testWidgets('the scene follows the tick', (tester) async {
      final model = FakeOfficeModel();
      final tick = ValueNotifier<int>(0);
      await pumpScreen(tester, model, tick: tick);
      expect(find.text('tick:0'), findsOneWidget);
      tick.value = 7;
      await tester.pump();
      expect(find.text('tick:7'), findsOneWidget);
    });
  });

  group('AgentOfficeApp', () {
    testWidgets('builds the screen with the real scene', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final model = FakeOfficeModel();
      await tester.pumpWidget(
        AgentOfficeApp(model: model, tick: ValueNotifier<int>(0)),
      );
      await tester.pump();
      expect(find.byType(OfficeScreen), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.byKey(PromptBar.sendButtonKey), findsOneWidget);
    });
  });
}
