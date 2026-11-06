import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';

import '../../../core/database/app_database.dart';
import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../../core/utils/clock.dart';
import '../domain/catalog_models.dart';
import '../domain/catalog_repository.dart';
import 'catalog_remote.dart';

/// Network-first catalog repository with an on-device cache (docs/05 §2.5).
///
/// * Every successful response is cached in Drift.
/// * When the network is unavailable, cached responses are served and
///   marked `fromCache`; search falls back to matching cached books.
class CatalogRepositoryImpl implements CatalogRepository {
  CatalogRepositoryImpl({
    required CatalogRemote remote,
    required AppDatabase db,
    required Clock clock,
  }) : _remote = remote,
       _db = db,
       _clock = clock;

  final CatalogRemote _remote;
  final AppDatabase _db;
  final Clock _clock;

  static const pageSize = 20;
  static const _maxRecent = 20;

  @override
  Future<Result<SearchPage>> search(
    String query, {
    SearchField field = SearchField.all,
    int page = 1,
  }) async {
    final text = query.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (text.length < 2) return const Result.err(ValidationFailure('Query too short'));
    final key = 'search:${field.name}:${text.toLowerCase()}:$page';
    final result = await _fetch(
      'catalogSearch',
      {'text': text, 'field': field.name, 'page': page, 'pageSize': pageSize},
      SearchPage.fromJson,
      cacheKey: key,
    );
    if (result.failureOrNull is NetworkFailure && page == 1) {
      final local = await _searchCachedWorks(text);
      if (local.isNotEmpty) return Result.ok(SearchPage(results: local, fromCache: true));
    }
    return result;
  }

  @override
  Future<Result<SearchPage>> trending() =>
      _fetch('catalogTrending', {'limit': 12}, SearchPage.fromJson, cacheKey: 'trending');

  @override
  Future<Result<WorkLookup>> lookupIsbn(String isbn) async {
    final result = await _fetch('catalogLookupIsbn', {'isbn': isbn}, WorkLookup.fromJson);
    final lookup = result.valueOrNull;
    if (lookup != null) await _put('work:${lookup.work.id}', lookup.work.toJson());
    return result;
  }

  @override
  Future<Result<CatalogWork>> getWork(WorkTarget target) async {
    final (Map<String, Object?> data, String? refKey) = switch (target) {
      WorkById(:final workId) => ({'workId': workId}, null),
      WorkByRef(:final ref) => (
        {
          'ref': {'provider': ref.provider.name, 'externalId': ref.externalId},
        },
        'workref:${ref.provider.name}:${ref.externalId}',
      ),
    };
    final result = await _fetch('catalogGetWork', data, WorkLookup.fromJson);
    final lookup = result.valueOrNull;
    if (lookup != null) {
      await _put('work:${lookup.work.id}', lookup.work.toJson());
      if (refKey != null) await _put(refKey, {'id': lookup.work.id});
      return Result.ok(lookup.work);
    }
    // Offline: serve the cached copy.
    final cachedId = switch (target) {
      WorkById(:final workId) => workId,
      WorkByRef() => (await _get(refKey!))?['id'] as String?,
    };
    final cached = cachedId == null ? null : await _get('work:$cachedId');
    if (cached != null && result.failureOrNull is NetworkFailure) {
      return Result.ok(CatalogWork.fromJson(cached));
    }
    return Result.err(result.failureOrNull!);
  }

  @override
  Future<Result<CatalogAuthor>> getAuthor({String? authorId, ProviderRef? ref}) {
    assert(authorId != null || ref != null, 'authorId or ref required');
    final data = authorId != null
        ? <String, Object?>{'authorId': authorId}
        : <String, Object?>{
            'ref': {'provider': ref!.provider.name, 'externalId': ref.externalId},
          };
    final key = authorId != null
        ? 'author:$authorId'
        : 'authorref:${ref!.provider.name}:${ref.externalId}';
    return _fetch('catalogGetAuthor', data, CatalogAuthor.fromJson, cacheKey: key);
  }

  @override
  Future<Result<CatalogSeries>> getSeries(String seriesId) => _fetch(
    'catalogGetSeries',
    {'seriesId': seriesId},
    CatalogSeries.fromJson,
    cacheKey: 'series:$seriesId',
  );

  @override
  Stream<List<String>> watchRecentSearches({int limit = 8}) {
    final query = _db.select(_db.recentSearches)
      ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
      ..limit(limit);
    return query.watch().map((rows) => [for (final r in rows) r.query]);
  }

