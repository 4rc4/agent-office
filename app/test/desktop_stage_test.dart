import 'package:agent_office_app/desktop/desktop_app.dart';
import 'package:agent_office_app/desktop/desktop_layer.dart';
import 'package:agent_office_app/desktop/desktop_stage.dart';
import 'package:agent_office_app/desktop/speech_bubble.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_desktop_channel.dart';
import 'support/test_fonts.dart';

const Size _screen = Size(1280, 720);

Future<void> _pumpStage(
  WidgetTester tester, {
  double dpr = 1,
  bool windowed = false,
}) async {
  tester.view.physicalSize = _screen * dpr;
  tester.view.devicePixelRatio = dpr;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    DesktopApp(
      layer: DesktopLayer(),
      windowed: windowed,
      animate: false,
      initialFolder: r'C:\work\repo',
    ),
  );
  // Second pump: the post-frame hit-rect report reaches the channel.
  await tester.pump();
}

Future<void> _openBubble(WidgetTester tester) async {
  await tester.tap(find.byKey(DesktopStage.characterKey));
  await tester.pump();
  await tester.pump();
}

void main() {
  late FakeDesktopChannel runner;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadPixelFont();
  });
  setUp(() => runner = FakeDesktopChannel());
  tearDown(() => runner.dispose());

  group('DesktopStage', () {
    testWidgets('starts with the character, no bubble, and reports its rect', (
      tester,
    ) async {
      await _pumpStage(tester);
      expect(find.byKey(DesktopStage.characterKey), findsOneWidget);
      expect(find.byType(SpeechBubble), findsNothing);
      expect(runner.methods, contains('setHitRects'));
      final rects = runner.hitRectCalls.last;
      expect(rects, hasLength(4));
      // 96x144 sprite box centred at 30% of 1280, feet 120 px above the
      // bottom, inflated by 4 px.
      expect(rects, [332, 452, 436, 604]);
    });

    testWidgets('a tap opens the bubble and brings the layer to front', (
      tester,
    ) async {
      await _pumpStage(tester);
      await _openBubble(tester);
      expect(find.byType(SpeechBubble), findsOneWidget);
      expect(find.text('Ne yapalım?'), findsOneWidget);
      expect(find.text(r'C:\work\repo'), findsOneWidget);
      expect(runner.methods, contains('bringToFront'));
      // The bubble's rect joins the character's.
      final rects = runner.hitRectCalls.last;
      expect(rects, hasLength(8));
      expect(rects[4], lessThan(rects[6]));
      expect(rects[5], lessThan(rects[7]));
      // The bubble sits above the character.
      expect(rects[7], lessThanOrEqualTo(rects[1] + 8));
    });

    testWidgets('Enter sends, logs the prompt and closes the bubble', (
      tester,
    ) async {
      await _pumpStage(tester);
      await _openBubble(tester);
      await tester.enterText(
        find.byKey(SpeechBubble.fieldKey),
        'Testleri düzelt',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byType(SpeechBubble), findsNothing);
      expect(find.byKey(DesktopStage.logKey), findsOneWidget);
      expect(find.textContaining('Testleri düzelt'), findsOneWidget);
      expect(find.textContaining(r'C:\work\repo'), findsOneWidget);
      expect(runner.methods, contains('sendToBack'));
    });

    testWidgets('Shift+Enter and an empty prompt keep the bubble open', (
      tester,
    ) async {
      await _pumpStage(tester);
      await _openBubble(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.byType(SpeechBubble), findsOneWidget);
      await tester.enterText(find.byKey(SpeechBubble.fieldKey), 'satır');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await tester.pump();
      expect(find.byType(SpeechBubble), findsOneWidget);
      expect(runner.methods, isNot(contains('sendToBack')));
    });

    testWidgets('Esc closes the bubble, a second Esc quits', (tester) async {
      await _pumpStage(tester);
      await _openBubble(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(find.byType(SpeechBubble), findsNothing);
      expect(runner.methods, contains('sendToBack'));
      expect(runner.methods, isNot(contains('quit')));
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(runner.methods, contains('quit'));
    });

    testWidgets('the send button and the close button work too', (
      tester,
    ) async {
      await _pumpStage(tester);
      await _openBubble(tester);
      await tester.tap(find.byKey(SpeechBubble.closeButtonKey));
      await tester.pump();
      expect(find.byType(SpeechBubble), findsNothing);
      await _openBubble(tester);
      await tester.enterText(find.byKey(SpeechBubble.fieldKey), 'Gönder dene');
      await tester.tap(find.byKey(SpeechBubble.sendButtonKey));
      await tester.pump();
      expect(find.byType(SpeechBubble), findsNothing);
      expect(find.textContaining('Gönder dene'), findsOneWidget);
    });

    testWidgets('a tap beside the character closes the bubble', (tester) async {
      await _pumpStage(tester);
      await _openBubble(tester);
      await tester.tapAt(const Offset(1100, 300));
      await tester.pump();
      expect(find.byType(SpeechBubble), findsNothing);
    });

    testWidgets('focusLost from the runner closes the bubble', (tester) async {
      await _pumpStage(tester);
      await _openBubble(tester);
      await runner.callDart('focusLost');
      await tester.pump();
      expect(find.byType(SpeechBubble), findsNothing);
      expect(runner.methods, contains('sendToBack'));
    });

    testWidgets('hit rects are physical pixels', (tester) async {
      await _pumpStage(tester, dpr: 2);
      expect(runner.hitRectCalls.last, [664, 904, 872, 1208]);
    });

    testWidgets('--window mode paints a dark backdrop', (tester) async {
      await _pumpStage(tester, windowed: true);
      expect(find.byKey(DesktopStage.backdropKey), findsOneWidget);
      expect(find.byKey(DesktopStage.characterKey), findsOneWidget);
    });
  });

  group('DesktopLayer', () {
    test('calls without a runner are swallowed', () async {
      runner.dispose();
      final layer = DesktopLayer();
      expect(await layer.enterWallpaperMode(), isFalse);
      expect(await layer.screenSize(), Size.zero);
      await layer.setHitRects([const Rect.fromLTWH(0, 0, 10, 10)]);
      await layer.quit();
    });

    test('screenSize and enterWallpaperMode read the runner', () async {
      final layer = DesktopLayer();
      expect(await layer.enterWallpaperMode(), isTrue);
      expect(await layer.screenSize(), const Size(1920, 1080));
      await layer.setHitRects([const Rect.fromLTRB(1, 2, 3, 4)]);
      expect(runner.hitRectCalls.single, [1, 2, 3, 4]);
    });
  });
}
