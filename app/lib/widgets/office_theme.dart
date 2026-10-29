import 'package:flutter/material.dart';
import 'package:office_core/office_core.dart';

import '../state/seat_state.dart';

/// Flat colours of the chrome around the scene (letterbox, status bar).
/// Solid fills only, the navy [OfficeColors.outline] is the one border
/// colour, no translucent tints.
abstract final class OfficeColors {
  /// Bar colour for a usage fraction: calm below 70 %, warm below 90 %,
  /// red at the limit.
  static Color usage(double pct) => pct < 0.7
      ? const Color(0xFF4CAF50)
      : pct < 0.9
      ? const Color(0xFFF2B33D)
      : const Color(0xFFE04B4B);

  static const Color outline = Color(0xFF2C2F7A);
  static const Color background = Color(0xFF0F1124);
  static const Color surface = Color(0xFF1A1D3D);
  static const Color surfaceRaised = Color(0xFF23264D);
  static const Color surfaceSunken = Color(0xFF141733);
  static const Color text = Color(0xFFF4F1E8);
  static const Color textMuted = Color(0xFFB8BCD0);
  static const Color textFaint = Color(0xFF7F8CB5);
  static const Color ink = outline;

  static const Color accent = Color(0xFFF2C14E);
  static const Color green = Color(0xFF6FCF97);
  static const Color orange = Color(0xFFF0A24A);
  static const Color red = Color(0xFFE05A5A);
  static const Color water = Color(0xFF66CFEA);
  static const Color grey = Color(0xFFB8BCD0);

  /// Tag colour of a desk, used on chips and log rows.
  static Color seat(Seat seat) => switch (seat) {
    Seat.claude => orange,
    Seat.gpt => green,
    Seat.gemini => water,
  };

  /// Sticky note colour of a task status (mirrors the scene's notes).
  static Color status(TaskStatus status) => switch (status) {
    TaskStatus.queued || TaskStatus.planned || TaskStatus.assigned => grey,
    TaskStatus.running || TaskStatus.review => accent,
    TaskStatus.waitingApproval ||
    TaskStatus.waitingUser ||
    TaskStatus.waitingBudget ||
    TaskStatus.interrupted ||
    TaskStatus.needsHuman => orange,
    TaskStatus.done => green,
    TaskStatus.failed => red,
  };

  /// Text colour that reads on a [status] sticky: ink on the light notes,
  /// cream on the red one.
  static Color onStatus(TaskStatus status) =>
      status == TaskStatus.failed ? text : ink;

  /// Dot colour next to a desk's state label.
  static Color visual(SeatVisual visual) => switch (visual) {
    SeatVisual.empty || SeatVisual.sleeping => grey,
    SeatVisual.idle => PixelColors.inkFaint,
    SeatVisual.waitingUser || SeatVisual.onBreak => orange,
    SeatVisual.celebrating => green,
    SeatVisual.failed => red,
    _ => accent,
  };
}

/// Paper, ink and metal tones of the pixel popups ([PixelFrame] and
/// friends). Every popup is a solid parchment sheet with navy ink; the
/// subtle checker uses two parchment tones, nothing is translucent.
abstract final class PixelColors {
  /// Parchment face of a frame.
  static const Color paper = Color(0xFFF3E9CF);

  /// Second checker tone, a touch darker than [paper].
  static const Color paperChecker = Color(0xFFEDE2C5);

  /// Highlight bevel (top and left) and the fill of sunken fields.
  static const Color paperLight = Color(0xFFFBF5E6);

  /// Shade bevel (bottom and right), ruled lines, pressed buttons.
  static const Color paperEdge = Color(0xFFD6C59B);

  /// Whiter paper of the mailbox letter.
  static const Color letter = Color(0xFFFBF7EA);

  /// Second checker tone of [letter].
  static const Color letterChecker = Color(0xFFF4EFE0);

  static const Color ink = OfficeColors.outline;
  static const Color inkMuted = Color(0xFF5B5F93);
  static const Color inkFaint = Color(0xFF8B8FBB);

  /// Solid 2 px drop shadow under frames and buttons.
  static const Color shadow = Color(0xFF14163A);

  /// Title tab and primary buttons.
  static const Color tab = OfficeColors.accent;

