import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/sync/sync_engine.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/goals/data/lww_goal_repository.dart';
import 'package:chapter/features/goals/domain/goal.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/notes/data/lww_notes_repository.dart';
import 'package:chapter/features/notes/domain/note.dart';
import 'package:chapter/features/reading/domain/reading_session.dart';
import 'package:chapter/features/reading/domain/session_clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_sync_remote.dart';

const uid = 'u1';

class Device {
  Device(this.remote, DateTime start) : clock = FakeClock(start) {
    db = AppDatabase(NativeDatabase.memory());
    store = LwwStore(db: db, clock: clock, ids: const UuidV7Generator());
    engine = SyncEngine(
      db: db,
      store: store,
      remote: remote,
      backoff: (_) => const Duration(hours: 1),
    )..start();
    notes = LwwNotesRepository(
      store: store,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: () {},
    );
    goals = LwwGoalRepository(
      store: store,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: () {},
    );
    library = LwwLibraryRepository(
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
  late final LwwNotesRepository notes;
  late final LwwGoalRepository goals;
  late final LwwLibraryRepository library;

  Future<void> attach() async {
    await notes.attachSync(engine);
    await goals.attachSync(engine);
    await library.attachSync(engine);
  }

  Future<List<Note>> notesOf(String work) => notes.watchNotes(work).first;

  Future<void> close() async {
    await engine.dispose();
    await db.close();
  }
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final t0 = DateTime.utc(2026, 11, 5, 12);
  late FakeSyncRemote remote;
  late Device phone;
  late Device tablet;

  setUp(() async {
    remote = FakeSyncRemote();
    phone = Device(remote, t0);
    tablet = Device(remote, t0);
    await phone.attach();
    await tablet.attach();
  });

  tearDown(() async {
    await phone.close();
    await tablet.close();
  });

  Future<void> syncBoth() async {
    phone.engine.setOnline(true);
    tablet.engine.setOnline(true);
    await phone.engine.flush();
    await settle();
    await tablet.engine.flush();
    await settle();
    await phone.engine.flush();
    await settle();
    await tablet.engine.flush();
    await settle();
  }

  group('notes', () {
    test('add, edit and delete offline, and sync to the other device', () async {
      phone.engine.setOnline(false);
      final id = (await phone.notes.add(
        workId: 'w',
        text: '  A line I liked  ',
        kind: NoteKind.quote,
        page: 42,
      ))!;
      var n = (await phone.notesOf('w')).single;
      expect(n.text, 'A line I liked');
      expect(n.kind, NoteKind.quote);
      expect(n.page, 42);

      await phone.notes.edit(id, text: 'A line I loved', kind: NoteKind.quote, page: 43);
      await syncBoth();
      n = (await tablet.notesOf('w')).single;
      expect(n.text, 'A line I loved');
      expect(n.page, 43);

      await tablet.notes.delete(id);
      await syncBoth();
      expect(await phone.notesOf('w'), isEmpty);
    });

    test('empty and oversized text are rejected', () async {
      expect(await phone.notes.add(workId: 'w', text: '   '), isNull);
      expect(
        await phone.notes.add(workId: 'w', text: 'x' * (NoteFields.maxTextLength + 1)),
        isNull,
      );
      final id = (await phone.notes.add(workId: 'w', text: 'ok'))!;
      expect(await phone.notes.edit(id, text: ''), isFalse);
      expect((await phone.notesOf('w')).single.text, 'ok');
    });

    test('edits on two devices offline: both texts survive, one copy, same everywhere', () async {
      final id = (await phone.notes.add(workId: 'w', text: 'original'))!;
      await syncBoth();

      phone.engine.setOnline(false);
      tablet.engine.setOnline(false);
      phone.clock.advance(const Duration(minutes: 1));
      tablet.clock.advance(const Duration(minutes: 5)); // later, so it wins
      await phone.notes.edit(id, text: 'phone version');
      await tablet.notes.edit(id, text: 'tablet version');
      await syncBoth();

      for (final d in [phone, tablet]) {
        final list = await d.notesOf('w');
        expect(list.map((n) => n.text).toSet(), {'tablet version', 'phone version'});
        expect(list, hasLength(2), reason: 'exactly one conflict copy');
        final main = list.singleWhere((n) => n.id == id);
        expect(main.text, 'tablet version');
        final copy = list.singleWhere((n) => n.id != id);
        expect(copy.isConflictCopy, isTrue);
        expect(copy.conflictOf, id);
      }
    });

    test('the same conflict in the other push order also keeps both', () async {
      final id = (await phone.notes.add(workId: 'w', text: 'original'))!;
      await syncBoth();
      phone.engine.setOnline(false);
      tablet.engine.setOnline(false);
      phone.clock.advance(const Duration(minutes: 5)); // phone wins this time
      tablet.clock.advance(const Duration(minutes: 1));
      await phone.notes.edit(id, text: 'phone version');
      await tablet.notes.edit(id, text: 'tablet version');

      tablet.engine.setOnline(true); // the loser reaches the server first
      await tablet.engine.flush();
      await settle();
      await syncBoth();

      for (final d in [phone, tablet]) {
        final list = await d.notesOf('w');
        expect(list.map((n) => n.text).toSet(), {'tablet version', 'phone version'});
        expect(list, hasLength(2));
        expect(list.singleWhere((n) => n.id == id).text, 'phone version');
      }
    });

    test('ordinary back-and-forth edits never create a copy', () async {
      final id = (await phone.notes.add(workId: 'w', text: 'v1'))!;
      await syncBoth();
      await tablet.notes.edit(id, text: 'v2');
      await syncBoth();
      await phone.notes.edit(id, text: 'v3');
      await syncBoth();
      await tablet.notes.edit(id, text: 'v4');
      await tablet.notes.edit(id, text: 'v5');
      await syncBoth();
      for (final d in [phone, tablet]) {
        expect((await d.notesOf('w')).single.text, 'v5');
      }
    });

    test('a device that missed several edits does not see a false conflict', () async {
      final id = (await phone.notes.add(workId: 'w', text: 'v1'))!;
      await syncBoth();
      tablet.engine.setOnline(false);
      await phone.notes.edit(id, text: 'v2');
      await phone.notes.edit(id, text: 'v3');
      await phone.notes.edit(id, text: 'v4');
      await syncBoth();
      expect((await tablet.notesOf('w')).single.text, 'v4');
    });
  });

  group('ratings and reviews', () {
    setUp(
      () => phone.library.add(
        workId: 'w',
        book: const BookSummary(title: 'T'),
      ),
    );

    test('only half-star steps from 0.5 to 5 are accepted', () async {
      for (final bad in [0.0, 0.25, 5.5, -1.0, 3.3, double.nan]) {
        expect(await phone.library.setRating('w', bad), isFalse, reason: '$bad');
      }
      expect(await phone.library.setRating('w', 4.5), isTrue);
      expect((await phone.library.watchEntry('w').first)!.rating, 4.5);
      expect(await phone.library.setRating('w', null), isTrue);
      expect((await phone.library.watchEntry('w').first)!.rating, isNull);
    });

    test('rating on one device and review on another both survive', () async {
      await syncBoth();
      phone.engine.setOnline(false);
      tablet.engine.setOnline(false);
      await phone.library.setRating('w', 4);
      await tablet.library.setReview('w', '  Loved it  ');
      await syncBoth();
      for (final d in [phone, tablet]) {
        final e = (await d.library.watchEntry('w').first)!;
        expect(e.rating, 4);
        expect(e.review, 'Loved it');
      }
    });

    test('an empty review clears it; a huge one is refused', () async {
      await phone.library.setReview('w', 'x');
      await phone.library.setReview('w', '   ');
      expect((await phone.library.watchEntry('w').first)!.review, isNull);
      expect(await phone.library.setReview('w', 'x' * (LibraryEntry.maxReviewLength + 1)), isFalse);
    });
  });

  group('goals', () {
    test('sync, edit without disturbing others, delete, work offline', () async {
      phone.engine.setOnline(false);
      final (start, end) = Goal.yearRange(2026);
      final a = (await phone.goals.create(
        metric: GoalMetric.books,
        period: GoalPeriod.year,
        start: start,
        end: end,
        target: 24,
      ))!;
      final (ms, me) = Goal.monthRange(2025, 3);
      await phone.goals.create(
        metric: GoalMetric.pages,
        period: GoalPeriod.month,
        start: ms,
        end: me,
        target: 500,
      );
      await syncBoth();
      var list = await tablet.goals.watchGoals().first;
      expect(list.map((g) => g.id).first, a, reason: 'newest period first');
      expect(list, hasLength(2));

      await tablet.goals.update(list.first, target: 30);
      await syncBoth();
      list = await phone.goals.watchGoals().first;
      expect(list.first.target, 30);
      expect(list.last.target, 500, reason: 'history untouched');

      await phone.goals.delete(a);
      await syncBoth();
      expect(await tablet.goals.watchGoals().first, hasLength(1));
    });

    test('invalid goals are refused', () async {
      expect(
        await phone.goals.create(
          metric: GoalMetric.books,
          period: GoalPeriod.custom,
          start: '2026-02-01',
          end: '2026-01-01',
          target: 1,
        ),
        isNull,
      );
      expect(
        await phone.goals.create(
          metric: GoalMetric.books,
          period: GoalPeriod.custom,
          start: '2026-01-01',
          end: '2026-02-01',
          target: 0,
        ),
        isNull,
      );
    });

    test('ended and upcoming are judged by local date', () {
      const g = Goal(
        id: 'g',
        metric: GoalMetric.books,
        period: GoalPeriod.month,
        start: '2026-11-01',
        end: '2026-11-30',
        target: 1,
      );
      expect(g.isEnded('2026-11-30'), isFalse);
      expect(g.isEnded('2026-12-01'), isTrue);
      expect(g.isUpcoming('2026-10-31'), isTrue);
      expect(g.isUpcoming('2026-11-01'), isFalse);
    });
  });

  group('deleting a session', () {
    Future<ReadingSession> saveOn(Device d) async {
      await d.library.add(
        workId: 'w',
        book: const BookSummary(title: 'T', pageCount: 100),
      );
      await d.library.setStatus('w', ReadingStatus.reading);
      return (await d.library.completeSession(
        ActiveSession(
          id: 's1',
          workId: 'w',
          clock: SessionClock.start(
            t0,
            const Duration(minutes: 30),
          ).end(t0.add(const Duration(minutes: 30))),
        ),
        activeDurationSec: 1800,
      ))!;
    }

    test('disappears from lists on both devices', () async {
      await saveOn(phone);
      await syncBoth();
      expect(await tablet.library.watchSessions().first, hasLength(1));
      await tablet.library.deleteSession('s1');
      await syncBoth();
      expect(await phone.library.watchSessions().first, isEmpty);
      expect(await tablet.library.watchSessions().first, isEmpty);
      expect(await phone.library.watchDeletedSessionIds().first, {'s1'});
    });

    test('a tombstone that arrives first still wins', () async {
      final session = await saveOn(phone);
      expect(session.id, 's1');
      // The tablet hears about the deletion before the session itself.
      await tablet.library.deleteSession('s1');
      await tablet.engine.flush();
      await settle();
      await syncBoth();
      expect(await tablet.library.watchSessions().first, isEmpty);
      expect(await phone.library.watchSessions().first, isEmpty);
    });

    test('the list updates live when a session is deleted', () async {
      await saveOn(phone);
      final emitted = expectLater(
        phone.library.watchSessions().map((l) => l.length),
        emitsThrough(0),
      );
      await phone.library.deleteSession('s1');
      await emitted;
    });
  });
}
