import 'package:chapter/app/providers.dart';
import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/error/result.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:chapter/features/integrations/data/import_queue.dart';
import 'package:chapter/features/integrations/data/platform_ports.dart';
import 'package:chapter/features/integrations/domain/integration.dart';
import 'package:chapter/features/integrations/domain/reading_import.dart' show parseReadingExport;
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/library/presentation/library_providers.dart';
import 'package:chapter/features/notes/data/lww_notes_repository.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_catalog.dart';
import '../../helpers/fake_session_ports.dart';
import '../../helpers/test_app.dart';
import 'parsers_test.dart' show goodreadsHeader, goodreadsRow;

class FakeOpener implements LinkOpener {
  final opened = <Uri>[];
  Object? throwing;
  bool result = true;
  int attempts = 0;

  @override
  Future<bool> open(Uri uri) async {
    attempts++;
    final t = throwing;
    if (t != null) throw t;
    opened.add(uri);
    return result;
  }
}

class FakePicker implements TextFilePicker {
  String? content;
  Object? throwing;

  @override
  Future<String?> pick(List<String> extensions) async {
    final t = throwing;
    if (t != null) throw t;
    return content;
  }
}

class _Broken implements Integration {
  const _Broken(this.id);

  @override
  final IntegrationId id;

  @override
  Set<IntegrationCapability> get capabilities => throw StateError('broken');

  @override
  Stream<IntegrationStatus> get status => throw StateError('broken');
}

class _BrokenStream implements Integration {
  const _BrokenStream(this.id);

  @override
  final IntegrationId id;

  @override
  Set<IntegrationCapability> get capabilities => const {};

  @override
  Stream<IntegrationStatus> get status => Stream.error(StateError('broken'));
}

