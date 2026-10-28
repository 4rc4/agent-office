import 'dart:ui';

import 'palette.dart';
import 'pixel.dart';
import 'scene_layout.dart';

/// Static furniture of the office. Each painter takes scene-pixel rects from
/// [SceneLayout] so the layout file stays the single source of positions.

/// Wall, baseboard and floorboards.
void paintRoom(Px px) {
  px.fill(0, 0, SceneLayout.width, SceneLayout.wallBottom, ScenePalette.wall);
  px.fill(
    0,
    SceneLayout.wallBottom,
    SceneLayout.width,
    1,
    ScenePalette.outline,
  );
  px.fill(
    0,
    SceneLayout.wallBottom + 1,
    SceneLayout.width,
    SceneLayout.floorTop - SceneLayout.wallBottom - 1,
    ScenePalette.woodDark,
  );
  var band = 0;
  for (var y = SceneLayout.floorTop; y < SceneLayout.height; y += 10) {
    final h = y + 10 > SceneLayout.height ? SceneLayout.height - y : 10;
    px.fill(
      0,
      y,
      SceneLayout.width,
      h,
      band.isEven ? ScenePalette.floorA : ScenePalette.floorB,
    );
    band++;
  }
}

/// Door in the back wall with a small window and a knob, plus a doormat.
void paintDoor(Px px, IRect r, IRect mat) {
  px.box(r.x, r.y, r.w, r.h, ScenePalette.woodLight);
  px.box(r.x + 3, r.y + 3, r.w - 6, r.h - 3, ScenePalette.woodDark);
  px.box(r.x + 10, r.y + 9, 10, 10, ScenePalette.cream);
  px.fill(r.x + 14, r.y + 10, 1, 8, ScenePalette.outline);
  px.fill(r.x + 11, r.y + 13, 8, 1, ScenePalette.outline);
  px.box(r.x + r.w - 9, r.y + 31, 4, 4, ScenePalette.yellow);
  px.roundBox(mat.x, mat.y, mat.w, mat.h, ScenePalette.slate);
}

/// Whiteboard frame with a marker tray; notes are drawn by the painter.
void paintWhiteboard(Px px, IRect r) {
  px.box(r.x, r.y, r.w, r.h, ScenePalette.grey);
  px.box(r.x + 3, r.y + 3, r.w - 6, r.h - 6, ScenePalette.cream);
  px.box(r.x + 10, r.bottom - 1, r.w - 20, 3, ScenePalette.steel);
}

/// Round wall clock showing a fixed, calm ten past ten.
void paintClock(Px px, IRect r) {
  final cx = r.centerX;
  final cy = r.centerY;
  px.disc(cx, cy, 6, ScenePalette.cream);
  px.fill(cx, cy - 4, 1, 4, ScenePalette.outline);
  px.fill(cx, cy, 4, 1, ScenePalette.outline);
  px.fill(cx, cy, 1, 1, ScenePalette.red);
}

/// Three usage meters. [levels] are 0..1 per bar and fill in the matching
/// accent colour from the bottom; a strip of the accent sits on top.
void paintGauges(Px px, IRect r, List<Color> accents, List<double> levels) {
  for (var i = 0; i < accents.length; i++) {
    final x = r.x + i * (SceneLayout.gaugeWidth + SceneLayout.gaugeGap);
    px.box(x, r.y, SceneLayout.gaugeWidth, r.h, ScenePalette.screenOff);
    px.fill(x + 1, r.y + 1, SceneLayout.gaugeWidth - 2, 2, accents[i]);
    px.fill(
      x + 1,
      r.y + 3,
      SceneLayout.gaugeWidth - 2,
      1,
      ScenePalette.outline,
    );
    final maxH = r.h - 6;
    final level = i < levels.length ? levels[i].clamp(0.0, 1.0) : 0.0;
    final h = (maxH * level).round();
    if (h > 0) {
      px.fill(
        x + 2,
        r.bottom - 2 - h,
        SceneLayout.gaugeWidth - 4,
        h,
        accents[i],
      );
    }
  }
}

/// Filing cabinet with three drawers.
void paintCabinet(Px px, IRect r) {
  px.roundBox(r.x, r.y, r.w, r.h, ScenePalette.steel);
  final drawerH = (r.h - 1) ~/ 3;
  for (var i = 1; i < 3; i++) {
    px.fill(r.x, r.y + i * drawerH, r.w, 1, ScenePalette.outline);
  }
  for (var i = 0; i < 3; i++) {
    final y = r.y + i * drawerH + drawerH ~/ 2;
    px.fill(r.x + r.w ~/ 2 - 3, y, 6, 1, ScenePalette.outline);
  }
}

