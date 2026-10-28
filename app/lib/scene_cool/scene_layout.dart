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

/// The coffee corner (counter, machine, lamp).
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
/// Characters are 24 wide and 32 tall; `seatX/seatY` is the top-left of the
/// seated sprite, `standX/standY` the top-left when standing beside the desk
/// and `breakX/breakY` the top-left when standing at the coffee counter.
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
    this.deskSurfaceHeight = 12,
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
  final int? mugX;
  final int? mugY;

  bool get hasDesk => desk != null;

  /// Top of the desk surface; characters behind the desk are clipped here.
  int? get deskSurfaceTop => desk?.y;
}

/// The 480x270 night studio: named rectangles and hit testing.
abstract final class SceneLayout {
  static const int width = 480;
  static const int height = 270;
  static const Size size = Size(480, 270);
  static const Rect bounds = Rect.fromLTWH(0, 0, 480, 270);

  /// Wall ends here; the skirting board runs to [floorTop].
  static const int wallBottom = 150;
  static const int floorTop = 156;

  static const IRect window = IRect(24, 20, 112, 86);
  static const IRect windowSill = IRect(20, 106, 120, 5);

  static const IRect door = IRect(446, 56, 30, 100);
  static const IRect doorMat = IRect(446, 158, 30, 9);

  static const IRect whiteboard = IRect(166, 24, 120, 72);
  static const int noteOriginX = 176;
  static const int noteOriginY = 34;
  static const int noteWidth = 22;
  static const int noteHeight = 18;
  static const int noteGap = 4;
  static const int noteColumns = 4;
  static const int maxNotes = 8;

  static const IRect posterTall = IRect(142, 34, 20, 28);
  static const IRect posterWide = IRect(410, 22, 28, 36);
  static const IRect shelf = IRect(300, 62, 50, 4);

  static const IRect clock = IRect(300, 26, 22, 22);
  static const IRect gauges = IRect(336, 28, 66, 20);
  static const int gaugeWidth = 18;
  static const int gaugeGap = 6;

  static const IRect cabinet = IRect(318, 98, 32, 58);

  static const IRect coffeeCounter = IRect(356, 112, 84, 44);
  static const IRect coffeeMachine = IRect(378, 78, 30, 36);
  static const IRect coffeeLamp = IRect(418, 82, 16, 32);
  static const IRect mugShelf = IRect(360, 66, 36, 4);
  static const IRect coffeeArea = IRect(354, 56, 88, 104);

  static const IRect rug = IRect(136, 184, 172, 62);

  static const IRect receptionDesk = IRect(14, 224, 82, 32);
  static const IRect mailboxBox = IRect(106, 208, 26, 18);
  static const IRect mailboxArea = IRect(102, 198, 34, 56);

  static const SeatPlacement claude = SeatPlacement(
    seat: Seat.claude,
    hitRect: IRect(146, 148, 150, 84),
    desk: IRect(150, 196, 140, 30),
    deskReturn: IRect(150, 168, 30, 28),
    plantX: 154,
    plantY: 146,
    monitor: IRect(176, 158, 48, 34),
    chairBack: IRect(226, 178, 36, 18),
    seatX: 232,
    seatY: 174,
    standX: 296,
    standY: 194,
    breakX: 360,
    breakY: 132,
    keyboardX: 234,
    keyboardY: 199,
    trayX: 262,
    trayY: 200,
    mugX: 280,
    mugY: 198,
    plateCenterX: 220,
    plateCenterY: 233,
  );

  static const SeatPlacement gpt = SeatPlacement(
    seat: Seat.gpt,
    hitRect: IRect(326, 168, 134, 70),
    desk: IRect(330, 208, 120, 30),
    monitor: IRect(346, 172, 42, 32),
    chairBack: IRect(394, 190, 36, 18),
    seatX: 400,
    seatY: 186,
    standX: 454,
    standY: 204,
    breakX: 386,
    breakY: 132,
    keyboardX: 402,
    keyboardY: 211,
    trayX: 428,
    trayY: 212,
    mugX: 334,
    mugY: 210,
    plateCenterX: 390,
    plateCenterY: 245,
  );

  static const SeatPlacement gemini = SeatPlacement(
    seat: Seat.gemini,
    hitRect: IRect(60, 170, 40, 50),
    visitorChair: IRect(66, 182, 32, 34),
    seatX: 70,
    seatY: 178,
    standX: 104,
    standY: 176,
    breakX: 412,
    breakY: 132,
    plateCenterX: 82,
    plateCenterY: 223,
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
