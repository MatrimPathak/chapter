import 'dart:convert';
import 'dart:io' show Platform;

import 'package:chapter/core/design_system/design_system.dart';
import 'package:chapter/core/sync/sync_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/pump_app.dart';

/// Exact pixel comparison of the design system, with the app's real fonts.
///
/// Font rendering differs per OS, so the images are the ones made on Linux and
/// these tests run only there, as CI does. After an intended visual change,
/// regenerate them on Linux with the Flutter version in `ci.yml`:
/// `flutter test --update-goldens test/goldens`
bool get _onLinux => Platform.isLinux;

/// Golden tests otherwise draw every glyph as a box.
Future<void> _loadFonts() async {
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json')) as List<dynamic>;
  for (final entry in manifest.cast<Map<String, dynamic>>()) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in (entry['fonts'] as List<dynamic>).cast<Map<String, dynamic>>()) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
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
  setUpAll(_loadFonts);

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
      }, skip: !_onLinux);
    }
  }
}