/// Counter with cupboard doors, a coffee machine on top and two stools.
void paintCoffeeCorner(
  Px px,
  IRect counter,
  IRect machine,
  List<IRect> stools,
) {
  px.box(counter.x, counter.y, counter.w, 7, ScenePalette.woodLight);
  px.box(
    counter.x,
    counter.y + 6,
    counter.w,
    counter.h - 6,
    ScenePalette.woodDark,
  );
  final doorTop = counter.y + 9;
  final doorH = counter.h - 12;
  px.ring(counter.x + 4, doorTop, counter.w ~/ 2 - 5, doorH);
  px.ring(counter.x + counter.w ~/ 2 + 1, doorTop, counter.w ~/ 2 - 5, doorH);
  px.fill(
    counter.x + counter.w ~/ 2 - 4,
    doorTop + doorH ~/ 2,
    2,
    2,
    ScenePalette.outline,
  );
  px.fill(
    counter.x + counter.w ~/ 2 + 3,
    doorTop + doorH ~/ 2,
    2,
    2,
    ScenePalette.outline,
  );

  px.roundBox(machine.x, machine.y, machine.w, machine.h, ScenePalette.slate);
  px.box(machine.x + machine.w - 7, machine.y + 3, 4, 4, ScenePalette.red);
  px.fill(
    machine.x + 3,
    machine.y + 10,
    machine.w - 6,
    1,
    ScenePalette.outline,
  );
  px.fill(
    machine.x + machine.w ~/ 2 - 1,
    machine.y + 11,
    2,
    3,
    ScenePalette.outline,
  );
  px.box(
    machine.x + machine.w ~/ 2 - 3,
    machine.y + machine.h - 7,
    6,
    5,
    ScenePalette.cream,
  );
  px.box(counter.x + 8, counter.y - 3, 6, 5, ScenePalette.cream);

  for (final s in stools) {
    px.fill(s.x + 2, s.y + 3, 1, s.h - 3, ScenePalette.outline);
    px.fill(s.right - 3, s.y + 3, 1, s.h - 3, ScenePalette.outline);
    px.roundBox(s.x, s.y, s.w, 4, ScenePalette.woodLight);
  }
}

/// Desk: light top surface band and a dark front face with one drawer.
void paintDesk(Px px, IRect r, int surfaceHeight) {
  px.box(r.x, r.y, r.w, surfaceHeight, ScenePalette.woodLight);
  px.box(
    r.x,
    r.y + surfaceHeight - 1,
    r.w,
    r.h - surfaceHeight + 1,
    ScenePalette.woodDark,
  );
  final dx = r.right - 18;
  final dy = r.y + surfaceHeight + 3;
  px.ring(dx, dy, 12, 7);
  px.fill(dx + 4, dy + 3, 4, 1, ScenePalette.outline);
}

/// Desk return going back toward the wall (corner desk).
void paintDeskReturn(Px px, IRect r) {
  px.box(r.x, r.y, r.w, r.h, ScenePalette.woodLight);
}

/// Pot plant; (x, y) is the top-left of the leaves, the pot ends at y + 14.
void paintPlant(Px px, int x, int y) {
  const leaves = <(int, int)>[
    (2, 0), (3, 0), (1, 1), (2, 1), (3, 1), (4, 1), //
    (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (5, 2), //
    (1, 3), (2, 3), (3, 3), (4, 3), //
  ];
  px.fill(x + 4, y + 4, 1, 4, ScenePalette.outline);
  px.roundBox(x + 1, y + 7, 8, 7, ScenePalette.terracotta);
  px.blob(leaves, ScenePalette.leaf, x: x + 1, y: y);
}

/// Office chair back, peeking out behind a seated character.
void paintChairBack(Px px, IRect r) {
  px.roundBox(r.x, r.y, r.w, r.h, ScenePalette.slate);
}

/// Visitor chair: backrest, seat and two legs. Greyed when nobody owns it.
void paintVisitorChair(Px px, IRect r, {required bool greyed}) {
  final color = greyed ? ScenePalette.greyed : ScenePalette.woodDark;
  px.fill(r.x + 2, r.y + 13, 2, 7, ScenePalette.outline);
  px.fill(r.right - 4, r.y + 13, 2, 7, ScenePalette.outline);
  px.roundBox(r.x + 2, r.y, r.w - 4, 9, color);
  px.box(r.x, r.y + 8, r.w, 6, color);
}

/// Reception desk with a lamp and a paper stack on top.
void paintReceptionDesk(Px px, IRect r) {
  const surface = 6;
  px.box(r.x, r.y, r.w, surface, ScenePalette.woodLight);
  px.box(r.x, r.y + surface - 1, r.w, r.h - surface + 1, ScenePalette.woodDark);
  px.box(r.x + 6, r.y - 3, 10, 4, ScenePalette.paper);
  px.fill(r.x + 42, r.y - 8, 1, 8, ScenePalette.outline);
  px.roundBox(r.x + 38, r.y - 12, 9, 5, ScenePalette.yellow);
}

/// Mailbox on a post. The red flag is up when a report is waiting.
void paintMailbox(Px px, IRect r, {required bool flagUp}) {
  px.box(r.x + r.w ~/ 2 - 2, r.bottom - 1, 4, 21, ScenePalette.woodDark);
  px.roundBox(r.x, r.y, r.w, r.h, ScenePalette.steel);
  px.fill(r.x + 4, r.y + 4, r.w - 8, 1, ScenePalette.outline);
  if (flagUp) {
    px.box(r.right - 4, r.y - 6, 4, 8, ScenePalette.red);
  } else {
    px.box(r.right - 1, r.y + 3, 6, 4, ScenePalette.red);
  }
}

/// 14x4 keyboard at (x, y).
void paintKeyboard(Px px, int x, int y) {
  px.box(x, y, 14, 4, ScenePalette.slate);
  for (var i = 0; i < 6; i++) {
    px.fill(x + 2 + i * 2, y + 1, 1, 1, ScenePalette.steel);
  }
}
