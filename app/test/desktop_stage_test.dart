import 'package:agent_office_app/desktop/autostart.dart';
import 'package:agent_office_app/desktop/desktop_app.dart';
import 'package:agent_office_app/desktop/desktop_layer.dart';
import 'package:agent_office_app/desktop/desktop_stage.dart';
import 'package:agent_office_app/desktop/info_bubbles.dart';
import 'package:agent_office_app/desktop/prompt_bubble.dart';
import 'package:agent_office_app/desktop/settings_bubble.dart';
import 'package:agent_office_app/desktop/stations.dart';
import 'package:agent_office_app/runtime/office_settings.dart';
import 'package:agent_office_app/state/seat_state.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:office_core/office_core.dart';

import 'support/desktop_fixtures.dart';
import 'support/fake_desktop_channel.dart';
import 'support/fake_office_model.dart';
import 'support/test_fonts.dart';

void main() {
  late FakeDesktopChannel runner;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPixelFont();
  });
  setUp(() => runner = FakeDesktopChannel());
  tearDown(() => runner.dispose());
  settingsTests(() => runner);

  Future<void> tapActor(WidgetTester tester, Seat seat) async {
    await tester.tap(find.byKey(DesktopStage.actorKey(seat)));
    await tester.pump();
    await tester.pump();
  }

  Future<void> tapStation(WidgetTester tester, StationKind kind) async {
    await tester.tap(find.byKey(DesktopStage.stationKey(kind)));
    await tester.pump();
    await tester.pump();
  }

  group('DesktopStage', () {
    testWidgets('reports every station and character as a hit rect', (
      tester,
    ) async {
      await pumpDesktop(tester, FakeOfficeModel());
      expect(find.byKey(DesktopStage.actorKey(Seat.claude)), findsOneWidget);
      expect(find.byKey(DesktopStage.actorKey(Seat.gpt)), findsOneWidget);
      for (final kind in StationKind.values) {
        expect(find.byKey(DesktopStage.stationKey(kind)), findsOneWidget);
      }
      final rects = runner.hitRectCalls.last;
      expect(rects, hasLength((StationKind.values.length + 2) * 4));
      // Every rect stands on the floor (600 + 4 px inflation) at DPR 1.
      for (var i = 3; i < rects.length; i += 4) {
        expect(rects[i], 604);
      }
    });

    testWidgets('the Claude bubble sends an office task in the folder', (
      tester,
    ) async {
      final model = FakeOfficeModel();
      final saved = <OfficeSettings>[];
      await pumpDesktop(tester, model, onSettingsChanged: saved.add);
      await tapActor(tester, Seat.claude);
      expect(find.text('Ne yapalım?'), findsOneWidget);
      expect(find.text(repoFolder), findsOneWidget);
      expect(find.text('agent-office'), findsOneWidget); // chip of the other
      expect(runner.methods, contains('bringToFront'));
      await tester.enterText(find.byKey(PromptBubble.fieldKey), 'Lint düzelt');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byType(PromptBubble), findsNothing);
      final sent = model.submissions.single;
      expect(sent.prompt, 'Lint düzelt');
      expect(sent.directSeat, isNull);
      expect(sent.cwd, repoFolder);
      // The folder was already first in the recent list: nothing to save.
      expect(saved, isEmpty);
      expect(runner.methods, contains('sendToBack'));
    });

    testWidgets('a folder chip switches the folder before sending', (
      tester,
    ) async {
      final model = FakeOfficeModel();
      final saved = <OfficeSettings>[];
      await pumpDesktop(tester, model, onSettingsChanged: saved.add);
      await tapActor(tester, Seat.claude);
      await tester.tap(find.text('agent-office'));
      await tester.pump();
      expect(find.text(otherFolder), findsOneWidget);
      await tester.enterText(find.byKey(PromptBubble.fieldKey), 'README');
      await tester.tap(find.byKey(PromptBubble.sendButtonKey));
      await tester.pump();
      expect(model.submissions.single.cwd, otherFolder);
      expect(saved.single.recentFolders, [otherFolder, repoFolder]);
    });

    testWidgets('the GPT bubble sends a direct task', (tester) async {
      final model = FakeOfficeModel();
      await pumpDesktop(tester, model);
      await tapActor(tester, Seat.gpt);
      expect(find.text('GPT ne yapsın?'), findsOneWidget);
      await tester.enterText(find.byKey(PromptBubble.fieldKey), 'Testi yaz');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(model.submissions.single.directSeat, Seat.gpt);
      expect(model.submissions.single.cwd, repoFolder);
    });

    testWidgets('a working character shows its status and can be stopped', (
      tester,
    ) async {
      final model = FakeOfficeModel(snapshot: workingSnapshot());
      await pumpDesktop(tester, model);
      await tapActor(tester, Seat.claude);
      expect(find.byType(StatusBubble), findsOneWidget);
      expect(find.text('Claude · Yazıyor'), findsOneWidget);
      expect(find.text('Testleri yeşile çevir'), findsOneWidget);
      expect(find.textContaining('18240'), findsOneWidget);
      await tester.tap(find.byKey(StatusBubble.stopButtonKey));
      await tester.pump();
      expect(model.stopCalls, 1);
      expect(find.byType(StatusBubble), findsNothing);
    });

    testWidgets('the whiteboard lists tasks by root with the folder', (
      tester,
    ) async {
      final model = FakeOfficeModel(snapshot: workingSnapshot());
      await pumpDesktop(tester, model);
      await tapStation(tester, StationKind.whiteboard);
      expect(find.byType(WhiteboardBubble), findsOneWidget);
      expect(find.text('Testleri yeşile çevir · repo'), findsOneWidget);
      expect(find.text('Widget testini düzelt'), findsOneWidget);
      expect(find.text('Bitti · Claude'), findsOneWidget);
      await tapStation(tester, StationKind.whiteboard);
      expect(find.byType(WhiteboardBubble), findsNothing);
    });

    testWidgets('the mailbox shows the letter, marks it read and copies', (
      tester,
    ) async {
      final model = FakeOfficeModel(snapshot: workingSnapshot());
      await pumpDesktop(tester, model);
      await tapStation(tester, StationKind.mailbox);
      expect(find.byType(MailboxBubble), findsOneWidget);
      expect(find.textContaining('README güncellendi'), findsOneWidget);
      expect(find.textContaining('agent-office'), findsOneWidget);
      expect(model.markReadCalls, 1);
      final copied = <Object?>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.setData') copied.add(call.arguments);
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null),
      );
      await tester.tap(find.byKey(MailboxBubble.copyButtonKey));
      await tester.pump();
      expect(find.text('Kopyalandı'), findsOneWidget);
      expect(copied.single, {'text': '# Rapor\n\nREADME güncellendi.'});
    });

    testWidgets('dragging a station persists its position', (tester) async {
      final saved = <OfficeSettings>[];
      await pumpDesktop(
        tester,
        FakeOfficeModel(),
        onSettingsChanged: saved.add,
      );
      final before = tester.getCenter(
        find.byKey(DesktopStage.stationKey(StationKind.mailbox)),
      );
      await tester.drag(
        find.byKey(DesktopStage.stationKey(StationKind.mailbox)),
        const Offset(-200, 0),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pump();
      final after = tester.getCenter(
        find.byKey(DesktopStage.stationKey(StationKind.mailbox)),
      );
      expect(after.dx, closeTo(before.dx - 200, 1));
      expect(
        saved.single.stationPositions['mailbox'],
        closeTo(0.92 - 200 / 1280, 0.001),
      );
    });

    testWidgets('Esc closes the bubble, a second Esc quits', (tester) async {
      await pumpDesktop(tester, FakeOfficeModel());
      await tapActor(tester, Seat.claude);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(PromptBubble), findsNothing);
      expect(runner.methods, isNot(contains('quit')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(runner.methods, contains('quit'));
    });

    testWidgets('focusLost from the runner closes the bubble', (tester) async {
      await pumpDesktop(tester, FakeOfficeModel());
      await tapActor(tester, Seat.gpt);
      await runner.callDart('focusLost');
      await tester.pump();
      expect(find.byType(PromptBubble), findsNothing);
    });

    testWidgets('a model change moves the characters at once', (tester) async {
      final model = FakeOfficeModel();
      await pumpDesktop(tester, model);
      final deskX = tester
          .getCenter(find.byKey(DesktopStage.actorKey(Seat.gpt)))
          .dx;
      model.snapshot = workingSnapshot().copyWithVisual(
        Seat.gpt,
        SeatVisual.onBreak,
      );
      await tester.pump();
      await tester.pump();
      final coffeeX = tester
          .getCenter(find.byKey(DesktopStage.actorKey(Seat.gpt)))
          .dx;
      expect(coffeeX, isNot(closeTo(deskX, 1)));
      expect(coffeeX, closeTo(1280 * 0.78 - 17 * 4, 1));
    });
  });
}

