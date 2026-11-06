import 'package:flutter/material.dart';

/// Type scale. Editorial serif for titles (book-like), a clean sans for UI
/// text. Literata and Inter are bundled under the SIL Open Font License
/// (assets/fonts), with the platform's serif as fallback.
abstract final class ChapterTypography {
  static const String serif = 'Literata';
  static const String sans = 'Inter';
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

    return TextTheme(
      displayLarge: serifStyle(40, FontWeight.w600, 1.1, -0.5),
      displayMedium: serifStyle(32, FontWeight.w600, 1.15, -0.25),
      displaySmall: serifStyle(28, FontWeight.w600, 1.2),
      headlineLarge: serifStyle(26, FontWeight.w600, 1.2),
      headlineMedium: serifStyle(22, FontWeight.w600, 1.25),
      headlineSmall: serifStyle(20, FontWeight.w600, 1.3),
      titleLarge: serifStyle(18, FontWeight.w600, 1.3),
      titleMedium: sansStyle(16, FontWeight.w600, 1.35, ink),
      titleSmall: sansStyle(14, FontWeight.w600, 1.35, ink),
      bodyLarge: sansStyle(16, FontWeight.w400, 1.5, ink),
      bodyMedium: sansStyle(14, FontWeight.w400, 1.45, ink),
      bodySmall: sansStyle(12, FontWeight.w400, 1.4, muted),
      labelLarge: sansStyle(15, FontWeight.w600, 1.2, ink, 0.1),
      labelMedium: sansStyle(13, FontWeight.w500, 1.2, muted, 0.2),
      labelSmall: sansStyle(11, FontWeight.w500, 1.2, muted, 0.4),
    );
  }
}
