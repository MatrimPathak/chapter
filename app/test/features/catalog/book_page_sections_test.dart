import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:chapter/features/catalog/presentation/book_detail_screen.dart';
import 'package:chapter/features/catalog/presentation/catalog_detail_providers.dart';
import 'package:chapter/features/library/presentation/library_providers.dart';
import 'package:chapter/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const _ref = ProviderRef(provider: CatalogProvider.hardcover, externalId: '1');

WorkSummary _summary(String id, String title) => WorkSummary(id: id, ref: _ref, title: title);

const _work = CatalogWork(
  id: 'w1',
  title: 'First Book',
  subtitle: 'Flammen und Finsternis',
  authors: [CatalogAuthorRef(id: 'a1', name: 'An Author')],
  series: [CatalogSeriesRef(seriesId: 's1', name: 'The Saga', position: 1, positionLabel: '1')],
  refreshedAt: '2026-11-09',
);

final _workWithCovers = _work.copyWith(
  coverUrl: 'https://covers.test/main',
  defaultEditionId: 'e1',
  editions: const [
    CatalogEdition(id: 'e1', workId: 'w1', language: 'eng', coverUrl: 'https://covers.test/e1'),
    CatalogEdition(id: 'e2', workId: 'w1', language: 'eng', coverUrl: 'https://covers.test/e2'),
  ],
);

CatalogSeries _series(int count) => CatalogSeries(
  id: 's1',
  name: 'The Saga',
  entries: [
    SeriesEntry(work: _summary('w1', 'First Book'), position: 1, positionLabel: '1'),
    if (count > 1)
      SeriesEntry(work: _summary('w2', 'Second Book'), position: 2, positionLabel: '2'),
  ],
);

Future<void> _pump(
  WidgetTester tester, {
  CatalogSeries? series,
  Object? seriesError,
  CatalogWork work = _work,
  String? editionId,
  bool tall = true,
}) async {
  tester.view.physicalSize = tall ? const Size(1080, 6000) : const Size(1080, 1800);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        workDetailProvider('id:w1').overrideWith((ref) async => work),
        seriesDetailProvider('s1').overrideWith((ref) async {
          if (seriesError != null) throw seriesError;
          return series ?? _series(2);
        }),
        authorDetailProvider('id:a1').overrideWith(
          (ref) async => const CatalogAuthor(id: 'a1', name: 'An Author', bio: 'Writes books.'),
        ),
        libraryEntryProvider('w1').overrideWith((ref) => Stream.value(null)),
        libraryEntryProvider('w2').overrideWith((ref) => Stream.value(null)),
        userEditionsProvider('w1').overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp(
        theme: ChapterTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: BookDetailScreen(workKey: 'id:w1', editionId: editionId),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists the books in the series and marks this one', (tester) async {
    await _pump(tester);
    expect(find.text('In this series'), findsOneWidget);
    expect(find.text('Second Book'), findsWidgets);
    expect(find.text('Book 2'), findsWidgets);
    expect(find.text('This book'), findsWidgets);
  });

  testWidgets('shows the series in one sideways row', (tester) async {
    await _pump(tester);
    final list = tester.widget<ListView>(
      find.descendant(
        of: find.byKey(const Key('book-series-list')),
        matching: find.byType(ListView),
      ),
    );
    expect(list.scrollDirection, Axis.horizontal);
  });

  testWidgets('keeps the cover that was tapped when no edition was chosen', (tester) async {
    await _pump(tester, work: _workWithCovers);
    final cover = tester.widget<BookCover>(find.byType(BookCover).first);
    expect(cover.imageUrl, 'https://covers.test/main');
  });

  testWidgets('shows the chosen edition cover', (tester) async {
    await _pump(tester, work: _workWithCovers, editionId: 'e2');
    final cover = tester.widget<BookCover>(find.byType(BookCover).first);
    expect(cover.imageUrl, 'https://covers.test/e2');
  });

  testWidgets('the app bar shows the title only once it has scrolled away', (tester) async {
    await _pump(tester, tall: false);
    final inBar = find.descendant(of: find.byType(AppBar), matching: find.text('First Book'));
    expect(inBar, findsNothing);
    await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(inBar, findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(inBar, findsNothing);
  });

  testWidgets('leaves out the series list for a single book', (tester) async {
    await _pump(tester, series: _series(1));
    expect(find.text('In this series'), findsNothing);
  });

  testWidgets('leaves out the series list when it cannot load', (tester) async {
    await _pump(tester, seriesError: StateError('down'));
    expect(find.text('In this series'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows the author biography', (tester) async {
    await _pump(tester);
    expect(find.text('About the author'), findsOneWidget);
    expect(find.text('Writes books.'), findsOneWidget);
  });

  testWidgets('does not show the provider subtitle', (tester) async {
    await _pump(tester);
    expect(find.text('Flammen und Finsternis'), findsNothing);
  });
}
