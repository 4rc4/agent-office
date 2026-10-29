import 'dart:math' as math;
import 'dart:ui';

import 'package:office_core/office_core.dart';

import '../scene/furniture.dart' show paintKeyboard, paintStickyNote;
import '../scene/palette.dart';
import '../scene/pixel.dart';
import '../scene/irect.dart';
import '../scene/screens.dart';
import '../state/seat_state.dart';

/// The props along the floor line. Each one has a slot in front of it where
/// a character stands to use it.
enum StationKind {
  whiteboard,
  deskClaude,
  deskGpt,
  tv,
  mailbox;

  /// The seat whose desk this is; null for the shared props.
  Seat? get owner => switch (this) {
    StationKind.deskClaude => Seat.claude,
    StationKind.deskGpt => Seat.gpt,
    _ => null,
  };

  bool get isDesk => owner != null;

  /// The desk of [seat]; null for a seat without one (Gemini).
  static StationKind? deskOf(Seat seat) => switch (seat) {
    Seat.claude => StationKind.deskClaude,
    Seat.gpt => StationKind.deskGpt,
    Seat.gemini => null,
  };
}

/// Where the stations stand for one screen width: the centre of each prop
/// as a fraction of the width (persisted in `OfficeSettings`), the floor
/// line and the sprite scale. Sizes are in sprite pixels; [rect] and the
/// slots are logical pixels.
class StationLayout {
  StationLayout({
    required this.width,
    required this.floorY,
    Map<String, double> fractions = const {},
    this.scale = 4,
  }) : fractions = {
         for (final kind in StationKind.values)
           kind: (fractions[kind.name] ?? defaultFractions[kind]!).clamp(
             minFraction,
             maxFraction,
           ),
       };

  /// Default spread across the screen.
  static const Map<StationKind, double> defaultFractions = {
    StationKind.whiteboard: 0.10,
    StationKind.deskClaude: 0.26,
    StationKind.deskGpt: 0.66,
    StationKind.tv: 0.78,
    StationKind.mailbox: 0.92,
  };

  /// Smallest distance between two props' edges while dragging.
  static const double dragGap = 16;

  /// Where a character waits for the user (no prop there).
  static const double userSpotFraction = 0.5;

  static const double minFraction = 0.04;
  static const double maxFraction = 0.96;

  final double width;
  final double floorY;
  final int scale;

  /// Centre of each prop as a fraction of [width]; mutable for dragging.
  final Map<StationKind, double> fractions;

  /// Prop width and height in sprite pixels.
  static (int, int) spriteSize(StationKind kind) => switch (kind) {
    StationKind.whiteboard => (32, 28),
    StationKind.deskClaude || StationKind.deskGpt => (36, 30),
    StationKind.tv => (28, 26),
    StationKind.mailbox => (14, 24),
  };

  double centerX(StationKind kind) => fractions[kind]! * width;

  /// The prop's bounds in logical pixels, standing on the floor.
  Rect rect(StationKind kind) {
    final (w, h) = spriteSize(kind);
    final cx = centerX(kind);
    return Rect.fromLTWH(
      (cx - w * scale / 2).roundToDouble(),
      floorY - h * scale,
      (w * scale).toDouble(),
      (h * scale).toDouble(),
    );
  }

  /// Feet centre of a character using [kind]; [slot] 1 is the second place
  /// at a shared prop. Desks have one slot, right of the monitor.
  double slotX(StationKind kind, {int slot = 0}) {
    final cx = centerX(kind);
    final s = scale.toDouble();
    return switch (kind) {
      StationKind.deskClaude || StationKind.deskGpt => cx + 7 * s,
      StationKind.whiteboard => cx + (slot == 0 ? 21 * s : -21 * s),
      StationKind.tv => cx + (slot == 0 ? -19 * s : 19 * s),
      StationKind.mailbox => cx + (slot == 0 ? -13 * s : 13 * s),
    };
  }

