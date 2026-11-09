import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Local source of truth (docs/02 D2). One database file per signed-in user,
/// so signing out isolates data by simply closing the file.
@DriftDatabase(
  tables: [
    LwwDocuments,
    OutboxEntries,
    SyncMeta,
    CatalogCacheEntries,
    RecentSearches,
    ProgressEvents,
    ActiveSessions,
    Sessions,
    SessionTombstones,
    ImportRows,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens (or creates) the database belonging to [uid].
  factory AppDatabase.forUser(String uid) =>
      AppDatabase(driftDatabase(name: 'chapter_${safeFileName(uid)}'));

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await m.createIndex(
        Index(
          'progress_events_work_recorded',
          'CREATE INDEX progress_events_work_recorded ON progress_events (work_id, recorded_at)',
        ),
      );
      await m.createIndex(_sessionsWorkStarted);
    },
    onUpgrade: (m, from, to) async {
      // v2 (Phase 3): catalog cache and recent searches.
      if (from < 2) {
        await m.createTable(catalogCacheEntries);
        await m.createTable(recentSearches);
      }
      // v3 (Phase 4): append-only progress log.
      if (from < 3) {
        await m.createTable(progressEvents);
        await m.createIndex(
          Index(
            'progress_events_work_recorded',
            'CREATE INDEX progress_events_work_recorded ON progress_events (work_id, recorded_at)',
          ),
        );
      }
      // v4 (Phase 5): live session timer and saved sessions.
      if (from < 4) {
        await m.createTable(activeSessions);
        await m.createTable(sessions);
        await m.createIndex(_sessionsWorkStarted);
      }
      // v5 (Phase 6): deleted sessions.
      if (from < 5) {
        await m.createTable(sessionTombstones);
      }
      // v6 (Phase 7): import queue.
      if (from < 6) {
        await m.createTable(importRows);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  /// Whether a local, unsynced flag has been set.
  Future<bool> hasFlag(String key) async =>
      await (select(syncMeta)..where((t) => t.key.equals(key))).getSingleOrNull() != null;

  /// Sets a local, unsynced flag. Flags live in `sync_meta`, which is not exported.
  Future<void> setFlag(String key) async {
    await into(syncMeta).insertOnConflictUpdate(SyncMetaCompanion.insert(key: key, value: '1'));
  }

  static String safeFileName(String uid) => uid.replaceAll(RegExp('[^A-Za-z0-9_-]'), '_');

  static final _sessionsWorkStarted = Index(
    'sessions_work_started',
    'CREATE INDEX sessions_work_started ON sessions (work_id, started_at)',
  );
}
