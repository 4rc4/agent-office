import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:office_core/office_core.dart';

import '../state/seat_state.dart';
import 'furniture.dart';
import 'objects.dart';
import 'palette.dart';
import 'pixel.dart';
import 'room.dart';
import 'scene_layout.dart';
import 'screens.dart';
import 'sprites.dart';

/// Paints the whole warm office for one [OfficeSnapshot] and animation
/// [tick].
///
/// The scene is composed in a [PixelBuffer] (so shading passes can read the
/// floor under them) and flushed as integer-scaled rectangles from [origin]
/// at [scale]; every scene pixel lands on whole device pixels. Text (name
/// plates, speech bubbles) is laid out at device resolution on top. Repaints
/// only when the snapshot, the tick or the geometry changed.
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
      ..color = const Color(Warm.background)
      ..isAntiAlias = false;
    canvas.drawRect(Offset.zero & size, bg);

    final draws = [for (final seat in Seat.values) _resolve(seat)];
    final labels = _layoutLabels(draws);

    final b = PixelBuffer(SceneLayout.width, SceneLayout.height);
    _compose(b, draws, labels);

    canvas.save();
    canvas.translate(origin.dx, origin.dy);
    canvas.scale(scale.toDouble());
    canvas.clipRect(SceneLayout.bounds);
    b.emit(canvas);
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

  void _compose(PixelBuffer b, List<_SeatDraw> draws, List<_Label> labels) {
    // Walls and fixtures on them.
    paintWall(b);
    paintWainscoting(b);
    paintCurtainRod(
      b,
      SceneLayout.curtainLeft.x - 2,
      SceneLayout.curtainLeft.y - 4,
      SceneLayout.curtainRight.right - SceneLayout.curtainLeft.x + 4,
    );
    paintWindow(b, SceneLayout.window);
    paintCurtain(b, SceneLayout.curtainLeft, left: true);
    paintCurtain(b, SceneLayout.curtainRight, left: false);
    paintDoor(b, SceneLayout.door);
    paintWhiteboard(b, SceneLayout.whiteboard);
    _paintStickyNotes(b);
    paintClock(b, SceneLayout.clock);
    paintGauges(
      b,
      SceneLayout.gauges,
      [
        CharacterPalette.claude.accent,
        CharacterPalette.gpt.accent,
        CharacterPalette.gemini.accent,
      ],
      [
        CharacterPalette.claude.bodyDark,
        CharacterPalette.gpt.bodyDark,
        CharacterPalette.gemini.bodyDark,
      ],
      gaugeLevels,
    );
    paintPosterLandscape(b, SceneLayout.posterLandscape);
    paintPosterCircles(b, SceneLayout.posterCircles);
    paintWallShelf(b, SceneLayout.wallShelf);
    paintCabinet(b, SceneLayout.cabinet);
    paintCoffeeCounter(b, SceneLayout.coffeeCounter, SceneLayout.coffeeMachine);
    paintCoffeeMachine(b, SceneLayout.coffeeMachine, frame);

    // Floor, rug and sunlight.
    paintFloor(b);
    paintRug(b, SceneLayout.rug);
    paintLightShaft(b);
    paintDoorMat(b, SceneLayout.doorMat);

    // Ambient occlusion under everything that stands on the floor.
    _floorShadows(b, draws);

    paintFloorPlant(b, SceneLayout.floorPlantX, SceneLayout.floorPlantY);

    // People at the coffee corner stand between the counter and the stools.
    for (final d in draws) {
      if (d.present && d.spot == Spot.coffee) _drawCharacter(b, d);
    }
    for (final s in SceneLayout.stools) {
      paintStool(b, s);
    }

    for (final d in draws) {
      _paintSeat(b, d);
    }
    paintWasteBin(b, SceneLayout.wasteBin);
    paintReceptionDesk(b, SceneLayout.receptionDesk);
    paintDeskLamp(
      b,
      SceneLayout.receptionDesk.x + 14,
      SceneLayout.receptionDesk.y + 2,
    );
    paintMailbox(
      b,
      SceneLayout.mailboxBox,
      flagUp: snapshot.lastReport != null,
    );
    for (final d in draws) {
      _paintObjects(b, d);
    }
    for (final l in labels) {
      l.paintBox(b);
    }
  }

  void _floorShadows(PixelBuffer b, List<_SeatDraw> draws) {
    void under(IRect r, {int dx = 4, int dy = 0, int h = 7}) {
      b.shadow(r.x + dx, r.bottom - 1 + dy, r.w + 2, h);
    }

    under(SceneLayout.receptionDesk);
    under(SceneLayout.coffeeCounter, dx: 3, h: 8);
    b.shadow(
      SceneLayout.cabinet.x + 3,
      SceneLayout.cabinet.bottom - 1,
      SceneLayout.cabinet.w,
      5,
    );
    for (final p in SceneLayout.placements) {
      final desk = p.desk;
      if (desk != null) {
        under(desk, h: 8);
        b.shadow(desk.right, desk.y + 10, 5, desk.h - 8);
      }
    }
    final post = SceneLayout.mailboxBox;
    b.ellipseShadow(post.centerX + 2, post.bottom + 25, 7, 2);
    for (final d in draws) {
      if (!d.present || d.spot == Spot.chair && d.place.hasDesk) continue;
      b.ellipseShadow(
        d.x + spriteWidth ~/ 2 + 1,
        d.top + spriteHeight - 1,
        11,
        3,
      );
    }
  }

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

  void _drawCharacter(PixelBuffer b, _SeatDraw d, {int clipBottom = 1 << 20}) {
    drawCharacter(
      b,
      d.x,
      d.baseY,
      d.pose!,
      CharacterPalette.of(d.place.seat),
      styleFor(d.place.seat),
      clipBottom: clipBottom,
    );
  }

  void _paintSeat(PixelBuffer b, _SeatDraw d) {
    final p = d.place;
    final palette = CharacterPalette.of(p.seat);
    final atDesk = d.present && d.spot != Spot.coffee;

    final chair = p.visitorChair;
    if (chair != null) {
      final greyed = d.visual == SeatVisual.empty;
      paintVisitorChairBack(b, chair, palette, greyed: greyed);
      if (atDesk) _drawCharacter(b, d);
      paintVisitorChairFront(b, chair, greyed: greyed);
      return;
    }

    final desk = p.desk!;
    final deskReturn = p.deskReturn;
    if (deskReturn != null) {
      paintDeskReturn(b, deskReturn);
      paintBooks(b, deskReturn.x + 6, deskReturn.y + 14);
    }
    if (p.plantX != null) paintDeskPlant(b, p.plantX!, p.plantY!);
    final chairBack = p.chairBack;
    if (chairBack != null) paintChairBack(b, chairBack, palette);
    if (atDesk) _drawCharacter(b, d, clipBottom: desk.y);
    paintDesk(b, desk, p.deskSurfaceHeight);

    final m = p.monitor!;
    final mode = screenFor(d.visual);
    final glow = screenGlow(mode, frame);
    if (glow != 0) {
      b.lightPool(
        m.centerX,
        desk.y + 3,
        m.w ~/ 2 + 4,
        4,
        tint: glow,
        strength: 0.35,
      );
    }
    if (p.lampX != null) {
      paintDeskLamp(
        b,
        p.lampX!,
        p.lampY!,
        lit: d.visual != SeatVisual.sleeping,
      );
    }
    paintMonitor(b, m, mode, frame);
    paintKeyboard(b, p.keyboardX!, p.keyboardY!);
    paintMouse(b, p.keyboardX! + 25, p.keyboardY! - 1);
    paintTray(b, p.trayX!, p.trayY!);
    if (p.mugX != null) {
      paintMug(b, p.mugX!, p.mugY!, stripe: palette.accent);
      if (atDesk && d.spot == Spot.chair) {
        paintMugSteam(b, p.mugX!, p.mugY!, frame);
      }
    }
    if (d.present && d.spot == Spot.chair && handsOnKeyboard(d.visual)) {
      drawHands(
        b,
        p.keyboardX!,
        p.keyboardY!,
        palette,
        animate: d.visual == SeatVisual.typing,
        frame: frame,
      );
    }
  }

  void _paintObjects(PixelBuffer b, _SeatDraw d) {
    if (!d.present) return;
    final x = d.x;
    final y = d.top;
    switch (d.visual) {
      case SeatVisual.thinking:
        drawCloud(b, x + 14, y - 16, frame);
      case SeatVisual.typing:
        if (d.snap.bubble == null) drawDots(b, x + 14, y - 16, frame);
      case SeatVisual.editing:
        drawPen(b, x + 16, y - 12, frame);
        final trayX = d.place.trayX;
        final trayY = d.place.trayY;
        if (trayX != null && trayY != null && d.spot == Spot.chair) {
          drawFlyingSheet(b, x + 20, y + 8, trayX + 3, trayY - 8, frame);
        }
      case SeatVisual.celebrating:
        drawCheck(b, x + 18, y - 14);
      case SeatVisual.failed:
        drawSweat(b, x - 2, y + 3, frame);
      case SeatVisual.sleeping:
        drawZzz(b, x + 19, y - 13);
      default:
        break;
    }
  }

  /// Height of the floating prop above the head, so a speech bubble can sit
  /// above it instead of over it.
  static int _propHeightAbove(SeatVisual visual) => switch (visual) {
    SeatVisual.thinking => 16,
    SeatVisual.editing => 12,
    SeatVisual.celebrating => 14,
    SeatVisual.sleeping => 13,
    _ => 0,
  };

  void _paintStickyNotes(PixelBuffer b) {
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
      final (fill, dark) = Warm.sticky(task.status);
      paintStickyNote(
        b,
        x,
        y,
        SceneLayout.noteWidth,
        SceneLayout.noteHeight,
        fill,
        dark,
        pinned: task.isRoot,
      );
    }
  }

  List<_Label> _layoutLabels(List<_SeatDraw> draws) {
    final labels = <_Label>[];
    for (final d in draws) {
      final p = d.place;
      labels.add(
        _Label(
          text: _text(_seatName(p.seat), const Color(Warm.cream)),
          box: IRect(p.plateCenterX - 18, p.plateCenterY - 5, 36, 11),
          fill: Warm.woodDark,
          edge: Warm.woodOutline,
          light: Warm.woodShade,
        ),
      );
      final bubble = d.snap.bubble;
      if (bubble == null || !d.present) continue;
      final text = _text(_ellipsis(bubble.text), Warm.bubbleText(bubble.kind));
      final w = (text.width / scale).ceil() + 8;
      const h = 13;
      final headX = d.x + spriteWidth ~/ 2;
      final bx = (headX - w ~/ 2).clamp(1, SceneLayout.width - 1 - w);
      final by = d.top - 18 - _propHeightAbove(d.visual);
      final fill = Warm.bubbleFill(bubble.kind);
      labels.add(
        _Label(
          text: text,
          box: IRect(bx, by, w, h),
          fill: fill,
          edge: Warm.ink,
          light: PixelBuffer.lightOf(fill),
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
          fontSize: 6.0 * scale,
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
    required this.edge,
    required this.light,
    this.tailX,
  });

  final TextPainter text;
  final IRect box;
  final int fill;
  final int edge;
  final int light;

  /// Scene x of the bubble tail; null for a name plate.
  final int? tailX;

  void paintBox(PixelBuffer b) {
    b.shadow(box.x + 1, box.y + 1, box.w, box.h, feather: 1);
    b.roundFill(box.x, box.y, box.w, box.h, fill);
    b.roundRing(box.x, box.y, box.w, box.h, edge);
    b.hline(box.x + 1, box.y + 1, box.w - 2, light);
    final tx = tailX;
    if (tx == null) return;
    final bottom = box.bottom - 1;
    b.hline(tx - 1, bottom, 3, fill);
    b.set(tx - 2, bottom + 1, edge);
    b.hline(tx - 1, bottom + 1, 2, fill);
    b.set(tx + 1, bottom + 1, edge);
    b.set(tx - 1, bottom + 2, edge);
    b.set(tx, bottom + 2, fill);
    b.set(tx + 1, bottom + 2, edge);
    b.set(tx, bottom + 3, edge);
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
