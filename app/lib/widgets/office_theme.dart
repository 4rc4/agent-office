import 'package:flutter/material.dart';
import 'package:office_core/office_core.dart';

import '../state/seat_state.dart';

/// Flat colours of the chrome around the scene. Solid fills only, the navy
/// [OfficeColors.outline] is the one border colour, no translucent tints.
abstract final class OfficeColors {
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
  static const Color grey = Color(0xFF7F8CB5);

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

  /// Dot colour next to a desk's state label.
  static Color visual(SeatVisual visual) => switch (visual) {
    SeatVisual.empty || SeatVisual.sleeping => grey,
    SeatVisual.idle => textMuted,
    SeatVisual.waitingUser || SeatVisual.onBreak => orange,
    SeatVisual.celebrating => green,
    SeatVisual.failed => red,
    _ => accent,
  };
}

/// Font families of the window. Material text uses the theme's family;
/// identifiers and clocks ask for `monospace` with a stack that resolves on
/// Windows (Consolas, Cascadia Mono), macOS (Menlo) and Linux (DejaVu).
abstract final class OfficeFonts {
  static const List<String> monoFallback = [
    'Consolas',
    'Cascadia Mono',
    'Menlo',
    'DejaVu Sans Mono',
    'Courier New',
  ];
}

/// The dark, cosy theme of the window. Primary buttons are opaque accent
/// fills with ink text; cards are solid raised surfaces with a navy border.
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
  const border = OutlineInputBorder(
    borderRadius: BorderRadius.all(Radius.circular(10)),
    borderSide: BorderSide(color: OfficeColors.outline, width: 1.5),
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: OfficeColors.text,
      displayColor: OfficeColors.text,
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: OfficeColors.surfaceSunken,
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: OfficeColors.accent, width: 1.5),
      ),
      hintStyle: TextStyle(color: OfficeColors.textFaint),
      labelStyle: TextStyle(color: OfficeColors.textMuted),
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: OfficeColors.accent,
        foregroundColor: OfficeColors.ink,
        disabledBackgroundColor: OfficeColors.surfaceRaised,
        disabledForegroundColor: OfficeColors.textFaint,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: OfficeColors.text,
        side: const BorderSide(color: OfficeColors.outline, width: 1.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
        ),
      ),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: OfficeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        side: BorderSide(color: OfficeColors.outline, width: 2),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: OfficeColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
        side: BorderSide(color: OfficeColors.outline, width: 2),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: OfficeColors.surfaceRaised,
      contentTextStyle: TextStyle(color: OfficeColors.text),
      behavior: SnackBarBehavior.floating,
    ),
    chipTheme: const ChipThemeData(
      side: BorderSide(color: OfficeColors.outline, width: 1.5),
      backgroundColor: OfficeColors.surfaceRaised,
      labelStyle: TextStyle(color: OfficeColors.text, fontSize: 12),
      padding: EdgeInsets.symmetric(horizontal: 6),
    ),
  );
}
