import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../core/error/failure.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../library/domain/library_models.dart';
import '../../library/presentation/library_providers.dart';
import '../../library/presentation/library_sheets.dart';
import '../../library/presentation/progress_format.dart';
import '../../notes/presentation/book_notes_section.dart';
import '../domain/catalog_models.dart';
import 'catalog_detail_providers.dart';
import 'search_controller.dart';

/// Book (work) detail: cover, titles, clickable authors and series,
/// description, publication details and editions (brief §4).
/// [LibrarySection] adds the user's shelf, edition and progress (Phase 4);
/// rating and notes join in Phases 5–6.
class BookDetailScreen extends ConsumerWidget {
  const BookDetailScreen({required this.workKey, this.editionId, super.key});

  /// `id:<uuid>` or `ref:<provider>:<externalId>`.
  final String workKey;

  /// The edition to show, when the reader arrived at a specific one.
  final String? editionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final work = ref.watch(workDetailProvider(workKey));
    return work.when(
      data: (w) => _WorkPage(work: w, editionId: editionId),
      loading: () => Scaffold(appBar: AppBar(), body: const _DetailSkeleton()),
      error: (error, _) => Scaffold(
        appBar: AppBar(),
        body: ErrorState(
          message: error is NotFoundFailure ? l10n.bookNotFound : l10n.genericError,
          retryLabel: error is NotFoundFailure ? null : l10n.retry,
          onRetry: () => ref.invalidate(workDetailProvider(workKey)),
        ),
      ),
    );
  }
}

/// The book page and its app bar, which picks up the title once the big one
/// has scrolled out of sight.
class _WorkPage extends StatefulWidget {
  const _WorkPage({required this.work, this.editionId});

  final CatalogWork work;
  final String? editionId;

  @override
  State<_WorkPage> createState() => _WorkPageState();
}

class _WorkPageState extends State<_WorkPage> {
  final _scroll = ScrollController();
  final _titleKey = GlobalKey();
  bool _titleOffScreen = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_update);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  // After the frame: scrolling back rebuilds the title only once it's laid out.
  void _update() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (!mounted) return;
    final box = _titleKey.currentContext?.findRenderObject() as RenderBox?;
    final barBottom = MediaQuery.paddingOf(context).top + kToolbarHeight;
    // The list drops rows far off screen, so no title here means it's gone.
    final offScreen = box == null || box.localToGlobal(Offset(0, box.size.height)).dy <= barBottom;
    if (offScreen != _titleOffScreen) setState(() => _titleOffScreen = offScreen);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: _titleOffScreen
          ? Text(widget.work.title, maxLines: 1, overflow: TextOverflow.ellipsis)
          : null,
      actions: [BookLibraryActions(work: widget.work)],
    ),
    body: _WorkView(
      work: widget.work,
      editionId: widget.editionId,
      scrollController: _scroll,
      titleKey: _titleKey,
    ),
  );
}

class _WorkView extends ConsumerWidget {
  const _WorkView({
    required this.work,
    required this.scrollController,
    required this.titleKey,
    this.editionId,
  });

  final CatalogWork work;
  final String? editionId;
  final ScrollController scrollController;
  final GlobalKey titleKey;

