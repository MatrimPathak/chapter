import 'package:cloud_firestore/cloud_firestore.dart';

import 'field_lww.dart';
import 'sync_remote.dart';

/// Firestore implementation of [SyncRemote].
///
/// Document layouts:
/// * LWW: `{ <field>: value, ..., fieldClock: { <field>: packedHlc }, updatedAt }`
/// * Append-only: `{ ...data, updatedAt }`, written once.
class FirestoreSyncRemote implements SyncRemote {
  FirestoreSyncRemote(this._firestore);

  final FirebaseFirestore _firestore;

  static const clockField = RemoteDoc.fieldClockKey;
  static const updatedAtField = RemoteDoc.updatedAtKey;

  @override
  Future<void> applyPatch(String path, LwwDocument patch) => _guard(() async {
    final ref = _firestore.doc(path);
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      final server = _remoteDoc(snapshot).lww;
      final winners = server.winningFieldsOf(patch);
      if (winners.isEmpty) return;
      final mergedClocks = {...server.clocks, for (final f in winners) f: patch.clocks[f]!};
      tx.set(ref, <String, Object?>{
        for (final f in winners) f: patch.fields[f],
        clockField: mergedClocks,
        updatedAtField: FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    });
  });

  @override
  Future<void> createIfAbsent(String path, Map<String, Object?> data) => _guard(() async {
    final ref = _firestore.doc(path);
    await _firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (snapshot.exists) return; // already delivered earlier
      tx.set(ref, {...data, updatedAtField: FieldValue.serverTimestamp()});
    });
  });

  @override
  Stream<LwwDocument?> watch(String path) =>
      _firestore.doc(path).snapshots().map((s) => s.exists ? _remoteDoc(s).lww : null);

  @override
  Stream<List<RemoteDoc>> watchCollection(String collectionPath, {DateTime? since}) {
    Query<Map<String, dynamic>> query = _firestore.collection(collectionPath);
    if (since != null) {
      // ">=" so documents sharing the cursor timestamp are not skipped;
      // re-applying them is idempotent.
      query = query.where(updatedAtField, isGreaterThanOrEqualTo: Timestamp.fromDate(since));
    }
    return query
        .orderBy(updatedAtField)
        .snapshots()
        .map(
          (snap) => [
            for (final change in snap.docChanges)
              if (change.type != DocumentChangeType.removed) _remoteDoc(change.doc),
          ],
        )
        .where((docs) => docs.isNotEmpty);
  }

  static RemoteDoc _remoteDoc(DocumentSnapshot<Map<String, dynamic>> snapshot) {
    final data = snapshot.data() ?? const <String, dynamic>{};
    final updated = data[updatedAtField];
    return RemoteDoc(
      path: snapshot.reference.path,
      data: {for (final e in data.entries) e.key: _toJsonSafe(e.value)},
      updatedAt: updated is Timestamp ? updated.toDate().toUtc() : null,
    );
  }

  static Object? _toJsonSafe(Object? value) => switch (value) {
    final Timestamp t => t.toDate().toUtc().toIso8601String(),
    final Map<Object?, Object?> m => {for (final e in m.entries) '${e.key}': _toJsonSafe(e.value)},
    final List<Object?> l => [for (final v in l) _toJsonSafe(v)],
    _ => value,
  };

  static Future<void> _guard(Future<void> Function() body) async {
    try {
      await body();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied' || e.code == 'invalid-argument') {
        throw SyncPermanentException('${e.code}: ${e.message}');
      }
      rethrow;
    }
  }
}
