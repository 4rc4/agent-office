import 'dart:ui';

import 'package:office_core/office_core.dart';

import '../state/seat_state.dart';

/// Daylight palette of the office. Every material has three or four tones
/// (highlight, base, shade, dark) and its own outline colour; light comes
/// from the window on the left, so highlights sit top-left and shades
/// bottom-right. Night is this palette seen through the night
/// `SceneLighting` tint, not a second palette.
///
/// Colours are plain ARGB ints because the scene is composed in a
/// `PixelBuffer` before it reaches the canvas.
abstract final class Palette {

  // Plaster wall.
  static const int wallLight = 0xFFFAEDD3;
  static const int wallBase = 0xFFF0DEBB;
  static const int wallShade = 0xFFDEC8A2;
  static const int wallDark = 0xFFC7AC86;

  // Wainscoting and skirting (painted warm wood).
  static const int wainLight = 0xFFD2A26E;
  static const int wainBase = 0xFFB58353;
  static const int wainShade = 0xFF94663C;
  static const int wainDark = 0xFF70492A;
  static const int wainOutline = 0xFF4E311A;

  // Floorboards.
  static const int floorLight = 0xFFCD935E;
  static const int floorBase = 0xFFB77D4C;
  static const int floorShade = 0xFF9C673C;
  static const int floorDark = 0xFF7E512E;
  static const int floorGap = 0xFF5D3B21;

  // Desk and counter wood.
  static const int woodLight = 0xFFE9C08C;
  static const int woodBase = 0xFFCE9E64;
  static const int woodShade = 0xFFAB7A42;
  static const int woodDark = 0xFF83572A;
  static const int woodOutline = 0xFF523418;

  // Cream painted frames (window, door).
  static const int creamLight = 0xFFFFF9E8;
  static const int creamBase = 0xFFF4E7CA;
  static const int creamShade = 0xFFDACAA6;
  static const int creamDark = 0xFFB39E77;
  static const int creamOutline = 0xFF7C6A4C;

  // Day sky through the window.
  static const int daySkyTop = 0xFF4E92E0;
  static const int daySkyHigh = 0xFF7FB6EC;
  static const int daySkyMid = 0xFFB4DAF5;
  static const int daySkyLow = 0xFFE2F2FA;
  static const int sun = 0xFFFFFBDC;
  static const int sunRim = 0xFFFFEDA6;
  static const int sunHalo = 0xFFD9E9F8;
  static const int cloud = 0xFFFFFFFF;
  static const int cloudShade = 0xFFD3E3F0;
  static const int dayHillFar = 0xFF9CCB92;
  static const int dayHillNear = 0xFF6FAD66;
  static const int dayBuildingFar = 0xFFA6BDD3;
  static const int dayBuilding = 0xFF8299B4;
  static const int dayBuildingLight = 0xFFC0D1E2;
  static const int dayWindow = 0xFF5F7390;
  static const int dayGround = 0xFF567F6A;

  // Night sky through the window.
  static const int nightSkyTop = 0xFF0C1330;
  static const int nightSkyMid = 0xFF131E46;
  static const int nightSkyLow = 0xFF1C2D62;
  static const int star = 0xFFE6EBFF;
  static const int starDim = 0xFF8E9BD0;
  static const int moon = 0xFFF4EFCF;
  static const int moonShade = 0xFFD5CFA2;
  static const int nightHillFar = 0xFF1A2A52;
  static const int nightHillNear = 0xFF152243;
  static const int nightBuildingFar = 0xFF1A2550;
  static const int nightBuilding = 0xFF0F1733;
  static const int cityWarm = 0xFFF2C76A;
  static const int cityTeal = 0xFF7FDCE6;
  static const int nightGround = 0xFF0B1128;

  // String light bulbs.
  static const int bulbWarm = 0xFFFFE3A1;
  static const int bulbCool = 0xFFC6F3F5;

  // Curtains (day tones; the lighting carries its own).
  static const int curtainLight = 0xFFCD6A50;
  static const int curtainBase = 0xFFAA503D;
  static const int curtainDark = 0xFF823C2E;
  static const int curtainOutline = 0xFF5A2921;

