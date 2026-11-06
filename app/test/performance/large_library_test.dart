import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/insights/domain/stats_engine.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/profile/application/data_exporter.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:chapter/features/reading/domain/reading_session.dart';
import 'package:chapter/features/reading/domain/session_clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Figures for docs/01 §6, on this machine, not a phone: they catch regressions
/// and show what is slow. The limits are generous on purpose. `dart test` prints
/// the numbers.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  const books = 2000;
  const eventsPerBook = 5;
  const sessions = 3000;
  final now = DateTime(2026, 11, 5, 9);
  late AppDatabase db;
  late FakeClock clock;
  late LwwLibraryRepository repo;

  setUpAll(() async {
    db = AppDatabase(NativeDatabase.memory());
    clock = FakeClock(now.subtract(const Duration(days: 800)));
    repo = LwwLibraryRepository(
      store: LwwStore(db: db, clock: clock, ids: const UuidV7Generator()),
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: 'u1',
      onLocalWrite: () {},
    );
    final watch = Stopwatch()..start();
    for (var i = 0; i < books; i++) {
      await repo.add(
        workId: 'w$i',
        book: BookSummary(
          title: 'Book number $i',
          authorNames: ['Author ${i % 200}'],
          pageCount: 200 + i % 400,
          genres: ['Genre ${i % 20}'],
        ),
        status: ReadingStatus.reading,
      );
      for (var e = 1; e <= eventsPerBook; e++) {
        clock.advance(const Duration(hours: 1));
        await repo.recordProgress(
          'w$i',
          ReadingPosition.percent(percent: e * 100 / (eventsPerBook + 1)),
        );
      }
    }
    for (var s = 0; s < sessions; s++) {
      final at = now.subtract(Duration(hours: s * 6));
      await repo.completeSession(
        ActiveSession(
          id: 's$s',
          workId: 'w${s % books}',
          clock: SessionClock.start(
            at,
            const Duration(minutes: 30),
          ).end(at.add(const Duration(minutes: 30))),
        ),
        activeDurationSec: 1800,
      );
    }
    // ignore: avoid_print
    print('seeded $books books in ${watch.elapsedMilliseconds} ms');
  });

  tearDownAll(() => db.close());

  Future<int> measure(String name, Future<void> Function() body, {required int limitMs}) async {
    final watch = Stopwatch()..start();
    await body();
    final ms = watch.elapsedMilliseconds;
    // ignore: avoid_print
    print('PERF $name: $ms ms');
    expect(ms, lessThan(limitMs), reason: name);
    return ms;
  }

  test('reading the library', () async {
    await measure(
      'library entries',
      () async => expect(await repo.watchEntries().first, hasLength(books)),
      limitMs: 2000,
    );
    await measure('latest progress', () => repo.watchLatestProgress().first, limitMs: 2000);
    await measure('all editions', () => repo.watchAllEditions().first, limitMs: 2000);
  });

  test('saving progress stays under the 50 ms target', () async {
    final times = <int>[];
    for (var i = 0; i < 100; i++) {
      final watch = Stopwatch()..start();
      await repo.recordProgress('w$i', const ReadingPosition.percent(percent: 90));
      times.add(watch.elapsedMicroseconds);
    }
    times.sort();
    final median = times[times.length ~/ 2] / 1000;
    final p95 = times[(times.length * 0.95).floor()] / 1000;
    // ignore: avoid_print
    print('PERF progress save: median $median ms, p95 $p95 ms');
    expect(median, lessThan(50));
  });

  test('statistics over the whole history', () async {
    late StatsInput input;
    await measure('load statistics input', () async {
      input = StatsInput(
        entries: await repo.watchEntries().first,
        readThroughs: await repo.watchAllReadThroughs().first,
        sessions: await repo.watchSessions(limit: 1 << 30).first,
        events: await repo.watchAllProgress().first,
        editions: await repo.watchAllEditions().first,
      );
    }, limitMs: 5000);
    expect(input.sessions, hasLength(sessions));
    await measure('StatsEngine build', () async {
      StatsEngine(input);
    }, limitMs: 3000);
  });

  test('export', () async {
    await measure('export build', () => DataExporter(db, 'u1', now).build(), limitMs: 10000);
  });
}
