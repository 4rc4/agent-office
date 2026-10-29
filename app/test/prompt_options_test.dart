import 'package:agent_office_app/desktop/autostart.dart';
import 'package:agent_office_app/desktop/desktop_app.dart';
import 'package:agent_office_app/desktop/desktop_layer.dart';
import 'package:agent_office_app/desktop/desktop_stage.dart';
import 'package:agent_office_app/desktop/model_choices.dart';
import 'package:agent_office_app/desktop/prompt_bubble.dart';
import 'package:agent_office_app/desktop/settings_bubble.dart';
import 'package:agent_office_app/runtime/office_settings.dart';
import 'package:flutter/material.dart';
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

  testWidgets('the prompt bubble sends model, effort and attachments', (
    tester,
  ) async {
    final model = FakeOfficeModel();
    await pumpDesktop(
      tester,
      model,
      settings: const OfficeSettings(
        cwd: repoFolder,
        claudeModel: 'opus',
        claudeEffort: 'high',
      ),
      pickFiles: () async => [r'C:\img\shot.png'],
    );
    await tester.tap(find.byKey(DesktopStage.actorKey(Seat.claude)));
    await tester.pump();
    await tester.pump();
    // The chips start from the settings' defaults.
    expect(find.textContaining('opus'), findsOneWidget);
    expect(find.textContaining('yüksek'), findsOneWidget);

    await tester.tap(find.byKey(PromptBubble.modelChipKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('haiku').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PromptBubble.effortChipKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('azami').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(PromptBubble.filesButtonKey));
    await tester.pumpAndSettle();
    expect(find.text('shot.png'), findsOneWidget);

    await tester.enterText(find.byKey(PromptBubble.fieldKey), 'Bak');
    await tester.tap(find.byKey(PromptBubble.sendButtonKey));
    await tester.pump();
    final sent = model.submissions.single;
    expect(
      sent.prompt,
      'Bak\n\nEkli dosyalar (yoluyla oku):\n- C:\\img\\shot.png',
    );
    expect(sent.options, const PromptOptions(model: 'haiku', effort: 'max'));
  });

  testWidgets('removing an attachment chip drops it from the prompt', (
    tester,
  ) async {
    final model = FakeOfficeModel();
    await pumpDesktop(
      tester,
      model,
      pickFiles: () async => [r'C:\img\a.png', r'C:\img\b.png'],
    );
    await tester.tap(find.byKey(DesktopStage.actorKey(Seat.gpt)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(PromptBubble.filesButtonKey));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(PromptBubble.attachmentKey(r'C:\img\a.png')),
        matching: find.byIcon(Icons.close_rounded),
      ),
    );
    await tester.pump();
    await tester.enterText(find.byKey(PromptBubble.fieldKey), 'Bak');
    await tester.tap(find.byKey(PromptBubble.sendButtonKey));
    await tester.pump();
    expect(model.submissions.single.prompt, contains(r'C:\img\b.png'));
    expect(model.submissions.single.prompt, isNot(contains(r'C:\img\a.png')));
    expect(model.submissions.single.options, const PromptOptions());
  });

  testWidgets('the settings sheet saves model and effort per seat', (
    tester,
  ) async {
    final commands = DesktopCommands();
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
        autostart: const NoAutostart(),
        animate: false,
      ),
    );
    await tester.pump();
    commands.openSettings();
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(SettingsBubble.claudeModelKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('sonnet').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsBubble.codexEffortKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('düşük').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(SettingsBubble.saveKey));
    await tester.pump();
    final next = saved.single;
    expect(next.claudeModel, 'sonnet');
    expect(next.claudeEffort, '');
    expect(next.codexEffort, 'low');
  });

  testWidgets('model choices open inside the bubble, never as a popup', (
    tester,
  ) async {
    await pumpDesktop(
      tester,
      FakeOfficeModel(),
      pickFiles: () async => [r'C:\img\shot.png'],
    );
    await tester.tap(find.byKey(DesktopStage.actorKey(Seat.claude)));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(PromptBubble.modelChipKey));
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(
      find.descendant(
        of: find.byType(PromptBubble),
        matching: find.text('haiku'),
      ),
      findsOneWidget,
    );
    // The open choices are part of the bubble, so they are in its hit rect.
    final bubble = tester.getRect(find.byType(PromptBubble));
    expect(bubble.contains(tester.getCenter(find.text('haiku'))), isTrue);
    // No tooltips either: their overlay outlives the bubble on the desktop.
    await tester.tap(find.byKey(PromptBubble.filesButtonKey));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(PromptBubble),
        matching: find.byType(Tooltip),
      ),
      findsNothing,
    );
    // Closing the bubble leaves nothing of the menu behind.
    await tester.tap(find.byKey(DesktopStage.actorKey(Seat.claude)));
    await tester.pumpAndSettle();
    expect(find.text('haiku'), findsNothing);
  });

  testWidgets('settings choices open inside the sheet, not as a dropdown', (
    tester,
  ) async {
    final commands = DesktopCommands();
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      DesktopApp(
        model: FakeOfficeModel(),
        layer: DesktopLayer(),
        settings: testSettings,
        commands: commands,
        animate: false,
      ),
    );
    await tester.pump();
    commands.openSettings();
    await tester.pump();
    await tester.pump();
    expect(find.byType(DropdownButton<String>), findsNothing);
    await tester.tap(find.byKey(SettingsBubble.claudeModelKey));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(SettingsBubble),
        matching: find.text('sonnet'),
      ),
      findsOneWidget,
    );
  });
}
