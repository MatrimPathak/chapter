import 'package:chapter/core/database/app_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('upgrading from schema v3 adds the v4, v5 and v6 tables and keeps working', () async {
    final db = AppDatabase(
      NativeDatabase.memory(setup: (raw) => raw.execute('PRAGMA user_version = 3')),
    );
    addTearDown(db.close);

    expect(await db.select(db.activeSessions).get(), isEmpty);
    expect(await db.select(db.sessions).get(), isEmpty);
    expect(await db.select(db.sessionTombstones).get(), isEmpty);
    expect(await db.select(db.importRows).get(), isEmpty);
    final index = await db
        .customSelect("SELECT name FROM sqlite_master WHERE name = 'sessions_work_started'")
        .get();
    expect(index, hasLength(1));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), db.schemaVersion);
  });
}
