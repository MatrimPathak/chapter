import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/error/failure.dart';
import 'package:chapter/core/error/result.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/sync/sync_engine.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:chapter/features/insights/domain/stats_engine.dart';
import 'package:chapter/features/integrations/application/import_runner.dart';
import 'package:chapter/features/integrations/data/import_queue.dart';
import 'package:chapter/features/integrations/domain/reading_import.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_catalog.dart';
import '../../helpers/fake_sync_remote.dart';

CatalogWork workFor(String id, {String title = 'Book', int? pages = 300}) => CatalogWork(
  id: id,
  title: title,
  authors: const [CatalogAuthorRef(name: 'Ann Lee')],
  pageCount: pages,
  refreshedAt: '2026-11-05T10:00:00.000Z',
);

ImportedBook book(
  String key, {
  String title = 'Book',
  String? isbn = '9780349440842',
  ReadingStatus status = ReadingStatus.read,
  List<DateTime> finishedOn = const [],
  int undated = 0,
  double? rating,
  String? review,
}) => ImportedBook(
  key: key,
  source: ImportSource.goodreads,
  title: title,
  authors: const ['Ann Lee'],
  isbn: isbn,
  status: status,
  finishedOn: finishedOn,
  undatedReads: undated,
  rating: rating,
  review: review,
);

/// Each ISBN resolves to its own work, so tests can tell books apart.
class CatalogFake extends FakeCatalogRepository {
  Failure? failWith;
  int lookups = 0;
  final worksByIsbn = <String, CatalogWork>{};

  @override
  Future<Result<WorkLookup>> lookupIsbn(String isbn) async {
    lookups++;
    final f = failWith;
    if (f != null) return Result.err(f);
    final w = worksByIsbn[isbn];
    return w == null ? const Result.err(NotFoundFailure('x')) : Result.ok(WorkLookup(work: w));
  }

  @override
  Future<Result<CatalogWork>> getWork(WorkTarget target) async => switch (target) {
    WorkById(:final workId) => Result.ok(workFor(workId, title: 'Found By Title')),
    WorkByRef() => Result.ok(workFor('from-ref', title: 'Found By Title')),
  };
}

class Device {
  Device(FakeSyncRemote remote, DateTime now) : clock = FakeClock(now) {
    db = AppDatabase(NativeDatabase.memory());
    store = LwwStore(db: db, clock: clock, ids: const UuidV7Generator());
    engine = SyncEngine(
      db: db,
      store: store,
      remote: remote,
      backoff: (_) => const Duration(hours: 1),
    )..start();
    library = LwwLibraryRepository(
      store: store,
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: 'u1',
      onLocalWrite: () {},
    );
    queue = ImportQueue(db, clock);
  }

  final FakeClock clock;
  late final AppDatabase db;
  late final LwwStore store;
  late final SyncEngine engine;
  late final LwwLibraryRepository library;
  late final ImportQueue queue;

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime.utc(2026, 11, 5, 12);
  late FakeSyncRemote remote;
  late Device phone;
  late CatalogFake catalog;

  ImportRunner runner(Device d, {List<Duration>? waits}) => ImportRunner(
    queue: d.queue,
    catalog: catalog,
    library: d.library,
    wait: (p) async => waits?.add(p),
  );

  setUp(() {
    remote = FakeSyncRemote();
    phone = Device(remote, now);
    catalog = CatalogFake();
    catalog.worksByIsbn['9780349440842'] = workFor('w1');
  });

  tearDown(() => phone.close());

  Future<List<ReadThrough>> reads(Device d, String work) => d.library.watchReadThroughs(work).first;

