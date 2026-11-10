import 'package:meta/meta.dart';

/// The built-in shelf, driven by the heart on each book. Not stored as a shelf.
const favoritesShelfId = 'favorites';

const maxShelfNameLength = 60;

/// A shelf the reader made (`users/{uid}/shelves/{id}`).
@immutable
class Shelf {
  const Shelf({required this.id, required this.name, this.createdAt});

  final String id;
  final String name;
  final DateTime? createdAt;

  static Shelf? fromFields(String id, Map<String, Object?> f) {
    final name = f['name'] as String?;
    if (name == null || f['deleted'] == true) return null;
    return Shelf(id: id, name: name, createdAt: DateTime.tryParse(f['createdAt'] as String? ?? ''));
  }
}

/// One book on one shelf (`users/{uid}/shelfBooks/{shelfId_workId}`).
@immutable
class ShelfBook {
  const ShelfBook({required this.shelfId, required this.workId, this.position});

  final String shelfId;
  final String workId;

  /// Where the reader dragged it; `null` until they arrange this shelf.
  final int? position;

  static ShelfBook? fromFields(Map<String, Object?> f) {
    final shelfId = f['shelfId'] as String?;
    final workId = f['workId'] as String?;
    if (shelfId == null || workId == null || f['removed'] == true) return null;
    return ShelfBook(shelfId: shelfId, workId: workId, position: (f['position'] as num?)?.toInt());
  }
}
