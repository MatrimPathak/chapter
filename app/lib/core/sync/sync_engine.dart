import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;

import '../database/app_database.dart';
import 'lww_store.dart';
import 'sync_remote.dart';
import 'sync_status.dart';

/// Pushes the outbox to the server and merges server changes into Drift.
///
/// * Push is single-flight and strictly ordered by outbox id.
/// * Transient failures keep the row and retry with exponential backoff.
/// * Permanent failures dead-letter the row; data is never dropped.
/// * Pull merges via [LwwStore.mergeRemote], so newer local edits win.
class SyncEngine {
  SyncEngine({
    required AppDatabase db,
    required LwwStore store,
    required SyncRemote remote,
    Duration Function(int attempt)? backoff,
    Random? random,
  }) : _db = db,
       _store = store,
       _remote = remote,
       _backoff = backoff ?? _defaultBackoff(random ?? Random());

  final AppDatabase _db;
  final LwwStore _store;
  final SyncRemote _remote;
  final Duration Function(int attempt) _backoff;

  final _statusController = StreamController<SyncStatus>.broadcast();
  final _subscriptions = <StreamSubscription<Object?>>[];
  StreamSubscription<List<OutboxEntry>>? _outboxSub;
  Timer? _retryTimer;

  bool _online = true;
  bool _flushing = false;
  bool _flushAgain = false;
  bool _disposed = false;
  int _consecutiveFailures = 0;
  int _pending = 0;
  int _deadLetters = 0;
  SyncStatus _status = const SyncSynced();

  SyncStatus get status => _status;
  Stream<SyncStatus> get statusStream => _statusController.stream;

  /// Starts observing the outbox for status reporting and kicks off a push.
  void start() {
    _outboxSub ??= _db.select(_db.outboxEntries).watch().listen((rows) {
      _pending = rows.where((r) => !r.deadLetter).length;
      _deadLetters = rows.where((r) => r.deadLetter).length;
      _emitStatus();
    });
    unawaited(flush());
  }

  /// Subscribes to server changes for the document at [path].
  void watchDocument(String path) {
    _subscriptions.add(
      _remote.watch(path).listen(
        (doc) {
          if (doc != null) unawaited(_store.mergeRemote(path, doc));
        },
        // Listener errors (e.g. offline) are surfaced by the push path;
        // Firestore re-delivers when the connection returns.
        onError: (Object _) {},
      ),
    );
  }

  /// Subscribes to server changes in the collection at [collectionPath],
  /// starting from the persisted cursor so only new changes are read.
  /// [apply] merges one document into local state; the cursor advances only
  /// after a batch has been applied, so a crash re-delivers rather than skips.
  Future<void> watchCollection(
    String collectionPath,
    Future<void> Function(RemoteDoc doc) apply,
  ) async {
    final cursorKey = 'cursor:$collectionPath';
    final stored = await (_db.select(
      _db.syncMeta,
    )..where((t) => t.key.equals(cursorKey))).getSingleOrNull();
    if (_disposed) return;
    final since = stored == null ? null : DateTime.tryParse(stored.value);
    _subscriptions.add(
      _remote
          .watchCollection(collectionPath, since: since)
          .asyncMap((docs) async {
            if (_disposed) return;
            DateTime? newest;
            var allApplied = true;
            for (final doc in docs) {
              // One bad document must not hold back the others.
              try {
                await apply(doc);
              } on Object catch (e) {
                allApplied = false;
                if (kDebugMode) {
                  debugPrint('Sync: could not apply a document in $collectionPath: $e');
                }
                continue;
              }
              final at = doc.updatedAt;
              if (at != null && (newest == null || at.isAfter(newest))) newest = at;
            }
            // Holding the cursor back redelivers a failed document next launch.
            if (allApplied && newest != null && !_disposed) {
              await _db
                  .into(_db.syncMeta)
                  .insertOnConflictUpdate(
                    SyncMetaCompanion.insert(
                      key: cursorKey,
                      value: newest.toUtc().toIso8601String(),
                    ),
                  );
            }
          })
          .listen(null, onError: (Object _) {}),
    );
  }

  /// Applies an LWW document from the server via the store's merge.
  Future<void> applyLww(RemoteDoc doc) => _store.mergeRemote(doc.path, doc.lww);

  /// Connectivity hint. Going online triggers an immediate push.
  void setOnline(bool online) {
    _online = online;
    _emitStatus();
    if (online) {
      _consecutiveFailures = 0;
      _retryTimer?.cancel();
      unawaited(flush());
    }
  }