  // Rug.
  static const int rugLight = 0xFFC96E52;
  static const int rugBase = 0xFFAB553F;
  static const int rugDark = 0xFF853B2C;
  static const int rugPattern = 0xFFEBC89C;
  static const int rugOutline = 0xFF5F2B20;

  // Brushed metal (cabinet, whiteboard frame, mailbox).
  static const int steelLight = 0xFFCDD2DC;
  static const int steelBase = 0xFFA6ACBB;
  static const int steelShade = 0xFF7E8597;
  static const int steelDark = 0xFF585E6E;
  static const int steelOutline = 0xFF353946;

  // Dark plastic (monitors, keyboards, coffee machine).
  static const int slateLight = 0xFF5F6480;
  static const int slateBase = 0xFF40445A;
  static const int slateShade = 0xFF2D3042;
  static const int slateDark = 0xFF1C1E2C;

  // Paper and the whiteboard.
  static const int paper = 0xFFFFF8E9;
  static const int paperShade = 0xFFE9DDC6;
  static const int paperLine = 0xFFA0A8C6;
  static const int boardFace = 0xFFFCF9F1;
  static const int boardShade = 0xFFE6E0D1;

  // Screens.
  static const int screenOff = 0xFF1D2034;
  static const int screenGlint = 0xFF2E3352;
  static const int terminalBg = 0xFF102B23;
  static const int terminalText = 0xFF5DE592;
  static const int terminalDim = 0xFF2F8E5C;
  static const int globeBg = 0xFF1F3D6C;
  static const int globeSea = 0xFF5EC8EA;
  static const int globeLand = 0xFF8FDA8B;
  static const int alertBright = 0xFFD9484A;
  static const int alertDim = 0xFF7A2A33;

  // Plants.
  static const int leafLight = 0xFF92DA7C;
  static const int leafBase = 0xFF61B25C;
  static const int leafDark = 0xFF3C8145;
  static const int leafOutline = 0xFF25562F;
  static const int potLight = 0xFFDB8C64;
  static const int potBase = 0xFFB7694B;
  static const int potDark = 0xFF8C4C35;
  static const int soil = 0xFF4E3220;

  // Accents.
  static const int amberLight = 0xFFFFE38F;
  static const int amber = 0xFFF3BA4E;
  static const int amberDark = 0xFFC98C2C;
  static const int lampGlow = 0xFFFFEBB0;
  static const int red = 0xFFE05A5A;
  static const int redDark = 0xFFA83B3B;
  static const int green = 0xFF7CD08F;
  static const int greenDark = 0xFF4E9B63;
  static const int orange = 0xFFF3A447;
  static const int orangeDark = 0xFFC27A28;
  static const int yellow = 0xFFF7D35B;
  static const int yellowDark = 0xFFC9A431;
  static const int greyNote = 0xFFD2CCC4;
  static const int greyNoteDark = 0xFFA39C93;
  static const int teal = 0xFF30A290;
  static const int tealLight = 0xFF5ECAB5;
  static const int tealDark = 0xFF1F7063;
  static const int tealOutline = 0xFF144B43;
  static const int violet = 0xFF7F6DF1;
  static const int violetLight = 0xFFA89CFF;
  static const int violetDark = 0xFF5B4CB9;
  static const int violetOutline = 0xFF3D3381;
  static const int water = 0xFF70D4F1;
  static const int waterDark = 0xFF3C9CC3;
  static const int cream = 0xFFFFF4DC;
  static const int creamMug = 0xFFD9CBB0;
  static const int steam = 0xFFFFF9EE;
  static const int pink = 0xFFF2A9A2;

  /// Generic dark line for mixed props and text boxes.
  static const int ink = 0xFF2B2127;

