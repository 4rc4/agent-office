import 'dart:ui';

import 'package:office_core/office_core.dart';

import '../state/seat_state.dart';

/// Four tones of one material, lit from the upper left: [light] on the top
/// and left edges, [base] in the middle, [shade] on the bottom and right
/// edges and [dark] for the selective outline.
class Tones {
  const Tones(this.light, this.base, this.shade, this.dark);

  final Color light;
  final Color base;
  final Color shade;
  final Color dark;
}

/// Colours of the night studio. Cool navy, slate and teal everywhere; warm
/// orange only on lamps, bulbs and Claude.
abstract final class ScenePalette {
  /// Letterbox colour around the scene.
  static const Color background = Color(0xFF0A0C16);

  /// Deepest line colour, used where a silhouette needs to pop.
  static const Color ink = Color(0xFF141628);

  // Walls and floor.
  static const Tones wall = Tones(
    Color(0xFF4C5880),
    Color(0xFF3E4869),
    Color(0xFF343C5A),
    Color(0xFF282E47),
  );
  static const Color wallGlow = Color(0xFF586690);
  static const Tones skirting = Tones(
    Color(0xFF5B6488),
    Color(0xFF444B6E),
    Color(0xFF32374F),
    Color(0xFF22263A),
  );
  static const Tones wood = Tones(
    Color(0xFF6C4A33),
    Color(0xFF563A29),
    Color(0xFF47301F),
    Color(0xFF2B1B12),
  );
  static const Color woodGrain = Color(0xFF3E2A1B);
  static const Color woodLit = Color(0xFF7E5A3F);

  // Rug.
  static const Tones rug = Tones(
    Color(0xFF3F8C96),
    Color(0xFF2E6E78),
    Color(0xFF235660),
    Color(0xFF183E46),
  );
  static const Color rugPattern = Color(0xFF5CA8B2);

  // Furniture materials.
  static const Tones deskTop = Tones(
    Color(0xFFBE9D6C),
    Color(0xFF9C7B52),
    Color(0xFF7B5F3F),
    Color(0xFF4A3724),
  );
  static const Tones deskFront = Tones(
    Color(0xFF7F6245),
    Color(0xFF66503A),
    Color(0xFF50402E),
    Color(0xFF32271B),
  );
  static const Tones steel = Tones(
    Color(0xFFA3AEC8),
    Color(0xFF7D889F),
    Color(0xFF5E6880),
    Color(0xFF3B4154),
  );
  static const Tones slate = Tones(
    Color(0xFF626E92),
    Color(0xFF3F4769),
    Color(0xFF2C324C),
    Color(0xFF1B1F33),
  );
  static const Tones cushion = Tones(
    Color(0xFF4D5A82),
    Color(0xFF384263),
    Color(0xFF28304A),
    Color(0xFF1B1F33),
  );
  static const Tones frame = Tones(
    Color(0xFFE4E8F0),
    Color(0xFFC2C8D6),
    Color(0xFF8E97AC),
    Color(0xFF5A6279),
  );
  static const Tones board = Tones(
    Color(0xFFF6F8FB),
    Color(0xFFECEFF5),
    Color(0xFFDADFE8),
    Color(0xFF8E97AC),
  );
  static const Tones doorWood = Tones(
    Color(0xFF8E6A48),
    Color(0xFF74553A),
    Color(0xFF5B4330),
    Color(0xFF3A2A1C),
  );
  static const Tones teal = Tones(
    Color(0xFF5ED3CC),
    Color(0xFF3AAFA8),
    Color(0xFF27837E),
    Color(0xFF185552),
  );
  static const Tones leaf = Tones(
    Color(0xFF7FD08E),
    Color(0xFF4FA866),
    Color(0xFF337A48),
    Color(0xFF1F4F2E),
  );
  static const Tones pot = Tones(
    Color(0xFFB07A5A),
    Color(0xFF8F6046),
    Color(0xFF6F4A36),
    Color(0xFF452C20),
  );
  static const Tones paper = Tones(
    Color(0xFFFFFFFF),
    Color(0xFFEEF1F7),
    Color(0xFFCCD3E0),
    Color(0xFF8B96AE),
  );
  static const Color paperLine = Color(0xFF8C9BD1);
  static const Tones mug = Tones(
    Color(0xFFF8F6F0),
    Color(0xFFE6E2D6),
    Color(0xFFBDB8AA),
    Color(0xFF6E6A62),
  );

