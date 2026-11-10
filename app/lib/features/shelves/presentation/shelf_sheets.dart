import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/design_system/design_system.dart';
import '../../../l10n/generated/app_localizations.dart';
import '../../library/domain/library_models.dart';
import '../../library/presentation/library_providers.dart';
import '../domain/shelf.dart';

final shelvesProvider = StreamProvider<List<Shelf>>(
  (ref) => ref.watch(shelfRepositoryProvider).watchShelves(),
);

final shelfBooksProvider = StreamProvider<List<ShelfBook>>(
  (ref) => ref.watch(shelfRepositoryProvider).watchBooks(),
);

/// Asks for a shelf name; `null` if the reader backs out.
Future<String?> promptShelfName(BuildContext context, {String? initial}) =>
    showChapterSheet<String>(
      context: context,
      title: initial == null
          ? AppLocalizations.of(context).shelfNew
          : AppLocalizations.of(context).shelfRename,
      builder: (_) => _ShelfNameForm(initial: initial),
    );

class _ShelfNameForm extends StatefulWidget {
  const _ShelfNameForm({this.initial});

  final String? initial;

  @override
  State<_ShelfNameForm> createState() => _ShelfNameFormState();
}

class _ShelfNameFormState extends State<_ShelfNameForm> {
  late final _name = TextEditingController(text: widget.initial ?? '');

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _save() {
    final name = _name.text.trim();
    if (name.isNotEmpty) Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('shelf-name'),
          controller: _name,
          autofocus: true,
          maxLength: maxShelfNameLength,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          decoration: InputDecoration(labelText: l10n.shelfName),
        ),
        const SizedBox(height: ChapterSpacing.md),
        ChapterButton(
          key: const Key('shelf-save'),
          label: l10n.shelfSave,
          expand: true,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// Which shelves a book is on. Each box applies straight away.
Future<void> showAddToShelfSheet(BuildContext context, LibraryEntry entry) =>
    showChapterSheet<void>(
      context: context,
      title: AppLocalizations.of(context).shelfAddTo,
      builder: (_) => _AddToShelf(workId: entry.workId),
    );

class _AddToShelf extends ConsumerWidget {
  const _AddToShelf({required this.workId});

  final String workId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final shelves = ref.watch(shelvesProvider).value ?? const <Shelf>[];
    final links = ref.watch(shelfBooksProvider).value ?? const <ShelfBook>[];
    final entry = ref.watch(libraryEntryProvider(workId)).value;
    final repo = ref.read(shelfRepositoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CheckboxListTile(
          key: const Key('shelf-check-favorites'),
          contentPadding: EdgeInsets.zero,
          title: Text(l10n.shelfFavorites),
          value: entry?.isFavorite ?? false,
          onChanged: (v) => unawaited(
            ref.read(libraryRepositoryProvider).setFavorite(workId, favorite: v ?? false),
          ),
        ),
        for (final shelf in shelves)
          CheckboxListTile(
            key: ValueKey('shelf-check-${shelf.id}'),
            contentPadding: EdgeInsets.zero,
            title: Text(shelf.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            value: links.any((l) => l.shelfId == shelf.id && l.workId == workId),
            onChanged: (v) => unawaited(repo.setOnShelf(shelf.id, workId, onShelf: v ?? false)),
          ),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
            key: const Key('shelf-new-inline'),
            icon: const Icon(Icons.add),
            label: Text(l10n.shelfNew),
            onPressed: () async {
              final name = await promptShelfName(context);
              if (name == null) return;
              final id = await repo.create(name);
              if (id != null) await repo.setOnShelf(id, workId, onShelf: true);
            },
          ),
        ),
      ],
    );
  }
}
