import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../library/domain/library_models.dart';
import '../../library/presentation/library_providers.dart';
import '../../library/presentation/library_screen.dart';
import '../../library/presentation/progress_format.dart';
import '../domain/shelf.dart';
import 'shelf_sheets.dart';
import 'shelves_screen.dart';

bool _matches(ShelfItem item, String query) {
  if (query.isEmpty) return true;
  final b = item.entry.book;
  return b.title.toLowerCase().contains(query) ||
      b.authorNames.any((a) => a.toLowerCase().contains(query));
}

/// Ticks library books on or off [shelfId], from anywhere.
Future<void> showAddBooksSheet(BuildContext context, String shelfId) => showChapterSheet<void>(
  context: context,
  title: AppLocalizations.of(context).shelfAddBooks,
  builder: (_) => _AddBooks(shelfId: shelfId),
);

/// All the books on one shelf.
class ShelfScreen extends ConsumerStatefulWidget {
  const ShelfScreen({required this.shelfId, super.key});

  final String shelfId;

  @override
  ConsumerState<ShelfScreen> createState() => _ShelfScreenState();
}

class _ShelfScreenState extends ConsumerState<ShelfScreen> {
  String _query = '';

  /// The order just dragged, shown until the saved order catches up.
  List<String>? _pending;

  void _move(List<ShelfItem> shown, List<ShelfBook> links, int from, int to) {
    final ids = [for (final b in shown) b.entry.workId];
    ids.insert(to, ids.removeAt(from));
    setState(() => _pending = ids);
    unawaited(
      ref
          .read(shelfRepositoryProvider)
          .saveOrder(
            widget.shelfId,
            ids,
            current: {
              for (final l in links)
                if (l.shelfId == widget.shelfId && l.position != null) l.workId: l.position!,
            },
          ),
    );
  }

  /// [stored] rearranged to match [_pending] while a save is on its way.
  List<ShelfItem> _withPending(List<ShelfItem> stored) {
    final pending = _pending;
    if (pending == null) return stored;
    if (listEquals(pending, [for (final b in stored) b.entry.workId])) {
      _pending = null;
      return stored;
    }
    final rank = {for (final (i, id) in pending.indexed) id: i};
    return [
      ...stored,
    ]..sort((a, b) => (rank[a.entry.workId] ?? 1 << 30).compareTo(rank[b.entry.workId] ?? 1 << 30));
  }

  Future<void> _rename(Shelf shelf) async {
    final repo = ref.read(shelfRepositoryProvider);
    final name = await promptShelfName(context, initial: shelf.name);
    if (name != null) await repo.rename(shelf.id, name);
  }

