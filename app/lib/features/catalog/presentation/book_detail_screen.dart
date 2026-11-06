import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../library/presentation/library_sheets.dart';
import '../domain/catalog_models.dart';
import 'catalog_detail_providers.dart';
import 'search_controller.dart';

/// Book (work) detail: cover, titles, clickable authors and series,
/// description, publication details and editions (brief §4).
/// [LibrarySection] adds the user's shelf, edition and progress (Phase 4);
/// rating and notes join in Phases 5–6.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({required this.workKey, super.key});

  /// `id:<uuid>` or `ref:<provider>:<externalId>`.
  final String workKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final work = ref.watch(workDetailProvider(workKey));
    return Scaffold(
      appBar: AppBar(),
      body: work.when(
        data: (w) => _WorkView(work: w),
        loading: () => const _DetailSkeleton(),
        error: (error, _) => ErrorState(
          message: error is NotFoundFailure ? l10n.bookNotFound : l10n.genericError,
          retryLabel: error is NotFoundFailure ? null : l10n.retry,
          onRetry: () => ref.invalidate(workDetailProvider(workKey)),
        ),
      ),
    );
  }
}

class _WorkView extends StatelessWidget {
  const _WorkView({required this.work});

  final CatalogWork work;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = context.chapterColors;
    final edition = work.defaultEdition;
    final series = work.series.firstOrNull;
    final year = RegExp(r'\d{4}').firstMatch(work.firstPublishedDate ?? '')?.group(0);

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        ChapterSpacing.gutter,
        0,
        ChapterSpacing.gutter,
        ChapterSpacing.xxxl,
      ),
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            BookCover(
              title: work.title,
              author: work.authors.firstOrNull?.name,
              imageUrl: work.coverUrl,
              width: 116,
            ),
            const SizedBox(width: ChapterSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Semantics(
                    header: true,
                    child: Text(work.title, style: context.textTheme.headlineMedium),
                  ),
                  if (work.subtitle != null) ...[
                    const SizedBox(height: ChapterSpacing.xs),
                    Text(
                      work.subtitle!,
                      style: context.textTheme.titleMedium?.copyWith(
                        color: colors.inkMuted,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                  const SizedBox(height: ChapterSpacing.sm),
                  Wrap(
                    spacing: ChapterSpacing.xs,
                    children: [
                      for (final author in work.authors)
                        _LinkText(
                          text: author.name,
                          onTap: author.id == null
                              ? null
                              : () => context.push(AppRoutes.author('id:${author.id}')),
                        ),
                    ],
                  ),
                  if (series != null) ...[
                    const SizedBox(height: ChapterSpacing.sm),
                    Consumer(
                      builder: (context, ref, _) => _LinkText(
                        text: series.position != null
                            ? l10n.bookSeriesPosition(series.positionLabel ?? '', series.name)
                            : l10n.bookInSeries(series.name),
                        muted: true,
                        // Without a series page (no Hardcover), search by its name.
                        onTap: series.seriesId == null
                            ? () {
                                ref.read(searchControllerProvider.notifier).submit(series.name);
                                context.go(AppRoutes.search);
                              }
                            : () => context.push(AppRoutes.series(series.seriesId!)),
                      ),
                    ),
                  ],
                  const SizedBox(height: ChapterSpacing.sm),
                  Text(
                    [
                      if (work.pageCount != null) l10n.bookPages(work.pageCount!),
                      ?year,
                    ].join(' · '),
                    style: context.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: ChapterSpacing.xl),
        LibrarySection(work: work),
        if (work.description != null) ...[
          _Heading(l10n.bookAbout),
          _ExpandableText(text: work.description!),
        ],
        if (work.genres.isNotEmpty) ...[
          const SizedBox(height: ChapterSpacing.lg),
          Wrap(
            spacing: ChapterSpacing.sm,
            runSpacing: ChapterSpacing.sm,
            children: [for (final g in work.genres) Chip(label: Text(g))],
          ),
        ],
        _Heading(l10n.bookDetails),
        _Fact(label: l10n.bookPublisher, value: edition?.publisher),
        _Fact(
          label: l10n.bookPublishedLabel,
          value: edition?.publishedDate ?? work.firstPublishedDate,
        ),
        _Fact(label: l10n.bookIsbn, value: edition?.isbn13 ?? edition?.isbn10),
        _Fact(label: l10n.bookFormat, value: edition == null ? null : _format(edition.format)),
        _Fact(label: l10n.bookLanguage, value: edition?.language ?? work.language),
        if (work.editions.length > 1) ...[
          _Heading(l10n.bookEditions(work.editions.length)),
          for (final e in work.editions.take(12))
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: Text(
                [_format(e.format), ?e.publisher].join(' · '),
                style: context.textTheme.bodyMedium,
              ),
              subtitle: Text(
                [
                  ?e.publishedDate,
                  if (e.pageCount != null) l10n.bookPages(e.pageCount!),
                  ?e.isbn13,
                ].join(' · '),
                style: context.textTheme.bodySmall,
              ),
            ),
        ],
      ],
    );
  }

  static String _format(String format) => switch (format) {
    'paperback' => 'Paperback',
    'hardcover' => 'Hardcover',
    'massMarket' => 'Mass market paperback',
    'ebook' => 'Ebook',
    'kindle' => 'Kindle',
    'epub' => 'EPUB',
    'audiobook' => 'Audiobook',
    'audible' => 'Audible',
    _ => 'Edition',
  };
}

class _LinkText extends StatelessWidget {
  const _LinkText({required this.text, this.onTap, this.muted = false});

  final String text;
  final VoidCallback? onTap;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final colors = context.chapterColors;
    final style = context.textTheme.titleMedium?.copyWith(
      color: onTap == null ? (muted ? colors.inkMuted : colors.ink) : colors.accent,
      fontWeight: muted ? FontWeight.w400 : FontWeight.w600,
    );
    if (onTap == null) return Text(text, style: style);
    return Semantics(
      link: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(ChapterRadius.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: ChapterSizes.minTouchTarget),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            widthFactor: 1,
            child: Text(text, style: style),
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: ChapterSpacing.xl, bottom: ChapterSpacing.sm),
    child: Semantics(header: true, child: Text(text, style: context.textTheme.titleLarge)),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});

  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ChapterSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 112, child: Text(label, style: context.textTheme.bodySmall)),
          Expanded(child: Text(value!, style: context.textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _ExpandableText extends StatefulWidget {
  const _ExpandableText({required this.text});

  final String text;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final long = widget.text.length > 360;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.text,
          style: context.textTheme.bodyLarge,
          maxLines: _expanded || !long ? null : 6,
          overflow: _expanded || !long ? null : TextOverflow.fade,
        ),
        if (long)
          TextButton(
            style: TextButton.styleFrom(padding: EdgeInsets.zero),
            onPressed: () => setState(() => _expanded = !_expanded),
            child: Text(_expanded ? l10n.bookShowLess : l10n.bookShowMore),
          ),
      ],
    );
  }
}

class _DetailSkeleton extends StatelessWidget {
  const _DetailSkeleton();

  @override
  Widget build(BuildContext context) => Semantics(
    label: AppLocalizations.of(context).loading,
    child: const Padding(
      padding: EdgeInsets.all(ChapterSpacing.gutter),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LoadingSkeleton.cover(width: 116),
          SizedBox(width: ChapterSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LoadingSkeleton(height: 24),
                SizedBox(height: ChapterSpacing.sm),
                LoadingSkeleton(width: 140),
                SizedBox(height: ChapterSpacing.sm),
                LoadingSkeleton(width: 90),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