  double get userSpotX => width * userSpotFraction;

  /// Moves [kind] towards [fraction] without crossing its neighbours in
  /// the current left-to-right order: the prop stops [dragGap] pixels
  /// before the next one and after the previous one, and never leaves the
  /// screen. Returns the fraction applied.
  double dragTo(StationKind kind, double fraction) {
    final order = [...StationKind.values]
      ..sort((a, b) => centerX(a).compareTo(centerX(b)));
    final index = order.indexOf(kind);
    final (w, _) = spriteSize(kind);
    final half = w * scale / 2;
    var low = minFraction * width;
    var high = maxFraction * width;
    if (index > 0) {
      low = math.max(low, rect(order[index - 1]).right + dragGap + half);
    }
    if (index < order.length - 1) {
      high = math.min(high, rect(order[index + 1]).left - dragGap - half);
    }
    final x = (fraction * width).clamp(math.min(low, high), high);
    final applied = x / width;
    fractions[kind] = applied;
    return applied;
  }

  /// Whether a feet centre at [x] would stand over a prop or its slots.
  bool overlapsStation(double x, {double margin = 96}) {
    for (final kind in StationKind.values) {
      final r = rect(kind).inflate(margin);
      if (x >= r.left && x <= r.right) return true;
    }
    return false;
  }

  /// Fractions keyed by station name, as `OfficeSettings` stores them.
  Map<String, double> toSettings() => {
    for (final e in fractions.entries) e.key.name: e.value,
  };
}

/// What the props show this frame.
class StationState {
  const StationState({
    this.screens = const {},
    this.notes = const [],
    this.flagUp = false,
    this.bars = const [],
  });

  /// Monitor content per desk owner.
  final Map<Seat, ScreenMode> screens;

  /// Sticky notes on the whiteboard, in display order (at most six shown).
  final List<TaskSnapshot> notes;

  /// Unread report in the mailbox.
  final bool flagUp;

  /// What the TV shows: usage bars, at most three drawn.
  final List<UsageBar> bars;
}

/// One bar on the TV: a seat's usage of one rate-limit window (0..1), or,
/// [dim], the tokens of a seat whose CLI reports no limits.
class UsageBar {
  const UsageBar({
    required this.seat,
    required this.window,
    required this.pct,
    this.resetsAt,
    this.dim = false,
    this.tokens = 0,
    this.known = true,
    this.renewed = false,
  });

  final Seat seat;
  final String window;
  final double pct;
  final DateTime? resetsAt;
  final bool dim;
  final int tokens;

  /// Whether [pct] is a real number. False when the CLI only said the
  /// window is fine, or when the window has been [renewed] since.
  final bool known;

  /// The window's reset time has passed: the old number no longer holds.
  final bool renewed;
}

/// Shadow on the floor under a prop or a character: two dithered ink rows
/// ending at row [floor] - 1, [rx] pixels to each side of [cx].
void paintFloorShadow(PixelBuffer b, int cx, int floor, int rx) {
  for (var x = -rx; x <= rx; x++) {
    final edge = x.abs() > rx - 3;
    if (!edge || (x & 1) == 0) b.set(cx + x, floor - 1, Palette.ink);
    if (((x + 1) & 1) == 0 && x.abs() <= rx - 2) {
      b.set(cx + x, floor - 2, Palette.ink);
    }
  }
}

/// Draws [kind] with its centre at sprite column [cx], standing on [floor]
/// (the first row below the prop).
void paintStation(
  PixelBuffer b,
  StationKind kind,
  int cx,
  int floor,
  StationState state,
  int frame,
) {
  final (w, _) = StationLayout.spriteSize(kind);
  paintFloorShadow(b, cx, floor, w ~/ 2 + 1);
  switch (kind) {
    case StationKind.deskClaude:
    case StationKind.deskGpt:
      _paintDesk(
        b,
        cx,
        floor,
        state.screens[kind.owner] ?? ScreenMode.off,
        frame,
      );
    case StationKind.whiteboard:
      _paintWhiteboard(b, cx, floor, state.notes);
    case StationKind.tv:
      _paintTv(b, cx, floor, state.bars, frame);
    case StationKind.mailbox:
      _paintMailbox(b, cx, floor, flagUp: state.flagUp);
  }
}