  // Night sky through the window.
  static const Color skyTop = Color(0xFF0C1330);
  static const Color skyMid = Color(0xFF131E46);
  static const Color skyLow = Color(0xFF1A2A5E);
  static const Color moon = Color(0xFFF4EFCF);
  static const Color moonShade = Color(0xFFD5CFA2);
  static const Color moonHalo = Color(0x33F4EFCF);
  static const Color star = Color(0xFFE6EBFF);
  static const Color starDim = Color(0xFF8E9BD0);
  static const Color building = Color(0xFF0F1733);
  static const Color buildingLit = Color(0xFF161F44);
  static const Color cityWarm = Color(0xFFF2C76A);
  static const Color cityTeal = Color(0xFF7FDCE6);
  static const Color glassHighlight = Color(0x40FFFFFF);

  // Light and shadow overlays.
  static const Color moonlight = Color(0x2CDCE8FF);
  static const Color moonlightSoft = Color(0x16DCE8FF);
  static const Color shadow = Color(0x5A0A0C1E);
  static const Color shadowSoft = Color(0x300A0C1E);
  static const Color lampGlow = Color(0x40FFB45A);
  static const Color lampGlowSoft = Color(0x22FFB45A);
  static const Color bulbGlow = Color(0x30FFE2A0);

  // Lamps (the warm spot).
  static const Color lampShade = Color(0xFFF4C27A);
  static const Color lampShadeShade = Color(0xFFD9964C);
  static const Color lampBulb = Color(0xFFFFF0C2);
  static const Color lampStem = Color(0xFF3B4154);
  static const Color bulbWarm = Color(0xFFFFE3A1);
  static const Color bulbCool = Color(0xFFC6F3F5);

  // Screens.
  static const Color screenOff = Color(0xFF151A33);
  static const Color screenOffReflect = Color(0xFF1F2646);
  static const Color editorBg = Color(0xFF1C2340);
  static const Color editorGutter = Color(0xFF28305A);
  static const Color codeTeal = Color(0xFF6ED8D8);
  static const Color codeOrange = Color(0xFFF2A95C);
  static const Color codePale = Color(0xFFC9D2F2);
  static const Color codeViolet = Color(0xFFA596F5);
  static const Color terminalBg = Color(0xFF0D1F1A);
  static const Color terminalText = Color(0xFF55E38F);
  static const Color terminalDim = Color(0xFF2E8F5C);
  static const Color globeBg = Color(0xFF17315E);
  static const Color globeSea = Color(0xFF5FC9E8);
  static const Color globeLand = Color(0xFF8EDBA0);
  static const Color alertBright = Color(0xFFE04F55);
  static const Color alertDim = Color(0xFF6E2630);
  static const Color glowTeal = Color(0x3858D6E0);
  static const Color glowGreen = Color(0x3055E38F);
  static const Color glowRed = Color(0x38E04F55);
  static const Color glowPale = Color(0x30C9D2F2);
  static const Color led = Color(0xFF5FE0D8);

  // Small accents.
  static const Color cream = Color(0xFFF4F1E8);
  static const Color red = Color(0xFFE05A5A);
  static const Color redDark = Color(0xFF9E3A3E);
  static const Color yellow = Color(0xFFF2C14E);
  static const Color yellowDark = Color(0xFFC2923A);
  static const Color orange = Color(0xFFF0A24A);
  static const Color orangeDark = Color(0xFFB8702C);
  static const Color green = Color(0xFF6FCF97);
  static const Color greenDark = Color(0xFF3E8F62);
  static const Color grey = Color(0xFFB8BCD0);
  static const Color greyDark = Color(0xFF7E849C);
  static const Color water = Color(0xFF7FDCE6);
  static const Color waterDark = Color(0xFF3FA7B8);
  static const Color pin = Color(0xFFE05A5A);
  static const Color steam = Color(0xFFD7DDEA);

  /// Sticky note colours for a task status: (light, base, shade).
  static Tones sticky(TaskStatus status) => switch (status) {
    TaskStatus.queued || TaskStatus.planned || TaskStatus.assigned => Tones(
      Color(0xFFD5D9E8),
      Color(0xFFB8BCD0),
      Color(0xFF8F94AE),
      Color(0xFF5E637C),
    ),
    TaskStatus.running || TaskStatus.review => Tones(
      Color(0xFFFBD97C),
      Color(0xFFF2C14E),
      Color(0xFFC9973A),
      Color(0xFF8A6422),
    ),
    TaskStatus.waitingApproval ||
    TaskStatus.waitingUser ||
    TaskStatus.waitingBudget ||
    TaskStatus.interrupted ||
    TaskStatus.needsHuman => Tones(
      Color(0xFFF7BD77),
      Color(0xFFF0A24A),
      Color(0xFFC27B30),
      Color(0xFF85511C),
    ),
    TaskStatus.done => Tones(
      Color(0xFF9BE2B8),
      Color(0xFF6FCF97),
      Color(0xFF4EA474),
      Color(0xFF2E6E4B),
    ),
    TaskStatus.failed => Tones(
      Color(0xFFF08A8A),
      Color(0xFFE05A5A),
      Color(0xFFB03F42),
      Color(0xFF772A2E),
    ),
  };

