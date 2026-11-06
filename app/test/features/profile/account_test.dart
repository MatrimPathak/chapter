import 'dart:convert';

import 'package:chapter/app/providers.dart';
import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/error/failure.dart';
import 'package:chapter/core/sync/lww_store.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/core/utils/id_generator.dart';
import 'package:chapter/features/library/data/lww_library_repository.dart';
import 'package:chapter/features/library/domain/library_models.dart';
import 'package:chapter/features/notes/data/lww_notes_repository.dart';
import 'package:chapter/features/notes/domain/note.dart';
import 'package:chapter/features/profile/application/data_exporter.dart';
import 'package:chapter/features/profile/data/account_ports.dart';
import 'package:chapter/features/progress/domain/reading_position.dart';
import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/fake_auth_repository.dart';
import '../../helpers/fake_catalog.dart';
import '../../helpers/test_app.dart';

class FakeRemote implements AccountRemote {
  final outcomes = <DeleteAccountOutcome>[];
  int calls = 0;
  Object? throwing;

  @override
  Future<DeleteAccountOutcome> deleteAccount() async {
    calls++;
    final t = throwing;
    if (t != null) throw t;
    return outcomes.isEmpty ? DeleteAccountOutcome.deleted : outcomes.removeAt(0);
  }
}

class FakeWiper implements LocalDataWiper {
  final log = <String>[];

  @override
  Future<void> markPending(String uid) async => log.add('mark:$uid');

  @override
  Future<void> finishPending() async => log.add('finish');
}

class FakeSharer implements ExportSharer {
  List<ExportFile>? shared;
  Object? throwing;

