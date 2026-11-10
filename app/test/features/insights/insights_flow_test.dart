import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/goals/data/lww_goal_repository.dart';
import 'package:chapter/features/goals/domain/goal.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:chapter/features/reading/domain/reading_session.dart';
import 'package:chapter/features/reading/domain/session_clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_catalog.dart';
import '../../helpers/test_app.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime(2026, 11, 5, 9);
  late AppDatabase db;
  late FakeClock clock;
  late LwwLibraryRepository repo;
  late LwwGoalRepository goals;
  final uid = FakeAuthRepository.testUser.uid;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    clock = FakeClock(now);
    final store = LwwStore(db: db, clock: clock, ids: const UuidV7Generator());
    repo = LwwLibraryRepository(
      store: store,
      db: db,
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
    await repo.add(
      workId: theDeal.id,
      book: const BookSummary(
        title: 'The Deal',
        authorNames: ['Elle Kennedy'],
        genres: ['Romance'],
        seriesName: 'Off-Campus',
        pageCount: 400,
      ),
      status: ReadingStatus.reading,
    );
  });

  Future<void> saveSession(String id, int minutes, {required DateTime at, int? page}) => repo
      .completeSession(
        ActiveSession(
          id: id,
          workId: theDeal.id,
          clock: SessionClock.start(
            at,
            Duration(minutes: minutes),
          ).end(at.add(Duration(minutes: minutes))),
        ),
        activeDurationSec: minutes * 60,
        endPosition: page == null ? null : ReadingPosition.page(page: page),
      )
      .then((_) {});

  Future<void> launch(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await pumpChapterApp(
      tester,
      auth: FakeAuthRepository(initialUser: FakeAuthRepository.testUser),
      catalog: FakeCatalogRepository(),
      clock: clock,
      database: db,
    );
    addTearDown(() => unmountApp(tester)); // so a failure can't hang the next test
    await tester.tap(find.text('Start reading')); // onboarding
    await settle(tester);
  }

  Future<void> open(WidgetTester tester, String entry) async {
    await tester.tap(find.text('Profile'));
    await settle(tester);
    await tester.tap(find.text(entry));
    await settle(tester);
  }

  testWidgets('Insights with no history is an honest empty state', (tester) async {
    await launch(tester);
    await open(tester, 'Insights');
    expect(find.text('Nothing here yet'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('sparse history: totals yes, conclusions no', (tester) async {
    await saveSession('s1', 30, at: now.subtract(const Duration(hours: 2)), page: 100);
    await launch(tester);
    await open(tester, 'Insights');
    expect(find.text('Books'), findsOneWidget);
    expect(find.text('0.5'), findsOneWidget, reason: 'half an hour');
    expect(find.text('100'), findsOneWidget, reason: 'pages');
    expect(find.text('Not enough data yet', skipOffstage: false), findsWidgets);

    // A day in the calendar explains itself.
    await tester.ensureVisible(find.byKey(const ValueKey('calendar-2026-11-05')));
    await tester.tap(find.byKey(const ValueKey('calendar-2026-11-05')));
    await settle(tester);
    expect(find.text('Nov 5: 30 min · 100 pages'), findsOneWidget);

    // Last month has nothing, and says so without judgement.
    await tester.ensureVisible(find.byKey(const ValueKey('calendar-2026-11-04')));
    await tester.tap(find.byKey(const ValueKey('calendar-2026-11-04')));
    await settle(tester);
    expect(find.text('Nov 4: no reading logged'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('dense history draws every chart and fact', (tester) async {
    // Three finished books over five months, nine sessions, reading days in a row.
    for (final (id, finishedOn) in [
      ('b1', DateTime(2026, 6, 10, 20)),
      ('b2', DateTime(2026, 8, 10, 20)),
      ('b3', DateTime(2026, 10, 10, 20)),
    ]) {
      clock.set(finishedOn);
      await repo.add(
        workId: id,
        book: const BookSummary(
          title: 'Other',
          authorNames: ['Sally Thorne'],
          genres: ['Comedy'],
          pageCount: 300,
        ),
        status: ReadingStatus.reading,
      );
      await repo.setStatus(id, ReadingStatus.read);
    }
    clock.set(now);
    for (var i = 0; i < 9; i++) {
      await saveSession(
        's$i',
        30,
        at: now.subtract(Duration(days: i, hours: 1)),
        page: 100 - i * 10, // i counts back in time, so the page falls with it
      );
    }
    await saveSession('june', 30, at: DateTime(2026, 6, 10, 8));

    await launch(tester);
    tester.view.physicalSize = const Size(1080, 9000); // everything built at once
    await settle(tester);
    await open(tester, 'Insights');
    expect(find.text('Not enough data yet', skipOffstage: false), findsNothing);
    expect(find.text('Sally Thorne', skipOffstage: false), findsOneWidget);
    expect(find.text('Comedy', skipOffstage: false), findsOneWidget);
    expect(find.text('3 books', skipOffstage: false), findsNWidgets(2));
    expect(find.text('30 min', skipOffstage: false), findsOneWidget, reason: 'average session');
    expect(tester.takeException(), isNull);

    // At 2x text nothing overflows either.
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await settle(tester);
    expect(tester.takeException(), isNull);
    await unmountApp(tester);
  });

  testWidgets('goals: add, see on Home, edit, delete; past goals are kept', (tester) async {
    await saveSession('s1', 45, at: now.subtract(const Duration(hours: 2)));
    final (start, end) = Goal.monthRange(2026, 3);
    await goals.create(
      metric: GoalMetric.books,
      period: GoalPeriod.month,
      start: start,
      end: end,
      target: 2,
    );
    await launch(tester);
    await open(tester, 'Goals');
    expect(find.text('Past goals'), findsOneWidget);
    expect(find.text('0 of 2 books'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-goal')));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Minutes'));
    await tester.enterText(find.byKey(const Key('goal-target')), '600');
    await tester.tap(find.byKey(const Key('goal-save')));
    await settle(tester);
    expect(find.text('45 of 600 minutes'), findsOneWidget, reason: 'computed from the session');

    await tester.tap(find.text('45 of 600 minutes'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('goal-target')), '90');
    await tester.tap(find.byKey(const Key('goal-save')));
    await settle(tester);
    expect(find.text('45 of 90 minutes'), findsOneWidget);
    expect(find.text('0 of 2 books'), findsOneWidget, reason: 'history untouched');

    // Home shows the running goal, not the past one.
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Home'));
    await settle(tester);
    expect(find.text('45 of 90 minutes'), findsOneWidget);
    expect(find.text('0 of 2 books'), findsNothing);

    await tester.tap(find.text('45 of 90 minutes'));
    await settle(tester);
    await tester.tap(find.text('45 of 90 minutes').last);
    await settle(tester);
    await tester.tap(find.text('Delete goal'));
    await settle(tester);
    await tester.tap(find.text('Delete goal').last);
    await settle(tester);
    expect(find.text('45 of 90 minutes'), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('book page: rate, review, add and edit a note, delete it', (tester) async {
    await launch(tester);
    await tester.tap(find.text('The Deal').first);
    await settle(tester);

    await tester.scrollUntilVisible(
      find.byKey(const Key('add-note')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const Key('add-note')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('add-note')));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Quote'));
    await tester.enterText(find.byKey(const Key('note-text')), 'A line I liked');
    await tester.enterText(find.byKey(const Key('note-page')), '42');
    await tester.tap(find.byKey(const Key('note-save')));
    await settle(tester);
    expect(find.text('A line I liked'), findsOneWidget);
    expect(find.text('Quote · p. 42'), findsOneWidget);

    await tester.tap(find.text('A line I liked'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('note-text')), 'A line I loved');
    await tester.tap(find.byKey(const Key('note-save')));
    await settle(tester);
    expect(find.text('A line I loved'), findsOneWidget);

    // Rating and review are at the bottom of the page.
    await tester.scrollUntilVisible(
      find.byKey(const Key('edit-review')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.byType(RatingStars), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('edit-review')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('edit-review')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('review-text')), 'Loved it.');
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Loved it.'), findsOneWidget);
    final saved = await tester.runAsync(() => repo.watchEntry(theDeal.id).first);
    expect(saved!.review, 'Loved it.');

    await tester.scrollUntilVisible(
      find.text('A line I loved'),
      -300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.text('A line I loved'));
    await settle(tester);
    await tester.tap(find.text('A line I loved'));
    await settle(tester);
    await tester.tap(find.text('Delete note'));
    await settle(tester);
    await tester.tap(find.text('Delete note').last);
    await settle(tester);
    expect(find.text('A line I loved'), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('marking an untracked book Read asks when; the date can change', (tester) async {
    final (start, end) = Goal.yearRange(2026);
    await goals.create(
      metric: GoalMetric.books,
      period: GoalPeriod.year,
      start: start,
      end: end,
      target: 5,
    );
    await launch(tester);
    tester.view.physicalSize = const Size(1080, 6000);
    await settle(tester);

    expect(find.text('0 of 5 books'), findsOneWidget);
    await tester.tap(find.text('The Deal').first);
    await settle(tester);

    // Tracked: the book was opened as Reading in setUp, so finishing is "now".
    await tester.tap(find.byKey(const Key('status-button')));
    await settle(tester);
    await tester.tap(find.text('Read').last);
    await settle(tester);
    expect(find.text('When did you finish it?'), findsNothing);
    expect(find.text('Finished Nov 5, 2026'), findsOneWidget);

    // Correct it to a day this month.
    await tester.tap(find.text('Finished Nov 5, 2026'));
    await settle(tester);
    await tester.tap(find.text('Choose a date'));
    await settle(tester);
    await tester.tap(find.text('2'));
    await tester.tap(find.text('OK'));
    await settle(tester);
    expect(find.text('Finished Nov 2, 2026'), findsOneWidget);

    // Backing out changes nothing.
    await tester.tap(find.text('Finished Nov 2, 2026'));
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text('Finished Nov 2, 2026'), findsOneWidget);

    // Unknown: stays on the shelf and leaves the goal.
    await tester.tap(find.text('Finished Nov 2, 2026'));
    await settle(tester);
    await tester.tap(find.text('I don\u2019t remember'));
    await settle(tester);
    expect(find.text('Finished, date not set'), findsOneWidget);

    // Not being tracked any more: marking it Read asks first.
    await tester.tap(find.byKey(const Key('status-button')));
    await settle(tester);
    await tester.tap(find.text('Want to Read').last);
    await settle(tester);
    await tester.tap(find.byKey(const Key('status-button')));
    await settle(tester);
    await tester.tap(find.text('Read').last);
    await settle(tester);
    expect(find.text('When did you finish it?'), findsOneWidget);

    // Backing out leaves the shelf as it was.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.widgetWithText(OutlinedButton, 'Want to Read'), findsOneWidget);

    await tester.tap(find.byKey(const Key('status-button')));
    await settle(tester);
    await tester.tap(find.text('Read').last);
    await settle(tester);
    await tester.tap(find.text('Today'));
    await settle(tester);
    expect(find.widgetWithText(OutlinedButton, 'Read'), findsOneWidget);
    expect(find.text('Read 2 times'), findsOneWidget);

    // Only the dated read counts.
    await tester.pageBack();
    await settle(tester);
    expect(find.text('1 of 5 books'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('the Notes screen lists notes from the library and filters them', (tester) async {
    await launch(tester);
    await tester.tap(find.text('The Deal').first);
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('add-note')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const Key('add-note')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('add-note')));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Quote'));
    await tester.enterText(find.byKey(const Key('note-text')), 'A line I liked');
    await tester.tap(find.byKey(const Key('note-save')));
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Profile'));
    await settle(tester);
    await tester.ensureVisible(find.byKey(const Key('open-notes')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('open-notes')));
    await settle(tester);

    expect(find.text('A line I liked'), findsOneWidget);
    expect(find.text('The Deal'), findsOneWidget);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Observation'));
    await settle(tester);
    expect(find.text('A line I liked'), findsNothing);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Quote'));
    await settle(tester);
    expect(find.text('A line I liked'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'nothing like this');
    await settle(tester);
    expect(find.text('A line I liked'), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('closing a note sheet with unsaved text asks first', (tester) async {
    await launch(tester);
    await tester.tap(find.text('The Deal').first);
    await settle(tester);
    await tester.scrollUntilVisible(
      find.byKey(const Key('add-note')),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.ensureVisible(find.byKey(const Key('add-note')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('add-note')));
    await settle(tester);

    // Nothing typed: closes straight away.
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.byKey(const Key('note-text')), findsNothing);

    await tester.tap(find.byKey(const Key('add-note')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('note-text')), 'My own words');
    await settle(tester);

    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.text('Discard what you wrote?'), findsOneWidget);
    await tester.tap(find.text('Keep editing'));
    await settle(tester);
    expect(find.text('My own words'), findsOneWidget, reason: 'nothing lost');

    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    await tester.tap(find.text('Discard'));
    await settle(tester);
    expect(find.byKey(const Key('note-text')), findsNothing);
    expect(find.text('My own words'), findsNothing);

    // Saving isn't interrupted by the check.
    await tester.tap(find.byKey(const Key('add-note')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('note-text')), 'Kept');
    await settle(tester);
    await tester.tap(find.byKey(const Key('note-save')));
    await settle(tester);
    expect(find.text('Discard what you wrote?'), findsNothing);
    expect(find.text('Kept'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('deleting a session removes it from history and statistics', (tester) async {
    await saveSession('s1', 25, at: now.subtract(const Duration(hours: 2)));
    await launch(tester);
    tester.view.physicalSize = const Size(1080, 6000);
    await tester.tap(find.text('Reading').last);
    await settle(tester);
    await tester.tap(find.byTooltip('Delete session'));
    await settle(tester);
    expect(find.text('Delete this session?'), findsOneWidget);
    await tester.tap(find.text('Delete session').last);
    await settle(tester);
    expect(find.byTooltip('Delete session'), findsNothing);
    expect(find.text('Session deleted'), findsOneWidget);

    await open(tester, 'Insights');
    expect(find.text('Nothing here yet'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('library filters combine; Continue Reading offers Read and Update', (tester) async {
    await repo.add(
      workId: 'other',
      book: const BookSummary(title: 'Dune', authorNames: ['Frank Herbert'], genres: ['SF']),
      status: ReadingStatus.reading,
    );
    await launch(tester);

    expect(find.text('Update'), findsOneWidget, reason: 'only the latest book has buttons');
    await tester.tap(find.text('Update'));
    await settle(tester);
    expect(find.text('Update progress'), findsOneWidget);
    await tester.tapAt(const Offset(10, 10)); // dismiss the sheet
    await settle(tester);

    await tester.tap(find.text('Library'));
    await settle(tester);
    expect(find.byType(BookListTile), findsNWidgets(2));

    await tester.tap(find.byKey(const Key('library-filter')));
    await settle(tester);
    await tester.tap(find.text('Any').first);
    await settle(tester);
    await tester.tap(find.text('Frank Herbert').last);
    await settle(tester);
    await tester.tapAt(const Offset(10, 10));
    await settle(tester);
    expect(find.byType(BookListTile), findsOneWidget);
    expect(find.text('Dune'), findsWidgets);

    await tester.tap(find.byKey(const Key('library-filter')));
    await settle(tester);
    await tester.tap(find.text('Clear filters'));
    await settle(tester);
    expect(find.byType(BookListTile), findsNWidgets(2));
    await unmountApp(tester);
  });
}
