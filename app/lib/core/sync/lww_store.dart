import 'dart:convert';

import 'package:drift/drift.dart';

import '../database/app_database.dart';
import '../utils/clock.dart';
import '../utils/id_generator.dart';
import 'field_lww.dart';
import 'hlc.dart';

/// Local read/write access to per-field LWW documents.
///
/// Every local write updates the document **and** enqueues an outbox entry in
/// one SQLite transaction (docs/05 §2.1), so a change can never be lost
/// between the UI and the network.
class LwwStore {
  LwwStore({required AppDatabase db, required Clock clock, required IdGenerator ids})
    : _db = db,
      _clock = clock,
      _ids = ids;

  final AppDatabase _db;
  final Clock _clock;
  final IdGenerator _ids;

  static const _hlcKey = 'hlc';
  static const _nodeKey = 'nodeId';
  static const opLwwPatch = 'lwwPatch';
  static const opCreate = 'create';

  /// Watches the local document at [path]; emits an empty document when the
  /// row does not exist yet.
  Stream<LwwDocument> watch(String path) {
    final query = _db.select(_db.lwwDocuments)..where((t) => t.path.equals(path));
    return query.watchSingleOrNull().map(_toDocument);
  }

  Future<LwwDocument> read(String path) async {
    final row = await (_db.select(
      _db.lwwDocuments,
    )..where((t) => t.path.equals(path))).getSingleOrNull();
    return _toDocument(row);
  }

  /// Watches every direct child document of [collectionPath] (e.g.
  /// `users/u1/library`), keyed by document id.
  Stream<Map<String, LwwDocument>> watchCollection(String collectionPath) {
    final prefix = '$collectionPath/';
    final query = _db.select(_db.lwwDocuments)..where((t) => t.path.like('$prefix%'));
    return query.watch().map((rows) => _childrenOf(prefix, rows));
  }

  Future<Map<String, LwwDocument>> readCollection(String collectionPath) async {
    final prefix = '$collectionPath/';
    final rows = await (_db.select(_db.lwwDocuments)..where((t) => t.path.like('$prefix%'))).get();
    return _childrenOf(prefix, rows);
  }

  /// Writes [changes] locally with a fresh HLC and queues them for push.
  Future<void> write(String path, Map<String, Object?> changes) =>
      batch((b) => b.write(path, changes));

  /// Applies several changes atomically: local state and outbox rows commit
  /// in one SQLite transaction and share a batch id, so a multi-document
  /// change (e.g. status + new read-through + progress event) is never half
  /// applied locally and is pushed together, in order.
  Future<void> batch(void Function(StoreBatch batch) build) {
    final ops = StoreBatch._();
    build(ops);
    if (ops._ops.isEmpty) return Future.value();
    return _db.transaction(() async {
      final batchId = _ids.newId();
      var hlc = await _currentHlc();
      for (final op in ops._ops) {
        hlc = hlc.send(_clock.now());
        final packed = hlc.pack();
        switch (op) {
          case _WriteOp(:final path, :final changes):
            if (changes.isEmpty) continue;
            final patch = LwwDocument(
              fields: changes,
              clocks: {for (final key in changes.keys) key: packed},
            );
            await _upsert(path, (await read(path)).merge(patch));
            await _enqueue(batchId, path, opLwwPatch, _encodePatch(patch), packed);
          case _AppendOp(:final path, :final data, :final applyLocally):
            await applyLocally();
            await _enqueue(batchId, path, opCreate, jsonEncode(data), packed);
        }
      }
      await _saveHlc(hlc);
    });
  }

  Future<void> _enqueue(String batchId, String path, String opType, String payload, String hlc) =>
      _db
          .into(_db.outboxEntries)
          .insert(
            OutboxEntriesCompanion.insert(
              batchId: batchId,
              docPath: path,
              opType: opType,
              payloadJson: payload,
              hlc: hlc,
              createdAt: _clock.now(),
            ),
          );

  static Map<String, LwwDocument> _childrenOf(String prefix, List<LwwDocumentRow> rows) => {
    for (final row in rows)
      // LIKE treats `_` as a wildcard, so check the prefix exactly.
      if (row.path.startsWith(prefix) && !row.path.substring(prefix.length).contains('/'))
        row.path.substring(prefix.length): _toDocument(row),
  };

