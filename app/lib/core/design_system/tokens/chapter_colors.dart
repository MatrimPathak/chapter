import 'package:flutter/material.dart';

/// Colour tokens from the Stitch project "Chapter Reading Companion UX/UI": ink on
/// warm paper, forest-green actions and terracotta highlights, so book covers stay
/// the most colourful thing on screen. Dark mode uses the same hues (see the
/// project's "Add to Library Sheet (Dark)"). All text pairs meet WCAG AA (verified by
/// `test/core/design_system/contrast_test.dart`).
@immutable
class ChapterColors {
  const ChapterColors({
    required this.paper,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceMuted,
    required this.ink,
    required this.inkMuted,
    required this.line,
    required this.accent,
    required this.onAccent,
    required this.accentSoft,
    required this.highlight,
    required this.onHighlight,
    required this.highlightSoft,
    required this.onHighlightSoft,
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

  /// Quiet fills: secondary buttons, tab containers, chips.
  final Color surfaceMuted;

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

  /// Terracotta: streaks, the timer ring, the selected tab, attention badges.
  final Color highlight;
  final Color onHighlight;
  final Color highlightSoft;
  final Color onHighlightSoft;

  final Color success;
  final Color warning;
  final Color error;
  final Color onError;

  /// Muted backgrounds for monogram covers when artwork is missing.
  final List<Color> coverPlaceholders;

  static const light = ChapterColors(
    paper: Color(0xFFFCF9F8),
    surface: Color(0xFFF6F3F2),
    surfaceRaised: Color(0xFFFFFFFF),
    surfaceMuted: Color(0xFFEAE7E7),
    ink: Color(0xFF1B1C1C),
    inkMuted: Color(0xFF424843),
    line: Color(0xFFC2C8C2),
    accent: Color(0xFF294335),
    onAccent: Color(0xFFFFFFFF),
    accentSoft: Color(0xFFCBEAD5),
    highlight: Color(0xFF8D4D35),
    onHighlight: Color(0xFFFFFFFF),
    highlightSoft: Color(0xFFFFDBCF),
    onHighlightSoft: Color(0xFF703720),
    success: Color(0xFF324C3D),
    warning: Color(0xFF8A5A0B),
    error: Color(0xFFBA1A1A),
    onError: Color(0xFFFFFFFF),
    coverPlaceholders: [
      Color(0xFFD9E7D0),
      Color(0xFFCBEAD5),
      Color(0xFFFFDBCF),
      Color(0xFFE4E2E1),
      Color(0xFFBDCBB5),
    ],
  );

  static const dark = ChapterColors(
    paper: Color(0xFF131513),
    surface: Color(0xFF1B1E1B),
    surfaceRaised: Color(0xFF2A2D2A),
    surfaceMuted: Color(0xFF353835),
    ink: Color(0xFFE7E4DF),
    inkMuted: Color(0xFFC2C8C2),
    line: Color(0xFF424843),
    accent: Color(0xFFB0CEBA),
    onAccent: Color(0xFF052013),
    accentSoft: Color(0xFF324C3D),
    highlight: Color(0xFFFFB59B),
    onHighlight: Color(0xFF380D00),
    highlightSoft: Color(0xFF703720),
    onHighlightSoft: Color(0xFFFFDBCF),
    success: Color(0xFFB0CEBA),
    warning: Color(0xFFE2B66A),
    error: Color(0xFFFFB4AB),
    onError: Color(0xFF690005),
    coverPlaceholders: [
      Color(0xFF3E4A39),
      Color(0xFF324C3D),
      Color(0xFF703720),
      Color(0xFF353835),
      Color(0xFF4D5948),
    ],
  );
}
