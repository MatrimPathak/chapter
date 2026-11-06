import 'dart:async';

import 'package:chapter/core/sync/field_lww.dart';
import 'package:chapter/core/sync/sync_remote.dart';

/// In-memory [SyncRemote] with the same semantics as the Firestore one:
/// per-field LWW patches, idempotent append-only creates, and a monotonic
/// server `updatedAt` per write. Shared between simulated devices in tests.
class FakeSyncRemote implements SyncRemote {
  /// Raw server documents (LWW docs include `fieldClock`).
  final Map<String, Map<String, Object?>> raw = {};
  final Map<String, DateTime> updatedAt = {};
  final _changes = StreamController<RemoteDoc>.broadcast();

  /// When set, the next push calls throw this error.
  Object? failWith;
  int pushCount = 0;
  int _tick = 0;

  /// LWW view of every document (for assertions).
  Map<String, LwwDocument> get docs => {for (final e in raw.entries) e.key: _doc(e.key).lww};

  RemoteDoc _doc(String path) =>
      RemoteDoc(path: path, data: Map.of(raw[path]!), updatedAt: updatedAt[path]);

  void _stamp(String path) {
    updatedAt[path] = DateTime.utc(2026).add(Duration(milliseconds: ++_tick));
    _changes.add(_doc(path));
  }

  @override
  Future<void> applyPatch(String path, LwwDocument patch) async {
    final error = failWith;
    if (error != null) throw error;
    pushCount++;
    final current = raw.containsKey(path) ? _doc(path).lww : const LwwDocument.empty();
    final merged = current.merge(patch);
    if (merged == current) return;
    raw[path] = {...merged.fields, RemoteDoc.fieldClockKey: merged.clocks};
    _stamp(path);
  }

  @override
  Future<void> createIfAbsent(String path, Map<String, Object?> data) async {
    final error = failWith;
    if (error != null) throw error;
    pushCount++;
    if (raw.containsKey(path)) return;
    raw[path] = Map.of(data);
    _stamp(path);
  }

  @override
  Stream<LwwDocument?> watch(String path) => Stream<LwwDocument?>.multi((sink) {
    sink.add(raw.containsKey(path) ? _doc(path).lww : null);
    final sub = _changes.stream.where((d) => d.path == path).listen((d) => sink.add(d.lww));
    sink.onCancel = sub.cancel;
  });

  @override
  Stream<List<RemoteDoc>> watchCollection(String collectionPath, {DateTime? since}) {
    final prefix = '$collectionPath/';
    bool inCollection(String path) =>
        path.startsWith(prefix) && !path.substring(prefix.length).contains('/');
    return Stream<List<RemoteDoc>>.multi((sink) {
      final initial = [
        for (final path in raw.keys)
          if (inCollection(path) && (since == null || !updatedAt[path]!.isBefore(since)))
            _doc(path),
      ]..sort((a, b) => a.updatedAt!.compareTo(b.updatedAt!));
      if (initial.isNotEmpty) sink.add(initial);
      final sub = _changes.stream.where((d) => inCollection(d.path)).listen((d) => sink.add([d]));
      sink.onCancel = sub.cancel;
    });
  }

  Future<void> dispose() => _changes.close();
}