  /// Merges a document received from the server. Fields with a newer local
  /// clock (including pending, unpushed edits) are kept.
  Future<void> mergeRemote(String path, LwwDocument remote) {
    return _db.transaction(() async {
      final local = await read(path);
      final merged = local.merge(remote);
      if (merged != local) await _upsert(path, merged);
      final newest = _newestClock(remote);
      if (newest != null) {
        final current = await _currentHlc();
        await _saveHlc(current.receive(newest, _clock.now()));
      }
    });
  }

  Future<Hlc> _currentHlc() async {
    final rows = await (_db.select(
      _db.syncMeta,
    )..where((t) => t.key.isIn([_hlcKey, _nodeKey]))).get();
    final values = {for (final r in rows) r.key: r.value};
    var node = values[_nodeKey];
    if (node == null) {
      node = _ids.newId();
      await _db
          .into(_db.syncMeta)
          .insertOnConflictUpdate(SyncMetaCompanion.insert(key: _nodeKey, value: node));
    }
    final stored = values[_hlcKey];
    return stored == null ? Hlc.zero(node) : Hlc.parse(stored).withNode(node);
  }

  Future<void> _saveHlc(Hlc hlc) => _db
      .into(_db.syncMeta)
      .insertOnConflictUpdate(SyncMetaCompanion.insert(key: _hlcKey, value: hlc.pack()));

  Future<void> _upsert(String path, LwwDocument doc) => _db
      .into(_db.lwwDocuments)
      .insertOnConflictUpdate(
        LwwDocumentsCompanion.insert(
          path: path,
          fieldsJson: Value(jsonEncode(doc.fields)),
          clocksJson: Value(jsonEncode(doc.clocks)),
        ),
      );

  static Hlc? _newestClock(LwwDocument doc) {
    if (doc.clocks.isEmpty) return null;
    final newest = doc.clocks.values.reduce((a, b) => a.compareTo(b) >= 0 ? a : b);
    return Hlc.parse(newest);
  }

  static LwwDocument _toDocument(LwwDocumentRow? row) {
    if (row == null) return const LwwDocument.empty();
    return LwwDocument(
      fields: (jsonDecode(row.fieldsJson) as Map<String, Object?>),
      clocks: (jsonDecode(row.clocksJson) as Map<String, Object?>).map(
        (k, v) => MapEntry(k, v! as String),
      ),
    );
  }

  static String _encodePatch(LwwDocument patch) =>
      jsonEncode({'fields': patch.fields, 'clocks': patch.clocks});

  /// Decodes an outbox payload written by [write].
  static LwwDocument decodePatch(String json) {
    final map = jsonDecode(json) as Map<String, Object?>;
    return LwwDocument(
      fields: map['fields']! as Map<String, Object?>,
      clocks: (map['clocks']! as Map<String, Object?>).map((k, v) => MapEntry(k, v! as String)),
    );
  }
}

extension on Hlc {
  Hlc withNode(String node) => Hlc(wallMs, counter, node);
}

/// Collects the operations of one atomic [LwwStore.batch].
final class StoreBatch {
  StoreBatch._();

  final List<_Op> _ops = [];

  /// Per-field LWW write to the document at [path].
  void write(String path, Map<String, Object?> changes) => _ops.add(_WriteOp(path, changes));

  /// Append-only create of the document at [path]. [applyLocally] inserts the
  /// row into its local table inside the same transaction; [data] is what is
  /// sent to the server.
  void append(String path, Map<String, Object?> data, Future<void> Function() applyLocally) =>
      _ops.add(_AppendOp(path, data, applyLocally));
}

sealed class _Op {
  const _Op();
}

final class _WriteOp extends _Op {
  const _WriteOp(this.path, this.changes);
  final String path;
  final Map<String, Object?> changes;
}

final class _AppendOp extends _Op {
  const _AppendOp(this.path, this.data, this.applyLocally);
  final String path;
  final Map<String, Object?> data;
  final Future<void> Function() applyLocally;
}