  Future<void> _delete(Shelf shelf) async {
    final l10n = AppLocalizations.of(context);
    final repo = ref.read(shelfRepositoryProvider);
    final router = GoRouter.of(context);
    final confirmed = await showChapterConfirmDialog(
      context: context,
      title: l10n.shelfDelete,
      body: l10n.shelfDeleteBody,
      confirmLabel: l10n.shelfDelete,
      cancelLabel: l10n.cancel,
      destructive: true,
    );
    if (!confirmed) return;
    await repo.delete(shelf.id);
    router.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final prefs = ref.watch(preferencesProvider).value;
    final sort = LibrarySort.values.asNameMap()[prefs?.shelfSort] ?? LibrarySort.recent;
    final grid = prefs?.shelfGrid ?? false;
    final views = ref.read(profileRepositoryProvider);
    final isFavorites = widget.shelfId == favoritesShelfId;
    final shelves = ref.watch(shelvesProvider).value ?? const <Shelf>[];
    final shelf = shelves.where((s) => s.id == widget.shelfId).firstOrNull;
    final links = ref.watch(shelfBooksProvider).value ?? const <ShelfBook>[];
    final all = watchShelf(ref).value ?? const <ShelfItem>[];
    final books = booksOnShelf(widget.shelfId, all, links);
    final name = isFavorites ? l10n.shelfFavorites : shelf?.name ?? '';
    final canDrag = sort == LibrarySort.manual && _query.isEmpty;
    final shown = _withPending(
      orderShelfBooks(
        widget.shelfId,
        books.where((b) => _matches(b, _query)).toList(),
        links,
        sort,
      ),
    );
    final breakdown = [
      for (final s in ReadingStatus.values)
        if (books.where((b) => b.entry.status == s).length case final n when n > 0)
          '${statusLabel(l10n, s)} $n',
    ].join(' · ');

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('add-books'),
        heroTag: null, // no flight from the Shelves tab's button
        icon: const Icon(Icons.add),
        label: Text(l10n.shelfAddBooks),
        onPressed: () => unawaited(showAddBooksSheet(context, widget.shelfId)),
      ),
      appBar: AppBar(
        actions: [
          PopupMenuButton<LibrarySort>(
            tooltip: l10n.librarySort,
            icon: const Icon(Icons.sort),
            initialValue: sort,
            onSelected: (s) => unawaited(views.setBookViews(shelfSort: s.name)),
            itemBuilder: (_) => librarySortItems(l10n, manual: true),
          ),
          IconButton(
            tooltip: grid ? l10n.libraryListView : l10n.libraryGridView,
            icon: Icon(grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
            onPressed: () => unawaited(views.setBookViews(shelfGrid: !grid)),
          ),
          if (shelf != null)
            PopupMenuButton<String>(
              key: const Key('shelf-menu'),
              onSelected: (v) => unawaited(v == 'rename' ? _rename(shelf) : _delete(shelf)),
              itemBuilder: (_) => [
                PopupMenuItem(value: 'rename', child: Text(l10n.shelfRename)),
                PopupMenuItem(value: 'delete', child: Text(l10n.shelfDelete)),
              ],
            ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              ChapterSpacing.gutter,
              0,
              ChapterSpacing.gutter,
              ChapterSpacing.sm,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(header: true, child: Text(name, style: context.textTheme.displayMedium)),
                Text(l10n.seriesBooks(books.length), style: context.textTheme.bodyMedium),
                if (breakdown.isNotEmpty) Text(breakdown, style: context.textTheme.bodySmall),
                if (canDrag && shown.length > 1)
                  Text(
                    grid ? l10n.shelfDragHintGrid : l10n.shelfDragHintList,
                    style: context.textTheme.bodySmall,
                  ),
                const SizedBox(height: ChapterSpacing.md),
                ChapterTextField(
                  hint: l10n.shelfSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ],
            ),
          ),
          Expanded(
            child: LibraryBookList(
              items: shown,
              grid: grid,
              onReorder: canDrag ? (from, to) => _move(shown, links, from, to) : null,
              emptyText: _query.isEmpty ? l10n.shelfEmpty : l10n.libraryNoMatches,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ticks library books on or off this shelf, without leaving the page.
class _AddBooks extends ConsumerStatefulWidget {
  const _AddBooks({required this.shelfId});

  final String shelfId;

  @override
  ConsumerState<_AddBooks> createState() => _AddBooksState();
}

class _AddBooksState extends ConsumerState<_AddBooks> {
  String _query = '';

  void _set(String workId, {required bool on}) {
    unawaited(
      widget.shelfId == favoritesShelfId
          ? ref.read(libraryRepositoryProvider).setFavorite(workId, favorite: on)
          : ref.read(shelfRepositoryProvider).setOnShelf(widget.shelfId, workId, onShelf: on),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final all = watchShelf(ref).value ?? const <ShelfItem>[];
    final links = ref.watch(shelfBooksProvider).value ?? const <ShelfBook>[];
    final onShelf = {for (final i in booksOnShelf(widget.shelfId, all, links)) i.entry.workId};
    final shown = sortShelfItems(all.where((b) => _matches(b, _query)).toList(), LibrarySort.title);
    final media = MediaQuery.of(context);
    final grid = ref.watch(preferencesProvider).value?.addBooksGrid ?? false;

    // Fixed height so the list can build lazily, however big the library is.
    return SizedBox(
      height: (media.size.height * 0.7 - media.viewInsets.bottom).clamp(240, double.infinity),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: ChapterTextField(
                  hint: l10n.librarySearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
                ),
              ),
              IconButton(
                key: const Key('add-books-view'),
                tooltip: grid ? l10n.libraryListView : l10n.libraryGridView,
                icon: Icon(grid ? Icons.view_list_outlined : Icons.grid_view_outlined),
                onPressed: () => unawaited(
                  ref.read(profileRepositoryProvider).setBookViews(addBooksGrid: !grid),
                ),
              ),
            ],
          ),
          const SizedBox(height: ChapterSpacing.sm),
          Expanded(
            child: shown.isEmpty
                ? Center(
                    child: Text(_query.isEmpty ? l10n.shelfLibraryEmpty : l10n.libraryNoMatches),
                  )
                : !grid
                ? ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final workId = shown[i].entry.workId;
                      final on = onShelf.contains(workId);
                      return MergeSemantics(
                        child: BookListTile(
                          key: ValueKey('add-book-$workId'),
                          data: cardData(l10n, shown[i]),
                          padding: const EdgeInsets.symmetric(vertical: ChapterSpacing.sm),
                          onTap: () => _set(workId, on: !on),
                          trailing: IgnorePointer(
                            child: Checkbox(value: on, onChanged: (_) {}),
                          ),
                        ),
                      );
                    },
                  )
                : _AddBooksGrid(items: shown, onShelf: onShelf, onToggle: _set),
          ),
        ],
      ),
    );
  }
}

/// The same choices as covers, three or so across.
class _AddBooksGrid extends StatelessWidget {
  const _AddBooksGrid({required this.items, required this.onShelf, required this.onToggle});

  final List<ShelfItem> items;
  final Set<String> onShelf;
  final void Function(String workId, {required bool on}) onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = ChapterSpacing.sm;
        final columns = ((constraints.maxWidth + gap) / (100 + gap)).floor().clamp(2, 8);
        final width = (constraints.maxWidth - gap * (columns - 1)) / columns;
        final rows = (items.length / columns).ceil();
        Widget cell(ShelfItem item) {
          final workId = item.entry.workId;
          final on = onShelf.contains(workId);
          return Stack(
            children: [
              BookChoiceCard(
                key: ValueKey('add-book-$workId'),
                width: width,
                selected: on,
                onTap: () => onToggle(workId, on: !on),
                child: BookGridCard(
                  data: cardData(l10n, item),
                  coverWidth: width - 2 * ChapterSpacing.xs - 4,
                ),
              ),
              if (on)
                PositionedDirectional(
                  top: ChapterSpacing.sm,
                  end: ChapterSpacing.sm,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check_circle,
                      size: 22,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
            ],
          );
        }

        return ListView.separated(
          itemCount: rows,
          separatorBuilder: (_, _) => const SizedBox(height: gap),
          itemBuilder: (_, row) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                if (row * columns + c < items.length)
                  cell(items[row * columns + c])
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
