import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/progress/domain/progress_event.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:chapter/features/reading/application/session_service.dart';
import 'package:chapter/features/reading/data/drift_active_session_store.dart';
import 'package:chapter/features/reading/domain/reading_session.dart';
import 'package:chapter/features/reading/domain/session_clock.dart';
import 'package:chapter/features/reading/domain/session_ports.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_session_ports.dart';

const book = BookSummary(title: 'The Deal', authorNames: ['Elle Kennedy'], pageCount: 400);
const kindle = UserEdition(editionId: 'e1', workId: 'w1', format: 'kindle', pageCount: 400);

void main() {
  final t0 = DateTime.utc(2026, 11, 4, 20);
  late AppDatabase db;
  late FakeClock clock;
  late LwwLibraryRepository library;
  late FakeSessionNotifications notifications;
  late FakeFocusMode focus;

  /// A fresh service over the same database = an app relaunch.
  SessionService launch() => SessionService(
    store: DriftActiveSessionStore(db, clock),
    library: library,
    notifications: notifications,
    focus: focus,
    clock: clock,
    ids: const UuidV7Generator(),
  );

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    clock = FakeClock(t0);
    library = LwwLibraryRepository(
      store: LwwStore(db: db, clock: clock, ids: const UuidV7Generator()),
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: 'u1',
      onLocalWrite: () {},
    );
    notifications = FakeSessionNotifications();
    focus = FakeFocusMode();
    await library.add(workId: 'w1', book: book, edition: kindle);
    await library.recordProgress('w1', const ReadingPosition.page(page: 100));
  });

  tearDown(() => db.close());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('start records the starting position and arms the end notification', () async {
    final s = await launch().start(workId: 'w1', planned: const Duration(minutes: 30));
    await settle();
    expect(s.startPosition, const ReadingPosition.page(page: 100));
    expect(s.startFraction, 0.25);
    expect(notifications.scheduledEnd, t0.add(const Duration(minutes: 30)));
    await expectLater(
      launch().start(workId: 'w1', planned: const Duration(minutes: 5)),
      throwsStateError,
    );
  });

  test('pause cancels the end time, resume moves it by the pause', () async {
    final svc = launch();
    var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 30));
    await settle();
    clock.advance(const Duration(minutes: 10));
    s = await svc.pause(s);
    expect(notifications.scheduledEnd, isNull);
    clock.advance(const Duration(minutes: 5));
    s = await svc.resume(s);
    expect(notifications.scheduledEnd, t0.add(const Duration(minutes: 35)));
  });

  group('recovery after the app is killed', () {
    test('a running session resumes with the exact elapsed time', () async {
      final s = await launch().start(workId: 'w1', planned: const Duration(hours: 2));
      await launch().pause(s.copyWith()); // persisted pause at t0
      clock.advance(const Duration(minutes: 7));
      final relaunched = await launch().load();
      expect(relaunched!.clock.state, ClockState.paused);
      final resumed = await launch().resume(relaunched);
      clock.advance(const Duration(minutes: 93, seconds: 1));
      expect(resumed.clock.elapsed(clock.now()), const Duration(minutes: 93, seconds: 1));
      expect(notifications.scheduledEnd, isNotNull);
    });

    test('an overdue session ends at its planned end as recovered', () async {
      focus.filter = 1;
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 20));
      (s, _) = await svc.enableFocus(s);
      expect(focus.filter, 2);

      clock.advance(const Duration(hours: 6)); // app was dead
      final r = (await launch().load())!;
      expect(r.isEnded, isTrue);
      expect(r.recovered, isTrue);
      expect(r.completion, SessionCompletion.recovered);
      expect(r.clock.endedAt, t0.add(const Duration(minutes: 20)));
      expect(focus.filter, 1, reason: 'DND restored on recovery');
      expect(notifications.ongoing, isFalse);
    });

    test('an ended but unsaved session reopens for the summary', () async {
      final svc = launch();
      final s = await svc.start(workId: 'w1', planned: const Duration(minutes: 20));
      clock.advance(const Duration(minutes: 12));
      await svc.end(s);
      expect(notifications.completedShown, isFalse, reason: 'ending early is silent');
      final r = (await launch().load())!;
      expect(r.isEnded, isTrue);
      expect(r.completion, SessionCompletion.endedEarly);
      expect(r.clock.elapsed(clock.now()), const Duration(minutes: 12));
    });
  });

  group('summary', () {
    test('save writes session, progress event and clears the live row atomically', () async {
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 30));
      clock.advance(const Duration(minutes: 30));
      s = await svc.checkOverdue(s);
      expect(s.isEnded, isTrue);
      expect(s.completion, SessionCompletion.completed);
      expect(notifications.completedShown, isTrue, reason: 'running out alerts the reader');
      expect(notifications.ongoing, isFalse);

      // The reader edits the time (read 25 of the 30 minutes) and the page.
      final saved = (await svc.save(
        s,
        readingTime: const Duration(minutes: 25),
        endPosition: const ReadingPosition.page(page: 140),
      ))!;
      expect(saved.activeDurationSec, 1500);
      expect(saved.pagesRead, 40);
      expect(saved.pagesPerHour, closeTo(96, 1e-9));
      expect(await launch().load(), isNull);

      final sessions = await library.watchSessions(workId: 'w1').first;
      expect(sessions.single.id, s.id);
      final entry = (await library.watchEntry('w1').first)!;
      final latest = (await library.watchLatestProgress().first)[entry.activeReadThroughId]!;
      expect(latest.fraction, 0.35);
      expect(latest.source, ProgressSource.session);
      expect(latest.sessionId, s.id);

      final rows = await db.select(db.outboxEntries).get();
      final batch = rows.where((r) => r.batchId == rows.last.batchId).map((r) => r.docPath);
      expect(
        batch,
        containsAll(['users/u1/sessions/${s.id}', 'users/u1/progressEvents/${latest.id}']),
      );
    });

    test('saving without a new position still records the session', () async {
      final svc = launch();
      final s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      clock.advance(const Duration(minutes: 4));
      final saved = (await svc.save(s, readingTime: const Duration(minutes: 4)))!;
      expect(saved.completion, SessionCompletion.endedEarly);
      expect(saved.endPosition, isNull);
      expect(await library.watchSessions().first, hasLength(1));
    });

    test('discard leaves nothing behind and restores DND', () async {
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      (s, _) = await svc.enableFocus(s);
      final outboxBefore = (await db.select(db.outboxEntries).get()).length;
      await svc.discard(s);
      expect(await launch().load(), isNull);
      expect(await library.watchSessions().first, isEmpty);
      expect((await db.select(db.outboxEntries).get()).length, outboxBefore);
      expect(focus.filter, 1);
    });
  });

  group('focus mode', () {
    test('a restore is scheduled at the planned end, for when the app is dead', () async {
      var s = await launch().start(workId: 'w1', planned: const Duration(minutes: 15));
      expect(focus.scheduledRestore, isNull, reason: 'nothing without focus mode');
      (s, _) = await launch().enableFocus(s);
      expect(focus.scheduledRestore!.$1, 1);
      expect(
        focus.scheduledRestore!.$2.isAtSameMomentAs(t0.add(const Duration(minutes: 15))),
        isTrue,
      );

      // The app dies, the platform alarm fires, and DND is back with no Dart running.
      clock.advance(const Duration(minutes: 15));
      await focus.fireScheduledRestore();
      expect(focus.filter, 1);

      // The reader turns DND on themselves; the later relaunch leaves it alone.
      focus.filter = 2;
      final r = (await launch().load())!;
      expect(r.recovered, isTrue);
      expect(focus.filter, 2);
    });

    test('pausing moves the restore; resuming after the limit turns DND back on', () async {
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      (s, _) = await svc.enableFocus(s);
      clock.advance(const Duration(minutes: 5));
      s = await svc.pause(s);
      final limit = t0.add(
        const Duration(minutes: 5) +
            const Duration(minutes: 10) +
            SessionService.pausedRestoreLimit,
      );
      expect(focus.scheduledRestore!.$2.isAtSameMomentAs(limit), isTrue);

      clock.advance(const Duration(hours: 2));
      await focus.fireScheduledRestore();
      expect(focus.filter, 1, reason: 'a forgotten pause does not hold DND forever');

      s = await svc.resume(s);
      expect(focus.filter, 2);
      expect(s.dndPreviousFilter, 1);
      final end = t0.add(const Duration(hours: 2, minutes: 15));
      expect(focus.scheduledRestore!.$2.isAtSameMomentAs(end), isTrue);
      await svc.end(s);
      expect(focus.filter, 1);
      expect(focus.scheduledRestore, isNull);
    });

    test('DND the reader already had on is never taken over', () async {
      focus.filter = 2;
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      (s, _) = await svc.enableFocus(s);
      await svc.end(s);
      expect(focus.filter, 2);
      expect(focus.applied, isFalse);
    });

    test('a reader who changes DND during the session keeps their change', () async {
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      (s, _) = await svc.enableFocus(s);
      focus.filter = 3; // alarms only, chosen in system settings
      await svc.end(s);
      expect(focus.filter, 3);
    });

    test('DND is back before the end alert, so the alert is not silenced', () async {
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      (s, _) = await svc.enableFocus(s);
      int? filterAtAlert;
      notifications.onCompleted = () => filterAtAlert = focus.filter;
      clock.advance(const Duration(minutes: 15));
      await svc.checkOverdue(s);
      expect(filterAtAlert, 1);
    });

    test('relaunching an unsaved session never re-applies an old DND setting', () async {
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      (s, _) = await svc.enableFocus(s);
      await svc.end(s);
      focus.filter = 3; // the reader changes DND themselves afterwards
      final r = (await launch().load())!;
      expect(r.isEnded, isTrue);
      expect(r.focusModeOn, isFalse);
      expect(focus.filter, 3);
    });

    test('a notification failure never blocks restoring DND or saving', () async {
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      (s, _) = await svc.enableFocus(s);
      notifications.failWith = StateError('notifications unavailable');
      s = await svc.end(s);
      expect(focus.filter, 1);
      expect(await svc.save(s, readingTime: Duration.zero), isNotNull);
    });

    test('DND is restored when the session ends', () async {
      focus.filter = 1;
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      final (next, result) = await svc.enableFocus(s);
      s = next;
      expect(result, FocusResult.enabled);
      expect(focus.filter, 2);
      await svc.end(s);
      expect(focus.filter, 1);
    });

    test('a user who already had DND on gets their own setting back', () async {
      focus.filter = 3; // e.g. alarms only, set by the user
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      (s, _) = await svc.enableFocus(s);
      await svc.end(s);
      expect(focus.filter, 3);
    });

    test('denied access or an unsupported platform never changes anything', () async {
      final svc = launch();
      final s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      focus.accessState = FocusAccess.denied;
      expect((await svc.enableFocus(s)).$2, FocusResult.needsAccess);
      focus.accessState = FocusAccess.unsupported;
      expect((await svc.enableFocus(s)).$2, FocusResult.unsupported);
      expect(focus.filter, 1);
      expect(focus.openedSettings, 0, reason: 'settings only open on an explicit tap');
    });

    test('a failure while enabling leaves DND untouched', () async {
      final svc = launch();
      final s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      focus.throwOnEnable = true;
      final (after, result) = await svc.enableFocus(s);
      expect(result, FocusResult.failed);
      expect(after.focusModeOn, isFalse);
      expect(focus.filter, 1);
    });

    test('turning focus off mid-session restores immediately', () async {
      final svc = launch();
      var s = await svc.start(workId: 'w1', planned: const Duration(minutes: 15));
      (s, _) = await svc.enableFocus(s);
      s = await svc.disableFocus(s);
      expect(focus.filter, 1);
      expect(s.focusModeOn, isFalse);
      await svc.end(s);
      expect(focus.filter, 1);
    });
  });
}
