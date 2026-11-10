import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/library/presentation/library_screen.dart' show LibrarySort;
import 'package:chapter/features/shelves/data/lww_shelf_repository.dart';
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
  final uid = FakeAuthRepository.testUser.uid;
  late AppDatabase db;
  late FakeClock clock;
  late LwwLibraryRepository library;
  late LwwShelfRepository shelves;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    clock = FakeClock(now);
    final store = LwwStore(db: db, clock: clock, ids: const UuidV7Generator());
    library = LwwLibraryRepository(
      store: store,
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: () {},
    );
    shelves = LwwShelfRepository(
      store: store,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: () {},
    );
    await library.add(
      workId: theDeal.id,
      book: const BookSummary(title: 'The Deal', authorNames: ['Elle Kennedy'], pageCount: 400),
      status: ReadingStatus.reading,
    );
  });

  group('repository', () {
    test('saves an order, writing only what moved', () async {
      final a = (await shelves.create('A'))!;
      await shelves.setOnShelf(a, 'one', onShelf: true);
      await shelves.setOnShelf(a, 'two', onShelf: true);
      await shelves.saveOrder(a, ['two', 'one']);
      final links = await shelves.watchBooks().first;
      expect({for (final l in links) l.workId: l.position}, {'two': 0, 'one': 1});
    });

    test('creates, renames and deletes, oldest first', () async {
      final first = await shelves.create('  Comfort reads ');
      clock.advance(const Duration(minutes: 1));
      final second = await shelves.create('Holiday');

      var list = await shelves.watchShelves().first;
      expect(list.map((s) => s.id), [first, second]);
      expect(list.first.name, 'Comfort reads');

      await shelves.rename(first!, 'Rainy days');
      await shelves.delete(second!);
      list = await shelves.watchShelves().first;
      expect(list.map((s) => s.name), ['Rainy days']);
    });

    test('refuses an empty or over-long name', () async {
      expect(await shelves.create('   '), isNull);
      expect(await shelves.create('x' * 61), isNull);
      expect(await shelves.watchShelves().first, isEmpty);
    });

    test('a book can be on several shelves and come off one', () async {
      final a = (await shelves.create('A'))!;
      final b = (await shelves.create('B'))!;
      await shelves.setOnShelf(a, theDeal.id, onShelf: true);
      await shelves.setOnShelf(b, theDeal.id, onShelf: true);
      expect((await shelves.watchBooks().first).map((l) => l.shelfId).toSet(), {a, b});

      await shelves.setOnShelf(a, theDeal.id, onShelf: false);
      expect((await shelves.watchBooks().first).map((l) => l.shelfId), [b]);
    });

    test('deleting a shelf keeps its books in the library', () async {
      final a = (await shelves.create('A'))!;
      await shelves.setOnShelf(a, theDeal.id, onShelf: true);
      await shelves.delete(a);
      expect(await library.watchEntry(theDeal.id).first, isNotNull);
    });
  });

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
    await tester.scrollUntilVisible(find.text('Start reading'), 200);
    await tester.ensureVisible(find.text('Start reading'));
    await settle(tester);
    await tester.tap(find.text('Start reading'));
    await settle(tester);
  }

  Future<void> openShelves(WidgetTester tester) async {
    await tester.tap(find.text('Shelves'));
    await settle(tester);
  }

  testWidgets('Library opens on All and has no heart filter', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Library'));
    await settle(tester);

    final tabs = find.byType(Tab);
    expect(tester.widget<Tab>(tabs.first).text, startsWith('All'));
    expect(find.byTooltip('Favourites only'), findsNothing);
    expect(find.byKey(const Key('open-search')), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('with nothing shelved, Shelves invites you to make one', (tester) async {
    await launch(tester);
    await openShelves(tester);
    expect(find.byKey(const Key('shelves-empty')), findsOneWidget);
    expect(find.byKey(const Key('new-shelf')), findsNothing);

    await tester.tap(find.text('New shelf'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('shelf-name')), 'Holiday');
    await tester.tap(find.byKey(const Key('shelf-save')));
    await settle(tester);
    expect(find.text('Holiday'), findsOneWidget);
    expect(find.text('Tap the heart on a book to add it here.'), findsOneWidget);

    await tester.tap(find.text('Add books'));
    await settle(tester);
    expect(find.byKey(ValueKey('add-book-${theDeal.id}')), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('Favourites comes first and follows the heart', (tester) async {
    await library.setFavorite(theDeal.id, favorite: true);
    await launch(tester);
    await openShelves(tester);

    expect(find.text('Favourites'), findsOneWidget);
    expect(find.text('The Deal'), findsWidgets);
    await tester.tap(find.byKey(const Key('shelf-view-favorites')));
    await settle(tester);
    expect(find.byKey(const Key('shelf-menu')), findsNothing, reason: 'cannot rename or delete');
    await unmountApp(tester);
  });

  testWidgets('add and remove a book from inside the shelf page', (tester) async {
    final id = (await shelves.create('Holiday'))!;
    await launch(tester);
    await openShelves(tester);
    await tester.tap(find.byKey(ValueKey('shelf-view-$id')));
    await settle(tester);
    expect(find.text('Reading 1'), findsNothing);

    await tester.tap(find.byKey(const Key('add-books')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('add-book-${theDeal.id}')));
    await settle(tester);
    expect(find.text('Reading 1'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('add-book-${theDeal.id}')));
    await settle(tester);
    expect(find.text('Reading 1'), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('adding to Favourites sets the heart', (tester) async {
    await shelves.create('Holiday'); // so the shelves list shows
    await launch(tester);
    await openShelves(tester);
    await tester.tap(find.byKey(const ValueKey('shelf-empty-favorites')));
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('add-book-${theDeal.id}')));
    await settle(tester);
    // The Favourites row now shows the book instead of the empty placeholder.
    expect(find.byKey(const ValueKey('shelf-empty-favorites')), findsNothing);
    await unmountApp(tester);
  });

  testWidgets('sort and layout are remembered after leaving the shelf', (tester) async {
    final id = (await shelves.create('Holiday'))!;
    await shelves.setOnShelf(id, theDeal.id, onShelf: true);
    await launch(tester);
    await openShelves(tester);
    await tester.tap(find.byKey(ValueKey('shelf-view-$id')));
    await settle(tester);

    await tester.tap(find.byTooltip('Sort'));
    await settle(tester);
    await tester.tap(find.text('Title').last);
    await settle(tester);
    await tester.tap(find.byTooltip('Grid view'));
    await settle(tester);

    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('shelf-view-$id')));
    await settle(tester);

    expect(find.byTooltip('List view'), findsOneWidget);
    final sort = tester.widget<PopupMenuButton<LibrarySort>>(
      find.byType(PopupMenuButton<LibrarySort>),
    );
    expect(sort.initialValue, LibrarySort.title);
    await unmountApp(tester);
  });

  testWidgets('Add books works as a grid and remembers it', (tester) async {
    final id = (await shelves.create('Holiday'))!;
    await launch(tester);
    await openShelves(tester);
    await tester.tap(find.byKey(ValueKey('shelf-view-$id')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('add-books')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('add-books-view')));
    await settle(tester);

    await tester.tap(find.byKey(ValueKey('add-book-${theDeal.id}')));
    await settle(tester);
    expect(find.text('Reading 1'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await unmountApp(tester);
  });

  Future<String> twoBookShelf(WidgetTester tester) async {
    await library.add(
      workId: 'zed',
      book: const BookSummary(title: 'Zed', authorNames: ['Someone'], pageCount: 200),
      status: ReadingStatus.reading,
    );
    final id = (await shelves.create('Holiday'))!;
    await shelves.setOnShelf(id, theDeal.id, onShelf: true);
    await shelves.setOnShelf(id, 'zed', onShelf: true);
    await launch(tester);
    await openShelves(tester);
    await tester.tap(find.byKey(ValueKey('shelf-view-$id')));
    await settle(tester);
    await tester.tap(find.byTooltip('Sort'));
    await settle(tester);
    await tester.tap(find.text('My order').last);
    await settle(tester);
    return id;
  }

  double top(WidgetTester tester, String title) => tester.getTopLeft(find.text(title).first).dy;
  double left(WidgetTester tester, String title) => tester.getTopLeft(find.text(title).first).dx;

  testWidgets('drag a book to a new place in the list, and it stays there', (tester) async {
    final id = await twoBookShelf(tester);
    final firstIsDeal = top(tester, 'The Deal') < top(tester, 'Zed');

    tester.widget<ReorderableListView>(find.byType(ReorderableListView)).onReorderItem!(0, 1);
    await settle(tester);
    expect(top(tester, 'The Deal') < top(tester, 'Zed'), !firstIsDeal);

    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.byKey(ValueKey('shelf-view-$id')));
    await settle(tester);
    expect(top(tester, 'The Deal') < top(tester, 'Zed'), !firstIsDeal);
    await unmountApp(tester);
  });

  testWidgets('hold and drag a cover in the grid', (tester) async {
    await twoBookShelf(tester);
    await tester.tap(find.byTooltip('Grid view'));
    await settle(tester);
    final firstIsDeal = left(tester, 'The Deal') < left(tester, 'Zed');
    final (from, to) = firstIsDeal ? ('The Deal', 'Zed') : ('Zed', 'The Deal');

    final gesture = await tester.startGesture(tester.getCenter(find.text(from).first));
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(tester.getCenter(find.text(to).first));
    await tester.pump(const Duration(milliseconds: 100));
    await gesture.up();
    await settle(tester);

    expect(left(tester, 'The Deal') < left(tester, 'Zed'), !firstIsDeal);
    await unmountApp(tester);
  });

  testWidgets('make a shelf, see its books, then delete it', (tester) async {
    final id = (await shelves.create('Comfort reads'))!;
    await shelves.setOnShelf(id, theDeal.id, onShelf: true);
    await launch(tester);
    await openShelves(tester);
    expect(find.text('Comfort reads'), findsOneWidget);
    expect(find.text('The Deal'), findsWidgets);

    await tester.tap(find.byKey(const Key('new-shelf')));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('shelf-name')), 'Holiday');
    await tester.tap(find.byKey(const Key('shelf-save')));
    await settle(tester);
    expect(find.text('Holiday'), findsOneWidget);

    await tester.tap(find.byKey(ValueKey('shelf-view-$id')));
    await settle(tester);
    expect(find.text('Reading 1'), findsOneWidget);
    await tester.tap(find.byKey(const Key('shelf-menu')));
    await settle(tester);
    await tester.tap(find.text('Delete shelf'));
    await settle(tester);
    await tester.tap(find.text('Delete shelf').last);
    await settle(tester);

    expect(find.text('Comfort reads'), findsNothing);
    await tester.tap(find.text('Library'));
    await settle(tester);
    expect(find.text('The Deal'), findsWidgets);
    await unmountApp(tester);
  });
}
