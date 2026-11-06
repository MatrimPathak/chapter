import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/chapter_theme.dart';
import '../tokens/chapter_tokens.dart';

/// A book cover at a fixed 2:3 aspect ratio. Falls back to a typographic
/// monogram cover (title + author on a muted colour) when there is no
/// artwork or it fails to load. Covers are cached on disk for offline use.
class BookCover extends StatelessWidget {
  const BookCover({
    required this.title,
    required this.width,
    super.key,
    this.imageUrl,
    this.author,
  });

  final String title;
  final String? author;
  final String? imageUrl;
  final double width;

  double get height => width / ChapterSizes.coverAspectRatio;

  @override
  Widget build(BuildContext context) {
    final fallback = _MonogramCover(title: title, author: author, width: width);
    final url = imageUrl;
    return Semantics(
      image: true,
      label: author == null ? 'Cover of $title' : 'Cover of $title by $author',
      child: ExcludeSemantics(
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ChapterRadius.cover),
            boxShadow: const [
              BoxShadow(color: Color(0x33000000), blurRadius: 4, offset: Offset(0, 2)),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: url == null || url.isEmpty
              ? fallback
              : CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  fadeInDuration: ChapterMotion.fast,
                  placeholder: (_, _) => fallback,
                  errorWidget: (_, _, _) => fallback,
                ),
        ),
      ),
    );
  }
}

class _MonogramCover extends StatelessWidget {
  const _MonogramCover({required this.title, required this.width, this.author});

  final String title;
  final String? author;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final palette = colors.coverPlaceholders;
    final background = palette[title.hashCode.abs() % palette.length];
    final compact = width < 72;
    return ColoredBox(
      color: background,
      child: Padding(
        padding: EdgeInsets.all(compact ? ChapterSpacing.xs : ChapterSpacing.sm),
        child: compact
            ? Center(
                child: Text(
                  _initials(title),
                  style: context.textTheme.titleLarge?.copyWith(color: colors.ink),
                  textScaler: TextScaler.noScaling,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 5,
                      overflow: TextOverflow.fade,
                      style: context.textTheme.titleLarge?.copyWith(
                        color: colors.ink,
                        fontSize: width / 7.5,
                      ),
                      textScaler: TextScaler.noScaling,
                    ),
                  ),
                  if (author != null)
                    Text(
                      author!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: context.textTheme.labelSmall?.copyWith(color: colors.ink),
                      textScaler: TextScaler.noScaling,
                    ),
                ],
              ),
      ),
    );
  }

  static String _initials(String title) {
    final words = title.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }
}
