import 'package:flutter/material.dart';

/// Colour tokens. Warm, paper-and-ink palette that keeps book covers the most
/// colourful thing on screen. All text pairs meet WCAG AA (verified by
/// `test/core/design_system/contrast_test.dart`).
@immutable
class ChapterColors {
  const ChapterColors({
    required this.paper,
    required this.surface,
    required this.surfaceRaised,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.success,
    required this.warning,
    required this.error,
    required this.onError,
    required this.coverPlaceholders,
  });

  /// App background.
  final Color paper;

  /// Cards, sheets, inputs.
  final Color surface;

  /// Dialogs and elevated sheets.
  final Color surfaceRaised;

  /// Primary text.
  final Color ink;

  /// Secondary text, captions.
  final Color inkMuted;

  /// Dividers and outlines.
  final Color line;

  /// Primary actions and progress.
  final Color accent;
  final Color onAccent;

  /// Tinted backgrounds (selected nav item, chips).
  final Color accentSoft;

  final Color success;
  final Color warning;
  final Color error;
  final Color onError;

  /// Muted backgrounds for monogram covers when artwork is missing.
  final List<Color> coverPlaceholders;

  static const light = ChapterColors(
    paper: Color(0xFFFAF7F2),
    surface: Color(0xFFF3EEE6),
    surfaceRaised: Color(0xFFFFFFFF),
    ink: Color(0xFF1D1B18),
    inkMuted: Color(0xFF665F55),
    line: Color(0xFFE2DACD),
    accent: Color(0xFF9A3B2E),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFF1DED8),
    success: Color(0xFF3B6A4D),
    warning: Color(0xFF8A5A0B),
    error: Color(0xFFB3261E),
    onError: Color(0xFFFFFFFF),
    coverPlaceholders: [
      Color(0xFFD9CBB6),
      Color(0xFFC9D3C4),
      Color(0xFFCFC6D6),
      Color(0xFFD8C2BC),
      Color(0xFFC3CFD8),
    ],
  );

  static const dark = ChapterColors(
    paper: Color(0xFF141210),
    surface: Color(0xFF1E1B18),
    surfaceRaised: Color(0xFF282420),
    ink: Color(0xFFEFE8DC),
    inkMuted: Color(0xFFA69E91),
    line: Color(0xFF3A342D),
    accent: Color(0xFFE08A6E),
    onAccent: Color(0xFF1D1B18),
    accentSoft: Color(0xFF3A2620),
    success: Color(0xFF8CC3A0),
    warning: Color(0xFFE2B66A),
    error: Color(0xFFF2B8B5),
    onError: Color(0xFF601410),
    coverPlaceholders: [
      Color(0xFF3B342B),
      Color(0xFF2F3A30),
      Color(0xFF362F3D),
      Color(0xFF3D2E2A),
      Color(0xFF2B3540),
    ],
  );
}
