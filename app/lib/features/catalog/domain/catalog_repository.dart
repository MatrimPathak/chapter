import '../../../core/error/result.dart';
import 'catalog_models.dart';

/// Book discovery boundary (docs/04 §1). Network-first with an on-device
/// cache so previously viewed books and searches work offline (docs/05 §2.5).
abstract interface class CatalogRepository {
  Future<Result<SearchPage>> search(String query, {SearchField field, int page});

  Future<Result<SearchPage>> trending();

  /// Exact lookup; [isbn] may be ISBN-10 or ISBN-13.
  Future<Result<WorkLookup>> lookupIsbn(String isbn);

  Future<Result<CatalogWork>> getWork(WorkTarget target);

  Future<Result<CatalogAuthor>> getAuthor({String? authorId, ProviderRef? ref});

  Future<Result<CatalogSeries>> getSeries(String seriesId);

  /// Most recent first, at most [limit].
  Stream<List<String>> watchRecentSearches({int limit});

  Future<void> addRecentSearch(String query);

  Future<void> clearRecentSearches();
}
