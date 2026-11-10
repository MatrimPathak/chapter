import '../../../core/sync/lww_store.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../domain/shelf.dart';

/// Shelves over the local LWW store. A shelf only groups books: nothing here
/// ever touches the library, so deleting a shelf can't remove a book.
class LwwShelfRepository {
  LwwShelfRepository({
    required LwwStore store,
    required Clock clock,
    required IdGenerator ids,
    required String uid,
    required void Function() onLocalWrite,
  }) : _store = store,
       _clock = clock,
       _ids = ids,
       _onLocalWrite = onLocalWrite,
       shelvesPath = 'users/$uid/shelves',
       booksPath = 'users/$uid/shelfBooks';

  final LwwStore _store;
  final Clock _clock;
  final IdGenerator _ids;
  final void Function() _onLocalWrite;
  final String shelvesPath;
  final String booksPath;

  String get _now => _clock.now().toUtc().toIso8601String();

  static String? _clean(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty || trimmed.length > maxShelfNameLength ? null : trimmed;
  }

  /// Oldest first, so shelves stay where the reader put them.
  Stream<List<Shelf>> watchShelves() => _store.watchCollection(shelvesPath).map((docs) {
    final list = [for (final e in docs.entries) ?Shelf.fromFields(e.key, e.value.fields)]
      ..sort((a, b) {
        final at = a.createdAt, bt = b.createdAt;
        final byDate = at == null || bt == null ? 0 : at.compareTo(bt);
        return byDate != 0 ? byDate : a.id.compareTo(b.id);
      });
    return list;
  });

  Stream<List<ShelfBook>> watchBooks() => _store
      .watchCollection(booksPath)
      .map((docs) => [for (final d in docs.values) ?ShelfBook.fromFields(d.fields)]);

  /// The new shelf's id, or `null` if the name is empty or too long.
  Future<String?> create(String name) async {
    final clean = _clean(name);
    if (clean == null) return null;
    final id = _ids.newId();
    await _store.write('$shelvesPath/$id', {'name': clean, 'createdAt': _now});
    _onLocalWrite();
    return id;
  }

  Future<bool> rename(String id, String name) async {
    final clean = _clean(name);
    if (clean == null) return false;
    await _store.write('$shelvesPath/$id', {'name': clean});
    _onLocalWrite();
    return true;
  }

  /// Removes the shelf only. Its books stay in the library.
  Future<void> delete(String id) async {
    await _store.write('$shelvesPath/$id', {'deleted': true});
    _onLocalWrite();
  }

  Future<void> setOnShelf(String shelfId, String workId, {required bool onShelf}) async {
    await _store.write('$booksPath/${shelfId}_$workId', {
      'shelfId': shelfId,
      'workId': workId,
      'addedAt': _now,
      'removed': !onShelf,
    });
    _onLocalWrite();
  }

  /// Saves [workIds] as the shelf's order, in one go. [current] holds the
  /// known positions, so only books that actually moved are written.
  Future<void> saveOrder(
    String shelfId,
    List<String> workIds, {
    Map<String, int> current = const {},
  }) async {
    await _store.batch((b) {
      for (final (i, workId) in workIds.indexed) {
        if (current[workId] == i) continue;
        b.write('$booksPath/${shelfId}_$workId', {
          'shelfId': shelfId,
          'workId': workId,
          'position': i,
        });
      }
    });
    _onLocalWrite();
  }

  Future<void> attachSync(SyncEngine engine) async {
    await engine.watchCollection(shelvesPath, engine.applyLww);
    await engine.watchCollection(booksPath, engine.applyLww);
  }
}