  /// Requests a push soon (called after local writes).
  void nudge() => unawaited(flush());

  /// Pushes all pending outbox rows in order. Safe to call concurrently:
  /// callers arriving during an in-flight push wait for it, and the push
  /// loops once more to pick up rows they may have added.
  Future<void> flush() {
    if (_disposed || !_online || _halted) return Future.value();
    final inflight = _inflight;
    if (inflight != null) {
      _flushAgain = true;
      return inflight;
    }
    return _inflight = _runFlush().whenComplete(() => _inflight = null);
  }

  Future<void>? _inflight;
  bool _halted = false;

  /// Stops pushing and waits for any push in progress, so nothing can reach the
  /// server after this returns. Pending rows stay in the outbox.
  Future<void> halt() async {
    _halted = true;
    _retryTimer?.cancel();
    await _inflight;
  }

  /// Undoes [halt].
  void resume() {
    _halted = false;
    nudge();
  }

  Future<void> _runFlush() async {
    _flushing = true;
    _emitStatus();
    try {
      do {
        _flushAgain = false;
        await _pushAll();
      } while (_flushAgain && !_disposed && _online && !_halted);
    } finally {
      _flushing = false;
      _emitStatus();
    }
  }

  Future<void> _pushAll() async {
    final rows =
        await (_db.select(_db.outboxEntries)
              ..where((t) => t.deadLetter.equals(false))
              ..orderBy([(t) => OrderingTerm.asc(t.id)]))
            .get();
    for (final row in rows) {
      if (_disposed || !_online || _halted) return;
      try {
        switch (row.opType) {
          case LwwStore.opCreate:
            await _remote.createIfAbsent(
              row.docPath,
              jsonDecode(row.payloadJson) as Map<String, Object?>,
            );
          default:
            await _remote.applyPatch(row.docPath, LwwStore.decodePatch(row.payloadJson));
        }
        await (_db.delete(_db.outboxEntries)..where((t) => t.id.equals(row.id))).go();
        _consecutiveFailures = 0;
      } on SyncPermanentException catch (e) {
        await (_db.update(_db.outboxEntries)..where((t) => t.id.equals(row.id))).write(
          OutboxEntriesCompanion(
            deadLetter: const Value(true),
            lastError: Value(e.message),
            attempts: Value(row.attempts + 1),
          ),
        );
      } catch (e) {
        await (_db.update(_db.outboxEntries)..where((t) => t.id.equals(row.id))).write(
          OutboxEntriesCompanion(lastError: Value(e.toString()), attempts: Value(row.attempts + 1)),
        );
        _scheduleRetry();
        // Preserve ordering: stop at the first transient failure.
        return;
      }
    }
  }

  void _scheduleRetry() {
    _consecutiveFailures++;
    _retryTimer?.cancel();
    if (_disposed) return;
    _retryTimer = Timer(_backoff(_consecutiveFailures), () => unawaited(flush()));
  }

  void _emitStatus() {
    if (_disposed) return;
    final SyncStatus next;
    if (_deadLetters > 0) {
      next = SyncError(_deadLetters);
    } else if (!_online) {
      next = const SyncOffline();
    } else if (_flushing && _pending > 0) {
      next = const SyncSyncing();
    } else if (_pending > 0) {
      next = SyncPending(_pending);
    } else {
      next = const SyncSynced();
    }
    if (next != _status) {
      _status = next;
      _statusController.add(next);
    }
  }

  /// Number of rows not yet pushed (excluding dead letters).
  Future<int> pendingCount() async {
    final count = _db.outboxEntries.id.count();
    final query = _db.selectOnly(_db.outboxEntries)
      ..addColumns([count])
      ..where(_db.outboxEntries.deadLetter.equals(false));
    return (await query.getSingle()).read(count) ?? 0;
  }

  Future<void> dispose() async {
    _disposed = true;
    _retryTimer?.cancel();
    await _outboxSub?.cancel();
    for (final sub in _subscriptions) {
      await sub.cancel();
    }
    await _statusController.close();
  }

  static Duration Function(int) _defaultBackoff(Random random) => (attempt) {
    final base = 1000 * pow(2, min(attempt - 1, 8)).toInt();
    final capped = min(base, const Duration(minutes: 5).inMilliseconds);
    final jitter = random.nextInt(capped ~/ 2 + 1);
    return Duration(milliseconds: capped ~/ 2 + jitter);
  };
}
