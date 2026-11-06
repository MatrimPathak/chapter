import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/sync/sync_engine.dart';
import 'package:chapter/core/sync/sync_remote.dart';
import 'package:chapter/core/sync/sync_status.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_sync_remote.dart';

/// One simulated device: its own database, clock, store and engine.
class Device {
  Device(this.remote, DateTime start) : clock = FakeClock(start) {
    db = AppDatabase(NativeDatabase.memory());
    store = LwwStore(db: db, clock: clock, ids: const UuidV7Generator());
    engine = SyncEngine(
      db: db,
      store: store,
      remote: remote,
      backoff: (_) => const Duration(hours: 1),
    );
  }

  final FakeSyncRemote remote;
  final FakeClock clock;
  late final AppDatabase db;
  late final LwwStore store;
  late final SyncEngine engine;

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

const path = 'users/u1';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final t0 = DateTime.utc(2026, 11, 4, 12);
  late FakeSyncRemote remote;
  late Device phone;
  late Device tablet;

  setUp(() {
    remote = FakeSyncRemote();
    phone = Device(remote, t0);
    tablet = Device(remote, t0);
  });

  tearDown(() async {
    await phone.close();
    await tablet.close();
  });

  test('local write and outbox entry are committed together', () async {
    await phone.store.write(path, {'theme': 'dark'});
    expect((await phone.store.read(path)).fields['theme'], 'dark');
    expect(await phone.engine.pendingCount(), 1);
  });

  test('offline write is kept and pushed when back online', () async {
    phone.engine
      ..start()
      ..setOnline(false);
    await phone.store.write(path, {'analyticsConsent': true});
    await phone.engine.flush();
    expect(remote.pushCount, 0);
    expect(await phone.engine.pendingCount(), 1);
    expect(phone.engine.status, isA<SyncOffline>());

    phone.engine.setOnline(true);
    await phone.engine.flush();
    expect(remote.docs[path]!.fields['analyticsConsent'], true);
    expect(await phone.engine.pendingCount(), 0);
  });

  test('transient failure keeps the row and records the error', () async {
    await phone.store.write(path, {'theme': 'dark'});
    remote.failWith = Exception('network down');
    await phone.engine.flush();
    expect(await phone.engine.pendingCount(), 1);
    final row = await phone.db.select(phone.db.outboxEntries).getSingle();
    expect(row.attempts, 1);
    expect(row.lastError, contains('network down'));

    remote.failWith = null;
    await phone.engine.flush();
    expect(await phone.engine.pendingCount(), 0);
  });

  test('permanent failure dead-letters the row instead of dropping it', () async {
    phone.engine.start();
    await phone.store.write(path, {'theme': 'dark'});
    remote.failWith = const SyncPermanentException('permission-denied');
    await phone.engine.flush();
    final row = await phone.db.select(phone.db.outboxEntries).getSingle();
    expect(row.deadLetter, isTrue);
    expect(await phone.engine.pendingCount(), 0);
    await pumpEventQueue();
    expect(phone.engine.status, const SyncError(1));
  });

  test('two devices editing different fields offline both keep their change', () async {
    await phone.store.write(path, {'theme': 'dark'});
    tablet.clock.advance(const Duration(seconds: 1));
    await tablet.store.write(path, {'crashConsent': false});

    await phone.engine.flush();
    await tablet.engine.flush();
    phone.engine.watchDocument(path);
    tablet.engine.watchDocument(path);
    await pumpEventQueue();

    final expected = {'theme': 'dark', 'crashConsent': false};
    expect(remote.docs[path]!.fields, expected);
    expect((await phone.store.read(path)).fields, expected);
    expect((await tablet.store.read(path)).fields, expected);
  });

  test('concurrent edits of the same field converge on the newest', () async {
    await phone.store.write(path, {'theme': 'dark'});
    tablet.clock.advance(const Duration(minutes: 1));
    await tablet.store.write(path, {'theme': 'light'});

    // Newer edit reaches the server first; the older one must not win.
    await tablet.engine.flush();
    await phone.engine.flush();
    phone.engine.watchDocument(path);
    tablet.engine.watchDocument(path);
    await pumpEventQueue();

    expect(remote.docs[path]!.fields['theme'], 'light');
    expect((await phone.store.read(path)).fields['theme'], 'light');
    expect((await tablet.store.read(path)).fields['theme'], 'light');
  });

  test('pending local edit is not overwritten by an older server value', () async {
    await tablet.store.write(path, {'theme': 'light'});
    await tablet.engine.flush();

    phone.clock.advance(const Duration(minutes: 5));
    phone.engine.setOnline(false);
    await phone.store.write(path, {'theme': 'dark'});
    phone.engine.watchDocument(path);
    await pumpEventQueue();

    expect((await phone.store.read(path)).fields['theme'], 'dark');
    phone.engine.setOnline(true);
    await phone.engine.flush();
    expect(remote.docs[path]!.fields['theme'], 'dark');
  });

  test('a phone with the wrong date does not stop anyone syncing', () async {
    const collection = 'users/u1/items';
    await tablet.engine.watchCollection(collection, tablet.engine.applyLww);
    phone.clock.advance(const Duration(days: 3));
    await phone.store.write('$collection/a', {'v': 'from the wrong date'});
    await phone.engine.flush();
    await tablet.store.write('$collection/b', {'v': 'ok'});
    await pumpEventQueue();
    await tablet.engine.flush();

    expect((await tablet.store.read('$collection/a')).fields['v'], 'from the wrong date');

    // An edit made here, in real time, still beats what it saw.
    await tablet.store.write('$collection/a', {'v': 'edited later'});
    await tablet.engine.flush();
    expect(remote.docs['$collection/a']!.fields['v'], 'edited later');
  });

  test('one document that fails does not hold back the rest', () async {
    const collection = 'users/u1/items';
    await phone.store.write('$collection/a', {'v': 1});
    await phone.store.write('$collection/b', {'v': 2});
    await phone.store.write('$collection/c', {'v': 3});
    await phone.engine.flush();

    final applied = <String>[];
    await tablet.engine.watchCollection(collection, (doc) async {
      if (doc.id == 'b') throw StateError('bad document');
      applied.add(doc.id);
    });
    await pumpEventQueue();
    expect(applied, ['a', 'c']);

    // The cursor stayed back, so the next launch gets another chance at it.
    final retried = <String>[];
    final again = Device(remote, t0);
    addTearDown(again.close);
    await again.engine.watchCollection(collection, (doc) async => retried.add(doc.id));
    await pumpEventQueue();
    expect(retried, containsAll(['a', 'b', 'c']));
  });
}