  CatalogEdition? _edition(String? id) => work.editions.where((e) => e.id == id).firstOrNull;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    // What the reader asked for, then the copy they have, then a sensible default.
    final entry = ref.watch(libraryEntryProvider(work.id)).value;
    final chosen = _edition(editionId) ?? _edition(entry?.activeEditionId);
    final fallback = work.defaultEdition;
    // Nothing chosen: keep the cover the reader tapped, and describe that edition.
    final edition =
        chosen ??
        (fallback?.coverUrl == work.coverUrl
            ? fallback
            : work.editions.where((e) => e.coverUrl == work.coverUrl).firstOrNull ?? fallback);
    // A removed book keeps its record, but isn't one the reader has any more.
    final owned = entry == null
        ? const <UserEdition>[]
        : (ref.watch(userEditionsProvider(work.id)).value ?? const <UserEdition>[])
              .where((e) => e.owned)
              .toList();
    final series = work.series.firstOrNull;
    final author = work.authors.where((a) => a.id != null).firstOrNull;
    final year = RegExp(r'\d{4}').firstMatch(work.firstPublishedDate ?? '')?.group(0);

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(
        ChapterSpacing.gutter,
        0,
        ChapterSpacing.gutter,
        ChapterSpacing.xxxl,
      ),
      children: [
        Center(
          child: BookCover(
            title: work.title,
            author: work.authors.firstOrNull?.name,
            imageUrl: chosen?.coverUrl ?? work.coverUrl,
            width: 176,
          ),
        ),
        const SizedBox(height: ChapterSpacing.xl),
        Semantics(
          header: true,
          child: Text(
            key: titleKey,
            work.title,
            textAlign: TextAlign.center,
            style: context.textTheme.displayMedium,
          ),
        ),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: ChapterSpacing.sm,
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
        if (series != null)
          Center(
            child: Consumer(
              builder: (context, ref, _) => _LinkText(
                text: series.position != null
                    ? l10n.bookSeriesPosition(series.positionLabel ?? '', series.name)
                    : l10n.bookInSeries(series.name),
                muted: true,
                // Without a series page (no Hardcover), search by its name.
                onTap: series.seriesId == null
                    ? () {
                        ref.read(searchControllerProvider.notifier).submit(series.name);
                        context.push(AppRoutes.search);
                      }
                    : () => context.push(AppRoutes.series(series.seriesId!)),
              ),
            ),
          ),
        Text(
          [
            if ((edition?.pageCount ?? work.pageCount) != null)
              l10n.bookPages((edition?.pageCount ?? work.pageCount)!),
            ?year,
          ].join(' · '),
          textAlign: TextAlign.center,
          style: context.textTheme.bodySmall,
        ),
        const SizedBox(height: ChapterSpacing.xl),
        LibrarySection(work: work, editionId: edition?.id),
        if (work.description != null) ...[
          _Heading(l10n.bookAbout),
          ChapterCard(child: _ExpandableText(text: work.description!)),
        ],
        if (work.genres.isNotEmpty) ...[
          const SizedBox(height: ChapterSpacing.lg),
          Wrap(
            spacing: ChapterSpacing.sm,
            runSpacing: ChapterSpacing.sm,
            children: [for (final g in work.genres) Chip(label: Text(g))],
          ),
        ],
        if (series?.seriesId != null) _SeriesBooks(seriesId: series!.seriesId!, workId: work.id),
        if (author?.id != null) _AboutAuthor(authorId: author!.id!),
        _Heading(l10n.bookDetails),
        ChapterCard(
          child: Column(
            children: [
              _Fact(label: l10n.bookPublisher, value: edition?.publisher),
              _Fact(
                label: l10n.bookPublishedLabel,
                value: edition?.publishedDate ?? work.firstPublishedDate,
              ),
              _Fact(label: l10n.bookIsbn, value: edition?.isbn13 ?? edition?.isbn10),
              _Fact(
                label: l10n.bookFormat,
                value: edition == null || edition.format == 'other'
                    ? null
                    : _format(edition.format),
              ),
              _Fact(label: l10n.bookLanguage, value: _language(edition?.language ?? work.language)),
            ],
          ),
        ),
        if (entry != null) ...[
          _Heading(l10n.bookYourEditions),
          if (owned.isNotEmpty)
            SizedBox(
              height: bookRowHeight(context),
              child: ListView.separated(
                key: const Key('owned-editions'),
                scrollDirection: Axis.horizontal,
                itemCount: owned.length,
                separatorBuilder: (_, _) => const SizedBox(width: ChapterSpacing.lg),
                itemBuilder: (context, i) {
                  final e = owned[i];
                  return Stack(
                    key: ValueKey('owned-edition-${e.editionId}'),
                    children: [
                      BookGridCard(
                        data: BookCardData(
                          title: [_format(e.format), ?e.publisher].join(' · '),
                          author: [
                            if (e.pageCount != null) l10n.bookPages(e.pageCount!),
                            if (e.audioDurationSec != null) formatDuration(e.audioDurationSec!),
                          ].join(' · '),
                          coverUrl: e.coverUrl ?? work.coverUrl,
                        ),
                      ),
                      PositionedDirectional(
                        top: 0,
                        end: 0,
                        child: IconButton.filledTonal(
                          icon: const Icon(Icons.remove),
                          tooltip: l10n.editionRemove,
                          onPressed: () async {
                            final repo = ref.read(libraryRepositoryProvider);
                            final confirmed = await showChapterConfirmDialog(
                              context: context,
                              title: l10n.editionRemove,
                              body: l10n.editionRemoveBody,
                              confirmLabel: l10n.editionRemove,
                              cancelLabel: l10n.cancel,
                              destructive: true,
                            );
                            if (confirmed) await repo.setOwned(e, owned: false);
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const Key('add-edition'),
              icon: const Icon(Icons.add),
              label: Text(l10n.editionAdd),
              onPressed: () => showAddEditionSheet(context, work),
            ),
          ),
        ],
        if (entry != null) BookRatingSection(entry: entry),
      ],
    );
  }

  static String? _language(String? code) => const {'eng': 'English', 'en': 'English'}[code] ?? code;

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

/// Every book in the series, in reading order. If it can't load, it isn't shown.
class _SeriesBooks extends ConsumerWidget {
  const _SeriesBooks({required this.seriesId, required this.workId});

  final String seriesId;
  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final series = ref.watch(seriesDetailProvider(seriesId)).value;
    if (series == null || series.entries.length < 2) return const SizedBox.shrink();
    return Column(
      key: const Key('book-series-list'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(l10n.bookInThisSeries),
        // Sideways, so a long series doesn't push the rest of the page away.
        SizedBox(
          height: bookRowHeight(context),
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: series.entries.length,
            separatorBuilder: (_, _) => const SizedBox(width: ChapterSpacing.lg),
            itemBuilder: (context, i) => _SeriesBookCard(
              entry: series.entries[i],
              current: series.entries[i].work.id == workId,
            ),
          ),
        ),
      ],
    );
  }
}

/// One book in the row. A book in the library shows the reader's own edition.
class _SeriesBookCard extends ConsumerWidget {
  const _SeriesBookCard({required this.entry, required this.current});

  final SeriesEntry entry;
  final bool current;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final work = entry.work;
    final owned = work.id == null ? null : ref.watch(libraryEntryProvider(work.id!)).value;
    final label = entry.positionLabel;
    return BookGridCard(
      data: BookCardData(
        title: work.title,
        author: current
            ? l10n.bookThisBook
            : label == null
            ? l10n.seriesNovella
            : l10n.seriesBookNumber(label),
        coverUrl: owned?.book.coverUrl ?? work.coverUrl,
      ),
      onTap: current ? null : () => context.push(AppRoutes.book(workKeyOf(work))),
    );
  }
}

/// The first credited author's biography. If it can't load, it isn't shown.
class _AboutAuthor extends ConsumerWidget {
  const _AboutAuthor({required this.authorId});

  final String authorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final key = 'id:$authorId';
    final author = ref.watch(authorDetailProvider(key)).value;
    if (author == null) return const SizedBox.shrink();
    return Column(
      key: const Key('book-about-author'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Heading(l10n.bookAboutAuthor),
        ChapterCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(author.name, style: context.textTheme.headlineSmall),
              const SizedBox(height: ChapterSpacing.sm),
              if (author.bio == null)
                Text(l10n.authorNoBio, style: context.textTheme.bodyMedium)
              else
                _ExpandableText(text: author.bio!),
              TextButton(
                onPressed: () => context.push(AppRoutes.author(key)),
                child: Text(l10n.bookViewAuthor),
              ),
            ],
          ),
        ),
      ],
    );
  }
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
    child: Semantics(header: true, child: Text(text, style: context.textTheme.headlineMedium)),
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
      child: Column(
        children: [
          LoadingSkeleton.cover(width: 176),
          SizedBox(height: ChapterSpacing.xl),
          LoadingSkeleton(height: 32, width: 220),
          SizedBox(height: ChapterSpacing.sm),
          LoadingSkeleton(width: 140),
          SizedBox(height: ChapterSpacing.sm),
          LoadingSkeleton(width: 90),
        ],
      ),
    ),
  );
}