  /// Whiteboard face, frame band and marker tray.
  static const Color board = Color(0xFFF9F9F4);
  static const Color boardFrame = Color(0xFFC3C9E0);
  static const Color boardTray = Color(0xFF7F8CB5);

  /// Clipboard wood and its metal clip.
  static const Color clipboard = Color(0xFFC9A77A);
  static const Color clip = Color(0xFF8E9AC2);
  static const Color clipDark = Color(0xFF3D4470);

  /// Stamp on the letter and the spiral holes of the notepad.
  static const Color stamp = Color(0xFF66CFEA);
  static const Color hole = Color(0xFF3D4470);

  /// Disabled button face.
  static const Color disabled = Color(0xFFE2DAC3);
}

/// Font families of the window. Material text uses the theme's family;
/// identifiers and clocks ask for `monospace` with a stack that resolves on
/// Windows (Consolas, Cascadia Mono), macOS (Menlo) and Linux (DejaVu).
abstract final class OfficeFonts {
  /// The pixel face (VT323, assets/fonts) for titles, tabs and buttons.
  static const String pixel = 'PixelFont';

  static const List<String> monoFallback = [
    'Consolas',
    'Cascadia Mono',
    'Menlo',
    'DejaVu Sans Mono',
    'Courier New',
  ];
}

/// Text styles used on paper. Titles and labels are pixel, body is Roboto.
abstract final class PixelText {
  /// Frame tab titles.
  static const TextStyle title = TextStyle(
    fontFamily: OfficeFonts.pixel,
    fontSize: 20,
    height: 1,
    color: PixelColors.ink,
  );

  /// Section headings and button labels.
  static const TextStyle label = TextStyle(
    fontFamily: OfficeFonts.pixel,
    fontSize: 18,
    height: 1,
    color: PixelColors.ink,
  );

  /// Body text on paper.
  static const TextStyle body = TextStyle(
    fontSize: 13,
    height: 1.35,
    color: PixelColors.ink,
  );

  static const TextStyle bodyStrong = TextStyle(
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w700,
    color: PixelColors.ink,
  );

  static const TextStyle muted = TextStyle(
    fontSize: 12,
    height: 1.3,
    color: PixelColors.inkMuted,
  );

  static const TextStyle faint = TextStyle(
    fontSize: 11,
    height: 1.3,
    color: PixelColors.inkFaint,
  );

  /// Clocks and session references.
  static const TextStyle mono = TextStyle(
    fontFamily: 'monospace',
    fontFamilyFallback: OfficeFonts.monoFallback,
    fontSize: 11,
    height: 1.3,
    color: PixelColors.inkMuted,
  );
}

/// The dark, cosy theme of the window. The chrome (letterbox and status
/// bar) is navy; everything the user opens is a pixel paper frame, so the
/// Material defaults here only matter for text fields and the odd snackbar.
ThemeData officeTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.dark,
    primary: OfficeColors.accent,
    onPrimary: OfficeColors.ink,
    secondary: OfficeColors.water,
    onSecondary: OfficeColors.ink,
    error: OfficeColors.red,
    onError: OfficeColors.text,
    surface: OfficeColors.surface,
    onSurface: OfficeColors.text,
    surfaceContainerHighest: OfficeColors.surfaceRaised,
    onSurfaceVariant: OfficeColors.textMuted,
    outline: OfficeColors.outline,
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: OfficeColors.background,
    canvasColor: OfficeColors.surfaceRaised,
    dividerColor: OfficeColors.outline,
    splashFactory: NoSplash.splashFactory,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: OfficeColors.text,
      displayColor: OfficeColors.text,
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: PixelColors.ink,
      selectionColor: PixelColors.paperEdge,
      selectionHandleColor: PixelColors.ink,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: PixelColors.paper,
      contentTextStyle: TextStyle(color: PixelColors.ink, fontSize: 13),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: OfficeColors.outline, width: 2),
      ),
    ),
    tooltipTheme: const TooltipThemeData(
      decoration: BoxDecoration(
        color: PixelColors.paper,
        border: Border.fromBorderSide(
          BorderSide(color: OfficeColors.outline, width: 2),
        ),
      ),
      textStyle: TextStyle(color: PixelColors.ink, fontSize: 12),
    ),
  );
}
