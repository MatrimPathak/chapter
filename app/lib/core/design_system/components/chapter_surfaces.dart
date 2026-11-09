import 'package:flutter/material.dart';

import '../theme/chapter_theme.dart';
import '../tokens/chapter_tokens.dart';
import '../tokens/chapter_typography.dart';

/// The app's icon from the Stitch project, for the splash and sign-in screens.
class ChapterLogo extends StatelessWidget {
  const ChapterLogo({super.key, this.size = 96});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: Image.asset('assets/images/chapter_logo.png', width: size, height: size),
    ),
  );
}

/// The raised card used across the app: paper-white on the page, with a hairline
/// and a warm shadow in light mode, and tone alone in dark mode.
class ChapterCard extends StatelessWidget {
  const ChapterCard({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(ChapterSpacing.lg),
    this.onTap,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(ChapterRadius.lg);
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: isDark ? null : ChapterShadows.card,
      ),
      child: Material(
        color: color ?? (isDark ? colors.surface : colors.surfaceRaised),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: colors.line.withValues(alpha: 0.5)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// A section title in the serif, with an optional action on the right.
class ChapterSectionHeader extends StatelessWidget {
  const ChapterSectionHeader({
    required this.title,
    super.key,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title, style: context.textTheme.headlineMedium)),
              if (subtitle != null)
                Text(
                  subtitle!,
                  style: context.textTheme.bodySmall?.copyWith(color: colors.inkMuted),
                ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(foregroundColor: colors.highlight),
            child: Text(actionLabel!),
          ),
      ],
    );
  }
}

/// One number with its label, as in the Insights and session summary cards.
class ChapterStatTile extends StatelessWidget {
  const ChapterStatTile({
    required this.label,
    required this.value,
    super.key,
    this.unit,
    this.caption,
    this.icon,
  });

  final String label;
  final String value;
  final String? unit;
  final String? caption;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final text = context.textTheme;
    return ChapterCard(
      child: MergeSemantics(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(label.toUpperCase(), style: text.labelSmall)),
                if (icon != null) Icon(icon, size: 18, color: colors.inkMuted),
              ],
            ),
            const SizedBox(height: ChapterSpacing.sm),
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(text: value, style: text.displaySmall),
                  if (unit != null)
                    TextSpan(
                      text: ' $unit',
                      style: text.bodySmall?.copyWith(color: colors.inkMuted),
                    ),
                ],
              ),
            ),
            if (caption != null) ...[
              const SizedBox(height: ChapterSpacing.xs),
              Text(caption!, style: text.bodySmall?.copyWith(color: colors.inkMuted)),
            ],
          ],
        ),
      ),
    );
  }
}

/// A quote or personal note in the italic serif, with its source below.
class ChapterQuote extends StatelessWidget {
  const ChapterQuote({required this.text, super.key, this.source});

  final String text;
  final String? source;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text, style: ChapterTypography.quote(colors.ink)),
        if (source != null) ...[
          const SizedBox(height: ChapterSpacing.sm),
          Text(source!, style: context.textTheme.labelMedium),
        ],
      ],
    );
  }
}

enum ChapterPillTone { neutral, accent, highlight }

/// Small rounded label: shelf, edition, streak, status.
class ChapterPill extends StatelessWidget {
  const ChapterPill({
    required this.label,
    super.key,
    this.icon,
    this.tone = ChapterPillTone.neutral,
  });

  final String label;
  final IconData? icon;
  final ChapterPillTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final (Color fill, Color ink) = switch (tone) {
      ChapterPillTone.neutral => (colors.surfaceMuted, colors.inkMuted),
      ChapterPillTone.accent => (colors.accentSoft, colors.ink),
      ChapterPillTone.highlight => (colors.highlightSoft, colors.onHighlightSoft),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ChapterSpacing.sm + ChapterSpacing.xxs,
        vertical: ChapterSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(ChapterRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: ink),
            const SizedBox(width: ChapterSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.labelMedium?.copyWith(color: ink),
            ),
          ),
        ],
      ),
    );
  }
}
