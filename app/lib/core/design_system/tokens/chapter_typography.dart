import 'package:flutter/material.dart';

/// Type scale from the Stitch design system: Newsreader for titles and quotes,
/// Plus Jakarta Sans for everything else. Both are bundled under the SIL Open Font
/// License (assets/fonts), so type doesn't depend on a connection.
abstract final class ChapterTypography {
  static const String serif = 'Newsreader';
  static const String sans = 'PlusJakartaSans';
  static const List<String> serifFallback = ['Georgia', 'Noto Serif', 'Times New Roman'];

  static TextTheme textTheme(Color ink, Color muted) {
    TextStyle serifStyle(double size, FontWeight weight, double height, [double spacing = 0]) =>
        TextStyle(
          fontFamily: serif,
          fontFamilyFallback: serifFallback,
          fontSize: size,
          fontWeight: weight,
          height: height,
          letterSpacing: spacing,
          color: ink,
        );
    TextStyle sansStyle(
      double size,
      FontWeight weight,
      double height,
      Color color, [
      double spacing = 0,
    ]) => TextStyle(
      fontFamily: sans,
      fontSize: size,
      fontWeight: weight,
      height: height,
      letterSpacing: spacing,
      color: color,
    );

    // Heights are Stitch's line heights divided by the size; spacing is its em value
    // times the size.
    return TextTheme(
      displayLarge: serifStyle(44, FontWeight.w400, 52 / 44, -0.88),
      displayMedium: serifStyle(34, FontWeight.w400, 42 / 34, -0.51),
      displaySmall: serifStyle(32, FontWeight.w500, 40 / 32, -0.32),
      headlineLarge: serifStyle(26, FontWeight.w500, 34 / 26, -0.26),
      headlineMedium: serifStyle(22, FontWeight.w600, 30 / 22),
      headlineSmall: serifStyle(18, FontWeight.w600, 26 / 18),
      titleLarge: serifStyle(18, FontWeight.w600, 26 / 18),
      titleMedium: sansStyle(16, FontWeight.w600, 24 / 16, ink),
      titleSmall: sansStyle(14, FontWeight.w600, 20 / 14, ink, 0.14),
      bodyLarge: sansStyle(16, FontWeight.w400, 26 / 16, ink),
      bodyMedium: sansStyle(14, FontWeight.w400, 22 / 14, ink),
      bodySmall: sansStyle(12, FontWeight.w400, 18 / 12, muted),
      labelLarge: sansStyle(14, FontWeight.w600, 20 / 14, ink, 0.14),
      labelMedium: sansStyle(12, FontWeight.w600, 16 / 12, muted, 0.24),
      labelSmall: sansStyle(10, FontWeight.w700, 14 / 10, muted, 0.5),
    );
  }

  /// Quotes and personal reflections: Stitch's "quote" style, in italics.
  static TextStyle quote(Color color) => TextStyle(
    fontFamily: serif,
    fontFamilyFallback: serifFallback,
    fontSize: 20,
    fontWeight: FontWeight.w400,
    fontStyle: FontStyle.italic,
    height: 32 / 20,
    letterSpacing: 0.2,
    color: color,
  );
}
