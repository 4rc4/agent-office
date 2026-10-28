import 'dart:ui';

import 'package:office_core/office_core.dart';

import '../state/seat_state.dart';

/// Flat colours of the office. Every part is one solid colour and the navy
/// [outline] is the only thing that separates parts (Catudy art rule: no
/// gradients, no shadows, at most three colours per part).
abstract final class ScenePalette {
  static const Color outline = Color(0xFF2C2F7A);
  static const Color ink = outline;

  /// Letterbox colour around the scene.
  static const Color background = Color(0xFF0F1124);

  static const Color wall = Color(0xFF56609C);
  static const Color floorA = Color(0xFF6B4634);
  static const Color floorB = Color(0xFF75503B);
  static const Color woodDark = Color(0xFF8A5A3C);
  static const Color woodLight = Color(0xFFC9A77A);

  static const Color cream = Color(0xFFF4F1E8);
  static const Color paper = Color(0xFFE9EEF7);
  static const Color paperLine = Color(0xFF8C9BD1);
  static const Color steel = Color(0xFF7F8CB5);
  static const Color slate = Color(0xFF3D4470);
  static const Color greyed = Color(0xFF5A5E80);
  static const Color grey = Color(0xFFB8BCD0);

  static const Color screenOff = Color(0xFF1A1D3D);
  static const Color terminalBg = Color(0xFF102A20);
  static const Color terminalText = Color(0xFF53E08C);
  static const Color globeBg = Color(0xFF1C3C6E);
  static const Color globeSea = Color(0xFF66CFEA);
  static const Color alertBright = Color(0xFFD9484A);
  static const Color alertDim = Color(0xFF7A2A33);

  static const Color leaf = Color(0xFF5FBF7A);
  static const Color terracotta = Color(0xFFB5674A);
  static const Color yellow = Color(0xFFF2C14E);
  static const Color red = Color(0xFFE05A5A);
  static const Color green = Color(0xFF6FCF97);
  static const Color orange = Color(0xFFF0A24A);
  static const Color water = Color(0xFF66CFEA);

  /// Sticky note colour for a task status.
  static Color sticky(TaskStatus status) => switch (status) {
    TaskStatus.queued || TaskStatus.planned || TaskStatus.assigned => grey,
    TaskStatus.running || TaskStatus.review => yellow,
    TaskStatus.waitingApproval ||
    TaskStatus.waitingUser ||
    TaskStatus.waitingBudget ||
    TaskStatus.interrupted ||
    TaskStatus.needsHuman => orange,
    TaskStatus.done => green,
    TaskStatus.failed => red,
  };

  /// Speech bubble fill for a bubble kind.
  static Color bubbleFill(BubbleKind kind) => switch (kind) {
    BubbleKind.info => cream,
    BubbleKind.question => yellow,
    BubbleKind.warning => orange,
    BubbleKind.error => red,
    BubbleKind.success => green,
  };

  /// Speech bubble text colour; ink on light fills, cream on the red one.
  static Color bubbleText(BubbleKind kind) =>
      kind == BubbleKind.error ? cream : ink;
}

/// The three colours of one employee sprite plus trousers.
class CharacterPalette {
  const CharacterPalette({
    required this.body,
    required this.skin,
    required this.hair,
    required this.pants,
  });

  /// Hoodie colour; also the accent used for the seat's gauge and bubbles.
  final Color body;
  final Color skin;
  final Color hair;
  final Color pants;

  static const CharacterPalette claude = CharacterPalette(
    body: Color(0xFFE8873A),
    skin: Color(0xFFF6D9B0),
    hair: Color(0xFFE8873A),
    pants: Color(0xFF3A3F6E),
  );

  static const CharacterPalette gpt = CharacterPalette(
    body: Color(0xFF3FB58A),
    skin: Color(0xFFF6D9B0),
    hair: Color(0xFF3B2A4A),
    pants: Color(0xFF3A3F6E),
  );

  static const CharacterPalette gemini = CharacterPalette(
    body: Color(0xFF7B6CF0),
    skin: Color(0xFFF6D9B0),
    hair: Color(0xFF2B2048),
    pants: Color(0xFF3A3F6E),
  );

  static CharacterPalette of(Seat seat) => switch (seat) {
    Seat.claude => claude,
    Seat.gpt => gpt,
    Seat.gemini => gemini,
  };
}
