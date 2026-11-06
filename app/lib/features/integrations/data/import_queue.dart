import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../core/database/app_database.dart';
import '../../../core/utils/clock.dart';
import '../domain/reading_import.dart';

/// Import progress, for the screen.
class ImportProgress {
  const ImportProgress({
    this.pending = 0,
    this.added = 0,
    this.existing = 0,
    this.removedEarlier = 0,
    this.unmatched = const [],
  });

  final int pending;
  final int added;
  final int existing;
  final int removedEarlier;

  int get done => added + existing + removedEarlier;

  /// Titles that couldn't be matched. Reported, never dropped.
  final List<String> unmatched;

  bool get isEmpty => pending == 0 && done == 0 && unmatched.isEmpty;
}

/// The persistent queue behind an import: it survives restarts, and finished
/// rows stay so a reimport recognizes them.
class ImportQueue {
  ImportQueue(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  static const _pending = 'pending';
  static const _unmatched = 'unmatched';

  /// Books in [books] already finished by an earlier import.
  Future<int> countAlreadyDone(List<ImportedBook> books) async {
    final rows = await _db.select(_db.importRows).get();
    final finished = {
      for (final r in rows)
        if (r.state != _pending && r.state != _unmatched) r.key,
    };
    return books.where((b) => finished.contains(b.key)).length;
  }

  /// Queues [books]. New books wait; books that didn't match before get another
  /// chance; finished ones are left alone. Returns how many will be processed.
  Future<int> enqueue(List<ImportedBook> books) => _db.transaction(() async {
    final existing = {for (final r in await _db.select(_db.importRows).get()) r.key: r.state};
    var queued = 0;
    final now = _clock.now();
    for (final b in books) {
      final state = existing[b.key];
      if (state != null && state != _unmatched) continue;
      await _db
          .into(_db.importRows)
          .insertOnConflictUpdate(
            ImportRowsCompanion.insert(
              key: b.key,
              state: _pending,
              title: b.title,
              dataJson: jsonEncode(b.toJson()),
              queuedAt: now,
            ),
          );
      queued++;
    }
    return queued;
  });

  Future<List<ImportedBook>> next(int limit) async {
    final q = _db.select(_db.importRows)
      ..where((t) => t.state.equals(_pending))
      ..orderBy([(t) => OrderingTerm.asc(t.queuedAt), (t) => OrderingTerm.asc(t.key)])
      ..limit(limit);
    final rows = await q.get();
    return [
      for (final r in rows)
        ImportedBook.fromJson((jsonDecode(r.dataJson) as Map).cast<String, Object?>()),
    ];
  }

  Future<void> markDone(String key, ImportOutcome outcome) => _mark(key, outcome.name);

  Future<void> markUnmatched(String key) => _mark(key, _unmatched);

  Future<void> _mark(String key, String state) => (_db.update(
    _db.importRows,
  )..where((t) => t.key.equals(key))).write(ImportRowsCompanion(state: Value(state)));

  /// Forgets the unmatched list (they can be imported again later).
  Future<void> clearUnmatched() =>
      (_db.delete(_db.importRows)..where((t) => t.state.equals(_unmatched))).go();

  /// Progress of the latest file. Earlier files' finished rows stay so reimports
  /// recognise them, but they aren't this import's numbers. Anything still
  /// waiting or unmatched always shows.
  Stream<ImportProgress> watchProgress() => _db.select(_db.importRows).watch().map((all) {
    final latest = all.isEmpty
        ? null
        : all.map((r) => r.queuedAt).reduce((a, b) => a.isAfter(b) ? a : b);
    final rows = all.where(
      (r) => r.state == _pending || r.state == _unmatched || r.queuedAt == latest,
    );
    var pending = 0;
    var added = 0;
    var existing = 0;
    var removedEarlier = 0;
    final unmatched = <String>[];
    for (final r in rows) {
      switch (r.state) {
        case _pending:
          pending++;
        case 'added':
          added++;
        case 'alreadyInLibrary':
          existing++;
        case 'removedEarlier':
          removedEarlier++;
        case _unmatched:
          unmatched.add(r.title);
      }
    }
    unmatched.sort();
    return ImportProgress(
      pending: pending,
      added: added,
      existing: existing,
      removedEarlier: removedEarlier,
      unmatched: unmatched,
    );
  });
}