  @override
  Future<void> addRecentSearch(String query) async {
    final text = query.trim();
    if (text.length < 2) return;
    await _db.transaction(() async {
      await _db
          .into(_db.recentSearches)
          .insertOnConflictUpdate(
            RecentSearchesCompanion.insert(query: text, searchedAt: _clock.now()),
          );
      final keep =
          await (_db.select(_db.recentSearches)
                ..orderBy([(t) => OrderingTerm.desc(t.searchedAt)])
                ..limit(_maxRecent))
              .get();
      await (_db.delete(
        _db.recentSearches,
      )..where((t) => t.query.isNotIn([for (final r in keep) r.query]))).go();
    });
  }

  @override
  Future<void> clearRecentSearches() => _db.delete(_db.recentSearches).go();

  // ─── internals ───

  Future<Result<T>> _fetch<T>(
    String callable,
    Map<String, Object?> data,
    T Function(Map<String, dynamic>) decode, {
    String? cacheKey,
  }) async {
    try {
      final json = await _remote.call(callable, data);
      final value = decode(json);
      if (cacheKey != null) await _put(cacheKey, json);
      return Result.ok(value);
    } on CatalogRemoteException catch (e) {
      if (kDebugMode) debugPrint('chapter.catalog: $callable failed: ${e.code} ${e.message}');
      final failure = _mapError(e);
      if (cacheKey != null && failure is NetworkFailure) {
        final cached = await _get(cacheKey);
        if (cached != null) {
          final value = decode(cached);
          return Result.ok(value is SearchPage ? value.copyWith(fromCache: true) as T : value);
        }
      }
      return Result.err(failure);
    } on FormatException catch (e) {
      return Result.err(UnknownFailure('Malformed catalog response', cause: e));
    } on TypeError catch (e) {
      return Result.err(UnknownFailure('Malformed catalog response', cause: e));
    }
  }

  static Failure _mapError(CatalogRemoteException e) => switch (e.code) {
    'unavailable' || 'deadline-exceeded' => NetworkFailure(e.message ?? e.code, cause: e),
    'not-found' => NotFoundFailure(e.message ?? e.code, cause: e),
    'invalid-argument' => ValidationFailure(e.message ?? e.code, cause: e),
    'resource-exhausted' => RateLimitedFailure(e.message ?? e.code, cause: e),
    'unauthenticated' || 'permission-denied' => UnauthorizedFailure(e.message ?? e.code, cause: e),
    _ => UnknownFailure(e.message ?? e.code, cause: e),
  };

  Future<void> _put(String key, Map<String, dynamic> json) => _db
      .into(_db.catalogCacheEntries)
      .insertOnConflictUpdate(
        CatalogCacheEntriesCompanion.insert(
          key: key,
          json: jsonEncode(json),
          cachedAt: _clock.now(),
        ),
      );

  Future<Map<String, dynamic>?> _get(String key) async {
    final row = await (_db.select(
      _db.catalogCacheEntries,
    )..where((t) => t.key.equals(key))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.json) as Map<String, dynamic>;
  }

  /// Offline search: cached books whose title or author contains the query.
  Future<List<WorkSummary>> _searchCachedWorks(String text) async {
    final needle = text.toLowerCase();
    final rows = await (_db.select(
      _db.catalogCacheEntries,
    )..where((t) => t.key.like('work:%'))).get();
    final matches = <WorkSummary>[];
    for (final row in rows) {
      final work = CatalogWork.fromJson(jsonDecode(row.json) as Map<String, dynamic>);
      final haystack = '${work.title} ${work.authorLine}'.toLowerCase();
      if (!haystack.contains(needle)) continue;
      final ref = work.providerIds.entries.firstOrNull;
      matches.add(
        WorkSummary(
          id: work.id,
          ref: ProviderRef(
            provider: CatalogProvider.values.firstWhere(
              (p) => p.name == ref?.key,
              orElse: () => CatalogProvider.openLibrary,
            ),
            externalId: ref?.value ?? work.id,
          ),
          title: work.title,
          subtitle: work.subtitle,
          authors: [for (final a in work.authors) a.name],
          coverUrl: work.coverUrl,
          pageCount: work.pageCount,
          seriesName: work.series.firstOrNull?.name,
          seriesPosition: work.series.firstOrNull?.position,
        ),
      );
      if (matches.length >= pageSize) break;
    }
    return matches;
  }
}