/// Remembers what the settings bubble asked for.
class FakeAutostart extends Autostart {
  bool enabled = false;

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<bool> setEnabled(bool value) async => enabled = value;
}

void settingsTests(FakeDesktopChannel Function() channel) {
  testWidgets('the tray opens the settings; Kaydet hands them back', (
    tester,
  ) async {
    final runner = channel();
    final commands = DesktopCommands();
    final autostart = FakeAutostart();
    final saved = <OfficeSettings>[];
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      DesktopApp(
        model: FakeOfficeModel(),
        layer: DesktopLayer(),
        settings: testSettings,
        onSettingsChanged: saved.add,
        commands: commands,
        autostart: autostart,
        animate: false,
      ),
    );
    await tester.pump();
    commands.openSettings();
    await tester.pump();
    await tester.pump();
    expect(find.byType(SettingsBubble), findsOneWidget);
    expect(find.text('Ayarlar'), findsOneWidget);
    expect(runner.methods, contains('bringToFront'));
    // The bubble's rect joins the hit rects.
    expect(runner.hitRectCalls.last.length, greaterThan(7 * 4));

    await tester.enterText(
      find.byKey(SettingsBubble.codexFieldKey),
      r'C:\tools\codex.cmd',
    );
    await tester.tap(find.byKey(SettingsBubble.modeKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('plan').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsBubble.fakeKey));
    await tester.pump();
    await tester.tap(find.byKey(SettingsBubble.autostartKey));
    await tester.pump();
    expect(autostart.enabled, isTrue);
    await tester.tap(find.byKey(SettingsBubble.saveKey));
    await tester.pump();
    expect(find.byType(SettingsBubble), findsNothing);
    final next = saved.single;
    expect(next.codexExecutable, r'C:\tools\codex.cmd');
    expect(next.claudeExecutable, 'claude');
    expect(next.permissionMode, 'plan');
    expect(next.fake, isTrue);
    expect(next.recentFolders, testSettings.recentFolders);
    expect(runner.methods, contains('sendToBack'));
  });
}

extension on OfficeSnapshot {
  OfficeSnapshot copyWithVisual(Seat seat, SeatVisual visual) => OfficeSnapshot(
    seats: [
      for (final s in seats) s.seat == seat ? s.copyWith(visual: visual) : s,
    ],
    tasks: tasks,
    recentEvents: recentEvents,
    busy: busy,
    lastReport: lastReport,
    reports: reports,
    unreadReports: unreadReports,
    statusLine: statusLine,
  );
}
