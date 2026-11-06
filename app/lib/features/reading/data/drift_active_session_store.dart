import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../../core/database/app_database.dart';
import '../../../core/utils/clock.dart';
import '../domain/reading_session.dart';
import '../domain/session_ports.dart';

/// [ActiveSessionStore] over the singleton `active_sessions` row (id 1).
class DriftActiveSessionStore implements ActiveSessionStore {
  DriftActiveSessionStore(this._db, this._clock);

  final AppDatabase _db;
  final Clock _clock;

  @override
  Future<ActiveSession?> read() async {
    final row = await _db.select(_db.activeSessions).getSingleOrNull();
    if (row == null) return null;
    try {
      return ActiveSession.fromJson((jsonDecode(row.stateJson) as Map).cast<String, Object?>());
    } on Object {
      return null; // corrupt row: treat as no session rather than crash at launch
    }
  }

  @override
  Future<void> write(ActiveSession session) => _db
      .into(_db.activeSessions)
      .insertOnConflictUpdate(
        ActiveSessionsCompanion.insert(
          id: const Value(_singletonId),
          stateJson: jsonEncode(session.toJson()),
          updatedAt: _clock.now(),
        ),
      );

  @override
  Future<void> clear() => _db.delete(_db.activeSessions).go();
}

const _singletonId = 1;