/// Desk: a 36-wide top band with the keyboard, a front with two drawers and
/// the monitor on the left; the character stands right of the monitor.
void _paintDesk(PixelBuffer b, int cx, int floor, ScreenMode mode, int frame) {
  final x = cx - 18;
  final top = floor - 14;
  b.shadeRect(
    x,
    top,
    36,
    7,
    base: Palette.woodLight,
    light: Palette.creamLight,
    dark: Palette.woodBase,
  );
  b.fill(x, top + 7, 36, 7, Palette.woodBase);
  b.hline(x, top + 7, 36, Palette.woodDark);
  b.hline(x, floor - 1, 36, Palette.woodOutline);
  b.vline(x, top, 14, Palette.woodOutline);
  b.vline(x + 35, top, 14, Palette.woodDark);
  for (var i = 0; i < 2; i++) {
    final dx = x + 3 + i * 12;
    b.shadeRect(
      dx,
      top + 9,
      10,
      4,
      base: Palette.woodBase,
      light: Palette.woodLight,
      dark: Palette.woodDark,
    );
    b.hline(dx + 3, top + 11, 4, Palette.amber);
  }
  paintKeyboard(b, cx + 7 - 11, top + 1);
  paintMonitor(b, IRect(x + 2, top - 15, 14, 11), mode, frame);
}

/// Rolling whiteboard: a steel frame on two legs with wheels, sticky notes
/// in a 3x2 grid and a marker tray.
void _paintWhiteboard(
  PixelBuffer b,
  int cx,
  int floor,
  List<TaskSnapshot> notes,
) {
  final x = cx - 16;
  final top = floor - 28;
  for (final lx in [x + 4, x + 26]) {
    b.fill(lx, floor - 8, 2, 6, Palette.steelShade);
    b.vline(lx, floor - 8, 6, Palette.steelLight);
    b.fill(lx - 1, floor - 2, 4, 2, Palette.steelDark);
  }
  b.shadeRect(
    x,
    top,
    32,
    20,
    base: Palette.steelBase,
    light: Palette.steelLight,
    dark: Palette.steelShade,
    bevel: 2,
  );
  b.hline(x, top + 19, 32, Palette.steelOutline);
  b.vline(x + 31, top, 20, Palette.steelOutline);
  b.fill(x + 3, top + 3, 26, 14, Palette.boardFace);
  b.hline(x + 3, top + 3, 26, Palette.boardShade);
  b.vline(x + 3, top + 3, 14, Palette.boardShade);
  for (var i = 0; i < notes.length && i < 6; i++) {
    final note = notes[i];
    final (fill, dark) = Palette.sticky(note.status);
    paintStickyNote(
      b,
      x + 5 + (i % 3) * 8,
      top + 5 + (i ~/ 3) * 6,
      7,
      5,
      fill,
      dark,
      pinned: note.isRoot,
    );
  }
  b.fill(x + 6, top + 20, 20, 2, Palette.steelShade);
  b.hline(x + 6, top + 20, 20, Palette.steelLight);
  b.fill(x + 8, top + 19, 5, 1, Palette.red);
  b.fill(x + 15, top + 19, 5, 1, Palette.teal);
}