  group('adding', () {
    test('a read book arrives with shelf, rating, review, dated read and pages', () async {
      final at = DateTime(2021, 3, 4, 12);
      await phone.queue.enqueue([
        book('k', finishedOn: [at], undated: 1, rating: 4.5, review: 'Good'),
      ]);
      await runner(phone).run();

      final e = (await phone.library.watchEntry('w1').first)!;
      expect(e.status, ReadingStatus.read);
      expect(e.rating, 4.5);
      expect(e.review, 'Good');
      expect(e.book.pageCount, 300);

      final rts = await reads(phone, 'w1');
      expect(rts, hasLength(2));
      expect(rts.first.finishedAt!.isAtSameMomentAs(at), isTrue);
      expect(rts.last.finishedAt, isNull);

      final stats = StatsEngine(
        StatsInput(
          entries: [e],
          readThroughs: rts,
          events: await phone.library.watchAllProgress().first,
        ),
      );
      expect(stats.totals(from: '2021-01-01', to: '2021-12-31').books, 1);
      expect(stats.totals(from: '2021-01-01', to: '2021-12-31').pages, 300);
      expect(stats.totals(from: '2026-01-01', to: '2026-12-31').books, 0);
    });

    test('Currently reading opens a read-through; to-read does not', () async {
      catalog.worksByIsbn['1111111111'] = workFor('w2');
      await phone.queue.enqueue([
        book('a', status: ReadingStatus.reading),
        book('b', status: ReadingStatus.wantToRead, isbn: '1111111111'),
      ]);
      await runner(phone).run();
      final a = (await phone.library.watchEntry('w1').first)!;
      expect(a.status, ReadingStatus.reading);
      expect((await reads(phone, 'w1')).single.outcome, ReadThroughOutcome.inProgress);
      expect(a.activeReadThroughId, (await reads(phone, 'w1')).single.id);
      expect(await reads(phone, 'w2'), isEmpty);
    });

    test('with no ISBN or an unknown one, an exact title and author match counts', () async {
      catalog.onSearch = (q, _, _) => const Result.ok(
        SearchPage(
          results: [
            WorkSummary(
              id: 'w-near',
              ref: ProviderRef(provider: CatalogProvider.openLibrary, externalId: 'x'),
              title: 'Book of Other Things',
              authors: ['Ann Lee'],
            ),
            WorkSummary(
              id: 'w-title',
              ref: ProviderRef(provider: CatalogProvider.openLibrary, externalId: 'y'),
              title: 'Exact: A Subtitle',
              authors: ['Lee, Ann'],
            ),
          ],
        ),
      );
      await phone.queue.enqueue([book('k', title: 'Exact', isbn: null)]);
      await runner(phone).run();
      expect(await phone.library.watchEntry('w-title').first, isNotNull);
      expect(await phone.library.watchEntry('w-near').first, isNull);
    });

    test('anything less is reported as unmatched, not added or dropped', () async {
      catalog.onSearch = (q, _, _) => const Result.ok(
        SearchPage(
          results: [
            WorkSummary(
              id: 'wrong-author',
              ref: ProviderRef(provider: CatalogProvider.openLibrary, externalId: 'z'),
              title: 'Lost Book',
              authors: ['Someone Else'],
            ),
          ],
        ),
      );
      await phone.queue.enqueue([
        book('k', title: 'Lost Book', isbn: null),
        book('m', title: 'Never Heard Of', isbn: '9999999999'),
      ]);
      await runner(phone).run();
      expect(await phone.library.watchEntries().first, isEmpty);
      final p = await phone.queue.watchProgress().first;
      expect(p.unmatched, ['Lost Book', 'Never Heard Of']);
      expect(p.pending, 0);
    });
  });

  group('never overwrites', () {
    setUp(() async {
      await phone.library.add(
        workId: 'w1',
        book: const BookSummary(title: 'Mine'),
        status: ReadingStatus.reading,
      );
      await phone.library.setRating('w1', 2);
    });

    test('existing shelf and rating stay; only an empty review is filled', () async {
      await phone.queue.enqueue([
        book('k', rating: 5, review: 'From export', finishedOn: [DateTime(2021, 3, 4, 12)]),
      ]);
      await runner(phone).run();
      final e = (await phone.library.watchEntry('w1').first)!;
      expect(e.status, ReadingStatus.reading);
      expect(e.book.title, 'Mine');
      expect(e.rating, 2);
      expect(e.review, 'From export');
    });

    test('the read history gains the old read', () async {
      await phone.queue.enqueue([
        book('k', finishedOn: [DateTime(2021, 3, 4, 12)]),
      ]);
      await runner(phone).run();
      expect((await reads(phone, 'w1')).map((r) => r.outcome), [
        ReadThroughOutcome.inProgress,
        ReadThroughOutcome.finished,
      ]);
    });

    test('a read already recorded on that day is not added twice', () async {
      final day = DateTime(2021, 3, 4, 12);
      await phone.library.setStatus('w1', ReadingStatus.read, finish: ReadFinish.on(day));
      await phone.queue.enqueue([
        book('k', finishedOn: [day]),
      ]);
      await runner(phone).run();
      expect(await reads(phone, 'w1'), hasLength(1));
    });

    test('a book the reader removed stays removed', () async {
      await phone.library.remove('w1');
      await phone.queue.enqueue([book('k')]);
      await runner(phone).run();
      expect(await phone.library.watchEntry('w1').first, isNull);
    });
  });

  group('reimporting', () {
    test('the same file adds nothing and looks nothing up', () async {
      final b = book('k', finishedOn: [DateTime(2021, 3, 4, 12)], undated: 1);
      await phone.queue.enqueue([b]);
      await runner(phone).run();
      final firstLookups = catalog.lookups;
      final outbox = (await phone.db.select(phone.db.outboxEntries).get()).length;

      expect(await phone.queue.enqueue([b]), 0);
      await runner(phone).run();
      expect(catalog.lookups, firstLookups);
      expect(await reads(phone, 'w1'), hasLength(2));
      expect((await phone.db.select(phone.db.outboxEntries).get()).length, outbox);
    });

    test('on a second device there are still no duplicates', () async {
      final tablet = Device(remote, now);
      addTearDown(tablet.close);
      await phone.library.attachSync(phone.engine);
      await tablet.library.attachSync(tablet.engine);
      final b = book('k', finishedOn: [DateTime(2021, 3, 4, 12)], undated: 1);

      // Both import offline, then sync.
      phone.engine.setOnline(false);
      tablet.engine.setOnline(false);
      await phone.queue.enqueue([b]);
      await tablet.queue.enqueue([b]);
      await runner(phone).run();
      await runner(tablet).run();
      for (final d in [phone, tablet, phone, tablet]) {
        d.engine.setOnline(true);
        await d.engine.flush();
        await settle();
      }

      for (final d in [phone, tablet]) {
        expect(await reads(d, 'w1'), hasLength(2));
        expect(await d.library.watchAllProgress().first, hasLength(1));
        expect(await d.library.watchEntries().first, hasLength(1));
      }
    });

    test('books that did not match before get another chance', () async {
      final b = book('k', isbn: '9999999999');
      await phone.queue.enqueue([b]);
      await runner(phone).run();
      expect((await phone.queue.watchProgress().first).unmatched, ['Book']);

      catalog.worksByIsbn['9999999999'] = workFor('w9');
      expect(await phone.queue.enqueue([b]), 1);
      await runner(phone).run();
      expect(await phone.library.watchEntry('w9').first, isNotNull);
      expect((await phone.queue.watchProgress().first).unmatched, isEmpty);
    });
  });

