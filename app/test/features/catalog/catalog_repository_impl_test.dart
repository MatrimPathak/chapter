import 'dart:io';

import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/error/failure.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/features/catalog/data/catalog_remote.dart';
import 'package:chapter/features/catalog/data/catalog_repository_impl.dart';
import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../helpers/fake_catalog.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late AppDatabase db;
  late FakeCatalogRemote remote;
  late CatalogRepositoryImpl repo;
  final clock = FakeClock(DateTime.utc(2026, 11, 4, 10));

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    remote = FakeCatalogRemote();
    repo = CatalogRepositoryImpl(remote: remote, db: db, clock: clock);
  });

  tearDown(() => db.close());

  Map<String, dynamic> pageJson(List<WorkSummary> results, {bool hasMore = false}) => {
    'results': [for (final r in results) r.toJson()..['ref'] = r.ref.toJson()],
    'page': 1,
    'hasMore': hasMore,
    'provider': 'openLibrary',
    'degraded': false,
  };

  group('search', () {
    test('sends normalized query and decodes results', () async {
      remote.handlers['catalogSearch'] = (_) => pageJson([summary('The Deal', year: 2015)]);
      final result = await repo.search('  the   deal ', field: SearchField.title);
      expect(result.valueOrNull?.results.single.title, 'The Deal');
      expect(remote.calls.single.$2, {
        'text': 'the deal',
        'field': 'title',
        'page': 1,
        'pageSize': 20,
      });
    });

    test('rejects queries shorter than two characters without calling the server', () async {
      final result = await repo.search('a');
      expect(result.failureOrNull, isA<ValidationFailure>());
      expect(remote.calls, isEmpty);
    });

    test('serves the cached page when offline and marks it fromCache', () async {
      remote.handlers['catalogSearch'] = (_) => pageJson([summary('The Deal')]);
      await repo.search('the deal');
      remote.handlers['catalogSearch'] = (_) => throw const CatalogRemoteException('unavailable');
      final offline = await repo.search('The Deal');
      expect(offline.valueOrNull?.fromCache, isTrue);
      expect(offline.valueOrNull?.results.single.title, 'The Deal');
    });

    test('offline with no cached page searches cached books by title or author', () async {
      remote.handlers['catalogGetWork'] = (_) => {'work': theDeal.toJson(), 'editionId': 'e1'};
      await repo.getWork(const WorkByRef(dealRef));
      remote.handlers['catalogSearch'] = (_) => throw const CatalogRemoteException('unavailable');
      final byAuthor = await repo.search('kennedy');
      expect(byAuthor.valueOrNull?.results.single.id, theDeal.id);
      expect(byAuthor.valueOrNull?.fromCache, isTrue);
    });

    test('maps server error codes to failures', () async {
      for (final (code, type) in [
        ('not-found', NotFoundFailure),
        ('resource-exhausted', RateLimitedFailure),
        ('unauthenticated', UnauthorizedFailure),
        ('internal', UnknownFailure),
      ]) {
        remote.handlers['catalogSearch'] = (_) => throw CatalogRemoteException(code);
        final result = await repo.search('nothing cached $code');
        expect(result.failureOrNull.runtimeType, type, reason: code);
      }
    });
  });

  group('works', () {
    test('caches a work and serves it offline by id and by provider ref', () async {
      remote.handlers['catalogGetWork'] = (_) => {'work': theDeal.toJson(), 'editionId': 'e1'};
      expect((await repo.getWork(const WorkByRef(dealRef))).valueOrNull?.title, 'The Deal');
      remote.handlers['catalogGetWork'] = (_) => throw const CatalogRemoteException('unavailable');
      expect((await repo.getWork(WorkById(theDeal.id))).valueOrNull?.id, theDeal.id);
      expect((await repo.getWork(const WorkByRef(dealRef))).valueOrNull?.id, theDeal.id);
    });

    test('does not mask non-network errors with stale cache', () async {
      remote.handlers['catalogGetWork'] = (_) => {'work': theDeal.toJson(), 'editionId': 'e1'};
      await repo.getWork(WorkById(theDeal.id));
      remote.handlers['catalogGetWork'] = (_) => throw const CatalogRemoteException('not-found');
      expect((await repo.getWork(WorkById(theDeal.id))).failureOrNull, isA<NotFoundFailure>());
    });

    test('an ISBN lookup also caches the work for offline use', () async {
      remote.handlers['catalogLookupIsbn'] = (_) => {'work': theDeal.toJson(), 'editionId': 'e1'};
      final lookup = await repo.lookupIsbn('0349440840');
      expect(lookup.valueOrNull?.editionId, 'e1');
      remote.handlers['catalogGetWork'] = (_) => throw const CatalogRemoteException('unavailable');
      expect((await repo.getWork(WorkById(theDeal.id))).isOk, isTrue);
    });
  });

  group('recent searches', () {
    test('most recent first, deduplicated, capped at 20', () async {
      for (var i = 0; i < 25; i++) {
        clock.advance(const Duration(seconds: 1));
        await repo.addRecentSearch('query $i');
      }
      clock.advance(const Duration(seconds: 1));
      await repo.addRecentSearch('query 3');
      final recent = await repo.watchRecentSearches(limit: 50).first;
      expect(recent.length, 20);
      expect(recent.first, 'query 3');
      expect(recent.where((q) => q == 'query 3').length, 1);
      await repo.clearRecentSearches();
      expect(await repo.watchRecentSearches().first, isEmpty);
    });
  });

  test('upgrading a v1 database adds the catalog tables and keeps existing data', () async {
    final dir = await Directory.systemTemp.createTemp('chapter_migration');
    final file = File('${dir.path}/v1.sqlite');
    // Build a schema-v1 database by hand (Phase 2 tables only).
    sqlite3.open(file.path)
      ..execute(
        'CREATE TABLE lww_documents (path TEXT NOT NULL PRIMARY KEY, '
        "fields_json TEXT NOT NULL DEFAULT '{}', clocks_json TEXT NOT NULL DEFAULT '{}')",
      )
      ..execute(
        'CREATE TABLE outbox_entries (id INTEGER PRIMARY KEY AUTOINCREMENT, batch_id TEXT NOT NULL, '
        'doc_path TEXT NOT NULL, op_type TEXT NOT NULL, payload_json TEXT NOT NULL, hlc TEXT NOT NULL, '
        'attempts INTEGER NOT NULL DEFAULT 0, last_error TEXT, dead_letter INTEGER NOT NULL DEFAULT 0, '
        'created_at INTEGER NOT NULL)',
      )
      ..execute('CREATE TABLE sync_meta ("key" TEXT NOT NULL PRIMARY KEY, value TEXT NOT NULL)')
      ..execute("INSERT INTO lww_documents (path) VALUES ('users/u1')")
      ..execute('PRAGMA user_version = 1')
      ..close();

    final upgraded = AppDatabase(NativeDatabase(file));
    final repo2 = CatalogRepositoryImpl(remote: remote, db: upgraded, clock: clock);
    await repo2.addRecentSearch('after upgrade');
    expect(await repo2.watchRecentSearches().first, ['after upgrade']);
    expect((await upgraded.select(upgraded.lwwDocuments).get()).single.path, 'users/u1');
    await upgraded.close();
    await dir.delete(recursive: true);
  });
}
