import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_catalog.dart';
import '../helpers/test_app.dart';

/// W17: the Library with 2,000 books. In a test the frame times aren't a
/// phone's, so this checks the part that decides scrolling cost: only what's on
/// screen is built, however long the list is, and flinging stays bounded.
void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  testWidgets('2,000 books: lazily built, and scrolling stays bounded', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final clock = FakeClock(DateTime(2026, 11, 5, 9));
    final repo = LwwLibraryRepository(
      store: LwwStore(db: db, clock: clock, ids: const UuidV7Generator()),
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: FakeAuthRepository.testUser.uid,
      onLocalWrite: () {},
    );
    await tester.runAsync(() async {
      for (var i = 0; i < 2000; i++) {
        await repo.add(
          workId: 'w$i',
          book: BookSummary(title: 'Book $i', authorNames: ['Author ${i % 50}'], pageCount: 300),
        );
      }
    });
    await pumpChapterApp(
      tester,
      auth: FakeAuthRepository(initialUser: FakeAuthRepository.testUser),
      catalog: FakeCatalogRepository(),
      clock: clock,
      database: db,
    );
    addTearDown(() => unmountApp(tester));
    await tester.tap(find.text('Start reading'));
    await settle(tester);

    final open = Stopwatch()..start();
    await tester.tap(find.text('Library'));
    await settle(tester);
    await tester.tap(find.textContaining('Want to Read'));
    await settle(tester);
    open.stop();

    final built = find.byType(BookGridCard).evaluate().length;
    expect(built, greaterThan(0));
    expect(built, lessThan(60), reason: 'only what is near the screen');

    final fling = Stopwatch()..start();
    var frames = 0;
    for (var i = 0; i < 30; i++) {
      await tester.drag(find.byType(Scrollable).last, const Offset(0, -1500));
      await tester.pump(const Duration(milliseconds: 16));
      frames++;
    }
    fling.stop();
    await settle(tester);
    expect(
      find.byType(BookGridCard).evaluate().length,
      lessThan(60),
      reason: 'old rows are released',
    );
    // ignore: avoid_print
    print(
      'PERF library open ${open.elapsedMilliseconds} ms; '
      '$built cards built; '
      '${(fling.elapsedMilliseconds / frames).toStringAsFixed(1)} ms per scroll step',
    );
    expect(fling.elapsedMilliseconds / frames, lessThan(500));
    await unmountApp(tester);
  }, timeout: const Timeout(Duration(minutes: 4)));
}
