import 'package:meta/meta.dart';

import 'field_lww.dart';

/// Server-side counterpart of the sync engine. Implemented by Firestore in
/// production and by an in-memory fake in tests.
abstract interface class SyncRemote {
  /// Merges [patch] into the document at [path] using per-field
  /// last-writer-wins. Must be atomic on the server (a transaction), so two
  /// devices pushing concurrently still converge.
  ///
  /// Throws [SyncPermanentException] when the server will never accept the
  /// patch (e.g. rejected by security rules), any other error is treated as
  /// transient and retried.
  Future<void> applyPatch(String path, LwwDocument patch);

  /// Creates an append-only document unless it already exists. Idempotent:
  /// re-sending the same event (after a lost acknowledgement) is a no-op.
  Future<void> createIfAbsent(String path, Map<String, Object?> data);

  /// Emits the current server state of [path] and every later change.
  /// Emits `null` while the document does not exist.
  Stream<LwwDocument?> watch(String path);

  /// Emits batches of documents in the collection at [collectionPath] whose
  /// server `updatedAt` is at or after [since] (all documents when null),
  /// and every later change. Values are JSON-safe (timestamps as ISO strings).
  Stream<List<RemoteDoc>> watchCollection(String collectionPath, {DateTime? since});
}

/// A document received from the server.
@immutable
final class RemoteDoc {
  const RemoteDoc({required this.path, required this.data, required this.updatedAt});

  final String path;

  /// Document fields, JSON-safe. For LWW documents this includes
  /// `fieldClock`; use [lww] to decode.
  final Map<String, Object?> data;

  /// Server timestamp of the last write; drives the pull cursor.
  final DateTime? updatedAt;

  String get id => path.split('/').last;

  /// Decodes a per-field LWW document (fields that have a clock).
  LwwDocument get lww {
    final rawClocks = data[fieldClockKey];
    final clocks = rawClocks is Map
        ? {
            for (final e in rawClocks.entries)
              if (e.value is String) e.key as String: e.value as String,
          }
        : <String, String>{};
    return LwwDocument(
      fields: {
        for (final e in data.entries)
          if (e.key != fieldClockKey && e.key != updatedAtKey && clocks.containsKey(e.key))
            e.key: e.value,
      },
      clocks: clocks,
    );
  }

  static const fieldClockKey = 'fieldClock';
  static const updatedAtKey = 'updatedAt';
}

/// A push failure that retrying cannot fix.
final class SyncPermanentException implements Exception {
  const SyncPermanentException(this.message);
  final String message;

  @override
  String toString() => 'SyncPermanentException: $message';
}
