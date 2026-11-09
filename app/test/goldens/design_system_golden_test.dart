import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/core/sync/sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Regenerate after an intended visual change:
/// `flutter test --update-goldens test/goldens`
///
/// Goldens are generated on Windows and CI runs on Linux. Text is drawn in
/// Flutter's block test font because real fonts render differently per OS, so
/// these images check layout, colour and shape. Fonts are checked by the theme
/// tests. Text still lands up to 2 % of pixels differently between the two, so
/// small visual changes can pass; these catch larger regressions only.
class _TolerantComparator extends LocalFileComparator {
  _TolerantComparator(super.testFile);

  static const _maxDiff = 0.025;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    final passed = result.passed || result.diffPercent <= _maxDiff;
    if (!passed) {
      final failure = await generateFailureOutput(result, golden, basedir);
      result.dispose();
      throw FlutterError(failure);
    }
    result.dispose();
    return true;
  }
}

const _book = BookCardData(
  title: 'The Deal',
  author: 'Elle Kennedy',
  progress: 0.4675,
  progressLabel: 'p. 187 of 400 · 47%',
  caption: 'Last read 2 days ago',
  isApproximate: true,
);

final _scenes = <String, Widget>{
  'buttons_fields': Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChapterButton(label: 'Primary', onPressed: () {}),
      const SizedBox(height: 12),
      ChapterButton(
        label: 'Secondary',
        onPressed: () {},
        variant: ChapterButtonVariant.secondary,
        icon: const Icon(Icons.add),
      ),
      const SizedBox(height: 12),
      const ChapterButton(label: 'Disabled', onPressed: null),
      const SizedBox(height: 12),
      const ChapterTextField(label: 'Search', hint: 'Title, author or ISBN'),
    ],
  ),
  'book_cards': Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookCover(title: 'The Deal', author: 'Elle Kennedy', width: 96),
          SizedBox(width: 12),
          SizedBox(width: 150, child: BookGridCard(data: _book)),
        ],
      ),
      const SizedBox(height: 12),
      const BookListTile(data: _book),
      const SizedBox(height: 12),
      ContinueReadingCard(data: _book, resumeLabel: 'Read', onResume: () {}),
    ],
  ),
  'progress_badges': const Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ChapterProgressBar(fraction: 0.5),
      SizedBox(height: 12),
      ChapterProgressRing(fraction: 0.25, center: Text('25%')),
      SizedBox(height: 12),
      RatingStars(rating: 3.5),
      SizedBox(height: 12),
      ApproximateBadge(),
      SizedBox(height: 12),
      SyncBadge(status: SyncPending(3)),
      SizedBox(height: 12),
      SyncBadge(status: SyncOffline()),
    ],
  ),
  'states': Column(
    children: [
      const SizedBox(
        height: 300,
        child: EmptyState(title: 'Nothing here yet', body: 'Books you add will appear here.'),
      ),
      SizedBox(
        height: 240,
        child: ErrorState(message: 'Something went wrong', retryLabel: 'Retry', onRetry: () {}),
      ),
    ],
  ),
  'surfaces': const Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      ChapterSectionHeader(title: 'Currently reading', subtitle: 'Two books'),
      SizedBox(height: 12),
      ChapterStatTile(
        label: 'Pages',
        value: '8,420',
        unit: 'pages',
        caption: 'This year',
        icon: Icons.menu_book_outlined,
      ),
      SizedBox(height: 12),
      ChapterCard(child: ChapterQuote(text: 'All great and precious things are lonely.')),
      SizedBox(height: 12),
      Align(
        alignment: Alignment.centerLeft,
        child: ChapterPill(label: 'Want to Read', tone: ChapterPillTone.highlight),
      ),
    ],
  ),
  'nav_bar': ChapterNavBar(
    selectedIndex: 1,
    onSelected: (_) {},
    items: const [
      ChapterNavItem(label: 'Home', icon: Icons.home_outlined, selectedIcon: Icons.home),
      ChapterNavItem(label: 'Library', icon: Icons.book_outlined, selectedIcon: Icons.book),
      ChapterNavItem(label: 'Search', icon: Icons.search, selectedIcon: Icons.search),
    ],
  ),
};

void main() {
  late GoldenFileComparator previous;

  setUpAll(() {
    previous = goldenFileComparator;
    final dir = (previous as LocalFileComparator).basedir;
    goldenFileComparator = _TolerantComparator(dir.resolve('design_system_golden_test.dart'));
  });
  tearDownAll(() => goldenFileComparator = previous);

  for (final MapEntry(key: name, value: scene) in _scenes.entries) {
    for (final (brightness, scale) in themeVariants) {
      final variant = '${brightness.name}_${scale.toInt()}x';
      testWidgets('$name matches its golden ($variant)', (tester) async {
        tester.view.physicalSize = const Size(420, 2400);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        const key = ValueKey('scene');
        await pumpThemed(
          tester,
          RepaintBoundary(
            key: key,
            child: ColoredBox(
              color: brightness == Brightness.light
                  ? ChapterColors.light.paper
                  : ChapterColors.dark.paper,
              child: Padding(padding: const EdgeInsets.all(16), child: scene),
            ),
          ),
          brightness: brightness,
          textScale: scale,
        );
        await tester.pump();
        expect(tester.takeException(), isNull);
        await expectLater(find.byKey(key), matchesGoldenFile('images/${name}_$variant.png'));
      });
    }
  }
}
