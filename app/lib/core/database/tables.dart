import 'package:drift/drift.dart';

/// Generic per-field last-writer-wins documents (see `LwwDocument`).
/// Keyed by their Firestore path, e.g. `users/{uid}`.
@DataClassName('LwwDocumentRow')
class LwwDocuments extends Table {
  TextColumn get path => text()();
  TextColumn get fieldsJson => text().withDefault(const Constant('{}'))();
  TextColumn get clocksJson => text().withDefault(const Constant('{}'))();

  @override
  Set<Column<Object>> get primaryKey => {path};
}

/// Transactional outbox. A row is written in the same SQLite transaction as
/// the local mutation it describes, so no change can be lost between the UI
/// write and the network push.
class OutboxEntries extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Rows sharing a batch id must be pushed atomically.
  TextColumn get batchId => text()();
  TextColumn get docPath => text()();

  /// `lwwPatch` for now; append-only ops are added in later phases.
  TextColumn get opType => text()();
  TextColumn get payloadJson => text()();
  TextColumn get hlc => text()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  TextColumn get lastError => text().nullable()();

  /// Permanently rejected (e.g. security rules). Kept, never dropped, so the
  /// user can export it.
  BoolColumn get deadLetter => boolean().withDefault(const Constant(false))();
  DateTimeColumn get createdAt => dateTime()();
}

/// Small key/value store for sync bookkeeping (HLC state, node id, cursors).
class SyncMeta extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// On-device cache of catalog responses (works, authors, series, search
/// pages), keyed by kind + id/query. Lets viewed books and past searches work
/// offline (docs/05 §2.5). Schema v2.
class CatalogCacheEntries extends Table {
  TextColumn get key => text()();
  TextColumn get json => text()();
  DateTimeColumn get cachedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

/// Recent search queries, most recent first. Schema v2.
class RecentSearches extends Table {
  TextColumn get query => text()();
  DateTimeColumn get searchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {query};
}

/// Append-only reading-progress log (docs/03 §2.2, D4). Rows are never
/// updated in place; corrections are new events. Merging across devices is a
/// set union, so no progress update can be lost. Schema v3.
@DataClassName('ProgressEventRow')
class ProgressEvents extends Table {
  TextColumn get id => text()();
  TextColumn get workId => text()();
  TextColumn get readThroughId => text()();
  TextColumn get editionId => text().nullable()();

  /// `ReadingPosition` as JSON (tagged union).
  TextColumn get positionJson => text()();
  RealColumn get fraction => real()();
  BoolColumn get isApproximate => boolean()();

  /// manual | session | import
  TextColumn get source => text()();
  TextColumn get sessionId => text().nullable()();
  DateTimeColumn get recordedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// The live session timer, a singleton row (id = 1) rewritten on every
/// transition (docs/05 §2.7). Survives the process being killed. Schema v4.
@DataClassName('ActiveSessionRow')
class ActiveSessions extends Table {
  IntColumn get id => integer()();

  /// `ActiveSession.toJson()`.
  TextColumn get stateJson => text()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Saved reading sessions, append-only like progress events (D4). Schema v4.
@DataClassName('SessionRow')
class Sessions extends Table {
  TextColumn get id => text()();
  TextColumn get workId => text()();
  TextColumn get readThroughId => text()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get activeDurationSec => integer()();

  /// `YYYY-MM-DD` in the reader's zone at the start.
  TextColumn get localDate => text()();

  /// The full session document as synced (positions, pauses, …).
  TextColumn get dataJson => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Ids of deleted sessions (schema v5). Kept apart from `sessions` so a
/// deletion wins even if it reaches a device before the session itself.
@DataClassName('SessionTombstoneRow')
class SessionTombstones extends Table {
  TextColumn get id => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Books waiting to be matched to the catalog during an import (schema v6).
/// Device-local. Kept after they finish, so a reimport recognizes them.
@DataClassName('ImportRow')
class ImportRows extends Table {
  TextColumn get key => text()();

  /// pending | done | unmatched
  TextColumn get state => text()();
  TextColumn get title => text()();

  /// `ImportedBook.toJson()`.
  TextColumn get dataJson => text()();
  DateTimeColumn get queuedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
