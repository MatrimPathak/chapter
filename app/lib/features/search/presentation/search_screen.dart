import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/presentation/catalog_detail_providers.dart';
import '../../catalog/presentation/search_controller.dart';

/// Search tab: debounced search with field filters, pagination, recent
/// searches, trending books and a barcode shortcut (docs/02 §6, brief §16).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  late final TextEditingController _text;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _text = TextEditingController(text: ref.read(searchControllerProvider).query);
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (_scroll.position.extentAfter < 400) {
      ref.read(searchControllerProvider.notifier).loadMore();
    }
  }

  void _useQuery(String query) {
    _text
      ..text = query
      ..selection = TextSelection.collapsed(offset: query.length);
    ref.read(searchControllerProvider.notifier).submit(query);
  }

  @override
  Widget build(BuildContext context) {
    // A search started elsewhere, such as a series name on a book page.
    ref.listen(searchControllerProvider.select((s) => s.query), (_, query) {
      if (_text.text != query) _text.text = query;
    });
    final l10n = AppLocalizations.of(context);
    final state = ref.watch(searchControllerProvider);
    final controller = ref.read(searchControllerProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.navSearch),
        actions: [
          IconButton(
            tooltip: l10n.searchScan,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            onPressed: () => context.push(AppRoutes.scan),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ChapterSpacing.gutter,
              0,
              ChapterSpacing.gutter,
              ChapterSpacing.sm,
            ),
            child: ChapterTextField(
              controller: _text,
              hint: l10n.searchHint,
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: state.query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () {
                        _text.clear();
                        controller.setQuery('');
                      },
                    ),
              textInputAction: TextInputAction.search,
              onChanged: controller.setQuery,
              onSubmitted: controller.submit,
            ),
          ),
          _FieldChips(selected: state.field, onSelected: controller.setField),
          Expanded(
            child: switch (state) {
              SearchState(hasQuery: false) => _IdleView(onQuery: _useQuery),
              SearchState(status: SearchStatus.loading) => LoadingState(label: l10n.loading),
              SearchState(status: SearchStatus.error) => ErrorState(
                message: l10n.searchErrorBody,
                retryLabel: l10n.retry,
                onRetry: controller.retry,
              ),
              SearchState(results: []) => EmptyState(
                icon: Icons.search_off_rounded,
                title: l10n.searchNoResultsTitle,
                body: l10n.searchNoResultsBody,
                actionLabel: l10n.searchScan,
                onAction: () => context.push(AppRoutes.scan),
              ),
              _ => _Results(state: state, scroll: _scroll),
            },
          ),
        ],
      ),
    );
  }
}

class _FieldChips extends StatelessWidget {
  const _FieldChips({required this.selected, required this.onSelected});

  final SearchField selected;
  final ValueChanged<SearchField> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = {
      SearchField.all: l10n.searchFieldAll,
      SearchField.title: l10n.searchFieldTitle,
      SearchField.author: l10n.searchFieldAuthor,
      SearchField.series: l10n.searchFieldSeries,
      SearchField.isbn: l10n.searchFieldIsbn,
      SearchField.publisher: l10n.searchFieldPublisher,
    };
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.gutter),
        children: [
          for (final entry in labels.entries)
            Padding(
              padding: const EdgeInsets.only(right: ChapterSpacing.sm),
              child: ChoiceChip(
                label: Text(entry.value),
                selected: entry.key == selected,
                onSelected: (_) => onSelected(entry.key),
              ),
            ),
        ],
      ),
    );
  }
}

class _IdleView extends ConsumerWidget {
  const _IdleView({required this.onQuery});

  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final recents = ref.watch(recentSearchesProvider).value ?? const [];
    final trending = ref.watch(trendingProvider);
    final trendingBooks = trending.value?.results ?? const <WorkSummary>[];

