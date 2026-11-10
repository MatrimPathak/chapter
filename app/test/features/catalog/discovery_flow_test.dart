import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/core/error/result.dart';
import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_catalog.dart';
import '../../helpers/test_app.dart';

Future<FakeCatalogRepository> openSearch(WidgetTester tester, {FakeCatalogRepository? repo}) async {
  final catalog = repo ?? FakeCatalogRepository();
  await pumpChapterApp(
    tester,
    auth: FakeAuthRepository(initialUser: FakeAuthRepository.testUser),
    catalog: catalog,
  );
  await tester.tap(find.text('Start reading'));
  await settle(tester);
  await tester.tap(find.byKey(const Key('open-search')).first);
  await settle(tester);
  return catalog;
}

void main() {
  testWidgets('idle search shows trending books and recent searches', (tester) async {
    final repo = FakeCatalogRepository()
      ..trendingPage = SearchPage(results: [summary('Atomic Habits', ext: 'OL9W')])
      ..recents.add('the deal');
    await openSearch(tester, repo: repo);
    expect(find.text('Popular this week'), findsOneWidget);
    expect(find.text('Atomic Habits'), findsWidgets);
    expect(find.text('the deal'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('typing searches, results open the book, the author link opens the author', (
    tester,
  ) async {
    final repo = FakeCatalogRepository()
      ..onSearch = ((q, _, page) => Result.ok(
        SearchPage(
          results: [summary('The Deal', ext: 'OL42430111W', year: 2015)],
          page: page,
        ),
      ))
      ..author = const CatalogAuthor(
        id: '01a1a6e7-0000-7000-8000-000000000001',
        name: 'Elle Kennedy',
        bio: 'Elle Kennedy is a New York Times bestselling author.',
      );
    await openSearch(tester, repo: repo);

    await tester.enterText(find.byType(TextField), 'the deal');
    await settle(tester);
    expect(repo.searchCalls.single.$1, 'the deal');
    expect(find.text('2015'), findsOneWidget);

    await tester.tap(find.text('The Deal').last);
    await settle(tester);
    expect(find.text('The international sensation'), findsNothing);
    expect(find.text('Book 1 of Off-Campus'), findsOneWidget);
    expect(find.text('374 pages · 2015'), findsOneWidget);
    expect(find.text('Add to library'), findsOneWidget);

    // The author link (the monogram cover also renders the name).
    await tester.tap(find.widgetWithText(InkWell, 'Elle Kennedy').last);
    await settle(tester);
    expect(find.textContaining('New York Times bestselling'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('no results shows an empty state with a scan shortcut', (tester) async {
    final repo = FakeCatalogRepository()..onSearch = (_, _, _) => const Result.ok(SearchPage());
    await openSearch(tester, repo: repo);
    await tester.enterText(find.byType(TextField), 'zzzz unknown');
    await settle(tester);
    expect(find.text('No books found'), findsOneWidget);
    expect(find.text('Scan a barcode'), findsWidgets);
    await unmountApp(tester);
  });

  testWidgets('offline cached results show the offline banner', (tester) async {
    final repo = FakeCatalogRepository()
      ..onSearch = (_, _, _) =>
          Result.ok(SearchPage(results: [summary('The Deal', id: 'x')], fromCache: true));
    await openSearch(tester, repo: repo);
    await tester.enterText(find.byType(TextField), 'deal');
    await settle(tester);
    expect(find.text('Showing saved results. Connect to search all books.'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('series screen lists books in reading order and marks novellas', (tester) async {
    final repo = FakeCatalogRepository()
      ..onSearch = ((_, _, page) =>
          Result.ok(SearchPage(results: [summary('The Deal')], page: page)))
      ..series = CatalogSeries(
        id: '01a1a6e7-0000-7000-8000-000000000009',
        name: 'Off-Campus',
        primaryCount: 2,
        entries: [
          SeriesEntry(
            work: summary('The Deal', ext: 'a'),
            position: 1,
            positionLabel: '1',
            isPrimary: true,
          ),
          SeriesEntry(
            work: summary('Bonus Scenes', ext: 'b'),
            position: 1.5,
            positionLabel: '1.5',
          ),
          SeriesEntry(
            work: summary('The Mistake', ext: 'c'),
            position: 2,
            positionLabel: '2',
            isPrimary: true,
          ),
        ],
      );
    await openSearch(tester, repo: repo);
    await tester.enterText(find.byType(TextField), 'deal');
    await settle(tester);
    await tester.tap(find.text('The Deal').last);
    await settle(tester);
    await tester.tap(find.text('Book 1 of Off-Campus'));
    await settle(tester);

    expect(find.text('2 books · Reading order'), findsOneWidget);
    final titles = tester
        .widgetList<BookListTile>(find.byType(BookListTile))
        .map((t) => t.data.title)
        .toList();
    expect(titles, ['The Deal', 'Bonus Scenes', 'The Mistake']);
    expect(find.text('Novella or extra'), findsOneWidget);
    await unmountApp(tester);
  });
}
