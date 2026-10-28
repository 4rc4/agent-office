@Tags(['golden'])
library;

import 'package:agent_office_app/app.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:agent_office_app/widgets/office_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

import 'support/fake_office_model.dart';
import 'support/test_fonts.dart';

/// A fixed clock so event rows render the same time on every run.
final DateTime _t0 = DateTime(2026, 10, 28, 9, 30);

AgentEvent _event(
  Seat seat,
  AgentEventKind kind,
  String summary, {
  ToolCategory? category,
  int minute = 0,
}) => AgentEvent(
  seat: seat,
  kind: kind,
  summary: summary,
  category: category,
  taskId: seat == Seat.claude ? 'r1' : 's1',
  sessionRef: seat == Seat.claude ? 'sess-claude-7f3a9c' : 'sess-gpt-b21e04',
  timestamp: _t0.add(Duration(minutes: minute)),
);

/// The office in the middle of a run: Claude plans and types, GPT runs the
/// tests in a shell, Gemini's chair is empty, four notes on the whiteboard.
OfficeSnapshot busySnapshot() {
  final events = [
    _event(Seat.claude, AgentEventKind.sessionStarted, 'Oturum başladı'),
    _event(
      Seat.claude,
      AgentEventKind.thinking,
      'Plan hazırlanıyor',
      minute: 1,
    ),
    _event(
      Seat.gpt,
      AgentEventKind.toolStarted,
      'Bash: flutter test',
      category: ToolCategory.shell,
      minute: 2,
    ),
    _event(
      Seat.gpt,
      AgentEventKind.fileChanged,
      'lib/widgets/prompt_bar.dart',
      category: ToolCategory.edit,
      minute: 3,
    ),
    _event(
      Seat.claude,
      AgentEventKind.textDelta,
      'Testler yeşile döndü, birleştirme bekleniyor',
      minute: 4,
    ),
  ];
  const tasks = [
    TaskSnapshot(
      id: 'r1',
      rootId: 'r1',
      title: 'Testleri yeşile çevir',
      status: TaskStatus.running,
      isRoot: true,
      assignee: Seat.claude,
    ),
    TaskSnapshot(
      id: 's1',
      rootId: 'r1',
      title: 'Widget testini düzelt',
      status: TaskStatus.running,
      isRoot: false,
      assignee: Seat.gpt,
      attempt: 1,
    ),
    TaskSnapshot(
      id: 's2',
      rootId: 'r1',
      title: 'Analyzer uyarısı',
      status: TaskStatus.done,
      isRoot: false,
      assignee: Seat.claude,
      resultSummary: 'Temiz.',
    ),
    TaskSnapshot(
      id: 's3',
      rootId: 'r1',
      title: 'Golden güncelle',
      status: TaskStatus.queued,
      isRoot: false,
    ),
  ];
  return OfficeSnapshot(
    seats: const [
      SeatSnapshot(
        seat: Seat.claude,
        visual: SeatVisual.typing,
        currentTaskId: 'r1',
        currentTaskTitle: 'Testleri yeşile çevir',
        lastSummary: 'Testler yeşile döndü, birleştirme bekleniyor',
        xp: 40,
        tokensIn: 18240,
        tokensOut: 2310,
        sessionRef: 'sess-claude-7f3a9c',
      ),
      SeatSnapshot(
        seat: Seat.gpt,
        visual: SeatVisual.shell,
        bubble: SeatBubble(text: 'flutter test çalışıyor'),
        currentTaskId: 's1',
        currentTaskTitle: 'Widget testini düzelt',
        lastSummary: 'lib/widgets/prompt_bar.dart',
        xp: 20,
        tokensIn: 9120,
        tokensOut: 1480,
        sessionRef: 'sess-gpt-b21e04',
      ),
      SeatSnapshot(seat: Seat.gemini, visual: SeatVisual.empty),
    ],
    tasks: tasks,
    recentEvents: events,
    busy: true,
    statusLine: 'GPT çalışıyor: Widget testini düzelt',
  );
}

Future<void> _pumpApp(
  WidgetTester tester,
  Size size,
  FakeOfficeModel model,
) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AgentOfficeApp(model: model, tick: ValueNotifier<int>(1)),
  );
  // The busy spinner animates forever, so pump one frame instead of settling.
  await tester.pump();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadSdkFonts();
  });

  group('OfficeScreen goldens', () {
    testWidgets('busy office at 960x540', (tester) async {
      final model = FakeOfficeModel(snapshot: busySnapshot());
      await _pumpApp(tester, const Size(960, 540), model);
      expect(find.byType(OfficeScreen), findsOneWidget);
      await expectLater(
        find.byType(AgentOfficeApp),
        matchesGoldenFile('goldens/office_screen_960.png'),
      );
    });

    testWidgets('busy office at 1280x720', (tester) async {
      final model = FakeOfficeModel(snapshot: busySnapshot());
      await _pumpApp(tester, const Size(1280, 720), model);
      await expectLater(
        find.byType(AgentOfficeApp),
        matchesGoldenFile('goldens/office_screen_1280.png'),
      );
    });

    testWidgets('busy office with the Claude panel open at 1280x720', (
      tester,
    ) async {
      final model = FakeOfficeModel(snapshot: busySnapshot())
        ..selectSeat(Seat.claude);
      await _pumpApp(tester, const Size(1280, 720), model);
      expect(find.byKey(OfficeScreen.sidePanelKey), findsOneWidget);
      await expectLater(
        find.byType(AgentOfficeApp),
        matchesGoldenFile('goldens/office_screen_1280_panel.png'),
      );
    });
  });
}
