import 'dart:ui' as ui;

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

/// Paints the whole night studio for one [OfficeSnapshot] and animation
/// [tick].
///
/// Pixel art is drawn under an integer [scale] transform from [origin], so
/// every scene pixel lands on whole device pixels. Text (name plates, speech
/// bubbles) is laid out at device resolution on top. The static room is
/// recorded once into two pictures (behind and in front of the characters)
/// and replayed on every frame; only characters, screens, notes, gauges and
/// small animations are drawn live.
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

    canvas.drawPicture(_StaticLayers.instance.behind);
    paintBulbs(px, frame);
    _paintStickyNotes(px);
    paintGauges(px, SceneLayout.gauges, [
      CharacterPalette.claude.accent,
      CharacterPalette.gpt.accent,
      CharacterPalette.gemini.accent,
    ], gaugeLevels);
    paintSteam(px, SceneLayout.coffeeMachine, frame);
    for (final d in draws) {
      _paintSeatBack(px, d);
    }
    for (final d in draws) {
      _paintSeatFront(px, d);
    }
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

  /// Chair, seated character and the glow behind the monitor: everything
  /// that sits behind the desk block.
  void _paintSeatBack(Px px, _SeatDraw d) {
    final p = d.place;
    final palette = CharacterPalette.of(p.seat);
    final inChair = d.present && d.spot == Spot.chair;

    final chair = p.visitorChair;
    if (chair != null) {
      paintVisitorChair(px, chair, greyed: d.visual == SeatVisual.empty);
      if (inChair) {
        drawCharacter(px, d.x, d.baseY, d.pose!, palette, shadow: false);
      }
      return;
    }
    final desk = p.desk!;
    final chairBack = p.chairBack;
    if (chairBack != null) paintChairBack(px, chairBack);
    final m = p.monitor!;
    drawScreenGlow(px, m, screenFor(d.visual), onDesk: false);
    if (inChair) {
      px.canvas.save();
      px.canvas.clipRect(
        Rect.fromLTRB(0, 0, SceneLayout.width.toDouble(), desk.y.toDouble()),
      );
      drawCharacter(px, d.x, d.baseY, d.pose!, palette, shadow: false);
      px.canvas.restore();
    }
  }

  /// Desk, monitor, keyboard and hands, then characters standing on the
  /// floor (beside the desk or at the coffee counter).
  void _paintSeatFront(Px px, _SeatDraw d) {
    final p = d.place;
    final palette = CharacterPalette.of(p.seat);
    final desk = p.desk;
    if (desk != null) {
      paintDesk(px, desk, p.deskSurfaceHeight);
      final m = p.monitor!;
      final mode = screenFor(d.visual);
      drawMonitorBody(px, m.x, m.y, m.w, m.h);
      drawScreen(px, m.x, m.y, m.w, m.h, mode, frame);
      drawScreenGlow(px, m, mode, onDesk: true);
      paintKeyboard(px, p.keyboardX!, p.keyboardY!);
      drawTray(px, p.trayX!, p.trayY!);
      if (p.mugX != null) paintMug(px, p.mugX!, p.mugY!, ScenePalette.mug);
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
    if (d.present && d.spot != Spot.chair) {
      drawCharacter(px, d.x, d.baseY, d.pose!, palette);
    }
  }

  void _paintObjects(Px px, _SeatDraw d) {
    if (!d.present) return;
    final x = d.x;
    final y = d.top;
    switch (d.visual) {
      case SeatVisual.thinking:
        drawCloud(px, x + 16, y - 14, frame);
      case SeatVisual.typing:
        if (d.snap.bubble == null) drawDots(px, x + 14, y - 13, frame);
      case SeatVisual.editing:
        drawPen(px, x + 16, y - 11, frame);
        final trayX = d.place.trayX;
        final trayY = d.place.trayY;
        if (trayX != null && trayY != null && d.spot == Spot.chair) {
          drawFlyingSheet(px, x + 20, y + 8, trayX + 4, trayY - 8, frame);
        }
      case SeatVisual.celebrating:
        drawCheck(px, x + 18, y - 13);
      case SeatVisual.failed:
        drawSweat(px, x - 2, y + 3, frame);
      case SeatVisual.sleeping:
        drawZzz(px, x + 19, y - 12);
      default:
        break;
    }
  }

  /// Height of the floating prop above the head, so a speech bubble can sit
  /// above it instead of over it.
  static int _propHeightAbove(SeatVisual visual) => switch (visual) {
    SeatVisual.thinking => 15,
    SeatVisual.editing => 12,
    SeatVisual.celebrating => 14,
    SeatVisual.sleeping => 13,
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
      paintStickyNote(
        px,
        x,
        y,
        SceneLayout.noteWidth,
        SceneLayout.noteHeight,
        ScenePalette.sticky(task.status),
        pinned: task.isRoot,
      );
    }
  }

  List<_Label> _layoutLabels(List<_SeatDraw> draws) {
    final labels = <_Label>[];
    for (final d in draws) {
      final p = d.place;
      final accent = CharacterPalette.of(p.seat).accent;
      labels.add(
        _Label(
          text: _text(_seatName(p.seat), ScenePalette.cream),
          box: IRect(p.plateCenterX - 17, p.plateCenterY - 5, 34, 10),
          fill: ScenePalette.slate.base,
          edge: ScenePalette.slate.dark,
          light: ScenePalette.slate.light,
          stripe: accent,
        ),
      );
      final bubble = d.snap.bubble;
      if (bubble == null || !d.present) continue;
      final text = _text(
        _ellipsis(bubble.text),
        ScenePalette.bubbleText(bubble.kind),
      );
      final w = (text.width / scale).ceil() + 8;
      const h = 12;
      final headX = d.x + spriteWidth ~/ 2;
      final bx = (headX - w ~/ 2).clamp(1, SceneLayout.width - 1 - w);
      final by = d.top - 17 - _propHeightAbove(d.visual);
      labels.add(
        _Label(
          text: text,
          box: IRect(bx, by, w, h),
          fill: ScenePalette.bubbleFill(bubble.kind),
          edge: ScenePalette.bubbleEdge(bubble.kind),
          light: null,
          tailX: headX.clamp(bx + 3, bx + w - 4),
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
          fontSize: 5.0 * scale,
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

/// The unchanging parts of the room, recorded once as two pictures: what is
/// behind the characters and what is in front of them.
class _StaticLayers {
  _StaticLayers._() : behind = _record(_paintBehind);

  static final _StaticLayers instance = _StaticLayers._();

  final ui.Picture behind;

  static ui.Picture _record(void Function(Px px) body) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, SceneLayout.bounds);
    body(Px(canvas));
    return recorder.endRecording();
  }

  static void _paintBehind(Px px) {
    paintWall(px);
    paintSkirting(px);
    paintFloor(px);
    paintLightWire(px);
    paintWindow(px, SceneLayout.window, SceneLayout.windowSill);
    paintPosters(px, SceneLayout.posterTall, SceneLayout.posterWide);
    paintShelf(px, SceneLayout.shelf);
    paintDoor(px, SceneLayout.door, SceneLayout.doorMat);
    paintWhiteboard(px, SceneLayout.whiteboard);
    paintClock(px, SceneLayout.clock);
    paintCabinet(px, SceneLayout.cabinet);
    paintCoffeeCorner(
      px,
      SceneLayout.coffeeCounter,
      SceneLayout.coffeeMachine,
      SceneLayout.coffeeLamp,
      SceneLayout.mugShelf,
    );
    paintRug(px, SceneLayout.rug);
    for (final p in SceneLayout.placements) {
      final r = p.deskReturn;
      if (r != null) paintDeskReturn(px, r);
      if (p.plantX != null) paintPlant(px, p.plantX!, p.plantY!);
    }
    paintReceptionDesk(px, SceneLayout.receptionDesk);
  }
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
    required this.edge,
    required this.light,
    this.stripe,
    this.tailX,
  });

  final TextPainter text;
  final IRect box;
  final Color fill;
  final Color edge;
  final Color? light;

  /// Accent stripe along the left edge of a name plate.
  final Color? stripe;

  /// Scene x of the bubble tail; null for a name plate.
  final int? tailX;

  void paintBox(Px px) {
    final tx = tailX;
    if (tx == null) {
      px.dither(box.x + 1, box.bottom, box.w, 2, null, ScenePalette.shadowSoft);
    }
    px.roundRing(box.x, box.y, box.w, box.h, edge);
    px.fill(box.x + 1, box.y + 1, box.w - 2, box.h - 2, fill);
    final l = light;
    if (l != null) {
      px.hline(box.x + 2, box.y + 1, box.w - 4, l);
    } else {
      px.hline(box.x + 2, box.y + 1, box.w - 4, Color(0x55FFFFFF));
      px.hline(box.x + 2, box.bottom - 2, box.w - 4, Color(0x22000000));
    }
    final s = stripe;
    if (s != null) px.fill(box.x + 1, box.y + 2, 2, box.h - 4, s);
    if (tx == null) return;
    final bottom = box.bottom - 1;
    px.fill(tx - 1, bottom, 3, 1, fill);
    px.dot(tx - 2, bottom + 1, edge);
    px.fill(tx - 1, bottom + 1, 2, 1, fill);
    px.dot(tx + 1, bottom + 1, edge);
    px.dot(tx - 1, bottom + 2, edge);
    px.dot(tx, bottom + 2, fill);
    px.dot(tx + 1, bottom + 2, edge);
    px.dot(tx, bottom + 3, edge);
  }

  void paintText(Canvas canvas, Offset origin, int scale) {
    final cx =
        origin.dx + (box.x + box.w / 2 + (stripe != null ? 1 : 0)) * scale;
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
