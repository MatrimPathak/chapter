import 'package:flutter/material.dart';

import '../theme/chapter_theme.dart';
import '../tokens/chapter_tokens.dart';
import 'badges.dart';
import 'book_cover.dart';
import 'chapter_button.dart';
import 'chapter_progress.dart';
import 'chapter_surfaces.dart';

/// Presentation data for book cards. Feature code maps its models to this so
/// the design system stays independent of domain types.
@immutable
class BookCardData {
  const BookCardData({
    required this.title,
    this.author,
    this.coverUrl,
    this.progress,
    this.progressLabel,
    this.caption,
    this.isApproximate = false,
  });

  final String title;
  final String? author;
  final String? coverUrl;

  /// 0–1; `null` hides the progress bar.
  final double? progress;

  /// e.g. "p. 187 of 400 · 47%".
  final String? progressLabel;

  /// Secondary line, e.g. "Last read 2 days ago".
  final String? caption;
  final bool isApproximate;
}

/// Cover-first card for grids.
class BookGridCard extends StatelessWidget {
  const BookGridCard({required this.data, super.key, this.onTap, this.coverWidth = 104});

  final BookCardData data;
  final VoidCallback? onTap;
  final double coverWidth;

  @override
  Widget build(BuildContext context) {
    final progress = data.progress;
    return _Tappable(
      onTap: onTap,
      label: _semanticLabel(data),
      child: SizedBox(
        width: coverWidth,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            BookCover(
              title: data.title,
              author: data.author,
              imageUrl: data.coverUrl,
              width: coverWidth,
            ),
            if (progress != null) ...[
              const SizedBox(height: ChapterSpacing.sm),
              ChapterProgressBar(fraction: progress, height: 3),
            ],
            const SizedBox(height: ChapterSpacing.sm),
            Text(
              data.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: context.textTheme.titleSmall,
            ),
            if (data.author != null)
              Text(
                data.author!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

/// Dense row for lists.
class BookListTile extends StatelessWidget {
  const BookListTile({
    required this.data,
    super.key,
    this.onTap,
    this.trailing,
    this.padding = const EdgeInsets.symmetric(
      horizontal: ChapterSpacing.gutter,
      vertical: ChapterSpacing.md,
    ),
  });

  final BookCardData data;
  final VoidCallback? onTap;
  final Widget? trailing;

  /// Inside a [ChapterCard], use the card's own padding.
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final progress = data.progress;
    return _Tappable(
      onTap: onTap,
      label: _semanticLabel(data),
      child: Padding(
        padding: padding,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(title: data.title, author: data.author, imageUrl: data.coverUrl, width: 52),
            const SizedBox(width: ChapterSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    data.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.textTheme.titleLarge,
                  ),
                  if (data.author != null) Text(data.author!, style: context.textTheme.bodySmall),
                  if (progress != null) ...[
                    const SizedBox(height: ChapterSpacing.sm),
                    ChapterProgressBar(fraction: progress, height: 3),
                  ],
                  if (data.progressLabel != null || data.caption != null) ...[
                    const SizedBox(height: ChapterSpacing.xs),
                    _MetaLine(data: data),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: ChapterSpacing.sm), trailing!],
          ],
        ),
      ),
    );
  }
}

/// Wide "Continue Reading" card: large cover, progress and a resume action.
class ContinueReadingCard extends StatelessWidget {
  const ContinueReadingCard({
    required this.data,
    required this.resumeLabel,
    super.key,
    this.onTap,
    this.onResume,
    this.secondaryLabel,
    this.onSecondary,
  });

  final BookCardData data;
  final String resumeLabel;
  final VoidCallback? onTap;
  final VoidCallback? onResume;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    return ChapterCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              BookCover(title: data.title, author: data.author, imageUrl: data.coverUrl, width: 96),
              const SizedBox(width: ChapterSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.headlineMedium,
                    ),
                    if (data.author != null) Text(data.author!, style: context.textTheme.bodySmall),
                    const SizedBox(height: ChapterSpacing.lg),
                    ChapterProgressBar(fraction: data.progress ?? 0),
                    const SizedBox(height: ChapterSpacing.xs),
                    _MetaLine(data: data),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: ChapterSpacing.lg),
          Wrap(
            spacing: ChapterSpacing.sm,
            runSpacing: ChapterSpacing.sm,
            children: [
              ChapterButton(
                label: resumeLabel,
                onPressed: onResume,
                icon: const Icon(Icons.play_arrow_rounded),
              ),
              if (secondaryLabel != null)
                ChapterButton(
                  label: secondaryLabel!,
                  onPressed: onSecondary,
                  variant: ChapterButtonVariant.secondary,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.data});

  final BookCardData data;

  @override
  Widget build(BuildContext context) {
    final parts = [?data.progressLabel, ?data.caption];
    return Wrap(
      spacing: ChapterSpacing.sm,
      runSpacing: ChapterSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(parts.join(' · '), style: context.textTheme.bodySmall),
        if (data.isApproximate) const ApproximateBadge(),
      ],
    );
  }
}

class _Tappable extends StatelessWidget {
  const _Tappable({required this.child, required this.label, this.onTap});

  final Widget child;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: onTap != null,
    label: label,
    excludeSemantics: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(ChapterRadius.sm),
      child: child,
    ),
  );
}

String _semanticLabel(BookCardData d) => [
  d.title,
  if (d.author != null) 'by ${d.author}',
  if (d.progressLabel != null) d.progressLabel!,
  if (d.isApproximate) 'approximate',
].join(', ');