  group('large and interrupted imports', () {
    List<ImportedBook> many(int n) {
      for (var i = 0; i < n; i++) {
        catalog.worksByIsbn['isbn$i'] = workFor('work$i');
      }
      return [
        for (var i = 0; i < n; i++)
          book('k$i', isbn: 'isbn$i', finishedOn: [DateTime(2020, 1, 1 + i % 28, 12)]),
      ];
    }

    test(
      '1,000 rows complete, and a restart mid-way resumes without duplicates',
      () async {
        await phone.queue.enqueue(many(1000));

        // First run stops part way, as if the app were closed.
        final first = runner(phone);
        var seen = 0;
        final sub = phone.queue.watchProgress().listen((p) {
          seen = p.done;
          if (seen >= 300) first.dispose();
        });
        await first.run();
        await sub.cancel();
        final partial = await phone.queue.watchProgress().first;
        expect(partial.done, greaterThanOrEqualTo(300));
        expect(partial.pending, greaterThan(0));

        await runner(phone).run();
        final p = await phone.queue.watchProgress().first;
        expect(p.done, 1000);
        expect(p.pending, 0);
        expect(await phone.library.watchEntries().first, hasLength(1000));
        expect(await phone.library.watchAllReadThroughs().first, hasLength(1000));
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );

    test('a rate limit pauses for a minute, then carries on', () async {
      await phone.queue.enqueue(many(2));
      catalog.failWith = const RateLimitedFailure('x');
      final waits = <Duration>[];
      final r = ImportRunner(
        queue: phone.queue,
        catalog: catalog,
        library: phone.library,
        wait: (p) async {
          waits.add(p);
          catalog.failWith = null;
        },
      );
      await r.run();
      expect(waits, [r.rateLimitPause]);
      expect((await phone.queue.watchProgress().first).done, 2);
    });

    test('repeated failures wait longer, up to the limit, and success resets', () async {
      await phone.queue.enqueue(many(2));
      catalog.failWith = const NetworkFailure('x');
      final waits = <Duration>[];
      final r = ImportRunner(
        queue: phone.queue,
        catalog: catalog,
        library: phone.library,
        wait: (p) async {
          waits.add(p);
          if (waits.length == 6) catalog.failWith = null;
        },
      );
      await r.run();
      expect(waits.map((d) => d.inSeconds), [30, 60, 120, 240, 300, 300]);
      expect((await phone.queue.watchProgress().first).done, 2);
    });

    test('offline: everything stays queued and nothing is reported unmatched', () async {
      await phone.queue.enqueue(many(2));
      catalog.failWith = const NetworkFailure('x');
      final waits = <Duration>[];
      late ImportRunner r;
      r = ImportRunner(
        queue: phone.queue,
        catalog: catalog,
        library: phone.library,
        wait: (p) async {
          waits.add(p);
          r.dispose(); // the app closes while waiting
        },
      );
      await r.run();
      expect(waits, [r.firstRetryPause]);
      final p = await phone.queue.watchProgress().first;
      expect(p.pending, 2);
      expect(p.unmatched, isEmpty);
    });

    test('a catalog that throws is contained and retried, never lost', () async {
      await phone.queue.enqueue(many(1));
      final r = ImportRunner(
        queue: phone.queue,
        catalog: _ThrowingCatalog(),
        library: phone.library,
        wait: (p) async => throw StateError('stop'),
      );
      await r.run(); // must not throw
      expect((await phone.queue.watchProgress().first).pending, 1);
    });

    test('run() joins a run already going', () async {
      await phone.queue.enqueue(many(3));
      final r = runner(phone);
      await Future.wait([r.run(), r.run(), r.run()]);
      expect(catalog.lookups, 3);
    });

    test('an empty queue does nothing', () async {
      await runner(phone).run();
      expect(catalog.lookups, 0);
    });
  });
}

class _ThrowingCatalog extends FakeCatalogRepository {
  @override
  Future<Result<WorkLookup>> lookupIsbn(String isbn) => throw StateError('boom');
}
