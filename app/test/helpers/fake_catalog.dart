import 'dart:async';

import 'package:chapter/core/error/failure.dart';
import 'package:chapter/core/error/result.dart';
import 'package:chapter/features/catalog/data/catalog_remote.dart';
import 'package:chapter/features/catalog/domain/catalog_models.dart';
import 'package:chapter/features/catalog/domain/catalog_repository.dart';

const dealRef = ProviderRef(provider: CatalogProvider.openLibrary, externalId: 'OL42430111W');

WorkSummary summary(String title, {String? id, String ext = 'OL1W', int? year}) => WorkSummary(
  id: id,
  ref: ProviderRef(provider: CatalogProvider.openLibrary, externalId: ext),
  title: title,
  authors: const ['Elle Kennedy'],
  firstPublishedYear: year,
);

const theDeal = CatalogWork(
  id: '01a1a6e7-6503-7188-8dc5-12ed96efef6a',
  title: 'The Deal',
  subtitle: 'The international sensation',
  authors: [CatalogAuthorRef(id: '01a1a6e7-0000-7000-8000-000000000001', name: 'Elle Kennedy')],
  description: 'She is about to make a deal with the college bad boy.',
  firstPublishedDate: '2015',
  genres: ['Romance'],
  series: [
    CatalogSeriesRef(
      seriesId: '01a1a6e7-0000-7000-8000-000000000009',
      name: 'Off-Campus',
      position: 1,
      positionLabel: '1',
      isPrimary: true,
    ),
  ],
  pageCount: 374,
  defaultEditionId: 'e1',
  editions: [
    CatalogEdition(
      id: 'e1',
      workId: '01a1a6e7-6503-7188-8dc5-12ed96efef6a',
      format: 'paperback',
      isbn13: '9780349440842',
      publisher: 'Piatkus',
      pageCount: 374,
    ),
  ],
  providerIds: {'openLibrary': 'OL42430111W'},
  refreshedAt: '2026-11-04T10:00:00.000Z',
);

/// Scripted [CatalogRemote]: map callable name → handler.
class FakeCatalogRemote implements CatalogRemote {
  final handlers = <String, FutureOr<Map<String, dynamic>> Function(Map<String, Object?> data)>{};
  final calls = <(String, Map<String, Object?>)>[];

  @override
  Future<Map<String, dynamic>> call(String name, Map<String, Object?> data) async {
    calls.add((name, data));
    final handler = handlers[name];
    if (handler == null) throw const CatalogRemoteException('not-found');
    return handler(data);
  }
}

/// In-memory [CatalogRepository] for widget tests.
class FakeCatalogRepository implements CatalogRepository {
  final searchCalls = <(String, SearchField, int)>[];
  Result<SearchPage> Function(String query, SearchField field, int page)? onSearch;
  Result<WorkLookup> Function(String isbn)? onLookup;
  Duration searchDelay = Duration.zero;
  SearchPage trendingPage = const SearchPage();
  CatalogWork work = theDeal;
  CatalogAuthor? author;
  CatalogSeries? series;
  final _recent = StreamController<List<String>>.broadcast();
  final recents = <String>[];

  @override
  Future<Result<SearchPage>> search(
    String query, {
    SearchField field = SearchField.all,
    int page = 1,
  }) async {
    searchCalls.add((query, field, page));
    if (searchDelay > Duration.zero) await Future<void>.delayed(searchDelay);
    return onSearch?.call(query, field, page) ?? const Result.ok(SearchPage());
  }

  @override
  Future<Result<SearchPage>> trending() async => Result.ok(trendingPage);

  @override
  Future<Result<WorkLookup>> lookupIsbn(String isbn) async =>
      onLookup?.call(isbn) ?? Result.ok(WorkLookup(work: work, editionId: 'e1'));

  @override
  Future<Result<CatalogWork>> getWork(WorkTarget target) async => Result.ok(work);

  @override
  Future<Result<CatalogAuthor>> getAuthor({String? authorId, ProviderRef? ref}) async =>
      author == null ? const Result.err(NotFoundFailure('no author')) : Result.ok(author!);

  @override
  Future<Result<CatalogSeries>> getSeries(String seriesId) async =>
      series == null ? const Result.err(NotFoundFailure('no series')) : Result.ok(series!);

  @override
  Stream<List<String>> watchRecentSearches({int limit = 8}) => Stream.multi((sink) {
    sink.add(List.of(recents));
    final sub = _recent.stream.listen(sink.add);
    sink.onCancel = sub.cancel;
  });

  @override
  Future<void> addRecentSearch(String query) async {
    recents
      ..remove(query)
      ..insert(0, query);
    _recent.add(List.of(recents));
  }

  @override
  Future<void> clearRecentSearches() async {
    recents.clear();
    _recent.add(const []);
  }
}
