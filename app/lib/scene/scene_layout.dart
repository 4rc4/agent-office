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
/// Characters are 16 wide; `seatX/seatY` is the top-left of the seated sprite,
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

  /// Monitor screen box including its frame; the stand is drawn below it.
  final IRect? monitor;

  /// Office chair back, peeking out behind the seated character.
  final IRect? chairBack;

  /// Full visitor chair (no desk).
  final IRect? visitorChair;
  final int? keyboardX;
  final int? keyboardY;
  final int? trayX;
  final int? trayY;

  bool get hasDesk => desk != null;

  /// Top of the desk surface; characters behind the desk are clipped here.
  int? get deskSurfaceTop => desk?.y;
}

/// The 320x180 office: named rectangles and hit testing.
abstract final class SceneLayout {
  static const int width = 320;
  static const int height = 180;
  static const Size size = Size(320, 180);
  static const Rect bounds = Rect.fromLTWH(0, 0, 320, 180);

  /// Wall ends here; the baseboard runs to [floorTop].
  static const int wallBottom = 92;
  static const int floorTop = 97;

  static const IRect door = IRect(8, 36, 30, 61);
  static const IRect doorMat = IRect(10, 98, 26, 6);

  static const IRect whiteboard = IRect(64, 16, 86, 44);
  static const int noteOriginX = 70;
  static const int noteOriginY = 22;
  static const int noteWidth = 16;
  static const int noteHeight = 14;
  static const int noteGap = 3;
  static const int noteColumns = 4;
  static const int maxNotes = 8;

  static const IRect clock = IRect(168, 18, 15, 15);
  static const IRect gauges = IRect(194, 18, 50, 12);
  static const int gaugeWidth = 14;
  static const int gaugeGap = 4;

  static const IRect cabinet = IRect(214, 58, 22, 39);

  static const IRect coffeeCounter = IRect(242, 66, 72, 31);
  static const IRect coffeeMachine = IRect(264, 44, 20, 24);
  static const List<IRect> stools = [
    IRect(248, 98, 12, 12),
    IRect(296, 98, 12, 12),
  ];
  static const IRect coffeeArea = IRect(242, 44, 72, 64);

  static const IRect receptionDesk = IRect(8, 138, 52, 22);
  static const IRect mailboxBox = IRect(70, 128, 18, 12);
  static const IRect mailboxArea = IRect(68, 122, 22, 38);

  static const SeatPlacement claude = SeatPlacement(
    seat: Seat.claude,
    hitRect: IRect(104, 90, 96, 50),
    desk: IRect(104, 118, 96, 18),
    deskReturn: IRect(104, 100, 20, 19),
    plantX: 109,
    plantY: 98,
    monitor: IRect(120, 92, 34, 24),
    chairBack: IRect(156, 108, 24, 10),
    seatX: 160,
    seatY: 102,
    standX: 180,
    standY: 98,
    breakX: 250,
    breakY: 87,
    keyboardX: 161,
    keyboardY: 120,
    trayX: 186,
    trayY: 120,
    plateCenterX: 152,
    plateCenterY: 141,
  );

  static const SeatPlacement gpt = SeatPlacement(
    seat: Seat.gpt,
    hitRect: IRect(216, 108, 76, 46),
    desk: IRect(216, 128, 76, 18),
    monitor: IRect(222, 110, 26, 20),
    chairBack: IRect(254, 118, 24, 10),
    seatX: 258,
    seatY: 112,
    standX: 276,
    standY: 108,
    breakX: 270,
    breakY: 87,
    keyboardX: 259,
    keyboardY: 130,
    trayX: 278,
    trayY: 130,
    plateCenterX: 254,
    plateCenterY: 151,
  );

  static const SeatPlacement gemini = SeatPlacement(
    seat: Seat.gemini,
    hitRect: IRect(42, 98, 26, 34),
    visitorChair: IRect(44, 108, 20, 20),
    seatX: 46,
    seatY: 106,
    standX: 66,
    standY: 104,
    breakX: 290,
    breakY: 87,
    plateCenterX: 54,
    plateCenterY: 133,
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