  @override
  Future<void> share(List<ExportFile> files) async {
    final t = throwing;
    if (t != null) throw t;
    shared = files;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  final uid = FakeAuthRepository.testUser.uid;
  final now = DateTime(2026, 11, 5, 9);
  late AppDatabase db;
  late FakeClock clock;
  late LwwLibraryRepository repo;
  late LwwNotesRepository notes;

  setUp(() {
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
  });

  group('export', () {
    const book = BookSummary(
      title: 'The Deal, "again"',
      authorNames: ['Elle Kennedy', 'A N Other'],
      pageCount: 400,
    );

    Future<List<ExportFile>> export() => DataExporter(db, uid, now).build();

    test('every table is either exported or deliberately left out', () {
      final known = {...DataExporter.exportedTables, ...DataExporter.excludedTables};
      expect(db.allTables.map((t) => t.actualTableName).toSet(), known);
    });

    test('JSON holds everything, and removed books stay in it', () async {
      await repo.add(workId: 'w1', book: book, status: ReadingStatus.reading);
      await repo.recordProgress('w1', const ReadingPosition.page(page: 100));
      await notes.add(workId: 'w1', text: 'A thought', kind: NoteKind.quote, page: 3);
      await repo.add(workId: 'w2', book: book);
      await repo.remove('w2');

      final json = jsonDecode((await export()).first.content) as Map<String, Object?>;
      expect(json['format'], 'chapter-export');
      expect(json['userId'], uid);
      expect((json['library']! as List).map((b) => (b as Map)['id']), containsAll(['w1', 'w2']));
      expect(json['readThroughs'], hasLength(1));
      expect((json['notes']! as List).single, containsPair('text', 'A thought'));
      final event = (json['progressEvents']! as List).single as Map;
      expect(event['position'], isA<Map<String, Object?>>(), reason: 'unwrapped, not a string');
      expect(event['recordedAt'], isA<String>());
    });

    test('the account email is left out', () async {
      await db
          .into(db.lwwDocuments)
          .insert(
            LwwDocumentsCompanion.insert(
              path: 'users/$uid',
              fieldsJson: const Value('{"email":"a@b.c","theme":"dark"}'),
            ),
          );
      final json = jsonDecode((await export()).first.content) as Map<String, Object?>;
      expect(json['profile'], {'theme': 'dark'});
    });

    test('an empty account exports cleanly', () async {
      final files = await export();
      expect(files, hasLength(4));
      expect(files.map((f) => f.name), contains('chapter-export-2026-11-05.json'));
      jsonDecode(files.first.content);
      for (final csv in files.skip(1)) {
        expect(csv.content.startsWith('﻿'), isTrue, reason: csv.name);
        expect(csv.content.trim().split('\r\n'), hasLength(1), reason: 'header only');
      }
    });

    test('CSV: readable library with quoting, and removed books left out', () async {
      await repo.add(
        workId: 'w1',
        book: book,
        status: ReadingStatus.read,
        finish: ReadFinish.on(DateTime(2021, 3, 4, 12)),
      );
      await repo.add(workId: 'w2', book: book);
      await repo.remove('w2');
      final library = (await export())[1].content;
      final lines = library.trim().split('\r\n');
      expect(lines, hasLength(2));
      expect(lines[1], startsWith('"The Deal, ""again""",Elle Kennedy; A N Other,read,'));
      expect(lines[1], contains('2021-03-04'));
    });

    test('CSV cells can\'t run as spreadsheet formulas', () {
      expect(DataExporter.csvCell('=HYPERLINK("x")'), '"\'=HYPERLINK(""x"")"');
      expect(DataExporter.csvCell('+1'), "'+1");
      expect(DataExporter.csvCell('@a'), "'@a");
      expect(DataExporter.csvCell('-a'), "'-a");
      expect(DataExporter.csvCell(-5), '-5', reason: 'real numbers stay numbers');
      expect(DataExporter.csvCell('line\nbreak'), '"line\nbreak"');
      expect(DataExporter.csvCell(null), '');
    });
  });

  group('screens', () {
    late FakeRemote remote;
    late FakeWiper wiper;
    late FakeSharer sharer;
    late FakeAuthRepository auth;

    setUp(() {
      remote = FakeRemote();
      wiper = FakeWiper();
      sharer = FakeSharer();
      auth = FakeAuthRepository(initialUser: FakeAuthRepository.testUser);
    });

    Future<void> openProfile(WidgetTester tester) async {
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
        extraOverrides: [
          accountRemoteProvider.overrideWithValue(remote),
          localDataWiperProvider.overrideWithValue(wiper),
          exportSharerProvider.overrideWithValue(sharer),
        ],
      );
      addTearDown(() => unmountApp(tester));
      await tester.tap(find.text('Start reading'));
      await settle(tester);
      await tester.tap(find.text('Profile'));
      await settle(tester);
    }

    Future<void> confirmDeletion(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('delete-account')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('delete-word')), 'DELETE');
      await settle(tester);
      await tester.tap(find.byKey(const Key('delete-confirm')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      await settle(tester);
    }

    testWidgets('export reaches the share sheet; a failure says so', (tester) async {
      await openProfile(tester);
      await tester.tap(find.byKey(const Key('export-data')));
      await settle(tester);
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await settle(tester);
      expect(sharer.shared, hasLength(4));

      sharer.throwing = StateError('no share sheet');
      await tester.tap(find.byKey(const Key('export-data')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await settle(tester);
      expect(find.textContaining('Couldn’t create the export'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await unmountApp(tester);
    });

    testWidgets('nothing happens until DELETE is typed exactly', (tester) async {
      await openProfile(tester);
      await tester.tap(find.byKey(const Key('delete-account')));
      await settle(tester);
      for (final wrong in ['', 'delete', 'DELETE IT']) {
        await tester.enterText(find.byKey(const Key('delete-word')), wrong);
        await settle(tester);
        await tester.tap(find.byKey(const Key('delete-confirm')), warnIfMissed: false);
        await settle(tester);
        expect(remote.calls, 0, reason: wrong);
      }
      await unmountApp(tester);
    });

    testWidgets('success: server first, then wiped and signed out', (tester) async {
      await openProfile(tester);
      await confirmDeletion(tester);
      expect(remote.calls, 1);
      expect(auth.signOutCalls, 1);
      expect(wiper.log, ['mark:$uid', 'finish']);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Your account has been deleted.'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('stale sign-in: reauthenticates once and retries', (tester) async {
      remote.outcomes.add(DeleteAccountOutcome.needsRecentSignIn);
      await openProfile(tester);
      await confirmDeletion(tester);
      expect(auth.reauthCalls, 1);
      expect(remote.calls, 2);
      expect(auth.signOutCalls, 1);
      await unmountApp(tester);
    });

    testWidgets('backing out of sign-in deletes nothing', (tester) async {
      remote.outcomes.add(DeleteAccountOutcome.needsRecentSignIn);
      auth.nextReauthFailure = const CancelledFailure('no');
      await openProfile(tester);
      await confirmDeletion(tester);
      expect(remote.calls, 1);
      expect(auth.signOutCalls, 0);
      expect(wiper.log, isEmpty);
      expect(find.textContaining('nothing was deleted'), findsOneWidget);
      await unmountApp(tester);
    });

    testWidgets('server failure or offline: account and data stay, sync resumes', (tester) async {
      for (final fail in <void Function()>[
        () => remote.outcomes.add(DeleteAccountOutcome.failed),
        () => remote.throwing = StateError('offline'),
      ]) {
        fail();
        await repo.add(
          workId: 'w${remote.calls}',
          book: const BookSummary(title: 'Kept'),
        );
      }
      await openProfile(tester);
      await confirmDeletion(tester);
      expect(auth.signOutCalls, 0);
      expect(wiper.log, isEmpty);
      expect(find.textContaining('Check your connection'), findsOneWidget);
      expect(await tester.runAsync(() => repo.watchEntries().first), isNotEmpty);
      await unmountApp(tester);
    });
  });
}
