import 'dart:ui';

import 'package:office_core/office_core.dart';

/// Integer rectangle in scene pixels.
class IRect {
  const IRect(this.x, this.y, this.w, this.h);

  final int x;
  final int y;
  final int w;
  final int h;

  int get right => x + w;
  int get bottom => y + h;
  int get centerX => x + w ~/ 2;
  int get centerY => y + h ~/ 2;

  Rect get rect =>
      Rect.fromLTWH(x.toDouble(), y.toDouble(), w.toDouble(), h.toDouble());

  /// True when the scene point lies inside (right and bottom edges excluded).
  bool contains(Offset p) =>
      p.dx >= x && p.dx < x + w && p.dy >= y && p.dy < y + h;

  @override
  String toString() => 'IRect($x, $y, $w, $h)';
}

/// What a tap on the scene landed on.
sealed class SceneTarget {
  const SceneTarget();

  const factory SceneTarget.seat(Seat seat) = SeatTarget;

  static const SceneTarget whiteboard = WhiteboardTarget();
  static const SceneTarget mailbox = MailboxTarget();
  static const SceneTarget coffee = CoffeeTarget();
  static const SceneTarget cabinet = CabinetTarget();
}

/// A desk or chair; [seat] says whose.
final class SeatTarget extends SceneTarget {
  const SeatTarget(this.seat);

  final Seat seat;

  @override
  bool operator ==(Object other) => other is SeatTarget && other.seat == seat;

  @override
  int get hashCode => seat.hashCode;

  @override
  String toString() => 'SceneTarget.seat(${seat.name})';
}

/// The whiteboard with the sticky notes.
final class WhiteboardTarget extends SceneTarget {
  const WhiteboardTarget();

  @override
  String toString() => 'SceneTarget.whiteboard';
}

/// The mailbox next to the reception desk (last report).
final class MailboxTarget extends SceneTarget {
  const MailboxTarget();

  @override
  String toString() => 'SceneTarget.mailbox';
}

/// The coffee corner (machine, counter, stools).
final class CoffeeTarget extends SceneTarget {
  const CoffeeTarget();

  @override
  String toString() => 'SceneTarget.coffee';
}

/// The filing cabinet (history).
final class CabinetTarget extends SceneTarget {
  const CabinetTarget();

  @override
  String toString() => 'SceneTarget.cabinet';
}

/// Where one seat's furniture and character go. All values are scene pixels.
/// Characters are 24 wide; `seatX/seatY` is the top-left of the seated sprite,
/// `standX/standY` the top-left when standing beside the chair and
/// `breakX/breakY` the top-left when standing at the coffee counter.
class SeatPlacement {
  const SeatPlacement({
    required this.seat,
    required this.hitRect,
    required this.seatX,
    required this.seatY,
    required this.standX,
    required this.standY,
    required this.breakX,
    required this.breakY,
    required this.plateCenterX,
    required this.plateCenterY,
    this.desk,
    this.deskSurfaceHeight = 8,
    this.deskReturn,
    this.plantX,
    this.plantY,
    this.monitor,
    this.chairBack,
    this.visitorChair,
    this.keyboardX,
    this.keyboardY,
    this.trayX,
    this.trayY,
    this.lampX,
    this.lampY,
    this.mugX,
    this.mugY,
  });

  final Seat seat;
  final IRect hitRect;
  final int seatX;
  final int seatY;
  final int standX;
  final int standY;
  final int breakX;
  final int breakY;
  final int plateCenterX;
  final int plateCenterY;

  /// Desk block (top surface band plus front face); null for the visitor chair.
  final IRect? desk;
  final int deskSurfaceHeight;

  /// Extra surface going back toward the wall (corner desk).
  final IRect? deskReturn;
  final int? plantX;
  final int? plantY;

  /// Monitor screen box including its bezel; the stand is drawn below it.
  final IRect? monitor;

  /// Office chair back, peeking out behind the seated character.
  final IRect? chairBack;

  /// Full visitor chair (no desk).
  final IRect? visitorChair;
  final int? keyboardX;
  final int? keyboardY;
  final int? trayX;
  final int? trayY;

  /// Desk lamp: bottom-centre of its base on the desk surface.
  final int? lampX;
  final int? lampY;

  /// Coffee mug on the desk (top-left).
  final int? mugX;
  final int? mugY;

  bool get hasDesk => desk != null;

  /// Top of the desk surface; characters behind the desk are clipped here.
  int? get deskSurfaceTop => desk?.y;
}

/// The 480x270 office: named rectangles and hit testing.
abstract final class SceneLayout {
  static const int width = 480;
  static const int height = 270;
  static const Size size = Size(480, 270);
  static const Rect bounds = Rect.fromLTWH(0, 0, 480, 270);

  /// Chair rail: plaster above, wainscoting below.
  static const int chairRail = 98;

  /// Wall ends here; the skirting board runs to [floorTop].
  static const int wallBottom = 146;
  static const int floorTop = 153;

