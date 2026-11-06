import 'dart:convert';
import 'dart:math';

import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/sync/sync_engine.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/notes/data/lww_notes_repository.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_sync_remote.dart';

const uid = 'u1';

class Device {
  Device(this.remote, DateTime start) : clock = FakeClock(start) {
    db = AppDatabase(NativeDatabase.memory());
    store = LwwStore(db: db, clock: clock, ids: const UuidV7Generator());
    engine = SyncEngine(
      db: db,
      store: store,
      remote: remote,
      backoff: (_) => const Duration(milliseconds: 1),
    )..start();
    library = LwwLibraryRepository(
      store: store,
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: engine.nudge,
    );
    notes = LwwNotesRepository(
      store: store,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: engine.nudge,
    );
  }

  final FakeSyncRemote remote;
  final FakeClock clock;
  late final AppDatabase db;
  late final LwwStore store;
  late final SyncEngine engine;
  late final LwwLibraryRepository library;
  late final LwwNotesRepository notes;

  Future<void> attach() async {
    await library.attachSync(engine);
    await notes.attachSync(engine);
  }

  Future<Map<String, String>> docs() async => {
    for (final d in await db.select(db.lwwDocuments).get())
      d.path: _canonical(jsonDecode(d.fieldsJson)),
  };

  Future<Set<String>> eventIds() async => {
    for (final e in await db.select(db.progressEvents).get()) e.id,
  };
}

/// Field order doesn't matter when comparing documents.
String _canonical(Object? v) => switch (v) {
  final Map<String, Object?> m => jsonEncode({
    for (final k in m.keys.toList()..sort()) k: jsonDecode(_canonical(m[k])),
  }),
  _ => jsonEncode(v),
};

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  // Long stretches offline, a flaky server and clocks that disagree: the
  // conditions real phones meet. Whatever happens, devices must end up equal and
  // no progress update may be lost.
  for (final seed in [1, 2, 3, 4, 5]) {
    test('seed $seed: three devices converge with nothing lost', () async {
      final random = Random(seed);
      final remote = FakeSyncRemote();
      addTearDown(remote.dispose);
      final start = DateTime.utc(2026, 11, 5);
      final devices = [
        Device(remote, start),
        Device(remote, start.add(const Duration(minutes: 3))),
        Device(remote, start.subtract(const Duration(minutes: 2))),
      ];
      for (final d in devices) {
        await d.attach();
      }
      addTearDown(() async {
        for (final d in devices) {
          await d.engine.dispose();
          await d.db.close();
        }
      });

      final books = [for (var i = 0; i < 12; i++) 'w$i'];
      final noteIds = <String>[];
      var recorded = 0;

      for (var step = 0; step < 400; step++) {
        final d = devices[random.nextInt(devices.length)];
        d.clock.advance(Duration(seconds: random.nextInt(600)));
        final work = books[random.nextInt(books.length)];
        switch (random.nextInt(12)) {
          case 0 || 1:
            await d.library.add(
              workId: work,
              book: BookSummary(title: 'Book $work', pageCount: 300),
              status: ReadingStatus.values[1 + random.nextInt(3)],
            );
          case 2 || 3:
            await d.library.setStatus(work, ReadingStatus.values[1 + random.nextInt(4)]);
          case 4 || 5 || 6:
            final event = await d.library.recordProgress(
              work,
              ReadingPosition.percent(percent: random.nextInt(100).toDouble()),
            );
            if (event != null) recorded++;
          case 7:
            await d.library.remove(work);
          case 8:
            await d.library.setFavorite(work, favorite: random.nextBool());
          case 9:
            final id = await d.notes.add(workId: work, text: 'Note $step');
            if (id != null) noteIds.add(id);
          case 10:
            if (noteIds.isNotEmpty) {
              await d.notes.edit(noteIds[random.nextInt(noteIds.length)], text: 'Edit $step');
            }
          default:
            // The network comes and goes, per device and at the server.
            d.engine.setOnline(random.nextBool());
            remote.failWith = random.nextInt(4) == 0 ? StateError('503') : null;
        }
        if (step % 25 == 0) await Future<void>.delayed(Duration.zero);
      }

      // Everyone comes back and settles.
      remote.failWith = null;
      for (final d in devices) {
        d.engine.setOnline(true);
      }
      // Pulls arrive in their own time. If this runs out, they never agreed.
      final settling = Stopwatch()..start();
      while (settling.elapsed < const Duration(seconds: 20)) {
        for (final d in devices) {
          await d.engine.flush();
        }
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final docs = await devices.first.docs();
        final ids = await devices.first.eventIds();
        var same = true;
        for (final d in devices.skip(1)) {
          final other = await d.docs();
          same =
              same &&
              other.length == docs.length &&
              other.keys.every((k) => other[k] == docs[k]) &&
              (await d.eventIds()).length == ids.length;
        }
        if (same) break;
      }
      // ignore: avoid_print
      print('SOAK settled in ${settling.elapsedMilliseconds} ms');

      for (final d in devices) {
        expect(await d.engine.pendingCount(), 0, reason: 'outbox drained');
        final dead = await (d.db.select(d.db.outboxEntries)).get();
        expect(dead.where((r) => r.deadLetter), isEmpty, reason: 'nothing rejected');
      }

      final reference = await devices.first.docs();
      expect(reference, isNotEmpty);
      for (final d in devices.skip(1)) {
        expect(await d.docs(), reference, reason: 'documents converge');
      }

      final events = await devices.first.eventIds();
      expect(events.length, greaterThanOrEqualTo(recorded), reason: 'no event lost');
      for (final d in devices.skip(1)) {
        expect(await d.eventIds(), events, reason: 'same events everywhere');
      }
    }, timeout: const Timeout(Duration(minutes: 3)));
  }
}
