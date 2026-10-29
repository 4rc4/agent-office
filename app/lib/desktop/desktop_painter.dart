import 'package:flutter/widgets.dart';
import 'package:office_core/office_core.dart';

import '../scene/palette.dart';
import '../scene/pixel.dart';
import '../scene/sprites.dart';
import '../widgets/office_theme.dart';
import 'actor_sprites.dart';
import 'office_actors.dart';
import 'stations.dart';
import 'wallpaper.dart';

/// Paints the whole desktop world for one frame: the backdrop (a copy of
/// the desktop wallpaper, or the dark `--window` surface with a floor
/// line), then the props,
/// the characters and the desks in front of them, all composed in one
/// [PixelBuffer] at the layout's scale and flushed as crisp rectangles.
class WorldPainter extends CustomPainter {
  const WorldPainter({
    required this.layout,
    required this.actors,
    required this.state,
    required this.frame,
    required this.tick,
    this.wallpaper,
    this.devicePixelRatio = 1,
    this.hovered,
    this.lifted,
    this.windowed = false,
  });

  final StationLayout layout;
  final List<Actor> actors;
  final StationState state;

  /// `tick % 4`, the sprite animation frame.
  final int frame;

  /// The raw clock, for the hover bob.
  final int tick;

  /// The desktop wallpaper to paint behind everything in wallpaper mode;
  /// null paints black.
  final DesktopWallpaper? wallpaper;

  /// Converts the wallpaper's physical pixels to this canvas.
  final double devicePixelRatio;

  /// Seat whose character bobs (pointer on it).
  final Seat? hovered;

  /// Station being dragged: drawn one sprite row higher.
  final StationKind? lifted;
  final bool windowed;

  @override
  void paint(Canvas canvas, Size size) {
    if (windowed) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = OfficeColors.background,
      );
      canvas.drawRect(
        Rect.fromLTWH(0, layout.floorY, size.width, 1),
        Paint()..color = OfficeColors.outline,
      );
    } else {
      _paintWallpaper(canvas, size);
    }
    final s = layout.scale;
    final b = PixelBuffer((size.width / s).ceil(), (size.height / s).ceil());
    final floor = layout.floorY ~/ s;
    int col(double x) => (x / s).round();

    int floorFor(StationKind kind) => kind == lifted ? floor - 1 : floor;
    for (final kind in const [
      StationKind.whiteboard,
      StationKind.tv,
      StationKind.mailbox,
    ]) {
      paintStation(
        b,
        kind,
        col(layout.centerX(kind)),
        floorFor(kind),
        state,
        frame,
      );
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
      paintStation(b, kind, cx, floorFor(kind), state, frame);
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

  /// The wallpaper copy: the background colour, then the image placed the
  /// way the shell places it, scaled from physical to logical pixels.
  void _paintWallpaper(Canvas canvas, Size size) {
    final paper = wallpaper;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = paper?.info.backgroundColor ?? const Color(0xFF000000),
    );
    final image = paper?.image;
    if (paper == null || image == null) return;
    final paint = Paint()..filterQuality = FilterQuality.high;
    final toLogical = 1 / devicePixelRatio;
    final imageSize = Size(image.width.toDouble(), image.height.toDouble());
    for (final tile in wallpaperTiles(imageSize, paper.info)) {
      final d = tile.destination;
      canvas.drawImageRect(
        image,
        tile.source,
        Rect.fromLTRB(
          d.left * toLogical,
          d.top * toLogical,
          d.right * toLogical,
          d.bottom * toLogical,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(WorldPainter old) => true;
}
