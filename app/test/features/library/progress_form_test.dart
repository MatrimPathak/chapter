import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/features/library/presentation/library_sheets.dart';
import 'package:chapter/features/progress/domain/progress_mapper.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:chapter/l10n/generated/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required double start,
    void Function(ReadingPosition)? onSubmit,
  }) async {
    tester.view
      ..physicalSize = const Size(1080, 2340)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: ChapterTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SingleChildScrollView(
            child: ProgressForm(
              metrics: const EditionMetrics(format: 'paperback', pageCount: 300),
              initialFraction: start,
              autofocus: false,
              onSubmit: onSubmit ?? (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  String page(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(const Key('progress-input'))).controller!.text;

  testWidgets('the page buttons move the page and saving uses it', (tester) async {
    ReadingPosition? saved;
    await pump(tester, start: 1 / 3, onSubmit: (p) => saved = p);
    expect(page(tester), '100');

    await tester.tap(find.byKey(const Key('progress-nudge-10')));
    await tester.pump();
    expect(page(tester), '110');

    await tester.tap(find.byKey(const Key('progress-nudge--1')));
    await tester.pump();
    expect(page(tester), '109');

    await tester.tap(find.byType(FilledButton));
    expect(saved, const ReadingPosition.page(page: 109));
  });

  testWidgets('the page buttons stop at the last page', (tester) async {
    await pump(tester, start: 295 / 300);
    await tester.tap(find.byKey(const Key('progress-nudge-10')));
    await tester.pump();
    expect(page(tester), '300');
  });

  testWidgets('the page buttons stop at the first page', (tester) async {
    await pump(tester, start: 0.01);
    expect(page(tester), '3');
    await tester.tap(find.byKey(const Key('progress-nudge--10')));
    await tester.pump();
    expect(page(tester), '0');
  });
}