    if (recents.isEmpty && trendingBooks.isEmpty && !trending.isLoading) {
      return EmptyState(
        icon: Icons.menu_book_outlined,
        title: l10n.searchIdleTitle,
        body: l10n.searchIdleBody,
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: ChapterSpacing.xxl),
      children: [
        if (recents.isNotEmpty) ...[
          _SectionHeader(
            title: l10n.searchRecent,
            action: TextButton(
              onPressed: () => ref.read(catalogRepositoryProvider).clearRecentSearches(),
              child: Text(l10n.searchClearRecent),
            ),
          ),
          for (final q in recents)
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text(q),
              onTap: () => onQuery(q),
            ),
        ],
        if (trending.isLoading && trendingBooks.isEmpty)
          const Padding(
            padding: EdgeInsets.all(ChapterSpacing.xl),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (trendingBooks.isNotEmpty) ...[
          _SectionHeader(title: l10n.searchTrending),
          SizedBox(
            height: 260,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.gutter),
              itemCount: trendingBooks.length,
              separatorBuilder: (_, _) => const SizedBox(width: ChapterSpacing.lg),
              itemBuilder: (context, i) {
                final book = trendingBooks[i];
                return BookGridCard(
                  data: BookCardData(
                    title: book.title,
                    author: book.authors.firstOrNull,
                    coverUrl: book.coverUrl,
                  ),
                  onTap: () => context.push(AppRoutes.book(workKeyOf(book))),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _Results extends ConsumerWidget {
  const _Results({required this.state, required this.scroll});

  final SearchState state;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final banner = state.fromCache
        ? l10n.searchOfflineBanner
        : state.degraded
        ? l10n.searchDegradedBanner
        : null;
    final footer = state.status == SearchStatus.loadingMore;
    return ListView.builder(
      controller: scroll,
      itemCount: state.results.length + (banner != null ? 1 : 0) + (footer ? 1 : 0),
      itemBuilder: (context, index) {
        var i = index;
        if (banner != null) {
          if (i == 0) return _Banner(text: banner);
          i -= 1;
        }
        if (i >= state.results.length) {
          return const Padding(
            padding: EdgeInsets.all(ChapterSpacing.lg),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final book = state.results[i];
        return BookListTile(
          data: BookCardData(
            title: book.title,
            author: book.authors.isEmpty ? null : book.authors.take(2).join(', '),
            coverUrl: book.coverUrl,
            caption: _caption(context, book),
          ),
          onTap: () => context.push(AppRoutes.book(workKeyOf(book))),
        );
      },
    );
  }

  static String? _caption(BuildContext context, WorkSummary book) {
    final l10n = AppLocalizations.of(context);
    final parts = <String>[
      if (book.seriesName != null)
        book.seriesPosition != null
            ? l10n.bookSeriesPosition(_position(book.seriesPosition!), book.seriesName!)
            : l10n.bookInSeries(book.seriesName!),
      if (book.firstPublishedYear != null) '${book.firstPublishedYear}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

String _position(double p) => p == p.roundToDouble() ? '${p.toInt()}' : '$p';

class _Banner extends StatelessWidget {
  const _Banner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.fromLTRB(
      ChapterSpacing.gutter,
      ChapterSpacing.sm,
      ChapterSpacing.gutter,
      ChapterSpacing.xs,
    ),
    padding: const EdgeInsets.all(ChapterSpacing.md),
    decoration: BoxDecoration(
      color: context.chapterColors.surface,
      borderRadius: BorderRadius.circular(ChapterRadius.sm),
    ),
    child: Semantics(liveRegion: true, child: Text(text, style: context.textTheme.bodySmall)),
  );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.action});

  final String title;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(
      ChapterSpacing.gutter,
      ChapterSpacing.lg,
      ChapterSpacing.sm,
      ChapterSpacing.sm,
    ),
    child: Row(
      children: [
        Expanded(
          child: Semantics(header: true, child: Text(title, style: context.textTheme.titleLarge)),
        ),
        ?action,
      ],
    ),
  );
}
