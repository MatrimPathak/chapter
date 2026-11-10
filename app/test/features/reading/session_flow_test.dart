import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:chapter/features/reading/data/drift_active_session_store.dart';
import 'package:chapter/features/reading/domain/reading_session.dart';
import 'package:chapter/features/reading/domain/session_clock.dart';
import 'package:chapter/features/reading/domain/session_ports.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_catalog.dart';
import '../../helpers/fake_session_ports.dart';
import '../../helpers/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final t0 = DateTime(2026, 11, 4, 9);
  late AppDatabase db;
  late FakeClock clock;
  late FakeSessionNotifications notifications;
  late FakeFocusMode focus;
  final uid = FakeAuthRepository.testUser.uid;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close); // runs after each test's unmount (LIFO)
    clock = FakeClock(t0);
    notifications = FakeSessionNotifications();
    focus = FakeFocusMode();
    final repo = LwwLibraryRepository(
      store: LwwStore(db: db, clock: clock, ids: const UuidV7Generator()),
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: () {},
    );
    await repo.add(
      workId: theDeal.id,
      book: const BookSummary(title: 'The Deal', authorNames: ['Elle Kennedy'], pageCount: 374),
      status: ReadingStatus.reading,
      edition: UserEdition(
        editionId: 'e1',
        workId: theDeal.id,
        format: 'paperback',
        pageCount: 374,
      ),
    );
    await repo.recordProgress(theDeal.id, const ReadingPosition.page(page: 100));
    await repo.add(
      workId: 'want-to-read-book',
      book: const BookSummary(title: 'Later', authorNames: ['Someone'], pageCount: 200),
    );
  });

  Future<void> launch(WidgetTester tester) async {
    await pumpChapterApp(
      tester,
      auth: FakeAuthRepository(initialUser: FakeAuthRepository.testUser),
      catalog: FakeCatalogRepository(),
      clock: clock,
      database: db,
      notifications: notifications,
      focus: focus,
    );
    addTearDown(() => unmountApp(tester)); // so a failure can't hang the next test
    await tester.tap(find.text('Start reading')); // onboarding
    await settle(tester);
  }

  testWidgets('Read tab offers only books in Reading', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Reading').last);
    await settle(tester);
    expect(find.byKey(ValueKey('read-book-${theDeal.id}')), findsOneWidget);
    expect(find.byKey(const ValueKey('read-book-want-to-read-book')), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('Read tab: start, pause, end, edit the summary and save', (tester) async {
    tester.view.physicalSize = const Size(1080, 6000);
    addTearDown(tester.view.reset);
    await launch(tester);
    await tester.tap(find.text('Reading').last);
    await settle(tester);
    expect(find.text('What are you reading?'), findsOneWidget);
    await tester.ensureVisible(find.text('20 min'));
    await tester.tap(find.text('20 min'));
    await tester.pump();
    await tester.ensureVisible(find.byKey(const Key('read-start')));
    await tester.tap(find.byKey(const Key('read-start')));
    await settle(tester);

    expect(find.byKey(const Key('session-remaining')), findsOneWidget);
    expect(find.text('20:00'), findsOneWidget);
    expect(
      notifications.scheduledEnd!.isAtSameMomentAs(t0.add(const Duration(minutes: 20))),
      isTrue,
    );

    clock.advance(const Duration(minutes: 8));
    await tester.pump(const Duration(seconds: 1)); // repaint tick
    await settle(tester);
    expect(find.text('12:00'), findsOneWidget);

    await tester.tap(find.text('Pause'));
    await settle(tester);
    expect(find.text('Paused'), findsOneWidget);
    expect(notifications.scheduledEnd, isNull);
    clock.advance(const Duration(minutes: 30)); // a long pause doesn't count
    await tester.tap(find.text('Resume'));
    await tester.pump(const Duration(seconds: 1));
    await settle(tester);
    expect(find.text('12:00'), findsOneWidget);

    clock.advance(const Duration(minutes: 2));
    await tester.tap(find.text('End session'));
    await settle(tester);
    await tester.tap(find.text('End session').last); // confirm
    await settle(tester);

    expect(find.widgetWithText(AppBar, 'Session summary'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('summary-minutes'))).controller!.text,
      '10',
    );
    await tester.enterText(find.byKey(const Key('progress-input')), '130');
    await settle(tester);
    expect(find.text('30 pages'), findsOneWidget);
    await tester.ensureVisible(find.text('Save session'));
    await tester.tap(find.text('Save session'));
    await settle(tester);

    expect(find.text('Session saved'), findsOneWidget);
    expect(find.text('Recent sessions'), findsOneWidget);
    expect(find.textContaining('10 min'), findsOneWidget);
    expect(notifications.ongoing, isFalse);

    // The book page lists the session too.
    await tester.tap(find.text('Home'));
    await settle(tester);
    await tester.tap(find.text('The Deal').first);
    await settle(tester);
    expect(find.text('Sessions', skipOffstage: false), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('relaunch after the timer ran out opens a recovered summary', (tester) async {
    final store = DriftActiveSessionStore(db, clock);
    await store.write(
      ActiveSession(
        id: '019a0000-0000-7000-8000-000000000001',
        workId: theDeal.id,
        editionId: 'e1',
        clock: SessionClock.start(
          t0.subtract(const Duration(hours: 2)),
          const Duration(minutes: 30),
        ),
        startPosition: const ReadingPosition.page(page: 100),
        startFraction: 100 / 374,
        dndPreviousFilter: 1,
      ),
    );
    focus
      ..filter =
          2 // DND was left on when the app died
      ..applied = true;

    await launch(tester);
    expect(find.widgetWithText(AppBar, 'Session summary'), findsOneWidget);
    expect(find.textContaining('finished while Chapter was closed'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byKey(const Key('summary-minutes'))).controller!.text,
      '30',
    );
    expect(focus.filter, 1, reason: 'DND restored on recovery');
    // The position form knows the paperback's page count (it waited for the edition).
    expect(find.text('Page'), findsOneWidget);
    expect(find.text('/ 374'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('relaunch mid-session resumes the timer exactly', (tester) async {
    final store = DriftActiveSessionStore(db, clock);
    await store.write(
      ActiveSession(
        id: '019a0000-0000-7000-8000-000000000002',
        workId: theDeal.id,
        clock: SessionClock.start(
          t0.subtract(const Duration(minutes: 11, seconds: 30)),
          const Duration(minutes: 45),
        ),
      ),
    );
    await launch(tester);
    expect(find.text('33:30'), findsOneWidget);
    expect(
      notifications.scheduledEnd!.isAtSameMomentAs(
        t0.add(const Duration(minutes: 33, seconds: 30)),
      ),
      isTrue,
    );
    await unmountApp(tester);
  });

  testWidgets('Home Read starts a session with the last-used duration', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Read').first); // Continue Reading card action
    await settle(tester);
    expect(find.text('30:00'), findsOneWidget, reason: 'default 30-minute timer');

    await tester.pageBack();
    await settle(tester);
    expect(find.byKey(const Key('active-session-bar')), findsOneWidget);
    await tester.tap(find.text('Reading').last);
    await settle(tester);
    expect(find.text('Session in progress'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('custom duration dialog sets the timer', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Reading').last);
    await settle(tester);
    await tester.ensureVisible(find.text('Custom'));
    await tester.tap(find.text('Custom'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('custom-minutes')), '1');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('1 min'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('read-start')));
    await tester.tap(find.byKey(const Key('read-start')));
    await settle(tester);
    expect(find.text('01:00'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('Android focus mode explains and only opens settings on a tap', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    focus.accessState = FocusAccess.denied;
    await launch(tester);
    await tester.tap(find.text('Reading').last);
    await settle(tester);
    // The page's own list, not the sideways row of books.
    final page = find.byWidgetPredicate((w) => w is Scrollable && w.axis == Axis.vertical).first;
    await tester.scrollUntilVisible(
      find.text('Do Not Disturb while reading'),
      200,
      scrollable: page,
    );
    await tester.ensureVisible(find.text('Do Not Disturb while reading'));
    await tester.pump();
    await tester.tap(find.text('Do Not Disturb while reading'));
    await tester.pump();
    await tester.scrollUntilVisible(find.byKey(const Key('read-start')), 200, scrollable: page);
    await tester.ensureVisible(find.byKey(const Key('read-start')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('read-start')));
    await settle(tester);

    expect(find.text('Allow Do Not Disturb access'), findsOneWidget);
    expect(focus.openedSettings, 0);
    await tester.tap(find.text('Open settings'));
    await settle(tester);
    expect(focus.openedSettings, 1);
    expect(focus.filter, 1, reason: 'nothing changed without access');

    // Access granted later: turning it on from the timer works and is undone on end.
    focus.accessState = FocusAccess.granted;
    await tester.tap(find.text('Turn on Do Not Disturb'));
    await settle(tester);
    expect(focus.filter, 2);
    expect(find.text('Do Not Disturb is on'), findsOneWidget);
    await tester.tap(find.text('End session'));
    await settle(tester);
    await tester.tap(find.text('End session').last);
    await settle(tester);
    expect(focus.filter, 1);
    await unmountApp(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}
