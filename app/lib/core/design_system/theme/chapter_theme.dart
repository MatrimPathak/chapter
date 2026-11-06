import 'package:flutter/material.dart';

import '../tokens/chapter_colors.dart';
import '../tokens/chapter_tokens.dart';
import '../tokens/chapter_typography.dart';

/// Gives widgets access to Chapter's tokens: `context.chapterColors`.
@immutable
class ChapterThemeExtension extends ThemeExtension<ChapterThemeExtension> {
  const ChapterThemeExtension(this.colors);

  final ChapterColors colors;

  @override
  ChapterThemeExtension copyWith({ChapterColors? colors}) =>
      ChapterThemeExtension(colors ?? this.colors);

  @override
  ChapterThemeExtension lerp(ChapterThemeExtension? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

extension ChapterThemeContext on BuildContext {
  ChapterColors get chapterColors => Theme.of(this).extension<ChapterThemeExtension>()!.colors;
  TextTheme get textTheme => Theme.of(this).textTheme;
}

/// Builds Material 3 themes from Chapter tokens.
abstract final class ChapterTheme {
  static ThemeData light() => _build(ChapterColors.light, Brightness.light);
  static ThemeData dark() => _build(ChapterColors.dark, Brightness.dark);

  static ThemeData _build(ChapterColors c, Brightness brightness) {
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.accent,
      onPrimary: c.onAccent,
      primaryContainer: c.accentSoft,
      onPrimaryContainer: c.ink,
      secondary: c.inkMuted,
      onSecondary: c.paper,
      error: c.error,
      onError: c.onError,
      surface: c.paper,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.paper,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceRaised,
      surfaceContainerHighest: c.surfaceRaised,
      outline: c.line,
      outlineVariant: c.line,
    );
    final text = ChapterTypography.textTheme(c.ink, c.inkMuted);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChapterRadius.md));

    return ThemeData(
      useMaterial3: true,
      fontFamily: ChapterTypography.sans,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: c.paper,
      textTheme: text,
      extensions: [ChapterThemeExtension(c)],
      splashFactory: InkSparkle.splashFactory,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: c.paper,
        foregroundColor: c.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.headlineSmall,
      ),
      dividerTheme: DividerThemeData(color: c.line, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: c.accent,
          foregroundColor: c.onAccent,
          minimumSize: const Size(64, ChapterSizes.minTouchTarget),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: c.ink,
          side: BorderSide(color: c.line),
          minimumSize: const Size(64, ChapterSizes.minTouchTarget),
          shape: shape,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: c.accent,
          minimumSize: const Size(48, ChapterSizes.minTouchTarget),
          textStyle: text.labelLarge,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: c.surface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ChapterSpacing.lg,
          vertical: ChapterSpacing.md,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: c.inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChapterRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChapterRadius.md),
          borderSide: BorderSide(color: c.accent, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChapterRadius.md),
          borderSide: BorderSide(color: c.error),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.paper,
        indicatorColor: c.accentSoft,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected) ? c.ink : c.inkMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) =>
              IconThemeData(color: states.contains(WidgetState.selected) ? c.accent : c.inkMuted),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ChapterRadius.lg)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChapterRadius.lg)),
        titleTextStyle: text.headlineSmall,
        contentTextStyle: text.bodyMedium,
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.accent : c.line,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.inkMuted,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.line,
        circularTrackColor: c.line,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.ink,
        contentTextStyle: text.bodyMedium?.copyWith(color: c.paper),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(ChapterRadius.sm)),
      ),
    );
  }
}
