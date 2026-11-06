import 'dart:io';

import 'package:chapter/app/providers.dart';
import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/insights/domain/stats_engine.dart';
import 'package:chapter/features/integrations/data/import_queue.dart';
import 'package:chapter/features/integrations/domain/kindle_clippings.dart';
import 'package:chapter/features/integrations/domain/reading_import.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/profile/data/account_ports.dart';
import 'package:chapter/features/progress/domain/progress_mapper.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:chapter/features/reading/domain/reading_session.dart';
import 'package:chapter/features/reading/domain/session_clock.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../helpers/fake_auth_repository.dart';
import '../helpers/fake_catalog.dart';
import '../helpers/test_app.dart';

class _Wiper implements LocalDataWiper {
  final log = <String>[];

  @override
  Future<void> markPending(String uid) async => log.add('mark:$uid');

  @override
  Future<void> finishPending() async => log.add('finish');
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final now = DateTime(2026, 11, 5, 9);
  const book = BookSummary(title: 'The Deal', authorNames: ['Elle Kennedy'], pageCount: 400);
  late AppDatabase db;
  late FakeClock clock;
  late LwwLibraryRepository repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    clock = FakeClock(now);
    repo = LwwLibraryRepository(
      store: LwwStore(db: db, clock: clock, ids: const UuidV7Generator()),
      db: db,
      clock: clock,
      ids: const UuidV7Generator(),
      uid: FakeAuthRepository.testUser.uid,
      onLocalWrite: () {},
    );
  });

  Future<StatsEngine> stats({bool withDeleted = true}) async => StatsEngine(
    StatsInput(
      entries: await repo.watchEntriesIncludingRemoved().first,
      readThroughs: await repo.watchAllReadThroughs().first,
      sessions: await repo.watchSessions(limit: 1 << 30).first,
      events: await repo.watchAllProgress().first,
      editions: await repo.watchAllEditions().first,
      deletedSessionIds: withDeleted ? await repo.watchDeletedSessionIds().first : const {},
    ),
    toLocal: (t) => t,
  );

  group('statistics', () {
    test('W28: pages of a deleted session do not come back later', () async {
      await repo.add(workId: 'w', book: book, status: ReadingStatus.reading);
      await repo.completeSession(
        ActiveSession(
          id: 's',
          workId: 'w',
          clock: SessionClock.start(
            now,
            const Duration(minutes: 30),
          ).end(now.add(const Duration(minutes: 30))),
        ),
        activeDurationSec: 1800,
        endPosition: const ReadingPosition.page(page: 100),
      );
      await repo.deleteSession('s');
      expect((await stats()).totals().pages, 0);

      clock.advance(const Duration(days: 1));
      await repo.recordProgress('w', const ReadingPosition.page(page: 120));
      expect((await stats()).totals().pages, 20, reason: 'only what is new');
    });

    test('W30: changing a finish date moves the pages; clearing it removes them', () async {
      await repo.add(
        workId: 'w',
        book: book,
        status: ReadingStatus.read,
        finish: ReadFinish.on(DateTime(2019, 6, 1, 12)),
      );
      expect((await stats()).totals(from: '2019-01-01', to: '2019-12-31').pages, 400);

      final through = (await repo.watchReadThroughs('w').first).single;
      await repo.setFinishDate(through.id, ReadFinish.on(DateTime(2021, 3, 4, 12)));
      var s = await stats();
      expect(s.totals(from: '2019-01-01', to: '2019-12-31').pages, 0);
      expect(s.totals(from: '2021-01-01', to: '2021-12-31').pages, 400);

      await repo.setFinishDate(through.id, const ReadFinish.unknown());
      s = await stats();
      expect(s.totals().pages, 0);
      expect(s.totals().books, 0);
    });

    test('W32: a removed book keeps its pages and its place in rankings', () async {
      await repo.add(
        workId: 'w',
        book: book,
        status: ReadingStatus.read,
        finish: ReadFinish.on(DateTime(2026, 6, 1, 12)),
      );
      await repo.remove('w');
      final s = await stats();
      expect(s.totals().books, 1);
      expect(s.totals().pages, 400);
    });
  });

  group('import counts (W46)', () {
    ImportedBook imported(String key) => ImportedBook.fromJson({
      'key': key,
      'source': 'goodreads',
      'title': 'T$key',
      'authors': <String>[],
      'status': 'read',
      'finishedOn': <String>[],
      'undatedReads': 0,
      'owned': false,
    });

    test('progress shows the latest file; earlier ones are recognised', () async {
      final queue = ImportQueue(db, clock);
      await queue.enqueue([imported('a'), imported('b')]);
      await queue.markDone('a', ImportOutcome.added);
      await queue.markDone('b', ImportOutcome.added);
      expect((await queue.watchProgress().first).added, 2);

      clock.advance(const Duration(days: 30));
      final next = [imported('a'), imported('c')];
      expect(await queue.countAlreadyDone(next), 1);
      await queue.enqueue(next);
      await queue.markDone('c', ImportOutcome.added);
      final p = await queue.watchProgress().first;
      expect(p.added, 1, reason: 'not 3');
    });
  });

  group('Kindle device languages (W35)', () {
    ({ClippingKind kind, int? page, int? location, String title}) one(String meta) {
      final file = parseClippings('Dune (Frank Herbert)\n$meta\n\nA line\n==========\n')!;
      final c = file.clippings.single;
      return (kind: c.kind, page: c.page, location: c.location, title: c.title);
    }

    test('highlights and notes are read in each language', () {
      final cases = {
        '- Your Highlight on page 45 | location 678-680 | Added on Thursday, May 9, 2019': (
          ClippingKind.highlight,
          45,
          678,
        ),
        '- Your Highlight on Location 10-11 | Added on Thursday': (
          ClippingKind.highlight,
          null,
          10,
        ),
        '- Your Note on page 7 | location 90 | Added on Thursday': (ClippingKind.note, 7, 90),
        '- Ihre Markierung auf Seite 45 | bei Position 678-680 | Hinzugefügt am Donnerstag': (
          ClippingKind.highlight,
          45,
          678,
        ),
        '- Ihre Notiz bei Position 12 | Hinzugefügt am': (ClippingKind.note, null, 12),
        '- Votre surlignement sur la page 45 | emplacement 678-680 | Ajouté le jeudi': (
          ClippingKind.highlight,
          45,
          678,
        ),
        '- Votre note à l\'emplacement 12 | Ajouté le': (ClippingKind.note, null, 12),
        '- La subrayado en la página 45 | posición 678-680 | Añadido el jueves': (
          ClippingKind.highlight,
          45,
          678,
        ),
        '- La tua evidenziazione a pagina 45 | posizione 678-680 | Aggiunto in data': (
          ClippingKind.highlight,
          45,
          678,
        ),
        '- Seu destaque na página 45 | posição 678-680 | Adicionado': (
          ClippingKind.highlight,
          45,
          678,
        ),
        '- 45ページ|位置No. 678-680のハイライト |作成日': (ClippingKind.highlight, 45, 678),
        '- 您在第 45 页（位置 #678-680）的标注 | 添加于': (ClippingKind.highlight, 45, 678),
      };
      cases.forEach((meta, want) {
        final got = one(meta);
        expect((got.kind, got.page, got.location), want, reason: meta);
        expect(got.title, 'Dune');
      });
    });

    test('bookmarks are skipped in each language and an unknown word is reported', () {
      for (final meta in [
        '- Your Bookmark on page 3',
        '- Ihr Lesezeichen auf Seite 3',
        '- Votre signet sur la page 3',
        '- ブックマーク',
      ]) {
        final file = parseClippings('Dune\n$meta\n\n\n==========\n')!;
        expect(file.clippings, isEmpty, reason: meta);
        expect(file.skipped, 0, reason: meta);
      }
      final unknown = parseClippings('Dune\n- Qwerty 3\n\nText\n==========\n')!;
      expect(unknown.skipped, 1);
    });
  });

  group('app', () {
    Future<void> launch(WidgetTester tester, FakeAuthRepository auth, {_Wiper? wiper}) async {
      tester.view
        ..physicalSize = const Size(1080, 6000)
        ..devicePixelRatio = 2.625;
      addTearDown(tester.view.reset);
      await pumpChapterApp(
        tester,
        auth: auth,
        catalog: FakeCatalogRepository(),
        clock: clock,
        database: db,
        extraOverrides: [if (wiper != null) localDataWiperProvider.overrideWithValue(wiper)],
      );
      addTearDown(() => unmountApp(tester));
    }

    testWidgets('W49: an account deleted elsewhere clears this device', (tester) async {
      final wiper = _Wiper();
      final auth = FakeAuthRepository(initialUser: FakeAuthRepository.testUser);
      await launch(tester, auth, wiper: wiper);
      await tester.tap(find.text('Start reading'));
      await settle(tester);
      expect(wiper.log, isEmpty, reason: 'still exists');

      auth.accountExists = false;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settle(tester);
      expect(wiper.log, ['mark:${FakeAuthRepository.testUser.uid}', 'finish']);
      expect(auth.signOutCalls, 1);
      expect(find.text('Continue with Google'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('W49: the wipe still runs when the SDK signed out by itself', (tester) async {
      final wiper = _Wiper();
      final auth = FakeAuthRepository(initialUser: FakeAuthRepository.testUser);
      await launch(tester, auth, wiper: wiper);
      await tester.tap(find.text('Start reading'));
      await settle(tester);

      auth.accountExists = false;
      auth.signOutWhenChecked = true;
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settle(tester);
      expect(wiper.log, ['mark:${FakeAuthRepository.testUser.uid}', 'finish']);
      await unmountApp(tester);
    });

    testWidgets('W18: wishlist and edition details on the book page', (tester) async {
      await tester.runAsync(
        () => repo.add(
          workId: theDeal.id,
          book: book,
          status: ReadingStatus.reading,
          edition: UserEdition(
            editionId: 'e',
            workId: theDeal.id,
            format: 'paperback',
            pageCount: 400,
          ),
        ),
      );
      await launch(tester, FakeAuthRepository(initialUser: FakeAuthRepository.testUser));
      await tester.tap(find.text('Start reading'));
      await settle(tester);
      await tester.tap(find.text('The Deal').first);
      await settle(tester);

      Future<void> menu(String item) async {
        await tester.tap(find.byType(PopupMenuButton<String>));
        await settle(tester);
        await tester.tap(find.text(item));
        await settle(tester);
      }

      await menu('Add to wishlist');
      var entry = (await tester.runAsync<LibraryEntry?>(() => repo.watchEntry(theDeal.id).first))!;
      expect(entry.isWishlist, isTrue);
      await menu('Remove from wishlist');
      entry = (await tester.runAsync<LibraryEntry?>(() => repo.watchEntry(theDeal.id).first))!;
      expect(entry.isWishlist, isFalse);

      await menu('Edition details');
      await tester.enterText(find.byKey(const Key('edition-start')), '20');
      await tester.enterText(find.byKey(const Key('edition-end')), '10');
      await tester.tap(find.byKey(const Key('edition-save')));
      await settle(tester);
      expect(find.byKey(const Key('edition-error')), findsOneWidget);

      await tester.enterText(find.byKey(const Key('edition-pages')), '420');
      await tester.enterText(find.byKey(const Key('edition-end')), '400');
      await tester.tap(find.byKey(const Key('edition-save')));
      await settle(tester);
      final e = (await tester.runAsync(() => repo.watchEditions(theDeal.id).first))!.single;
      expect(e.effectivePageCount, 420);
      expect(e.contentStartPage, 20);
      expect(e.contentEndPage, 400);
      await unmountApp(tester);
    });

    test('W18: match points round-trip through storage', () async {
      await repo.add(workId: 'w', book: book, status: ReadingStatus.reading);
      await repo.saveEditionDetails(
        const UserEdition(
          editionId: 'a',
          workId: 'w',
          format: 'audible',
          audioDurationSec: 3600,
          audioDurationOverride: 3700,
          calibration: [CalibrationPoint(page: 10, audioSeconds: 600)],
        ),
      );
      final e = (await repo.watchEditions('w').first).single;
      expect(e.effectiveAudioDuration, 3700);
      expect(e.calibration.single.audioSeconds, 600);
    });
  });

  group('FileLocalDataWiper', () {
    late Directory docs;
    late Directory temp;

    setUp(() {
      docs = Directory.systemTemp.createTempSync('chapter_docs');
      temp = Directory.systemTemp.createTempSync('chapter_tmp');
      addTearDown(() {
        docs.deleteSync(recursive: true);
        temp.deleteSync(recursive: true);
      });
      PathProviderPlatform.instance = _Paths(docs.path, temp.path);
    });

    File inDocs(String name) => File('${docs.path}/$name')..writeAsStringSync('x');

    test('marked accounts go, others stay, and a kill just before is finished later', () async {
      const wiper = FileLocalDataWiper();
      final mine = inDocs('chapter_alice.sqlite');
      final wal = inDocs('chapter_alice.sqlite-wal');
      final other = inDocs('chapter_bob.sqlite');
      final cover = File('${temp.path}/cover.jpg')..writeAsStringSync('x');

      await wiper.finishPending();
      expect(mine.existsSync(), isTrue, reason: 'nothing marked, nothing touched');
      expect(cover.existsSync(), isTrue);

      await wiper.markPending('alice');
      // The app is killed here. On the next launch:
      await const FileLocalDataWiper().finishPending();

      expect(mine.existsSync(), isFalse);
      expect(wal.existsSync(), isFalse);
      expect(cover.existsSync(), isFalse);
      expect(other.existsSync(), isTrue, reason: "another account's database");
      expect(docs.listSync().whereType<File>().map((f) => f.uri.pathSegments.last), [
        'chapter_bob.sqlite',
      ], reason: 'marker gone too');
    });
  });
}

class _Paths extends PathProviderPlatform {
  _Paths(this.docs, this.temp);

  final String docs;
  final String temp;

  @override
  Future<String?> getApplicationDocumentsPath() async => docs;

  @override
  Future<String?> getTemporaryPath() async => temp;
}
