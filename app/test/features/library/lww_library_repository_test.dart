import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/sync/sync_engine.dart';
import 'package:chapter/core/sync/sync_remote.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/library/domain/library_repository.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:chapter/features/reading/domain/reading_session.dart';
import 'package:chapter/features/reading/domain/session_clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_sync_remote.dart';

const uid = 'u1';
const book = BookSummary(title: 'The Deal', authorNames: ['Elle Kennedy'], pageCount: 400);
const kindle = UserEdition(editionId: 'e-kindle', workId: 'w1', format: 'kindle', pageCount: 400);
const audio = UserEdition(
  editionId: 'e-audio',
  workId: 'w1',
  format: 'audiobook',
  audioDurationSec: 40800,
);

/// One simulated device with its own database, clock, store, engine and repo.
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
    repo = LwwLibraryRepository(
      store: store,
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: () {},
    );
  }

  final FakeSyncRemote remote;
  final FakeClock clock;
  late final AppDatabase db;
  late final LwwStore store;
  late final SyncEngine engine;
  late final LwwLibraryRepository repo;

  Future<LibraryEntry?> entry(String workId) => repo.watchEntry(workId).first;
  Future<List<ReadThrough>> throughs(String workId) => repo.watchReadThroughs(workId).first;

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

/// Lets stream listeners and async applies settle.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 50));

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

  group('library and status rules', () {
    test('add defaults to Want to Read and detects duplicates', () async {
      expect(await phone.repo.add(workId: 'w1', book: book), AddResult.added);
      expect(await phone.repo.add(workId: 'w1', book: book), AddResult.alreadyInLibrary);
      final e = (await phone.entry('w1'))!;
      expect(e.status, ReadingStatus.wantToRead);
      expect(e.book.title, 'The Deal');
      expect(await phone.throughs('w1'), isEmpty);
    });

    test('add with an owned edition stores it and makes it active', () async {
      await phone.repo.add(
        workId: 'w1',
        book: book,
        edition: const UserEdition(editionId: 'e1', workId: 'w1', format: 'paperback', owned: true),
      );
      final eds = await phone.repo.watchEditions('w1').first;
      expect(eds.single.owned, isTrue);
      expect((await phone.entry('w1'))!.activeEditionId, 'e1');
    });

    test('Reading opens a read-through, Read closes it, reread opens a new one', () async {
      await phone.repo.add(workId: 'w1', book: book);
      await phone.repo.setStatus('w1', ReadingStatus.reading);
      var rts = await phone.throughs('w1');
      expect(rts.single.ordinal, 1);
      expect(rts.single.outcome, ReadThroughOutcome.inProgress);
      expect((await phone.entry('w1'))!.activeReadThroughId, rts.single.id);

      phone.clock.advance(const Duration(days: 3));
      await phone.repo.setStatus('w1', ReadingStatus.read);
      rts = await phone.throughs('w1');
      expect(rts.single.outcome, ReadThroughOutcome.finished);
      expect(rts.single.finishedAt, t0.add(const Duration(days: 3)));
      final progress = await phone.repo.watchProgress(rts.single.id).first;
      expect(progress.single.fraction, 1, reason: 'finishing logs a 100 % event');

      await phone.repo.setStatus('w1', ReadingStatus.reading);
      rts = await phone.throughs('w1');
      expect(rts.map((r) => r.ordinal), [1, 2]);
      expect(rts.last.outcome, ReadThroughOutcome.inProgress);
    });

    test('DNF abandons the open read-through; pausing keeps it open', () async {
      await phone.repo.add(workId: 'w1', book: book, status: ReadingStatus.reading);
      await phone.repo.setStatus('w1', ReadingStatus.wantToRead);
      expect((await phone.throughs('w1')).single.outcome, ReadThroughOutcome.inProgress);
      await phone.repo.setStatus('w1', ReadingStatus.reading);
      expect(await phone.throughs('w1'), hasLength(1), reason: 'resumes, not a reread');
      await phone.repo.setStatus('w1', ReadingStatus.dnf);
      expect((await phone.throughs('w1')).single.outcome, ReadThroughOutcome.abandoned);
    });

    test('marking Read without tracking records a finished read-through', () async {
      await phone.repo.add(workId: 'w1', book: book);
      await phone.repo.setStatus('w1', ReadingStatus.read);
      final rt = (await phone.throughs('w1')).single;
      expect(rt.outcome, ReadThroughOutcome.finished);
      expect(rt.startedAt, isNull);
    });

    test('a past finish date is stored, with its pages on that day', () async {
      await phone.repo.add(workId: 'w1', book: book);
      final old = DateTime.utc(2019, 3, 4, 12);
      await phone.repo.setStatus('w1', ReadingStatus.read, finish: ReadFinish.on(old));
      final rt = (await phone.throughs('w1')).single;
      expect(rt.finishedAt!.isAtSameMomentAs(old), isTrue);
      final events = await phone.repo.watchProgress(rt.id).first;
      expect(events.single.recordedAt.isAtSameMomentAs(old), isTrue);
      expect(events.single.fraction, 1);
    });

    test('an unknown finish date stores none and logs no progress', () async {
      await phone.repo.add(
        workId: 'w1',
        book: book,
        status: ReadingStatus.read,
        finish: const ReadFinish.unknown(),
      );
      final rt = (await phone.throughs('w1')).single;
      expect(rt.outcome, ReadThroughOutcome.finished);
      expect(rt.finishedAt, isNull);
      expect(await phone.repo.watchProgress(rt.id).first, isEmpty);
    });

    test('a future finish date becomes now', () async {
      await phone.repo.add(workId: 'w1', book: book);
      await phone.repo.setStatus(
        'w1',
        ReadingStatus.read,
        finish: ReadFinish.on(t0.add(const Duration(days: 30))),
      );
      expect((await phone.throughs('w1')).single.finishedAt, t0);
    });

    test('a finish date can be corrected, cleared, and only on finished reads', () async {
      await phone.repo.add(workId: 'w1', book: book, status: ReadingStatus.reading);
      expect(await phone.repo.hasOpenReadThrough('w1'), isTrue);
      var rt = (await phone.throughs('w1')).single;
      await phone.repo.setFinishDate(rt.id, ReadFinish.on(DateTime.utc(2020)));
      expect((await phone.throughs('w1')).single.finishedAt, isNull, reason: 'still reading');

      await phone.repo.setStatus('w1', ReadingStatus.read);
      expect(await phone.repo.hasOpenReadThrough('w1'), isFalse);
      await phone.repo.setFinishDate(rt.id, ReadFinish.on(DateTime.utc(2020, 6, 2)));
      rt = (await phone.throughs('w1')).single;
      expect(rt.finishedAt, DateTime.utc(2020, 6, 2));
      await phone.repo.setFinishDate(rt.id, const ReadFinish.unknown());
      expect((await phone.throughs('w1')).single.finishedAt, isNull);
    });

    test('a start date can be set on any read, never after its finish', () async {
      await phone.repo.add(workId: 'w1', book: book, status: ReadingStatus.reading);
      final rt = (await phone.throughs('w1')).single;
      await phone.repo.setStartDate(rt.id, DateTime.utc(2020, 6));
      expect((await phone.throughs('w1')).single.startedAt, DateTime.utc(2020, 6));

      await phone.repo.setStatus('w1', ReadingStatus.read);
      await phone.repo.setFinishDate(rt.id, ReadFinish.on(DateTime.utc(2020, 6, 10)));
      await phone.repo.setStartDate(rt.id, DateTime.utc(2020, 6, 11));
      expect((await phone.throughs('w1')).single.startedAt, DateTime.utc(2020, 6));
    });

    test('an earlier finish date moves the start back with it', () async {
      await phone.repo.add(workId: 'w1', book: book, status: ReadingStatus.reading);
      final rt = (await phone.throughs('w1')).single;
      await phone.repo.setStartDate(rt.id, DateTime.utc(2020, 6, 10));
      await phone.repo.setStatus('w1', ReadingStatus.read);
      await phone.repo.setFinishDate(rt.id, ReadFinish.on(DateTime.utc(2020, 6, 5)));
      final after = (await phone.throughs('w1')).single;
      expect(after.finishedAt, DateTime.utc(2020, 6, 5));
      expect(after.startedAt, DateTime.utc(2020, 6, 5));
    });

    test('one book can own several formats at once', () async {
      await phone.repo.add(workId: 'w1', book: book, status: ReadingStatus.reading);
      for (final format in ['paperback', 'hardcover', 'kindle', 'audible']) {
        await phone.repo.setOwned(
          UserEdition(editionId: format, workId: 'w1', format: format, owned: true),
          owned: true,
        );
      }
      final owned = (await phone.repo.watchEditions('w1').first).where((e) => e.owned);
      expect(
        owned.map((e) => e.format),
        containsAll(['paperback', 'hardcover', 'kindle', 'audible']),
      );

      await phone.repo.setOwned(owned.firstWhere((e) => e.format == 'kindle'), owned: false);
      final after = (await phone.repo.watchEditions('w1').first).where((e) => e.owned);
      expect(after.map((e) => e.format), isNot(contains('kindle')));
    });

    test('remove tombstones the entry; re-adding keeps the history', () async {
      await phone.repo.add(workId: 'w1', book: book);
      await phone.repo.setStatus('w1', ReadingStatus.read);
      await phone.repo.remove('w1');
      expect(await phone.entry('w1'), isNull);
      expect(await phone.repo.watchEntries().first, isEmpty);

      expect(await phone.repo.add(workId: 'w1', book: book), AddResult.added);
      await phone.repo.setStatus('w1', ReadingStatus.reading);
      expect((await phone.throughs('w1')).map((r) => r.ordinal), [1, 2]);
    });
  });

  group('progress', () {
    test('logging progress starts reading and maps the page to a fraction', () async {
      await phone.repo.add(workId: 'w1', book: book, edition: kindle);
      final e = (await phone.repo.recordProgress('w1', const ReadingPosition.page(page: 187)))!;
      expect(e.fraction, closeTo(0.4675, 1e-9));
      expect(e.editionId, 'e-kindle');
      final entry = (await phone.entry('w1'))!;
      expect(entry.status, ReadingStatus.reading);
      expect(entry.activeReadThroughId, e.readThroughId);
    });

    test('a page in a book of unknown length is rejected; percent works', () async {
      await phone.repo.add(
        workId: 'w1',
        book: const BookSummary(title: 'No pages'),
      );
      expect(await phone.repo.recordProgress('w1', const ReadingPosition.page(page: 10)), isNull);
      final e = await phone.repo.recordProgress('w1', const ReadingPosition.percent(percent: 30));
      expect(e!.fraction, closeTo(0.3, 1e-9));
    });

    test('switching edition keeps the work-level fraction', () async {
      await phone.repo.add(workId: 'w1', book: book, edition: kindle);
      await phone.repo.recordProgress('w1', const ReadingPosition.page(page: 187));
      await phone.repo.setActiveEdition('w1', audio);
      final entry = (await phone.entry('w1'))!;
      expect(entry.activeEditionId, 'e-audio');
      final latest = await phone.repo.watchLatestProgress().first;
      expect(latest[entry.activeReadThroughId]!.fraction, closeTo(0.4675, 1e-9));
    });

    test('a status change and its read-through share one outbox batch', () async {
      await phone.repo.add(workId: 'w1', book: book, edition: kindle);
      await phone.repo.recordProgress('w1', const ReadingPosition.page(page: 50));
      final rows = await phone.db.select(phone.db.outboxEntries).get();
      final last = rows.where((r) => r.batchId == rows.last.batchId).toList();
      expect(last.map((r) => r.opType), containsAll([LwwStore.opLwwPatch, LwwStore.opCreate]));
      expect(last.map((r) => r.docPath).any((p) => p.contains('/readThroughs/')), isTrue);
    });
  });

  group('two devices', () {
    Future<void> attach(Device d) async {
      d.engine.start();
      await d.repo.attachSync(d.engine);
    }

    test('library, read-throughs and progress reach the other device', () async {
      await attach(phone);
      await attach(tablet);
      await phone.repo.add(workId: 'w1', book: book, edition: kindle);
      await phone.repo.recordProgress('w1', const ReadingPosition.page(page: 100));
      await phone.engine.flush();
      await settle();

      final e = (await tablet.entry('w1'))!;
      expect(e.status, ReadingStatus.reading);
      expect(e.activeEditionId, 'e-kindle');
      expect((await tablet.throughs('w1')).single.id, e.activeReadThroughId);
      final progress = await tablet.repo.watchProgress(e.activeReadThroughId!).first;
      expect(progress.single.fraction, 0.25);
    });

    test('offline edits on both devices merge per field; no progress is lost', () async {
      await attach(phone);
      await attach(tablet);
      await phone.repo.add(workId: 'w1', book: book, edition: kindle);
      await phone.repo.recordProgress('w1', const ReadingPosition.page(page: 40));
      await phone.engine.flush();
      await settle();

      // Both offline: phone favourites and logs p.80, tablet logs p.120 later.
      phone.engine.setOnline(false);
      tablet.engine.setOnline(false);
      phone.clock.advance(const Duration(hours: 1));
      tablet.clock.advance(const Duration(hours: 2));
      await phone.repo.setFavorite('w1', favorite: true);
      await phone.repo.recordProgress('w1', const ReadingPosition.page(page: 80));
      await tablet.repo.recordProgress('w1', const ReadingPosition.page(page: 120));

      phone.engine.setOnline(true);
      tablet.engine.setOnline(true);
      await phone.engine.flush();
      await tablet.engine.flush();
      await settle();

      for (final d in [phone, tablet]) {
        final e = (await d.entry('w1'))!;
        expect(e.isFavorite, isTrue);
        final events = await d.repo.watchProgress(e.activeReadThroughId!).first;
        expect(events.map((x) => x.fraction), [0.1, 0.2, 0.3], reason: 'all three events kept');
        final latest = await d.repo.watchLatestProgress().first;
        expect(latest[e.activeReadThroughId]!.fraction, 0.3, reason: 'newest event wins');
      }
    });

    test('same field edited on both devices offline: the later edit wins everywhere', () async {
      await attach(phone);
      await attach(tablet);
      await phone.repo.add(workId: 'w1', book: book, edition: kindle);
      await phone.engine.flush();
      await settle();

      phone.engine.setOnline(false);
      tablet.engine.setOnline(false);
      phone.clock.advance(const Duration(minutes: 5));
      tablet.clock.advance(const Duration(minutes: 9)); // later wall clock
      await phone.repo.setStatus('w1', ReadingStatus.dnf);
      await tablet.repo.setStatus('w1', ReadingStatus.read);

      // Push in the "wrong" order: the later edit arrives first.
      tablet.engine.setOnline(true);
      await tablet.engine.flush();
      phone.engine.setOnline(true);
      await phone.engine.flush();
      await settle();

      for (final d in [phone, tablet]) {
        expect((await d.entry('w1'))!.status, ReadingStatus.read);
      }
    });

    test('a saved session and its progress reach the other device once', () async {
      await attach(phone);
      await attach(tablet);
      await phone.repo.add(workId: 'w1', book: book, edition: kindle);
      await phone.repo.setStatus('w1', ReadingStatus.reading);
      final clock = SessionClock.start(t0, const Duration(minutes: 30))
          .pause(t0.add(const Duration(minutes: 5)))
          .resume(t0.add(const Duration(minutes: 7)))
          .end(t0.add(const Duration(minutes: 22)));
      final saved = (await phone.repo.completeSession(
        ActiveSession(
          id: 's1',
          workId: 'w1',
          editionId: 'e-kindle',
          clock: clock,
          startPosition: const ReadingPosition.page(page: 10),
          startFraction: 0.025,
        ),
        activeDurationSec: 1200,
        endPosition: const ReadingPosition.page(page: 50),
      ))!;
      expect(saved.pagesRead, 40);
      await phone.engine.flush();
      await settle();

      final got = (await tablet.repo.watchSessions(workId: 'w1').first).single;
      expect(got.id, 's1');
      expect(got.activeDurationSec, 1200);
      expect(got.pagesRead, 40);
      expect(got.pauses, hasLength(1));
      expect(got.endPosition, const ReadingPosition.page(page: 50));
      expect(got.completion, SessionCompletion.endedEarly);

      final doc = remote.raw['users/$uid/sessions/s1']!;
      await tablet.repo.applyRemoteSession(
        RemoteDoc(
          path: 'users/$uid/sessions/s1',
          data: doc,
          updatedAt: remote.updatedAt['users/$uid/sessions/s1'],
        ),
      );
      expect(await tablet.repo.watchSessions().first, hasLength(1), reason: 'set union');
      final e = (await tablet.entry('w1'))!;
      final latest = await tablet.repo.watchLatestProgress().first;
      expect(latest[e.activeReadThroughId]!.sessionId, 's1');
    });

    test('pushing the same event twice creates it once', () async {
      await phone.repo.add(workId: 'w1', book: book, edition: kindle);
      final e = (await phone.repo.recordProgress('w1', const ReadingPosition.page(page: 10)))!;
      final path = 'users/$uid/progressEvents/${e.id}';
      await phone.engine.flush();
      final first = Map.of(remote.raw[path]!);
      await remote.createIfAbsent(path, {...first, 'fraction': 0.9});
      expect(remote.raw[path]!['fraction'], first['fraction']);
    });

    test('collection cursor is persisted so a restart pulls only newer docs', () async {
      await attach(phone);
      await phone.repo.add(workId: 'w1', book: book);
      await phone.engine.flush();
      await attach(tablet);
      await settle();
      final meta = await tablet.db.select(tablet.db.syncMeta).get();
      expect(meta.map((m) => m.key), contains('cursor:users/$uid/library'));
    });
  });
}