  static const IRect window = IRect(18, 16, 98, 90);
  static const IRect curtainLeft = IRect(6, 10, 12, 108);
  static const IRect curtainRight = IRect(116, 10, 12, 108);

  static const IRect door = IRect(128, 42, 44, 104);
  static const IRect doorMat = IRect(131, 154, 38, 8);

  static const IRect whiteboard = IRect(186, 24, 128, 70);
  static const int noteOriginX = 194;
  static const int noteOriginY = 32;
  static const int noteWidth = 24;
  static const int noteHeight = 18;
  static const int noteGap = 4;
  static const int noteColumns = 4;
  static const int maxNotes = 8;

  static const IRect clock = IRect(330, 26, 24, 24);
  static const IRect gauges = IRect(366, 26, 88, 24);
  static const int gaugeWidth = 24;
  static const int gaugeGap = 8;

  static const IRect posterLandscape = IRect(330, 56, 28, 26);
  static const IRect posterCircles = IRect(434, 58, 30, 36);

  /// Small wall shelf with a trailing plant, between cabinet and machine.
  static const IRect wallShelf = IRect(368, 66, 24, 4);

  static const IRect cabinet = IRect(330, 90, 36, 56);

  /// Tall floor plant between the main desk and the cabinet (top-left of
  /// the leaves).
  static const int floorPlantX = 296;
  static const int floorPlantY = 100;

  static const IRect coffeeCounter = IRect(372, 104, 102, 42);
  static const IRect coffeeMachine = IRect(396, 72, 26, 34);
  static const List<IRect> stools = [
    IRect(384, 156, 16, 18),
    IRect(446, 156, 16, 18),
  ];
  static const IRect coffeeArea = IRect(372, 72, 102, 92);

  static const IRect rug = IRect(144, 168, 170, 72);

  /// Wastebasket beside the second desk.
  static const IRect wasteBin = IRect(454, 218, 12, 15);

  static const IRect receptionDesk = IRect(10, 206, 80, 34);
  static const IRect mailboxBox = IRect(96, 196, 24, 16);
  static const IRect mailboxArea = IRect(94, 190, 28, 52);

  static const SeatPlacement claude = SeatPlacement(
    seat: Seat.claude,
    hitRect: IRect(160, 134, 140, 76),
    desk: IRect(160, 176, 140, 28),
    deskReturn: IRect(160, 150, 28, 28),
    plantX: 163,
    plantY: 134,
    monitor: IRect(188, 138, 52, 36),
    chairBack: IRect(240, 158, 36, 18),
    seatX: 246,
    seatY: 150,
    standX: 274,
    standY: 146,
    breakX: 380,
    breakY: 128,
    keyboardX: 244,
    keyboardY: 180,
    trayX: 272,
    trayY: 180,
    lampX: 292,
    lampY: 180,
    mugX: 176,
    mugY: 176,
    plateCenterX: 230,
    plateCenterY: 212,
  );

  static const SeatPlacement gpt = SeatPlacement(
    seat: Seat.gpt,
    hitRect: IRect(330, 164, 118, 86),
    desk: IRect(330, 206, 116, 28),
    monitor: IRect(340, 168, 44, 36),
    chairBack: IRect(394, 188, 36, 18),
    seatX: 400,
    seatY: 180,
    standX: 424,
    standY: 176,
    breakX: 410,
    breakY: 128,
    keyboardX: 398,
    keyboardY: 210,
    trayX: 424,
    trayY: 210,
    lampX: 438,
    lampY: 210,
    mugX: 386,
    mugY: 206,
    plateCenterX: 388,
    plateCenterY: 242,
  );

  static const SeatPlacement gemini = SeatPlacement(
    seat: Seat.gemini,
    hitRect: IRect(124, 150, 34, 48),
    visitorChair: IRect(126, 160, 30, 30),
    seatX: 129,
    seatY: 158,
    standX: 98,
    standY: 154,
    breakX: 440,
    breakY: 128,
    plateCenterX: 141,
    plateCenterY: 204,
  );

  static const List<SeatPlacement> placements = [claude, gpt, gemini];

  static SeatPlacement placement(Seat seat) => switch (seat) {
    Seat.claude => claude,
    Seat.gpt => gpt,
    Seat.gemini => gemini,
  };

  /// Maps a point in scene pixels to what sits there, or null for floor/wall.
  static SceneTarget? hitTest(Offset scenePoint) {
    if (!bounds.contains(scenePoint)) return null;
    for (final p in placements) {
      if (p.hitRect.contains(scenePoint)) return SceneTarget.seat(p.seat);
    }
    if (whiteboard.contains(scenePoint)) return SceneTarget.whiteboard;
    if (mailboxArea.contains(scenePoint)) return SceneTarget.mailbox;
    if (coffeeArea.contains(scenePoint)) return SceneTarget.coffee;
    if (cabinet.contains(scenePoint)) return SceneTarget.cabinet;
    return null;
  }
}
