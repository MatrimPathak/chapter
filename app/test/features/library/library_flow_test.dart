import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/core/error/result.dart';
import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_catalog.dart';
import '../../helpers/test_app.dart';

Future<void> openTheDeal(WidgetTester tester) async {
  final repo = FakeCatalogRepository()
    ..onSearch = ((q, _, page) => Result.ok(
      SearchPage(
        results: [summary('The Deal', ext: 'OL42430111W')],
        page: page,
      ),
    ));
  await pumpChapterApp(
    tester,
    auth: FakeAuthRepository(initialUser: FakeAuthRepository.testUser),
    catalog: repo,
  );
  await tester.scrollUntilVisible(find.text('Start reading'), 200);
  await tester.tap(find.text('Start reading'));
  await settle(tester);
  await tester.tap(find.text('Search').last);
  await settle(tester);
  await tester.enterText(find.byType(TextField), 'the deal');
  await settle(tester);
  await tester.tap(find.text('The Deal').last);
  await settle(tester);
}

void main() {
  testWidgets('add a book, log progress, see it on Home and in the Library', (tester) async {
    await openTheDeal(tester);

    // Add as Reading, owning the paperback.
    await tester.tap(find.text('Add to library'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Reading'));
    await tester.tap(find.text('I own this edition'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add to library').last);
    await settle(tester);
    expect(find.text('Added to Reading'), findsOneWidget);
    expect(find.textContaining('I own this edition'), findsOneWidget);

    // Duplicate detection: the add button is gone, the shelf is shown.
    expect(find.widgetWithText(OutlinedButton, 'Reading'), findsOneWidget);

    // Log p. 187 of 374.
    await tester.tap(find.text('Update progress'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('progress-input')), '187');
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('p. 187 of 374 · 50%'), findsOneWidget);

    // Home: Continue reading.
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Home'));
    await settle(tester);
    expect(find.text('Continue reading'), findsOneWidget);
    expect(find.text('The Deal'), findsWidgets);

    // Library: on the Reading shelf.
    await tester.tap(find.text('Library'));
    await settle(tester);
    expect(find.text('Reading (1)'), findsOneWidget);
    expect(find.text('Want to Read (0)'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('finishing via progress offers Mark as read; remove keeps history', (tester) async {
    await openTheDeal(tester);
    await tester.tap(find.text('Add to library'));
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add to library').last);
    await settle(tester);
    expect(find.text('Added to Want to Read'), findsOneWidget);

    await tester.tap(find.text('Start reading'));
    await settle(tester);
    await tester.tap(find.text('Update progress'));
    await settle(tester);
    await tester.enterText(find.byKey(const Key('progress-input')), '374');
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('That’s the end of the book. Mark it as read?'), findsOneWidget);
    await tester.tap(find.text('Mark as read').last);
    await settle(tester);
    expect(find.widgetWithText(OutlinedButton, 'Read'), findsOneWidget);
    expect(find.text('Read once'), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
    await tester.tap(find.text('Remove from library'));
    await settle(tester);
    await tester.tap(find.text('Remove from library').last);
    await settle(tester);
    expect(find.text('Add to library'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('library grid does not overflow at 2x text size', (tester) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await openTheDeal(tester);
    await tester.ensureVisible(find.text('Add to library'));
    await tester.tap(find.text('Add to library'));
    await settle(tester);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Reading'));
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Add to library').last);
    await tester.tap(find.widgetWithText(FilledButton, 'Add to library').last);
    await settle(tester);
    await tester.pageBack();
    await settle(tester);
    await tester.tap(find.text('Library'));
    await settle(tester);
    expect(find.byType(BookGridCard), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountApp(tester);
  });
}
