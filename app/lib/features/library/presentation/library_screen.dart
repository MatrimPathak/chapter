import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/routes.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../domain/library_models.dart';
import 'library_providers.dart';
import 'progress_format.dart';

enum LibrarySort { recent, title, author, added, progress }

/// Library tab (brief §5): shelves as tabs, grid/list, sort, favourites
/// filter and search within the library. Works fully offline.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _shelves = [
    ReadingStatus.reading,
    ReadingStatus.wantToRead,
    ReadingStatus.read,
    ReadingStatus.dnf,
    null, // All
  ];

  bool _grid = false;
  bool _favoritesOnly = false;
  bool _wishlistOnly = false;
  LibrarySort _sort = LibrarySort.recent;
  String _query = '';
  String? _author;
  String? _genre;
  String? _series;

  bool get _hasFilters => _author != null || _genre != null || _series != null || _wishlistOnly;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = watchShelf(ref);
    final all = items.value ?? const <ShelfItem>[];

    if (items.hasValue && all.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.navLibrary)),
        body: EmptyState(
          icon: Icons.auto_stories_outlined,
          title: l10n.libraryEmptyTitle,
          body: l10n.libraryEmptyBody,
          actionLabel: l10n.navSearch,
          onAction: () => context.go(AppRoutes.search),
          extraActions: [
            ChapterButton(
              label: l10n.searchScan,
              variant: ChapterButtonVariant.secondary,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              onPressed: () => context.push(AppRoutes.scan),
            ),
            ChapterButton(
              label: l10n.homeImportLibrary,
              variant: ChapterButtonVariant.text,
              onPressed: () => context.push(AppRoutes.integrations),
            ),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: _shelves.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.navLibrary),
          actions: [
            IconButton(
              tooltip: l10n.libraryFavoritesOnly,
              isSelected: _favoritesOnly,
              icon: const Icon(Icons.favorite_border),
              selectedIcon: const Icon(Icons.favorite),
              onPressed: () => setState(() => _favoritesOnly = !_favoritesOnly),
            ),
            IconButton(
              key: const Key('library-filter'),
              tooltip: l10n.libraryFilter,
              isSelected: _hasFilters,
              icon: const Icon(Icons.filter_list),
              selectedIcon: const Icon(Icons.filter_list_alt),
              onPressed: () => unawaited(_showFilters(context, all)),
            ),
            PopupMenuButton<LibrarySort>(
              tooltip: l10n.librarySort,
              icon: const Icon(Icons.sort),
              initialValue: _sort,
              onSelected: (s) => setState(() => _sort = s),
              itemBuilder: (_) => [
                PopupMenuItem(value: LibrarySort.recent, child: Text(l10n.librarySortRecent)),
                PopupMenuItem(value: LibrarySort.title, child: Text(l10n.librarySortTitle)),
                PopupMenuItem(value: LibrarySort.author, child: Text(l10n.librarySortAuthor)),
                PopupMenuItem(value: LibrarySort.added, child: Text(l10n.librarySortAdded)),
                PopupMenuItem(value: LibrarySort.progress, child: Text(l10n.librarySortProgress)),
              ],
            ),
            IconButton(
              tooltip: _grid ? l10n.libraryListView : l10n.libraryGridView,
              icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
              onPressed: () => setState(() => _grid = !_grid),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48 + 64),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    ChapterSpacing.gutter,
                    0,
                    ChapterSpacing.gutter,
                    ChapterSpacing.sm,
                  ),
                  child: ChapterTextField(
                    hint: l10n.librarySearchHint,
                    prefixIcon: const Icon(Icons.search_rounded),
                    onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                  ),
                ),
                TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  tabs: [
                    for (final s in _shelves)
                      Tab(
                        text:
                            '${s == null ? l10n.libraryTabAll : statusLabel(l10n, s)} '
                            '(${all.where((i) => s == null || i.entry.status == s).length})',
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: () => context.go(AppRoutes.search),
          icon: const Icon(Icons.add),
          label: Text(l10n.libraryAddBook),
        ),
        body: items.when(
          loading: () => LoadingState(label: l10n.loading),
          error: (_, _) => ErrorState(message: l10n.genericError),
          data: (data) =>
              TabBarView(children: [for (final s in _shelves) _shelf(context, _filter(data, s))]),
        ),
      ),
    );
  }

  List<ShelfItem> _filter(List<ShelfItem> items, ReadingStatus? shelf) {
    final list = items.where((i) {
      final e = i.entry;
      if (shelf != null && e.status != shelf) return false;
      if (_favoritesOnly && !e.isFavorite) return false;
      if (_wishlistOnly && !e.isWishlist) return false;
      if (_author != null && !e.book.authorNames.contains(_author)) return false;
      if (_genre != null && !e.book.genres.contains(_genre)) return false;
      if (_series != null && e.book.seriesName != _series) return false;
      if (_query.isEmpty) return true;
      return e.book.title.toLowerCase().contains(_query) ||
          e.book.authorNames.any((a) => a.toLowerCase().contains(_query)) ||
          (e.book.seriesName?.toLowerCase().contains(_query) ?? false);
    }).toList();
    int byTitle(ShelfItem a, ShelfItem b) =>
        a.entry.book.title.toLowerCase().compareTo(b.entry.book.title.toLowerCase());
    switch (_sort) {
      case LibrarySort.recent:
        list.sort((a, b) => b.lastActivity.compareTo(a.lastActivity));
      case LibrarySort.title:
        list.sort(byTitle);
      case LibrarySort.author:
        list.sort((a, b) {
          final c = a.entry.book.authorLine.toLowerCase().compareTo(
            b.entry.book.authorLine.toLowerCase(),
          );
          return c != 0 ? c : byTitle(a, b);
        });
      case LibrarySort.added:
        list.sort((a, b) => b.entry.addedAt.compareTo(a.entry.addedAt));
      case LibrarySort.progress:
        list.sort((a, b) {
          final c = (b.progress?.fraction ?? -1).compareTo(a.progress?.fraction ?? -1);
          return c != 0 ? c : byTitle(a, b);
        });
    }
    return list;
  }

  Future<void> _showFilters(BuildContext context, List<ShelfItem> all) {
    final l10n = AppLocalizations.of(context);
    List<String> sorted(Iterable<String> values) => values.toSet().toList()..sort();
    final authors = sorted(all.expand((i) => i.entry.book.authorNames));
    final genres = sorted(all.expand((i) => i.entry.book.genres));
    final series = sorted([for (final i in all) ?i.entry.book.seriesName]);
    return showChapterSheet<void>(
      context: context,
      title: l10n.libraryFilter,
      builder: (sheet) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StatefulBuilder(
            builder: (context, setSheet) => SwitchListTile(
              key: const Key('filter-wishlist'),
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.wishlistFilter),
              value: _wishlistOnly,
              onChanged: (v) {
                setSheet(() {});
                setState(() => _wishlistOnly = v);
              },
            ),
          ),
          const SizedBox(height: ChapterSpacing.sm),
          _FilterField(
            label: l10n.libraryFilterAuthor,
            anyLabel: l10n.libraryFilterAny,
            value: _author,
            options: authors,
            onChanged: (v) => setState(() => _author = v),
          ),
          const SizedBox(height: ChapterSpacing.md),
          _FilterField(
            label: l10n.libraryFilterGenre,
            anyLabel: l10n.libraryFilterAny,
            value: _genre,
            options: genres,
            onChanged: (v) => setState(() => _genre = v),
          ),
          const SizedBox(height: ChapterSpacing.md),
          _FilterField(
            label: l10n.libraryFilterSeries,
            anyLabel: l10n.libraryFilterAny,
            value: _series,
            options: series,
            onChanged: (v) => setState(() => _series = v),
          ),
          const SizedBox(height: ChapterSpacing.lg),
          ChapterButton(
            label: l10n.libraryFilterClear,
            expand: true,
            variant: ChapterButtonVariant.text,
            onPressed: () {
              setState(() {
                _author = null;
                _genre = null;
                _series = null;
                _wishlistOnly = false;
              });
              Navigator.of(sheet).pop();
            },
          ),
        ],
      ),
    );
  }

  Widget _shelf(BuildContext context, List<ShelfItem> items) {
    final l10n = AppLocalizations.of(context);
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ChapterSpacing.gutter),
          child: Text(
            _query.isEmpty && !_favoritesOnly && !_hasFilters
                ? l10n.libraryShelfEmpty
                : l10n.libraryNoMatches,
            style: context.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    void open(ShelfItem i) => unawaited(context.push(AppRoutes.book('id:${i.entry.workId}')));
    if (_grid) {
      // Rows of self-sizing cards rather than a fixed-aspect grid: card
      // height depends on the text scale (titles wrap to two lines).
      return LayoutBuilder(
        builder: (context, constraints) {
          const gap = ChapterSpacing.md;
          final usable = constraints.maxWidth - 2 * ChapterSpacing.gutter;
          final columns = ((usable + gap) / (128 + gap)).floor().clamp(2, 8);
          final width = (usable - gap * (columns - 1)) / columns;
          final rows = (items.length / columns).ceil();
          return ListView.separated(
            padding: const EdgeInsets.all(ChapterSpacing.gutter),
            itemCount: rows,
            separatorBuilder: (_, _) => const SizedBox(height: ChapterSpacing.lg),
            itemBuilder: (_, row) => Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var c = 0; c < columns; c++) ...[
                  if (c > 0) const SizedBox(width: gap),
                  if (row * columns + c < items.length)
                    BookGridCard(
                      data: cardData(l10n, items[row * columns + c]),
                      coverWidth: width,
                      onTap: () => open(items[row * columns + c]),
                    )
                  else
                    SizedBox(width: width),
                ],
              ],
            ),
          );
        },
      );
    }
    return ListView.separated(
      // Leaves room to scroll the last book clear of the Add book button.
      padding: const EdgeInsets.fromLTRB(
        ChapterSpacing.gutter,
        ChapterSpacing.md,
        ChapterSpacing.gutter,
        ChapterSpacing.xxxl * 2,
      ),
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: ChapterSpacing.md),
      itemBuilder: (_, i) => ChapterCard(
        padding: EdgeInsets.zero,
        child: BookListTile(
          data: cardData(l10n, items[i]),
          padding: const EdgeInsets.all(ChapterSpacing.lg),
          onTap: () => open(items[i]),
          trailing: items[i].entry.isFavorite ? const Icon(Icons.favorite, size: 18) : null,
        ),
      ),
    );
  }
}

class _FilterField extends StatelessWidget {
  const _FilterField({
    required this.label,
    required this.anyLabel,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final String label;
  final String anyLabel;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
    initialValue: value,
    isExpanded: true,
    decoration: InputDecoration(labelText: label),
    items: [
      DropdownMenuItem(child: Text(anyLabel)),
      for (final o in options)
        DropdownMenuItem(
          value: o,
          child: Text(o, overflow: TextOverflow.ellipsis),
        ),
    ],
    onChanged: onChanged,
  );
}

/// Card view model shared by Library and Home.
BookCardData cardData(AppLocalizations l10n, ShelfItem item) {
  final e = item.entry;
  final p = item.progress;
  final showProgress = e.status == ReadingStatus.reading && p != null;
  return BookCardData(
    title: e.book.title,
    author: e.book.authorLine.isEmpty ? null : e.book.authorLine,
    coverUrl: e.book.coverUrl,
    progress: showProgress ? p.fraction : null,
    progressLabel: showProgress ? l10n.progressPercentLabel((p.fraction * 100).round()) : null,
    caption: showProgress ? null : statusLabel(l10n, e.status),
    isApproximate: showProgress && p.isApproximate,
  );
}
