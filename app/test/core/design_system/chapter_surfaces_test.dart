import 'package:chapter/core/design_system/design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget host(ThemeData theme, Widget child) => MaterialApp(
    theme: theme,
    home: Scaffold(body: SingleChildScrollView(child: child)),
  );

  for (final (name, theme) in [('light', ChapterTheme.light()), ('dark', ChapterTheme.dark())]) {
    group('$name theme', () {
      testWidgets('shared surfaces render without overflow at 200 % text', (tester) async {
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
        await tester.pumpWidget(
          host(
            theme,
            const Column(
              children: [
                ChapterSectionHeader(title: 'Currently reading', subtitle: 'Two books'),
                ChapterStatTile(
                  label: 'Pages',
                  value: '8,420',
                  unit: 'pages',
                  caption: 'This year',
                  icon: Icons.menu_book_outlined,
                ),
                ChapterCard(child: ChapterQuote(text: 'All great and precious things are lonely.')),
                ChapterPill(label: 'Want to Read', tone: ChapterPillTone.highlight),
              ],
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        expect(find.textContaining('8,420', findRichText: true), findsOneWidget);
      });

      testWidgets('a card reports taps', (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          host(theme, ChapterCard(onTap: () => taps++, child: const Text('Open'))),
        );
        await tester.tap(find.text('Open'));
        expect(taps, 1);
      });
    });
  }

  test('the theme carries the Stitch fonts, including the italic quote', () {
    final text = ChapterTheme.light().textTheme;
    expect(text.headlineMedium?.fontFamily, 'Newsreader');
    expect(text.bodyMedium?.fontFamily, 'PlusJakartaSans');
    final quote = ChapterTypography.quote(ChapterColors.light.ink);
    expect(quote.fontFamily, 'Newsreader');
    expect(quote.fontStyle, FontStyle.italic);
  });
}