/// TV corner: a low cabinet with a wide flat screen on it. The screen
/// shows up to three usage bars (label block in the seat's colour, a track
/// and a fill that goes green, amber, red); a blinking LED sits under it.
void _paintTv(
  PixelBuffer b,
  int cx,
  int floor,
  List<UsageBar> bars,
  int frame,
) {
  final x = cx - 10;
  b.shadeRect(
    x,
    floor - 5,
    20,
    5,
    base: Palette.woodBase,
    light: Palette.woodLight,
    dark: Palette.woodDark,
  );
  b.hline(x, floor - 1, 20, Palette.woodOutline);
  b.hline(x + 3, floor - 3, 5, Palette.amber);
  final body = IRect(cx - 12, floor - 25, 24, 20);
  b.shadeRect(
    body.x,
    body.y,
    body.w,
    body.h,
    base: Palette.slateBase,
    light: Palette.slateLight,
    dark: Palette.slateDark,
    rounded: true,
  );
  b.roundRing(body.x, body.y, body.w, body.h, Palette.slateDark);
  b.fill(cx - 2, floor - 5, 4, 1, Palette.slateShade);
  final sx = body.x + 2;
  final sy = body.y + 2;
  const sw = 20;
  const sh = 14;
  b.emissive(() {
    b.fill(sx, sy, sw, sh, Palette.terminalBg);
    if (bars.isEmpty) {
      b.hline(sx + 3, sy + 5, 14, Palette.terminalDim);
      b.hline(sx + 3, sy + 8, 10, Palette.terminalDim);
    }
    for (var i = 0; i < bars.length && i < 3; i++) {
      final bar = bars[i];
      final y = sy + 2 + i * 4;
      final seatColor = bar.seat == Seat.gpt ? Palette.teal : Palette.orange;
      b.fill(sx + 1, y, 2, 3, seatColor);
      b.fill(sx + 4, y, 15, 3, Palette.slateShade);
      // An unknown but fine window shows a short green stub.
      final width = bar.known
          ? (bar.pct.clamp(0, 1) * 15).round()
          : (bar.renewed ? 0 : 2);
      final fill = bar.dim
          ? Palette.greyNoteDark
          : bar.pct < 0.7
          ? Palette.green
          : bar.pct < 0.9
          ? Palette.yellow
          : Palette.red;
      if (width > 0) b.fill(sx + 4, y, width, 3, fill);
    }
    b.set(
      body.right - 4,
      body.bottom - 2,
      frame.isEven ? Palette.amberLight : Palette.amberDark,
    );
  });
  b.hline(sx + 1, sy, 6, PixelBuffer.lightOf(Palette.terminalBg));
}

/// Mailbox on a post; the flag stands up while a report is unread.
void _paintMailbox(PixelBuffer b, int cx, int floor, {required bool flagUp}) {
  b.fill(cx - 1, floor - 15, 3, 15, Palette.woodShade);
  b.vline(cx - 1, floor - 15, 15, Palette.woodBase);
  b.vline(cx + 1, floor - 15, 15, Palette.woodDark);
  final r = IRect(cx - 7, floor - 24, 14, 10);
  b.shadeRect(
    r.x,
    r.y,
    r.w,
    r.h,
    base: Palette.steelBase,
    light: Palette.steelLight,
    dark: Palette.steelShade,
    rounded: true,
  );
  b.roundRing(r.x, r.y, r.w, r.h, Palette.steelOutline);
  b.hline(r.x + 2, r.y + 1, r.w - 4, Palette.steelLight);
  b.vline(r.x + 4, r.y + 2, r.h - 4, Palette.steelShade);
  b.vline(r.x + 5, r.y + 2, r.h - 4, Palette.steelLight);
  b.fill(r.x + 2, r.y + r.h ~/ 2 - 1, 2, 2, Palette.amber);
  if (flagUp) {
    b.fill(r.right - 4, r.y - 7, 2, 9, Palette.redDark);
    b.fill(r.right - 4, r.y - 7, 4, 3, Palette.red);
    b.hline(r.right - 4, r.y - 7, 4, PixelBuffer.lightOf(Palette.red));
  } else {
    b.fill(r.right - 1, r.y + 3, 6, 2, Palette.red);
    b.hline(r.right - 1, r.y + 3, 6, PixelBuffer.lightOf(Palette.red));
  }
}
