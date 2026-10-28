import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:office_core/office_core.dart';

import '../state/seat_state.dart';
import 'furniture.dart';
import 'objects.dart';
import 'palette.dart';
import 'pixel.dart';
import 'scene_layout.dart';
import 'screens.dart';
import 'sprites.dart';

/// Paints the whole office for one [OfficeSnapshot] and animation [tick].
///
/// Pixel art is drawn under an integer [scale] transform from [origin], so
/// every scene pixel lands on whole device pixels. Text (name plates, speech
/// bubbles) is laid out at device resolution on top. Repaints only when the
/// snapshot, the tick or the geometry changed.
class OfficePainter extends CustomPainter {
  OfficePainter({
    required this.snapshot,
    required this.tick,
    required this.scale,
    required this.origin,
    this.gaugeLevels = const [0, 0, 0],
  });

  final OfficeSnapshot snapshot;
  final int tick;
  final int scale;
  final Offset origin;

  /// Usage meter levels 0..1 in Seat.values order (empty for now).
  final List<double> gaugeLevels;

  /// Longest speech bubble text before it is ellipsised.
  static const int bubbleMaxChars = 24;

  int get frame => tick % 4;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()
      ..color = ScenePalette.background
      ..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, bg);

    final draws = [for (final seat in Seat.values) _resolve(seat)];
    final labels = _layoutLabels(draws);

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale.toDouble());
    canvas.clipRect(SceneLayout.bounds);
    final px = Px(canvas);

    paintRoom(px);
    paintDoor(px, SceneLayout.door, SceneLayout.doorMat);
    paintWhiteboard(px, SceneLayout.whiteboard);
    _paintStickyNotes(px);
    paintClock(px, SceneLayout.clock);
    paintGauges(px, SceneLayout.gauges, [
      CharacterPalette.claude.body,
      CharacterPalette.gpt.body,
      CharacterPalette.gemini.body,
    ], gaugeLevels);
    paintCabinet(px, SceneLayout.cabinet);
    paintCoffeeCorner(
      px,
      SceneLayout.coffeeCounter,
      SceneLayout.coffeeMachine,
      SceneLayout.stools,
    );
    for (final d in draws) {
      _paintSeat(px, d);
    }
    paintReceptionDesk(px, SceneLayout.receptionDesk);
    paintMailbox(
      px,
      SceneLayout.mailboxBox,
      flagUp: snapshot.lastReport != null,
    );
    for (final d in draws) {
      _paintObjects(px, d);
    }
    for (final l in labels) {
      l.paintBox(px);
    }
    canvas.restore();

    for (final l in labels) {
      l.paintText(canvas, origin, scale);
      l.text.dispose();
    }
  }

  @override
  bool shouldRepaint(OfficePainter oldDelegate) =>
      oldDelegate.snapshot != snapshot ||
      oldDelegate.tick != tick ||
      oldDelegate.scale != scale ||
      oldDelegate.origin != origin ||
      !listEquals(oldDelegate.gaugeLevels, gaugeLevels);

  _SeatDraw _resolve(Seat seat) {
    final place = SceneLayout.placement(seat);
    final snap = snapshot.seat(seat);
    final pose = poseFor(snap.visual, frame, hasDesk: place.hasDesk);
    final spot = spotFor(snap.visual);
    final (x, y) = switch (spot) {
      Spot.chair => (place.seatX, place.seatY),
      Spot.besideChair => (place.standX, place.standY),
      Spot.coffee => (place.breakX, place.breakY),
    };
    return _SeatDraw(
      place: place,
      snap: snap,
      pose: pose,
      spot: spot,
      x: x,
      baseY: y,
    );
  }

  void _paintSeat(Px px, _SeatDraw d) {
    final p = d.place;
    final palette = CharacterPalette.of(p.seat);
    final hood = p.seat == Seat.claude;
    final atDesk = d.present && d.spot != Spot.coffee;

    final chair = p.visitorChair;
    if (chair != null) {
      paintVisitorChair(px, chair, greyed: d.visual == SeatVisual.empty);
      if (atDesk) {
        drawCharacter(px, d.x, d.baseY, d.pose!, palette, hood: hood);
      }
    } else {
      final desk = p.desk!;
      final deskReturn = p.deskReturn;
      if (deskReturn != null) paintDeskReturn(px, deskReturn);
      if (p.plantX != null) paintPlant(px, p.plantX!, p.plantY!);
      final chairBack = p.chairBack;
      if (chairBack != null) paintChairBack(px, chairBack);
      if (atDesk) {
        px.canvas.save();
        px.canvas.clipRect(
          Rect.fromLTRB(0, 0, SceneLayout.width.toDouble(), desk.y.toDouble()),
        );
        drawCharacter(px, d.x, d.baseY, d.pose!, palette, hood: hood);
        px.canvas.restore();
      }
      paintDesk(px, desk, p.deskSurfaceHeight);
      final m = p.monitor!;
      drawMonitor(px, m.x, m.y, m.w, m.h, screenFor(d.visual), frame);
      paintKeyboard(px, p.keyboardX!, p.keyboardY!);
      drawTray(px, p.trayX!, p.trayY!);
      if (d.present && d.spot == Spot.chair && handsOnKeyboard(d.visual)) {
        drawHands(
          px,
          p.keyboardX!,
          p.keyboardY!,
          palette,
          animate: d.visual == SeatVisual.typing,
          frame: frame,
        );
      }
    }

    if (d.present && d.spot == Spot.coffee) {
      drawCharacter(px, d.x, d.baseY, d.pose!, palette, hood: hood);
    }
  }

  void _paintObjects(Px px, _SeatDraw d) {
    if (!d.present) return;
    final x = d.x;
    final y = d.top;
    switch (d.visual) {
      case SeatVisual.thinking:
        drawCloud(px, x + 10, y - 10, frame);
      case SeatVisual.typing:
        if (d.snap.bubble == null) drawDots(px, x + 10, y - 11, frame);
      case SeatVisual.editing:
        drawPen(px, x + 10, y - 8, frame);
        final trayX = d.place.trayX;
        final trayY = d.place.trayY;
        if (trayX != null && trayY != null && d.spot == Spot.chair) {
          drawFlyingSheet(px, x + 14, y + 6, trayX + 2, trayY - 5, frame);
        }
      case SeatVisual.celebrating:
        drawCheck(px, x + 12, y - 9);
      case SeatVisual.failed:
        drawSweat(px, x - 1, y + 2, frame);
      case SeatVisual.sleeping:
        drawZzz(px, x + 13, y - 9);
      default:
        break;
    }
  }

  /// Height of the floating prop above the head, so a speech bubble can sit
  /// above it instead of over it.
  static int _propHeightAbove(SeatVisual visual) => switch (visual) {
    SeatVisual.thinking => 11,
    SeatVisual.editing => 9,
    SeatVisual.celebrating => 10,
    SeatVisual.sleeping => 10,
    _ => 0,
  };

  void _paintStickyNotes(Px px) {
    final notes = snapshot.tasks.reversed.take(SceneLayout.maxNotes).toList();
    for (var i = 0; i < notes.length; i++) {
      final task = notes[i];
      final col = i % SceneLayout.noteColumns;
      final row = i ~/ SceneLayout.noteColumns;
      final x =
          SceneLayout.noteOriginX +
          col * (SceneLayout.noteWidth + SceneLayout.noteGap);
      final y =
          SceneLayout.noteOriginY +
          row * (SceneLayout.noteHeight + SceneLayout.noteGap);
      px.roundBox(
        x,
        y,
        SceneLayout.noteWidth,
        SceneLayout.noteHeight,
        ScenePalette.sticky(task.status),
      );
      if (task.isRoot) {
        px.fill(
          x + SceneLayout.noteWidth ~/ 2 - 1,
          y + 1,
          2,
          1,
          ScenePalette.outline,
        );
      }
    }
  }

  List<_Label> _layoutLabels(List<_SeatDraw> draws) {
    final labels = <_Label>[];
    for (final d in draws) {
      final p = d.place;
      labels.add(
        _Label(
          text: _text(_seatName(p.seat), ScenePalette.cream),
          box: IRect(p.plateCenterX - 13, p.plateCenterY - 4, 26, 8),
          fill: ScenePalette.slate,
        ),
      );
      final bubble = d.snap.bubble;
      if (bubble == null || !d.present) continue;
      final text = _text(
        _ellipsis(bubble.text),
        ScenePalette.bubbleText(bubble.kind),
      );
      final w = (text.width / scale).ceil() + 6;
      const h = 10;
      final headX = d.x + spriteWidth ~/ 2;
      final bx = (headX - w ~/ 2).clamp(1, SceneLayout.width - 1 - w);
      final by = d.top - 14 - _propHeightAbove(d.visual);
      labels.add(
        _Label(
          text: text,
          box: IRect(bx, by, w, h),
          fill: ScenePalette.bubbleFill(bubble.kind),
          tailX: headX.clamp(bx + 2, bx + w - 3),
        ),
      );
    }
    return labels;
  }

  TextPainter _text(String s, Color color) {
    final painter = TextPainter(
      text: TextSpan(
        text: s,
        style: TextStyle(
          color: color,
          fontSize: 4.0 * scale,
          height: 1.0,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      textScaler: TextScaler.noScaling,
    )..layout();
    return painter;
  }

  static String _seatName(Seat seat) => switch (seat) {
    Seat.claude => 'Claude',
    Seat.gpt => 'GPT',
    Seat.gemini => 'Gemini',
  };

  static String _ellipsis(String s) =>
      s.length > bubbleMaxChars ? '${s.substring(0, bubbleMaxChars - 1)}…' : s;
}

/// One seat resolved for this frame: pose, spot and sprite origin.
class _SeatDraw {
  _SeatDraw({
    required this.place,
    required this.snap,
    required this.pose,
    required this.spot,
    required this.x,
    required this.baseY,
  });

  final SeatPlacement place;
  final SeatSnapshot snap;
  final CharacterPose? pose;
  final Spot spot;
  final int x;

  /// Sprite origin before the pose's own vertical shift.
  final int baseY;

  SeatVisual get visual => snap.visual;
  bool get present => pose != null;

  /// Top of the head as drawn (pose shift applied).
  int get top => baseY + (pose?.dy ?? 0);
}

/// A text label with its pixel box: name plate or speech bubble.
class _Label {
  _Label({
    required this.text,
    required this.box,
    required this.fill,
    this.tailX,
  });

  final TextPainter text;
  final IRect box;
  final Color fill;

  /// Scene x of the bubble tail; null for a name plate.
  final int? tailX;

  void paintBox(Px px) {
    px.roundBox(box.x, box.y, box.w, box.h, fill);
    final tx = tailX;
    if (tx == null) return;
    final bottom = box.bottom - 1;
    px.fill(tx, bottom, 1, 1, fill);
    px.fill(tx - 1, bottom + 1, 1, 1, ScenePalette.outline);
    px.fill(tx, bottom + 1, 1, 1, fill);
    px.fill(tx + 1, bottom + 1, 1, 1, ScenePalette.outline);
    px.fill(tx, bottom + 2, 1, 1, ScenePalette.outline);
  }

  void paintText(Canvas canvas, Offset origin, int scale) {
    final cx = origin.dx + (box.x + box.w / 2) * scale;
    final cy = origin.dy + (box.y + box.h / 2) * scale;
    text.paint(
      canvas,
      Offset(
        (cx - text.width / 2).roundToDouble(),
        (cy - text.height / 2).roundToDouble(),
      ),
    );
  }
}
