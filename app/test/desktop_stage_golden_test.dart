@Tags(['golden'])
library;

import 'package:agent_office_app/desktop/desktop_app.dart';
import 'package:agent_office_app/desktop/desktop_stage.dart';
import 'package:agent_office_app/desktop/prompt_bubble.dart';
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
    await loadSdkFonts();
    await loadPixelFont();
  });
  setUp(() => runner = FakeDesktopChannel());
  tearDown(() => runner.dispose());

  testWidgets('both desks working, notes on the board, flag up', (
    tester,
  ) async {
    final model = FakeOfficeModel(snapshot: workingSnapshot());
    await pumpDesktop(tester, model, windowed: true);
    await expectLater(
      find.byType(DesktopApp),
      matchesGoldenFile('goldens/desktop_stage_working.png'),
    );
  });

  testWidgets('idle office with the Claude prompt bubble open', (tester) async {
    final model = FakeOfficeModel();
    await pumpDesktop(tester, model, windowed: true);
    await tester.tap(find.byKey(DesktopStage.actorKey(Seat.claude)));
    await tester.pump();
    await tester.enterText(
      find.byKey(PromptBubble.fieldKey),
      'Widget testlerini yeşile çevir, sonra golden\'ı güncelle',
    );
    await tester.pump();
    await expectLater(
      find.byType(DesktopApp),
      matchesGoldenFile('goldens/desktop_stage_bubble.png'),
    );
  });
}
