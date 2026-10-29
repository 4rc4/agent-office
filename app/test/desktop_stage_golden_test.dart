@Tags(['golden'])
library;

import 'package:agent_office_app/desktop/desktop_app.dart';
import 'package:agent_office_app/desktop/desktop_layer.dart';
import 'package:agent_office_app/desktop/desktop_stage.dart';
import 'package:agent_office_app/desktop/speech_bubble.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_channel.dart';
import 'support/test_fonts.dart';

void main() {
  late FakeDesktopChannel runner;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadSdkFonts();
    await loadPixelFont();
  });
  setUp(() => runner = FakeDesktopChannel());
  tearDown(() => runner.dispose());

  testWidgets('desktop stage with the bubble open at 1280x720', (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      DesktopApp(
        layer: DesktopLayer(),
        windowed: true,
        animate: false,
        initialFolder: r'C:\work\agent-office',
      ),
    );
    await tester.pump();
    // One prompt already sent, so the debug list shows under the character.
    await tester.tap(find.byKey(DesktopStage.characterKey));
    await tester.pump();
    await tester.enterText(
      find.byKey(SpeechBubble.fieldKey),
      'README için kısa bir kurulum bölümü yaz',
    );
    await tester.tap(find.byKey(SpeechBubble.sendButtonKey));
    await tester.pump();
    await tester.tap(find.byKey(DesktopStage.characterKey));
    await tester.pump();
    await tester.enterText(
      find.byKey(SpeechBubble.fieldKey),
      'Widget testlerini yeşile çevir, sonra golden\'ı güncelle',
    );
    await tester.pump();
    expect(find.byType(SpeechBubble), findsOneWidget);
    await expectLater(
      find.byType(DesktopApp),
      matchesGoldenFile('goldens/desktop_stage_bubble.png'),
    );
  });
}
