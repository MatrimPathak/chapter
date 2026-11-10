import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/providers.dart';
import '../../../app/router/routes.dart';
import '../../../app/router/search_action.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../library/presentation/library_providers.dart';
import '../../library/presentation/library_screen.dart';
import '../domain/shelf.dart';
import 'shelf_sheets.dart';

/// The books on [shelfId]. Favorites follows the heart on each book.
List<ShelfItem> booksOnShelf(String shelfId, List<ShelfItem> all, List<ShelfBook> links) {
  if (shelfId == favoritesShelfId) {
    return all.where((i) => i.entry.isFavorite).toList();
  }
  final ids = {
    for (final l in links)
      if (l.shelfId == shelfId) l.workId,
  };
  return all.where((i) => ids.contains(i.entry.workId)).toList();
}

/// [items] in [sort] order. For [LibrarySort.manual], books the reader has
/// placed come first, and any added since follow, newest activity first.
List<ShelfItem> orderShelfBooks(
  String shelfId,
  List<ShelfItem> items,
  List<ShelfBook> links,
  LibrarySort sort,
) {
  if (sort != LibrarySort.manual) return sortShelfItems(items, sort);
  final positions = {
    for (final l in links)
      if (l.shelfId == shelfId && l.position != null) l.workId: l.position!,
  };
  final recent = sortShelfItems(items, LibrarySort.recent);
  return [
    ...recent.where((i) => positions.containsKey(i.entry.workId)).toList()
      ..sort((a, b) => positions[a.entry.workId]!.compareTo(positions[b.entry.workId]!)),
    ...recent.where((i) => !positions.containsKey(i.entry.workId)),
  ];
}

/// Every shelf, Favorites first, each with a peek at its books.
class ShelvesScreen extends ConsumerWidget {
  const ShelvesScreen({super.key});

  static const _peek = 5;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shelves = ref.watch(shelvesProvider).value ?? const <Shelf>[];
    final links = ref.watch(shelfBooksProvider).value ?? const <ShelfBook>[];
    final all = watchShelf(ref).value ?? const <ShelfItem>[];
    final sort =
        LibrarySort.values.asNameMap()[ref.watch(preferencesProvider).value?.shelfSort] ??
        LibrarySort.recent;

    Widget section(String id, String name) {
      final books = orderShelfBooks(id, booksOnShelf(id, all, links), links, sort);
      return _ShelfSection(
        key: ValueKey('shelf-$id'),
        id: id,
        name: name,
        books: books.take(_peek).toList(),
        total: books.length,
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.navShelves), actions: const [SearchAction()]),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('new-shelf'),
        icon: const Icon(Icons.add),
        label: Text(l10n.shelfNew),
        onPressed: () async {
          final repo = ref.read(shelfRepositoryProvider);
          final name = await promptShelfName(context);
          if (name != null) await repo.create(name);
        },
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          ChapterSpacing.gutter,
          ChapterSpacing.md,
          ChapterSpacing.gutter,
          ChapterSpacing.xxxl * 2,
        ),
        children: [
          section(favoritesShelfId, l10n.shelfFavorites),
          for (final s in shelves) section(s.id, s.name),
        ],
      ),
    );
  }
}

class _ShelfSection extends StatelessWidget {
  const _ShelfSection({
    required this.id,
    required this.name,
    required this.books,
    required this.total,
    super.key,
  });

  final String id;
  final String name;
  final List<ShelfItem> books;
  final int total;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: ChapterSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(name, style: context.textTheme.headlineSmall),
                    ),
                    Text(l10n.seriesBooks(total), style: context.textTheme.bodySmall),
                  ],
                ),
              ),
              TextButton(
                key: ValueKey('shelf-view-$id'),
                onPressed: () => unawaited(context.push(AppRoutes.shelf(id))),
                child: Text(l10n.shelfViewAll),
              ),
            ],
          ),
          const SizedBox(height: ChapterSpacing.sm),
          if (books.isEmpty)
            Text(l10n.shelfEmpty, style: context.textTheme.bodyMedium)
          else
            SizedBox(
              height: bookRowHeight(context),
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: books.length,
                separatorBuilder: (_, _) => const SizedBox(width: ChapterSpacing.lg),
                itemBuilder: (context, i) => BookGridCard(
                  data: cardData(l10n, books[i]),
                  onTap: () =>
                      unawaited(context.push(AppRoutes.book('id:${books[i].entry.workId}'))),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
