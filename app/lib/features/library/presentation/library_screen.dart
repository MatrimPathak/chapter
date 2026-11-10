import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../app/router/search_action.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../progress/domain/progress_event.dart';
import '../../progress/domain/reading_position.dart';
import '../domain/library_models.dart';
import 'library_providers.dart';
import 'progress_format.dart';

/// [manual] is the reader's own drag-and-drop order, on shelf pages only.
enum LibrarySort { recent, title, author, series, added, progress, manual }

/// Library tab (brief §5): shelves as tabs, grid/list, sort, favourites
/// filter and search within the library. Works fully offline.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  static const _shelves = [
    null, // All
    ReadingStatus.reading,
    ReadingStatus.wantToRead,
    ReadingStatus.read,
    ReadingStatus.dnf,
  ];

  bool _grid = false;
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
    final prefs = ref.watch(preferencesProvider).value;
    _sort = LibrarySort.values.asNameMap()[prefs?.librarySort] ?? LibrarySort.recent;
    _grid = prefs?.libraryGrid ?? false;
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
          onAction: () => context.push(AppRoutes.search),
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
            const SearchAction(),
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
              onSelected: (s) =>
                  unawaited(ref.read(profileRepositoryProvider).setBookViews(librarySort: s.name)),
              itemBuilder: (_) => librarySortItems(l10n),
            ),
            IconButton(
              tooltip: _grid ? l10n.libraryListView : l10n.libraryGridView,
              icon: Icon(_grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
              onPressed: () =>
                  unawaited(ref.read(profileRepositoryProvider).setBookViews(libraryGrid: !_grid)),
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
                  // Lines the first chip up with the search field above.
                  padding: const EdgeInsets.symmetric(horizontal: ChapterSpacing.gutter),
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
          onPressed: () => context.push(AppRoutes.search),
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
      if (_wishlistOnly && !e.isWishlist) return false;
      if (_author != null && !e.book.authorNames.contains(_author)) return false;
      if (_genre != null && !e.book.genres.contains(_genre)) return false;
      if (_series != null && e.book.seriesName != _series) return false;
      if (_query.isEmpty) return true;
      return e.book.title.toLowerCase().contains(_query) ||
          e.book.authorNames.any((a) => a.toLowerCase().contains(_query)) ||
          (e.book.seriesName?.toLowerCase().contains(_query) ?? false);
    }).toList();
    return sortShelfItems(list, _sort);
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
    return LibraryBookList(
      items: items,
      grid: _grid,
      emptyText: _query.isEmpty && !_hasFilters ? l10n.libraryShelfEmpty : l10n.libraryNoMatches,
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

List<PopupMenuEntry<LibrarySort>> librarySortItems(AppLocalizations l10n, {bool manual = false}) =>
    [
      if (manual) PopupMenuItem(value: LibrarySort.manual, child: Text(l10n.shelfSortManual)),
      PopupMenuItem(value: LibrarySort.recent, child: Text(l10n.librarySortRecent)),
      PopupMenuItem(value: LibrarySort.title, child: Text(l10n.librarySortTitle)),
      PopupMenuItem(value: LibrarySort.author, child: Text(l10n.librarySortAuthor)),
      PopupMenuItem(value: LibrarySort.series, child: Text(l10n.librarySortSeries)),
      PopupMenuItem(value: LibrarySort.added, child: Text(l10n.librarySortAdded)),
      PopupMenuItem(value: LibrarySort.progress, child: Text(l10n.librarySortProgress)),
    ];

/// Sorts in place and returns [list].
List<ShelfItem> sortShelfItems(List<ShelfItem> list, LibrarySort sort) {
  int byTitle(ShelfItem a, ShelfItem b) =>
      a.entry.book.title.toLowerCase().compareTo(b.entry.book.title.toLowerCase());
  switch (sort) {
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
    case LibrarySort.series:
      list.sort((a, b) => compareBySeriesOrder(a.entry.book, b.entry.book));
    case LibrarySort.added:
      list.sort((a, b) => b.entry.addedAt.compareTo(a.entry.addedAt));
    case LibrarySort.progress:
      list.sort((a, b) {
        final c = (b.progress?.fraction ?? -1).compareTo(a.progress?.fraction ?? -1);
        return c != 0 ? c : byTitle(a, b);
      });
    case LibrarySort.manual:
      break; // shelves keep their own order (orderShelfBooks)
  }
  return list;
}

/// Books as a list or a grid, shared by Library tabs and shelf pages.
class LibraryBookList extends StatelessWidget {
  const LibraryBookList({
    required this.items,
    required this.grid,
    required this.emptyText,
    this.onReorder,
    super.key,
  });

  final List<ShelfItem> items;
  final bool grid;
  final String emptyText;

  /// Moves the book at the first index to the second. Set to allow dragging.
  final void Function(int from, int to)? onReorder;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(ChapterSpacing.gutter),
          child: Text(emptyText, style: context.textTheme.bodyMedium, textAlign: TextAlign.center),
        ),
      );
    }
    void open(ShelfItem i) => unawaited(context.push(AppRoutes.book('id:${i.entry.workId}')));
    if (onReorder case final reorder?) {
      if (grid) return _DragGrid(items: items, onReorder: reorder, open: open);
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.fromLTRB(
          ChapterSpacing.gutter,
          ChapterSpacing.md,
          ChapterSpacing.gutter,
          ChapterSpacing.xxxl * 2,
        ),
        itemCount: items.length,
        onReorderItem: reorder,
        itemBuilder: (_, i) => Padding(
          key: ValueKey(items[i].entry.workId),
          padding: const EdgeInsets.only(bottom: ChapterSpacing.md),
          child: ChapterCard(
            padding: EdgeInsets.zero,
            child: BookListTile(
              data: cardData(l10n, items[i]),
              padding: const EdgeInsets.all(ChapterSpacing.lg),
              onTap: () => open(items[i]),
              trailing: ReorderableDragStartListener(
                index: i,
                child: Semantics(
                  label: l10n.shelfMoveBook,
                  child: const Padding(
                    padding: EdgeInsets.all(ChapterSpacing.sm),
                    child: Icon(Icons.drag_handle_rounded),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (grid) {
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

/// Covers you hold and drag to rearrange. Scrolls when dragged near an edge.
class _DragGrid extends StatefulWidget {
  const _DragGrid({required this.items, required this.onReorder, required this.open});

  final List<ShelfItem> items;
  final void Function(int from, int to) onReorder;
  final void Function(ShelfItem item) open;

  @override
  State<_DragGrid> createState() => _DragGridState();
}

class _DragGridState extends State<_DragGrid> {
  final _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _autoScroll(Offset global) {
    if (!_scroll.hasClients) return;
    final box = context.findRenderObject()! as RenderBox;
    final y = box.globalToLocal(global).dy;
    const edge = 72.0;
    const step = 14.0;
    final delta = y < edge ? -step : (y > box.size.height - edge ? step : 0.0);
    if (delta == 0) return;
    final p = _scroll.position;
    _scroll.jumpTo((p.pixels + delta).clamp(p.minScrollExtent, p.maxScrollExtent));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final items = widget.items;
    final primary = Theme.of(context).colorScheme.primary;
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = ChapterSpacing.md;
        final usable = constraints.maxWidth - 2 * ChapterSpacing.gutter;
        final columns = ((usable + gap) / (128 + gap)).floor().clamp(2, 8);
        final width = (usable - gap * (columns - 1)) / columns;
        final rows = (items.length / columns).ceil();

        Widget cell(int i) {
          final card = BookGridCard(
            data: cardData(l10n, items[i]),
            coverWidth: width,
            onTap: () => widget.open(items[i]),
          );
          return DragTarget<int>(
            key: ValueKey(items[i].entry.workId),
            onWillAcceptWithDetails: (d) => d.data != i,
            onAcceptWithDetails: (d) => widget.onReorder(d.data, i),
            builder: (context, candidates, _) => DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: BorderDirectional(
                  start: BorderSide(
                    color: candidates.isEmpty ? Colors.transparent : primary,
                    width: 3,
                  ),
                ),
              ),
              child: LongPressDraggable<int>(
                data: i,
                onDragUpdate: (d) => _autoScroll(d.globalPosition),
                feedback: Material(
                  color: Colors.transparent,
                  child: BookGridCard(data: cardData(l10n, items[i]), coverWidth: width),
                ),
                childWhenDragging: Opacity(opacity: 0.3, child: card),
                child: card,
              ),
            ),
          );
        }

        return ListView.separated(
          controller: _scroll,
          padding: const EdgeInsets.all(ChapterSpacing.gutter),
          itemCount: rows,
          separatorBuilder: (_, _) => const SizedBox(height: ChapterSpacing.lg),
          itemBuilder: (_, row) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                if (row * columns + c < items.length)
                  cell(row * columns + c)
                else
                  SizedBox(width: width),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// "p. 30 of 370 · 8%" for a page-based book, otherwise just the percentage.
/// The total comes from the event itself, so it's the edition's own count.
String _cardProgressLabel(AppLocalizations l10n, ProgressEvent p) {
  final percent = l10n.progressPercentLabel((p.fraction * 100).round());
  final position = p.position;
  if (position is PagePosition && p.fraction > 0) {
    final total = (position.page / p.fraction).round();
    return '${l10n.progressPageOf(position.page, total)} · $percent';
  }
  return percent;
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
    progressLabel: showProgress ? _cardProgressLabel(l10n, p) : null,
    caption: showProgress ? null : statusLabel(l10n, e.status),
    isApproximate: showProgress && p.isApproximate,
  );
}