const clippings =
    'The Deal (Elle Kennedy)\n'
    '- Your Highlight on page 45 | location 678-680 | Added on Thursday, May 9, 2019 5:36:43 PM\n'
    '\n'
    'A line I liked\n'
    '==========\n'
    'Some Other Book (Bo Ng)\n'
    '- Your Highlight on Location 10 | Added on Thursday, May 9, 2019 5:36:43 PM\n'
    '\n'
    'Not in the library\n'
    '==========\n';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime(2026, 11, 5, 9);
  late AppDatabase db;
  late FakeClock clock;
  late LwwLibraryRepository repo;
  late LwwNotesRepository notes;
  late FakeOpener opener;
  late FakePicker picker;
  late FakeCatalogRepository catalog;
  final uid = FakeAuthRepository.testUser.uid;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    clock = FakeClock(now);
    final store = LwwStore(db: db, clock: clock, ids: const UuidV7Generator());
    repo = LwwLibraryRepository(
      store: store,
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: () {},
    );
    notes = LwwNotesRepository(
      store: store,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: uid,
      onLocalWrite: () {},
    );
    opener = FakeOpener();
    picker = FakePicker();
    catalog = FakeCatalogRepository();
  });

  Future<void> launch(
    WidgetTester tester, {
    List<Integration>? integrations,
    bool seedBook = true,
  }) async {
    tester.view
      ..physicalSize = const Size(1080, 4000)
      ..devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    if (seedBook) {
      await repo.add(
        workId: theDeal.id,
        book: const BookSummary(title: 'The Deal', authorNames: ['Elle Kennedy'], pageCount: 400),
        status: ReadingStatus.reading,
      );
    }
    final overrides = <Override>[
      linkOpenerProvider.overrideWithValue(opener),
      textFilePickerProvider.overrideWithValue(picker),
      if (integrations != null) integrationsProvider.overrideWithValue(integrations),
    ];
    await pumpChapterApp(
      tester,
      auth: FakeAuthRepository(initialUser: FakeAuthRepository.testUser),
      catalog: catalog,
      clock: clock,
      database: db,
      notifications: FakeSessionNotifications(),
      extraOverrides: overrides,
    );
    addTearDown(() => unmountApp(tester));
    await tester.tap(find.text('Start reading')); // onboarding
    await settle(tester);
  }

  Future<void> openServices(WidgetTester tester) async {
    await tester.tap(find.text('Profile'));
    await settle(tester);
    await tester.tap(find.text('Connected services'));
    await settle(tester);
  }

  testWidgets('no card or link claims automatic sync', (tester) async {
    await launch(tester);
    await openServices(tester);
    expect(find.textContaining('can’t read your Kindle progress'), findsOneWidget);
    expect(find.textContaining('can’t read your Audible progress'), findsOneWidget);
    expect(find.textContaining('can’t see or control'), findsOneWidget);
    final texts = tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' ');
    expect(
      RegExp('automatic sync|syncs with|sign in to', caseSensitive: false).hasMatch(texts),
      isFalse,
    );
    await unmountApp(tester);
  });

  testWidgets('CSV: preview, then books arrive; nothing changes before Import', (tester) async {
    catalog.onLookup = (isbn) => const Result.ok(WorkLookup(work: theDeal, editionId: 'e1'));
    picker.content = [
      goodreadsHeader,
      goodreadsRow(),
      goodreadsRow(id: '2', title: '', isbn13: '=""', isbn: '=""'),
    ].join('\n');
    await launch(tester, seedBook: false);
    await openServices(tester);
    await tester.tap(find.byKey(const ValueKey('integration-goodreads-action')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('import-choose')));
    await settle(tester);

    expect(find.text('1 book from Goodreads'), findsOneWidget);
    expect(find.textContaining('1 entry couldn’t be read'), findsOneWidget);
    expect(await tester.runAsync(() => repo.watchEntries().first), isEmpty);

    await tester.tap(find.byKey(const Key('import-start')));
    await settle(tester);
    expect(find.text('Added: 1'), findsOneWidget);
    final e = (await tester.runAsync(() => repo.watchEntry(theDeal.id).first))!;
    expect(e.status, ReadingStatus.read);
    expect(e.rating, 4);
    await unmountApp(tester);
  });

  testWidgets('CSV: not found is listed; a wrong file says so', (tester) async {
    catalog.onSearch = (q, _, _) => const Result.ok(SearchPage());
    picker.content = 'just,some,file\n1,2,3';
    await launch(tester);
    await openServices(tester);
    await tester.tap(find.byKey(const ValueKey('integration-goodreads-action')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('import-choose')));
    await settle(tester);
    expect(find.textContaining('doesn’t look like a Goodreads'), findsOneWidget);

    picker.content = [
      goodreadsHeader,
      goodreadsRow(title: 'Obscure', isbn13: '=""', isbn: '=""'),
    ].join('\n');
    await tester.tap(find.byKey(const Key('import-choose')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('import-start')));
    await settle(tester);
    expect(find.text('1 book not found'), findsOneWidget);
    expect(find.text('Obscure'), findsOneWidget);
    await unmountApp(tester);
  });

  testWidgets('clippings: match, import, reimport; unmatched books are listed', (tester) async {
    picker.content = clippings;
    await launch(tester);
    await openServices(tester);
    await tester.tap(find.byKey(const ValueKey('integration-kindle-action')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('import-choose')));
    await settle(tester);
    expect(find.text('1 highlight or note matches your library'), findsOneWidget);
    expect(find.text('Some Other Book (1)'), findsOneWidget);

    await tester.tap(find.byKey(const Key('clippings-import')));
    await settle(tester);
    expect(find.text('Added 1. Already had 0.'), findsOneWidget);
    final saved = (await tester.runAsync(() => notes.watchNotes(theDeal.id).first))!;
    expect(saved.single.text, 'A line I liked');
    expect(saved.single.page, 45);
    expect(saved.single.location, 678);

    // Edited since: reimporting leaves it alone.
    await tester.runAsync(() => notes.edit(saved.single.id, text: 'Edited', page: 45));
    await tester.tap(find.byKey(const Key('import-choose')));
    await settle(tester);
    await tester.tap(find.byKey(const Key('clippings-import')));
    await settle(tester);
    expect(find.text('Added 0. Already had 1.'), findsOneWidget);
    final after = (await tester.runAsync(() => notes.watchNotes(theDeal.id).first))!;
    expect(after.single.text, 'Edited');
    await unmountApp(tester);
  });

  testWidgets('Audible: add an edition, log time, progress carries over labelled', (tester) async {
    await launch(tester);
    await tester.runAsync(
      () => repo.recordProgress(theDeal.id, const ReadingPosition.percent(percent: 50)),
    );
    await tester.tap(find.text('The Deal').first);
    await settle(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
    await tester.tap(find.text('Add audiobook edition'));
    await settle(tester);

    // A bare number is refused: minutes or hours would be a guess.
    await tester.enterText(find.byKey(const Key('audio-duration')), '11');
    await tester.tap(find.byKey(const Key('audio-save')));
    await settle(tester);
    expect(find.textContaining('Enter the length'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('audio-duration')), '11:20:00');
    await tester.tap(find.byKey(const Key('audio-save')));
    await settle(tester);
    expect(find.textContaining('can’t read your Audible progress'), findsOneWidget);
    expect(
      find.text('≈ approximate').evaluate().isNotEmpty ||
          find.textContaining('50%').evaluate().isNotEmpty,
      isTrue,
    );

    await tester.tap(find.byKey(const Key('open-audible')));
    await settle(tester);
    expect(opener.opened.single.host, 'www.audible.com');
    expect(opener.opened.single.queryParameters['keywords'], theDeal.title);

    await tester.tap(find.text('Update progress'));
    await settle(tester);
    expect(find.text('Time'), findsOneWidget, reason: 'audio time, not pages');
    await tester.enterText(find.byKey(const Key('progress-input')), '8:30:00');
    await settle(tester);
    await tester.tap(find.text('Save'));
    await settle(tester);
    final entry = (await tester.runAsync(() => repo.watchEntry(theDeal.id).first))!;
    final latest = (await tester.runAsync(() => repo.watchLatestProgress().first))!;
    expect(latest[entry.activeReadThroughId]!.fraction, closeTo(0.75, 1e-9));
    await unmountApp(tester);
  });

  testWidgets('Spotify: links open with no account; a failure stays a message', (tester) async {
    await launch(tester);
    await tester.tap(find.text('Reading').last);
    await settle(tester);
    await tester.tap(find.byKey(const Key('music-card')));
    await settle(tester);
    await tester.tap(find.text('Reading playlists'));
    await settle(tester);
    expect(
      opener.opened.single.toString(),
      'https://open.spotify.com/search/music%20for%20reading/playlists',
    );

    opener.result = false;
    await tester.tap(find.text('Classical'));
    await settle(tester);
    expect(find.text('Couldn’t open that link.'), findsOneWidget);

    await tester.pump(const Duration(seconds: 6)); // the message covers the last link
    await settle(tester);
    opener.throwing = StateError('no browser');
    final attempts = opener.attempts;
    await tester.tap(find.text('Ambient'));
    await settle(tester);
    expect(opener.attempts, attempts + 1);
    expect(find.text('Couldn’t open that link.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await unmountApp(tester);
  });

  testWidgets('Audiobook: one edition to edit, reachable after switching away', (tester) async {
    await launch(tester);
    await tester.tap(find.text('The Deal').first);
    await settle(tester);

    Future<void> menu(String item) async {
      await tester.tap(find.byType(PopupMenuButton<String>));
      await settle(tester);
      await tester.tap(find.text(item));
      await settle(tester);
    }

    await menu('Add audiobook edition');
    await tester.enterText(find.byKey(const Key('audio-duration')), '11:20:00');
    await tester.tap(find.byKey(const Key('audio-save')));
    await settle(tester);
    expect(find.text('Start a listening session'), findsOneWidget);

    await menu('Edit audiobook edition');
    final field = tester.widget<TextField>(find.byKey(const Key('audio-duration')));
    expect(field.controller!.text, '11:20:00');
    expect(field.controller!.selection.end - field.controller!.selection.start, 8);
    await tester.enterText(find.byKey(const Key('audio-duration')), '12:00:00');
    await tester.tap(find.byKey(const Key('audio-save')));
    await settle(tester);
    final audio = (await tester.runAsync(
      () => repo.watchEditions(theDeal.id).first,
    ))!.where((e) => e.metrics.isAudio).toList();
    expect(audio.single.audioDurationSec, 12 * 3600);

    // Switch to a catalog edition, then back from the picker.
    final print = theDeal.editions.first;
    await tester.runAsync(() => repo.setActiveEdition(theDeal.id, userEditionOf(print)));
    await settle(tester);
    expect(find.text('Start a reading session'), findsOneWidget);
    await menu('Change edition');
    await tester.tap(find.textContaining('12:00:00'));
    await settle(tester);
    final entry = (await tester.runAsync(() => repo.watchEntry(theDeal.id).first))!;
    expect(entry.activeEditionId, audio.single.editionId);
    await unmountApp(tester);
  });

  test('W58: Audible links go to the local store, falling back to the US', () {
    expect(ExternalLinks.audibleSearch('Dune', country: 'IN').host, 'www.audible.in');
    expect(ExternalLinks.audibleSearch('Dune', country: 'gb').host, 'www.audible.co.uk');
    expect(ExternalLinks.audibleSearch('Dune', country: 'US').host, 'www.audible.com');
    expect(ExternalLinks.audibleSearch('Dune', country: 'ZZ').host, 'www.audible.com');
    expect(ExternalLinks.audibleSearch('Dune').host, 'www.audible.com');
    expect(ExternalLinks.audibleSearch('Dune', country: 'DE').queryParameters['keywords'], 'Dune');
  });

  testWidgets('typing in the progress field replaces what is there', (tester) async {
    await launch(tester);
    await tester.tap(find.text('The Deal').first);
    await settle(tester);
    await tester.tap(find.text('Update progress'));
    await settle(tester);
    final input = tester.widget<TextField>(find.byKey(const Key('progress-input')));
    final text = input.controller!;
    expect(text.text, isNotEmpty);
    expect(text.selection.start, 0);
    expect(text.selection.end, text.text.length);
    await unmountApp(tester);
  });

  test('removing and re-adding as Read keeps one read; as Reading starts another', () async {
    const book = BookSummary(title: 'The Deal', authorNames: ['Elle Kennedy'], pageCount: 400);
    await repo.add(
      workId: theDeal.id,
      book: book,
      status: ReadingStatus.read,
      finish: ReadFinish.on(DateTime(2019, 6, 1, 12)),
    );
    expect(await repo.restoresFinishedRead(theDeal.id), isFalse, reason: 'still in the library');
    await repo.remove(theDeal.id);
    expect(await repo.restoresFinishedRead(theDeal.id), isTrue);

    await repo.add(workId: theDeal.id, book: book, status: ReadingStatus.read);
    final throughs = await repo.watchReadThroughs(theDeal.id).first;
    expect(throughs, hasLength(1));
    expect(throughs.single.finishedAt?.toLocal(), DateTime(2019, 6, 1, 12));
    expect((await repo.watchEntry(theDeal.id).first)!.status, ReadingStatus.read);

    await repo.remove(theDeal.id);
    await repo.add(workId: theDeal.id, book: book, status: ReadingStatus.reading);
    expect(await repo.watchReadThroughs(theDeal.id).first, hasLength(2));
  });

  testWidgets('import separates added, already there and removed earlier', (tester) async {
    catalog.onLookup = (isbn) => const Result.ok(WorkLookup(work: theDeal, editionId: 'e1'));
    final queue = ImportQueue(db, clock);
    await tester.runAsync(() async {
      await queue.enqueue(parseReadingExport([goodreadsHeader, goodreadsRow()].join('\n'))!.books);
    });
    picker.content = [goodreadsHeader, goodreadsRow()].join('\n');
    await launch(tester);
    await openServices(tester);
    await tester.tap(find.byKey(const ValueKey('integration-goodreads-action')));
    await settle(tester);
    expect(find.text('Added: 0'), findsOneWidget);
    expect(find.text('Already in your library: 1'), findsOneWidget);
    await unmountApp(tester);
  });

  group('fault injection', () {
    for (final (name, make) in [('throws', _Broken.new), ('errors', _BrokenStream.new)]) {
      for (final id in IntegrationId.values) {
        testWidgets('${id.name} $name: only its own card is affected', (tester) async {
          await launch(
            tester,
            integrations: [for (final i in defaultIntegrations) i.id == id ? make(id) : i],
          );
          // Home and Library still work.
          expect(find.text('Continue reading'), findsOneWidget);
          await tester.tap(find.text('Library'));
          await settle(tester);
          expect(find.text('The Deal'), findsWidgets);

          await tester.tap(find.text('Reading').last);
          await settle(tester);
          expect(
            find.byKey(const Key('music-card')),
            id == IntegrationId.spotify ? findsNothing : findsOneWidget,
          );
          expect(find.text('What are you reading?'), findsOneWidget);

          await openServices(tester);
          expect(find.byKey(ValueKey('integration-${id.name}-unavailable')), findsOneWidget);
          for (final other in IntegrationId.values.where((o) => o != id)) {
            expect(find.byKey(ValueKey('integration-${other.name}')), findsOneWidget);
            expect(find.byKey(ValueKey('integration-${other.name}-unavailable')), findsNothing);
          }
          expect(tester.takeException(), isNull);
          await unmountApp(tester);
        });
      }
    }

    testWidgets('a file that can\'t be read stays on the import screen', (tester) async {
      picker.throwing = StateError('denied');
      await launch(tester);
      await openServices(tester);
      await tester.tap(find.byKey(const ValueKey('integration-goodreads-action')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('import-choose')));
      await settle(tester);
      expect(find.text('Couldn’t read that file.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountApp(tester);
    });

    testWidgets('import with the catalog down: books wait, the app is fine', (tester) async {
      catalog.onLookup = (_) => throw StateError('catalog down');
      picker.content = [goodreadsHeader, goodreadsRow()].join('\n');
      await launch(tester);
      await openServices(tester);
      await tester.tap(find.byKey(const ValueKey('integration-goodreads-action')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('import-choose')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('import-start')));
      await settle(tester);
      expect(find.text('Still to look up: 1'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountApp(tester);
      // The runner is waiting to retry; let the test binding drain that timer.
      await tester.pump(const Duration(minutes: 6));
    });
  });
}
