import 'package:chapter/app/providers.dart';
import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/core/error/failure.dart';
import 'package:chapter/core/error/result.dart';
import 'package:chapter/features/scanner/presentation/scan_screen.dart';
import 'package:chapter/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../helpers/fake_catalog.dart';

/// The camera is replaced by a button that "detects" [barcode].
Future<FakeCatalogRepository> pumpScanner(WidgetTester tester, String barcode) async {
  final repo = FakeCatalogRepository();
  final router = GoRouter(
    initialLocation: '/scan',
    routes: [
      GoRoute(
        path: '/scan',
        builder: (_, _) => ScanScreen(
          cameraBuilder: (context, onDetect) => Center(
            child: TextButton(onPressed: () => onDetect(barcode), child: const Text('fake-detect')),
          ),
        ),
      ),
      GoRoute(
        path: '/book/:key',
        builder: (_, state) => Scaffold(body: Text('BOOK ${state.pathParameters['key']}')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [catalogRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp.router(
        theme: ChapterTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  return repo;
}

void main() {
  testWidgets('a scanned book ISBN shows a confirmation and opens the book', (tester) async {
    await pumpScanner(tester, '9780349440842');
    await tester.tap(find.text('fake-detect'));
    await tester.pumpAndSettle();
    expect(find.text('Found it'), findsOneWidget);
    expect(find.text('The Deal'), findsWidgets);
    expect(find.textContaining('Piatkus'), findsOneWidget);

    await tester.tap(find.text('View book'));
    await tester.pumpAndSettle();
    expect(find.text('BOOK id:${theDeal.id}'), findsOneWidget);
  });

  testWidgets('a non-book barcode is rejected without a lookup', (tester) async {
    final repo = await pumpScanner(tester, '5012345678900');
    var lookups = 0;
    repo.onLookup = (_) {
      lookups++;
      return const Result.err(NotFoundFailure('x'));
    };
    await tester.tap(find.text('fake-detect'));
    await tester.pump();
    expect(find.text("That barcode isn't a book ISBN."), findsOneWidget);
    expect(lookups, 0);
  });

  testWidgets('unknown ISBN shows a not-found message', (tester) async {
    final repo = await pumpScanner(tester, '9780000000002');
    repo.onLookup = (_) => const Result.err(NotFoundFailure('none'));
    await tester.tap(find.text('fake-detect'));
    await tester.pumpAndSettle();
    expect(find.text('No book found for ISBN 9780000000002.'), findsOneWidget);
  });

  testWidgets('manual entry validates the ISBN before looking it up', (tester) async {
    await pumpScanner(tester, 'unused');
    await tester.tap(find.text('Enter ISBN instead'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0349440841');
    await tester.tap(find.text('Look up'));
    await tester.pumpAndSettle();
    expect(find.text("That doesn't look like a valid ISBN."), findsOneWidget);

    await tester.enterText(find.byType(TextField), '0-349-44084-0');
    await tester.tap(find.text('Look up'));
    await tester.pumpAndSettle();
    expect(find.text('Found it'), findsOneWidget);
  });
}