  /// Sticky note fill and edge colours for a task status.
  static (int, int) sticky(TaskStatus status) => switch (status) {
    TaskStatus.queued ||
    TaskStatus.planned ||
    TaskStatus.assigned => (greyNote, greyNoteDark),
    TaskStatus.running || TaskStatus.review => (yellow, yellowDark),
    TaskStatus.waitingApproval ||
    TaskStatus.waitingUser ||
    TaskStatus.waitingBudget ||
    TaskStatus.interrupted ||
    TaskStatus.needsHuman => (orange, orangeDark),
    TaskStatus.done => (green, greenDark),
    TaskStatus.failed => (red, redDark),
  };

  /// Speech bubble fill for a bubble kind.
  static int bubbleFill(BubbleKind kind) => switch (kind) {
    BubbleKind.info => cream,
    BubbleKind.question => yellow,
    BubbleKind.warning => orange,
    BubbleKind.error => red,
    BubbleKind.success => green,
  };

  /// Speech bubble text colour; ink on light fills, cream on the red one.
  static Color bubbleText(BubbleKind kind) =>
      Color(kind == BubbleKind.error ? cream : ink);
}

/// Shaded tones of one employee sprite.
class CharacterPalette {
  const CharacterPalette({
    required this.hairLight,
    required this.hair,
    required this.hairDark,
    required this.hairOutline,
    required this.bodyLight,
    required this.body,
    required this.bodyDark,
    required this.bodyOutline,
    required this.accent,
    required this.chair,
    required this.chairLight,
    required this.chairDark,
  });

  final int hairLight;
  final int hair;
  final int hairDark;
  final int hairOutline;

  /// Hoodie, shirt or sweater tones.
  final int bodyLight;
  final int body;
  final int bodyDark;
  final int bodyOutline;

  /// Accent used for the seat's gauge and name plate.
  final int accent;

  /// The seat's chair upholstery.
  final int chair;
  final int chairLight;
  final int chairDark;

  static const int skinLight = 0xFFFFE8CC;
  static const int skin = 0xFFF7D2A8;
  static const int skinShade = 0xFFDBA878;
  static const int skinOutline = 0xFF8E5C3E;
  static const int pants = 0xFF47516F;
  static const int pantsDark = 0xFF333B54;
  static const int pantsOutline = 0xFF20263A;
  static const int shoe = 0xFF3B2B30;
  static const int shoeLight = 0xFF5C474C;

  static const CharacterPalette claude = CharacterPalette(
    hairLight: 0xFF8A5A3C,
    hair: 0xFF6B3F2A,
    hairDark: 0xFF4A2A1C,
    hairOutline: 0xFF2E1810,
    bodyLight: 0xFFF7AA60,
    body: 0xFFE8873A,
    bodyDark: 0xFFBB612A,
    bodyOutline: 0xFF7E3E18,
    accent: 0xFFE8873A,
    chair: 0xFF7A3F33,
    chairLight: 0xFF9A5546,
    chairDark: 0xFF512A22,
  );

  static const CharacterPalette gpt = CharacterPalette(
    hairLight: 0xFF7C5339,
    hair: 0xFF5B3B29,
    hairDark: 0xFF3F281A,
    hairOutline: 0xFF261810,
    bodyLight: Palette.tealLight,
    body: Palette.teal,
    bodyDark: Palette.tealDark,
    bodyOutline: Palette.tealOutline,
    accent: Palette.teal,
    chair: 0xFF2A5E66,
    chairLight: 0xFF3B7E86,
    chairDark: 0xFF1B3F45,
  );

  static const CharacterPalette gemini = CharacterPalette(
    hairLight: 0xFF4F4072,
    hair: 0xFF31264B,
    hairDark: 0xFF201935,
    hairOutline: 0xFF120E1F,
    bodyLight: Palette.violetLight,
    body: Palette.violet,
    bodyDark: Palette.violetDark,
    bodyOutline: Palette.violetOutline,
    accent: Palette.violet,
    chair: 0xFF5A4CA0,
    chairLight: 0xFF7A6BC4,
    chairDark: 0xFF3C3270,
  );

  static CharacterPalette of(Seat seat) => switch (seat) {
    Seat.claude => claude,
    Seat.gpt => gpt,
    Seat.gemini => gemini,
  };
}
