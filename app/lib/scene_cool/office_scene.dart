import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../state/seat_state.dart';
import 'office_painter.dart';
import 'scene_layout.dart';

export 'scene_layout.dart'
    show
        SceneTarget,
        SeatTarget,
        WhiteboardTarget,
        MailboxTarget,
        CoffeeTarget,
        CabinetTarget;

/// How the 480x270 scene fits into an available size: the largest integer
/// scale that fits (at least 1), centred and letterboxed.
class SceneFit {
  const SceneFit({required this.scale, required this.origin});

  final int scale;

  /// Top-left of the scaled scene inside the widget, in logical pixels.
  final Offset origin;

  static SceneFit compute(Size available) {
    final sx = available.width.isFinite
        ? available.width ~/ SceneLayout.width
        : 1;
    final sy = available.height.isFinite
        ? available.height ~/ SceneLayout.height
        : 1;
    final scale = math.max(1, math.min(sx, sy));
    final w = SceneLayout.width * scale;
    final h = SceneLayout.height * scale;
    return SceneFit(
      scale: scale,
      origin: Offset(
        ((available.width - w) / 2).floorToDouble(),
        ((available.height - h) / 2).floorToDouble(),
      ),
    );
  }

  /// The scene's rectangle inside the widget.
  Rect get sceneRect => Rect.fromLTWH(
    origin.dx,
    origin.dy,
    (SceneLayout.width * scale).toDouble(),
    (SceneLayout.height * scale).toDouble(),
  );

  /// Widget-local point to scene pixels.
  Offset toScene(Offset local) =>
      Offset((local.dx - origin.dx) / scale, (local.dy - origin.dy) / scale);

  /// Scene pixel to the top-left of that pixel in widget-local coordinates.
  Offset fromScene(Offset scene) =>
      Offset(origin.dx + scene.dx * scale, origin.dy + scene.dy * scale);

  /// What a widget-local tap landed on.
  SceneTarget? hitTest(Offset local) => SceneLayout.hitTest(toScene(local));
}

/// The pixel night studio. Stateless: the parent owns the snapshot and the
/// ticker.
///
/// [tick] advances every 100 ms while something animates; the frame is
/// `tick % 4`. Taps on furniture call [onTap] with the [SceneTarget]; taps on
/// the floor or wall call [onTapEmpty] when given.
class OfficeScene extends StatelessWidget {
  const OfficeScene({
    super.key,
    required this.snapshot,
    required this.tick,
    required this.onTap,
    this.onTapEmpty,
    this.gaugeLevels = const [0, 0, 0],
  });

  final OfficeSnapshot snapshot;
  final int tick;
  final void Function(SceneTarget target) onTap;
  final VoidCallback? onTapEmpty;

  /// Usage meter levels 0..1 in Seat.values order; all empty by default.
  final List<double> gaugeLevels;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(
          constraints.hasBoundedWidth
              ? constraints.maxWidth
              : SceneLayout.width.toDouble(),
          constraints.hasBoundedHeight
              ? constraints.maxHeight
              : SceneLayout.height.toDouble(),
        );
        final fit = SceneFit.compute(size);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (details) {
            final target = fit.hitTest(details.localPosition);
            if (target != null) {
              onTap(target);
            } else {
              onTapEmpty?.call();
            }
          },
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: CustomPaint(
              size: size,
              isComplex: true,
              painter: OfficePainter(
                snapshot: snapshot,
                tick: tick,
                scale: fit.scale,
                origin: fit.origin,
                gaugeLevels: gaugeLevels,
              ),
            ),
          ),
        );
      },
    );
  }
}
