import 'package:agent_office_app/desktop/stations.dart';
import 'package:flutter_test/flutter_test.dart';

StationLayout layout() => StationLayout(width: 1280, floorY: 600);

void main() {
  group('StationLayout.dragTo', () {
    test('stops 16 px before the right neighbour', () {
      final l = layout();
      // Whiteboard (128 wide) at 0.10, Claude's desk (144 wide) at 0.26:
      // the desk's left edge is 332.8 - 72 = 260.8, so the board's centre
      // may reach 260.8 - 16 - 64 = 180.8.
      final limit =
          l.rect(StationKind.deskClaude).left - StationLayout.dragGap - 64;
      final applied = l.dragTo(StationKind.whiteboard, 0.5);
      expect(applied, closeTo(limit / 1280, 1e-6));
      expect(l.centerX(StationKind.whiteboard), closeTo(limit, 1e-6));
      expect(
        l.rect(StationKind.deskClaude).left -
            l.rect(StationKind.whiteboard).right,
        closeTo(16, 1),
      );
    });

    test('stops 16 px after the left neighbour', () {
      final l = layout();
      // The board's right edge is 128 + 64 = 192; the desk's centre may go
      // down to 192 + 16 + 72 = 280.
      final applied = l.dragTo(StationKind.deskClaude, 0.0);
      expect(applied, closeTo(280 / 1280, 1e-6));
      expect(l.centerX(StationKind.deskClaude), closeTo(280, 1e-6));
    });

    test('keeps the station order and the screen bounds', () {
      final l = layout();
      final before = [...StationKind.values]
        ..sort((a, b) => l.centerX(a).compareTo(l.centerX(b)));
      l.dragTo(StationKind.mailbox, 0.0);
      l.dragTo(StationKind.whiteboard, 1.0);
      final after = [...StationKind.values]
        ..sort((a, b) => l.centerX(a).compareTo(l.centerX(b)));
      expect(after, before);
      // Free movement still respects the screen edge.
      l.dragTo(StationKind.mailbox, 0.99);
      expect(l.fractions[StationKind.mailbox], StationLayout.maxFraction);
    });
  });

  test('the TV replaced the coffee machine', () {
    expect(
      StationKind.values,
      isNot(contains(StationKind.tv.name == 'coffee')),
    );
    expect(StationLayout.spriteSize(StationKind.tv), (28, 26));
    final l = layout();
    expect(l.slotX(StationKind.tv), l.centerX(StationKind.tv) - 19 * 4);
    expect(
      l.slotX(StationKind.tv, slot: 1),
      l.centerX(StationKind.tv) + 19 * 4,
    );
  });
}