  /// Speech bubble fill for a bubble kind.
  static Color bubbleFill(BubbleKind kind) => switch (kind) {
    BubbleKind.info => cream,
    BubbleKind.question => yellow,
    BubbleKind.warning => orange,
    BubbleKind.error => red,
    BubbleKind.success => green,
  };

  /// Darker edge of the bubble fill.
  static Color bubbleEdge(BubbleKind kind) => switch (kind) {
    BubbleKind.info => Color(0xFF9A9EB2),
    BubbleKind.question => yellowDark,
    BubbleKind.warning => orangeDark,
    BubbleKind.error => redDark,
    BubbleKind.success => greenDark,
  };

  /// Speech bubble text colour; ink on light fills, cream on the red one.
  static Color bubbleText(BubbleKind kind) =>
      kind == BubbleKind.error ? cream : ink;
}

/// Shaded colours of one employee sprite.
class CharacterPalette {
  const CharacterPalette({
    required this.body,
    required this.skin,
    required this.hair,
    required this.pants,
    required this.shoe,
    required this.accent,
    this.beanie = false,
    this.glasses = false,
  });

  /// Hoodie / shirt / sweater.
  final Tones body;
  final Tones skin;
  final Tones hair;
  final Tones pants;
  final Tones shoe;

  /// Accent used for the seat's gauge and the name plate stripe.
  final Color accent;

  /// Claude wears a cat-ear beanie instead of showing hair.
  final bool beanie;

  /// GPT wears glasses.
  final bool glasses;

  static const Tones _skin = Tones(
    Color(0xFFFFE6C8),
    Color(0xFFF6D2A6),
    Color(0xFFD9A677),
    Color(0xFF8F6243),
  );
  static const Tones _pants = Tones(
    Color(0xFF4B5282),
    Color(0xFF3A3F6E),
    Color(0xFF2B2F52),
    Color(0xFF1B1D36),
  );
  static const Tones _shoe = Tones(
    Color(0xFF3F4466),
    Color(0xFF2A2D44),
    Color(0xFF1C1E31),
    Color(0xFF111222),
  );

  static const CharacterPalette claude = CharacterPalette(
    body: Tones(
      Color(0xFFF7AE6A),
      Color(0xFFE8873A),
      Color(0xFFBF6428),
      Color(0xFF7A3E18),
    ),
    skin: _skin,
    hair: Tones(
      Color(0xFFF7AE6A),
      Color(0xFFE8873A),
      Color(0xFFBF6428),
      Color(0xFF7A3E18),
    ),
    pants: _pants,
    shoe: _shoe,
    accent: Color(0xFFE8873A),
    beanie: true,
  );

  static const CharacterPalette gpt = CharacterPalette(
    body: Tones(
      Color(0xFF6BD6AE),
      Color(0xFF3FB58A),
      Color(0xFF2A8466),
      Color(0xFF17513E),
    ),
    skin: _skin,
    hair: Tones(
      Color(0xFF5E4536),
      Color(0xFF3F2E24),
      Color(0xFF2B1F18),
      Color(0xFF17110D),
    ),
    pants: _pants,
    shoe: _shoe,
    accent: Color(0xFF3FB58A),
    glasses: true,
  );

  static const CharacterPalette gemini = CharacterPalette(
    body: Tones(
      Color(0xFFA79BF7),
      Color(0xFF7B6CF0),
      Color(0xFF5A4BC0),
      Color(0xFF362B7A),
    ),
    skin: _skin,
    hair: Tones(
      Color(0xFF4A3B72),
      Color(0xFF2F2452),
      Color(0xFF201839),
      Color(0xFF120D22),
    ),
    pants: _pants,
    shoe: _shoe,
    accent: Color(0xFF7B6CF0),
  );

  static CharacterPalette of(Seat seat) => switch (seat) {
    Seat.claude => claude,
    Seat.gpt => gpt,
    Seat.gemini => gemini,
  };
}
