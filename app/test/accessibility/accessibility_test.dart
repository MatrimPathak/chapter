import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_catalog.dart';
import '../helpers/test_app.dart';

/// Automated half of the accessibility pass (docs/01 §6). It can't replace a
/// person with TalkBack or VoiceOver: it checks sizes, labels and contrast.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime(2026, 11, 5, 9);

  Future<void> launch(
    WidgetTester tester, {
    required Brightness brightness,
    double scale = 1,
    Size size = const Size(1080, 2340),
    double ratio = 2.625,
  }) async {
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = ratio;
    tester.platformDispatcher.platformBrightnessTestValue = brightness;
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearAllTestValues);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FakeClock(now);
    final repo = LwwLibraryRepository(
      store: LwwStore(db: db, clock: clock, ids: const UuidV7Generator()),
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: FakeAuthRepository.testUser.uid,
      onLocalWrite: () {},
    );
    await repo.add(
      workId: theDeal.id,
      book: const BookSummary(title: 'The Deal', authorNames: ['Elle Kennedy'], pageCount: 400),
      status: ReadingStatus.reading,
    );
    await repo.recordProgress(theDeal.id, const ReadingPosition.page(page: 120));
    await pumpChapterApp(
      tester,
      auth: FakeAuthRepository(initialUser: FakeAuthRepository.testUser),
      catalog: FakeCatalogRepository(),
      clock: clock,
      database: db,
    );
    addTearDown(() => unmountApp(tester));
    await tester.scrollUntilVisible(find.text('Start reading'), 200);
    await tester.ensureVisible(find.text('Start reading'));
    await settle(tester);
    await tester.tap(find.text('Start reading'));
    await settle(tester);
  }

  /// Screens reached by tapping from the shell, in order. Each is a list of
  /// taps from the tab bar; the back button returns between them.
  final screens = <String, List<String>>{
    'Home': ['Home'],
    'Library': ['Library'],
    'Reading': ['Reading'],
    'Search': ['Search'],
    'Shelves': ['Shelves'],
    'Shelf page': ['Shelves', 'View all'],
    'Profile': ['Profile'],
    'Goals': ['Profile', 'Goals'],
    'Insights': ['Profile', 'Insights'],
    'Connected services': ['Profile', 'Connected services'],
    'Book page': ['Library', 'The Deal'],
    'Timer': ['Reading', 'Start reading'],
    'Delete account': ['Profile', 'Delete account'],
    'About': ['Profile', 'About Chapter'],
    'Privacy policy': ['Profile', 'About Chapter', 'Privacy policy'],
    'Import': ['Profile', 'Connected services', 'Choose a file'],
  };

  Future<void> open(WidgetTester tester, List<String> path) async {
    for (final label in path) {
      if (label == 'Search') {
        await tester.tap(find.byKey(const Key('open-search')).first);
        await settle(tester);
        continue;
      }
      // Long lists build lazily, more so at large text sizes.
      if (find.text(label).evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          find.text(label),
          300,
          scrollable: find.byType(Scrollable).first,
        );
      }
      await tester.ensureVisible(find.text(label).last);
      await settle(tester);
      await tester.tap(find.text(label).last, warnIfMissed: false);
      await settle(tester);
    }
  }

  for (final brightness in Brightness.values) {
    screens.forEach((name, path) {
      testWidgets('$name in ${brightness.name}: targets, labels, contrast', (tester) async {
        final handle = tester.ensureSemantics();
        await launch(tester, brightness: brightness);
        await open(tester, path);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
        await expectLater(tester, meetsGuideline(textContrastGuideline));
        handle.dispose();
        await unmountApp(tester);
      });
    });
  }

  // A small phone (320 x 568) and a tablet (800 x 1280), in both themes.
  for (final (device, size) in const [
    ('small phone', Size(640, 1136)),
    ('tablet', Size(1600, 2560)),
  ]) {
    for (final brightness in Brightness.values) {
      screens.forEach((name, path) {
        testWidgets('$name on a $device in ${brightness.name}: no overflow', (tester) async {
          await launch(tester, brightness: brightness, size: size, ratio: 2);
          await open(tester, path);
          expect(tester.takeException(), isNull);
          await unmountApp(tester);
        });
      });
    }
  }

  screens.forEach((name, path) {
    testWidgets('$name at 200 % text: no overflow', (tester) async {
      await launch(tester, brightness: Brightness.light, scale: 2);
      await open(tester, path);
      expect(tester.takeException(), isNull);
      await unmountApp(tester);
    });
  });

  for (final brightness in Brightness.values) {
    testWidgets('Sign-in in ${brightness.name}: targets, labels, contrast', (tester) async {
      final handle = tester.ensureSemantics();
      tester.view
        ..physicalSize = const Size(1080, 2340)
        ..devicePixelRatio = 2.625;
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      await pumpChapterApp(tester, catalog: FakeCatalogRepository());
      addTearDown(() => unmountApp(tester));
      expect(find.text('Continue with Google'), findsOneWidget);
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
      handle.dispose();
      await unmountApp(tester);
    });
  }
}
