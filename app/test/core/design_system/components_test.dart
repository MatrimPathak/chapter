import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/core/sync/sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/pump_app.dart';

const _book = BookCardData(
  title: 'The Deal',
  author: 'Elle Kennedy',
  progress: 0.4675,
  progressLabel: 'p. 187 of 400 · 47%',
  caption: 'Last read 2 days ago',
  isApproximate: true,
);

Widget _gallery() => Padding(
  padding: const EdgeInsets.all(16),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ChapterButton(label: 'Primary', onPressed: () {}),
      ChapterButton(
        label: 'Secondary',
        onPressed: () {},
        variant: ChapterButtonVariant.secondary,
        icon: const Icon(Icons.add),
      ),
      const ChapterButton(label: 'Loading', onPressed: null, isLoading: true),
      const ChapterTextField(label: 'Search', hint: 'Title, author or ISBN'),
      const BookCover(title: 'The Deal', author: 'Elle Kennedy', width: 120),
      const BookCover(title: 'Tiny', width: 48),
      const BookGridCard(data: _book),
      const BookListTile(data: _book),
      ContinueReadingCard(data: _book, resumeLabel: 'Read', onResume: () {}),
      const ChapterProgressBar(fraction: 0.5),
      const ChapterProgressRing(fraction: 0.25, center: Text('25%')),
      const RatingStars(rating: 3.5),
      RatingStars(rating: 4, onChanged: (_) {}),
      const ApproximateBadge(),
      const SyncBadge(status: SyncPending(3)),
      const SyncBadge(status: SyncOffline()),
      const SizedBox(
        height: 300,
        child: EmptyState(title: 'Empty', body: 'Nothing here yet.'),
      ),
      SizedBox(
        height: 200,
        child: ErrorState(message: 'Failed', retryLabel: 'Retry', onRetry: () {}),
      ),
      const LoadingSkeleton(width: 120),
      const LoadingSkeleton.cover(width: 60),
    ],
  ),
);

void main() {
  for (final (brightness, scale) in themeVariants) {
    testWidgets('component gallery renders without overflow ($brightness, ${scale}x)', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.6;
      addTearDown(tester.view.reset);
      await pumpThemed(tester, _gallery(), brightness: brightness, textScale: scale);
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('Primary'), findsOneWidget);
    });
  }

  testWidgets('BookCover without artwork shows a labelled monogram', (tester) async {
    await pumpThemed(
      tester,
      const BookCover(title: 'The Deal', author: 'Elle Kennedy', width: 120),
    );
    expect(find.bySemanticsLabel('Cover of The Deal by Elle Kennedy'), findsOneWidget);
    expect(find.text('The Deal'), findsOneWidget);
  });

  testWidgets('approximate progress is announced to screen readers', (tester) async {
    await pumpThemed(tester, const BookListTile(data: _book));
    expect(find.bySemanticsLabel(RegExp('The Deal, by Elle Kennedy.*approximate')), findsOneWidget);
  });

  testWidgets('loading button is disabled', (tester) async {
    var taps = 0;
    await pumpThemed(
      tester,
      ChapterButton(label: 'Save', onPressed: () => taps++, isLoading: true),
    );
    await tester.tap(find.byType(FilledButton));
    expect(taps, 0);
  });

  group('RatingStars', () {
    test('normalizes to half steps within 0.5–5', () {
      expect(RatingStars.normalize(3.3), 3.5);
      expect(RatingStars.normalize(0.1), 0.5);
      expect(RatingStars.normalize(7), 5);
      expect(RatingStars.normalize(null), isNull);
    });

    testWidgets('tapping halves sets half and whole stars; same value clears', (tester) async {
      double? value = 2;
      await pumpThemed(
        tester,
        StatefulBuilder(
          builder: (context, setState) =>
              RatingStars(rating: value, onChanged: (v) => setState(() => value = v)),
        ),
      );
      final fourth = find.byType(GestureDetector).at(6); // star 4, left half
      await tester.tap(fourth);
      await tester.pump();
      expect(value, 3.5);

      await tester.tap(find.byType(GestureDetector).at(7)); // star 4, right half
      await tester.pump();
      expect(value, 4);

      await tester.tap(find.byType(GestureDetector).at(7));
      await tester.pump();
      expect(value, isNull);
    });
  });

  testWidgets('nav bar marks the emphasized item and reports selection', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ChapterTheme.light(),
        home: Scaffold(
          bottomNavigationBar: ChapterNavBar(
            selectedIndex: 0,
            onSelected: (i) => selected = i,
            items: const [
              ChapterNavItem(label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home),
              ChapterNavItem(label: 'Library', icon: Icons.book_outlined, selectedIcon: Icons.book),
              ChapterNavItem(label: 'Read', icon: Icons.timer_outlined, selectedIcon: Icons.timer),
              ChapterNavItem(label: 'Search', icon: Icons.search, selectedIcon: Icons.search),
              ChapterNavItem(
                label: 'Profile',
                icon: Icons.person_outline,
                selectedIcon: Icons.person,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('Read'));
    expect(selected, 2);
  });
}
