import 'package:flutter/widgets.dart';
import 'package:office_core/office_core.dart';

import '../scene/palette.dart';
import '../scene/pixel.dart';
import '../scene/sprites.dart';
import '../widgets/office_theme.dart';
import 'actor_sprites.dart';
import 'office_actors.dart';
import 'stations.dart';

/// Paints the whole desktop world for one frame: the backdrop (the colour
/// key, or the dark `--window` surface with a floor line), then the props,
/// the characters and the desks in front of them, all composed in one
/// [PixelBuffer] at the layout's scale and flushed as crisp rectangles.
class WorldPainter extends CustomPainter {
  const WorldPainter({
    required this.layout,
    required this.actors,
    required this.state,
    required this.frame,
    required this.tick,
    required this.keyColor,
    this.hovered,
    this.windowed = false,
  });

  final StationLayout layout;
  final List<Actor> actors;
  final StationState state;

  /// `tick % 4`, the sprite animation frame.
  final int frame;

  /// The raw clock, for the hover bob.
  final int tick;
  final Color keyColor;

  /// Seat whose character bobs (pointer on it).
  final Seat? hovered;
  final bool windowed;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = windowed ? OfficeColors.background : keyColor,
    );
    if (windowed) {
      canvas.drawRect(
        Rect.fromLTWH(0, layout.floorY, size.width, 1),
        Paint()..color = OfficeColors.outline,
      );
    }
    final s = layout.scale;
    final b = PixelBuffer((size.width / s).ceil(), (size.height / s).ceil());
    final floor = layout.floorY ~/ s;
    int col(double x) => (x / s).round();

    for (final kind in const [
      StationKind.whiteboard,
      StationKind.coffee,
      StationKind.mailbox,
    ]) {
      paintStation(b, kind, col(layout.centerX(kind)), floor, state, frame);
    }
    final sorted = [...actors]..sort((a, c) => a.x.compareTo(c.x));
    for (final actor in sorted) {
      final bob = hovered == actor.seat && !actor.walking && tick.isEven
          ? -1
          : 0;
      drawActor(b, actor, col(actor.x), floor, frame, bob: bob);
    }
    for (final kind in const [StationKind.deskClaude, StationKind.deskGpt]) {
      final cx = col(layout.centerX(kind));
      paintStation(b, kind, cx, floor, state, frame);
      final owner = kind.owner!;
      final actor = actors.where((a) => a.seat == owner).firstOrNull;
      if (actor != null &&
          actor.station == kind &&
          actorTypesOnKeyboard(actor)) {
        drawHands(
          b,
          cx + 7 - 11,
          floor - 13,
          CharacterPalette.of(owner),
          animate: true,
          frame: frame,
        );
      }
    }
    canvas.save();
    canvas.scale(s.toDouble());
    b.emit(canvas);
    canvas.restore();
  }

  @override
  bool shouldRepaint(WorldPainter old) => true;
}
