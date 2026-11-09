import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
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
      secondary: c.highlight,
      onSecondary: c.onHighlight,
      secondaryContainer: c.highlightSoft,
      onSecondaryContainer: c.onHighlightSoft,
      error: c.error,
      onError: c.onError,
      surface: c.paper,
      onSurface: c.ink,
      onSurfaceVariant: c.inkMuted,
      surfaceContainerLowest: c.surfaceRaised,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surfaceMuted,
      surfaceContainerHighest: c.surfaceMuted,
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
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
      tabBarTheme: TabBarThemeData(
        dividerColor: Colors.transparent,
        indicatorSize: TabBarIndicatorSize.tab,
        indicator: BoxDecoration(
          color: c.accent,
          borderRadius: BorderRadius.circular(ChapterRadius.pill),
        ),
        labelColor: c.onAccent,
        unselectedLabelColor: c.inkMuted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        splashBorderRadius: BorderRadius.circular(ChapterRadius.pill),
        labelPadding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.lg),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
        elevation: 2,
        shape: const StadiumBorder(),
      ),
      cardTheme: CardThemeData(
        color: brightness == Brightness.dark ? c.surface : c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ChapterRadius.lg),
          side: BorderSide(color: c.line.withValues(alpha: 0.5)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surfaceRaised,
        selectedColor: c.accent,
        secondarySelectedColor: c.accent,
        disabledColor: c.surfaceMuted,
        checkmarkColor: c.onAccent,
        side: WidgetStateBorderSide.resolveWith(
          (s) => s.contains(WidgetState.selected) ? BorderSide.none : BorderSide(color: c.line),
        ),
        labelStyle: text.labelLarge?.copyWith(
          color: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.onAccent : c.ink,
          ),
        ),
        shape: const StadiumBorder(),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceRaised,
          ),
          foregroundColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.onAccent : c.ink,
          ),
          iconColor: WidgetStateColor.resolveWith(
            (s) => s.contains(WidgetState.selected) ? c.onAccent : c.ink,
          ),
          side: WidgetStatePropertyAll(BorderSide(color: c.line)),
          textStyle: WidgetStatePropertyAll(text.labelLarge),
        ),
      ),
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
          backgroundColor: c.surfaceMuted,
          side: BorderSide.none,
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
        fillColor: c.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: ChapterSpacing.lg,
          vertical: ChapterSpacing.md,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: c.inkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChapterRadius.md),
          borderSide: BorderSide(color: c.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(ChapterRadius.md),
          borderSide: BorderSide(color: c.line),
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
        indicatorColor: c.highlight,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 68,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelMedium?.copyWith(
            color: states.contains(WidgetState.selected) ? c.highlight : c.inkMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? c.onHighlight : c.inkMuted,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(ChapterRadius.xl)),
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
          (s) => s.contains(WidgetState.selected) ? c.accent : c.surfaceMuted,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.onAccent : c.inkMuted,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearTrackColor: c.surfaceMuted,
        circularTrackColor: c.surfaceMuted,
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
