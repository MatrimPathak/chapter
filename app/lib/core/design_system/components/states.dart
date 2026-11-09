import 'package:flutter/material.dart';

import '../theme/chapter_theme.dart';
import '../tokens/chapter_tokens.dart';
import 'chapter_button.dart';

/// Calm, typographic empty state. No illustrations, by design (brief §18).
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.title,
    required this.body,
    super.key,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.extraActions = const [],
  });

  final String title;
  final String body;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Further choices below the main action.
  final List<Widget> extraActions;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ChapterSpacing.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 32, color: colors.inkMuted),
                const SizedBox(height: ChapterSpacing.lg),
              ],
              Text(title, textAlign: TextAlign.center, style: context.textTheme.headlineMedium),
              const SizedBox(height: ChapterSpacing.sm),
              Text(
                body,
                textAlign: TextAlign.center,
                style: context.textTheme.bodyMedium?.copyWith(color: colors.inkMuted),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: ChapterSpacing.xl),
                ChapterButton(label: actionLabel!, onPressed: onAction),
              ],
              for (final action in extraActions) ...[
                const SizedBox(height: ChapterSpacing.sm),
                action,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Error state with an optional retry.
class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, super.key, this.retryLabel, this.onRetry});

  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ChapterSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 32, color: colors.error),
            const SizedBox(height: ChapterSpacing.md),
            Text(message, textAlign: TextAlign.center, style: context.textTheme.bodyLarge),
            if (retryLabel != null && onRetry != null) ...[
              const SizedBox(height: ChapterSpacing.lg),
              ChapterButton(
                label: retryLabel!,
                onPressed: onRetry,
                variant: ChapterButtonVariant.secondary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Placeholder block shown while content loads. Static (no shimmer) to avoid
/// unnecessary motion.
class LoadingSkeleton extends StatelessWidget {
  const LoadingSkeleton({super.key, this.width, this.height = 16, this.radius = ChapterRadius.sm});

  /// A cover-shaped skeleton.
  const LoadingSkeleton.cover({super.key, required double this.width})
    : height = width / ChapterSizes.coverAspectRatio,
      radius = ChapterRadius.cover;

  final double? width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: context.chapterColors.surfaceMuted,
        borderRadius: BorderRadius.circular(radius),
      ),
    ),
  );
}

/// Full-area loading indicator with an accessible label.
class LoadingState extends StatelessWidget {
  const LoadingState({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) =>
      Center(child: CircularProgressIndicator(semanticsLabel: label));
}
