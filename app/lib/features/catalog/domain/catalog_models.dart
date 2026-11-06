import 'package:freezed_annotation/freezed_annotation.dart';

part 'catalog_models.freezed.dart';
part 'catalog_models.g.dart';

/// Client-side views of the catalog returned by the Cloud Functions
/// (functions/src/catalog/types.ts). Field names match the server JSON.

enum CatalogProvider { hardcover, openLibrary, googleBooks }

enum SearchField { all, title, author, isbn, series, publisher }

@freezed
abstract class ProviderRef with _$ProviderRef {
  const factory ProviderRef({required CatalogProvider provider, required String externalId}) =
      _ProviderRef;

  factory ProviderRef.fromJson(Map<String, dynamic> json) => _$ProviderRefFromJson(json);
}

@freezed
abstract class WorkSummary with _$WorkSummary {
  const factory WorkSummary({
    String? id,
    required ProviderRef ref,
    required String title,
    String? subtitle,
    @Default([]) List<String> authors,
    String? coverUrl,
    int? firstPublishedYear,
    String? seriesName,
    double? seriesPosition,
    int? pageCount,
  }) = _WorkSummary;

  factory WorkSummary.fromJson(Map<String, dynamic> json) => _$WorkSummaryFromJson(json);
}

@freezed
abstract class SearchPage with _$SearchPage {
  const factory SearchPage({
    @Default([]) List<WorkSummary> results,
    @Default(1) int page,
    @Default(false) bool hasMore,
    CatalogProvider? provider,
    @Default(false) bool degraded,

    /// Set by the repository when served from the on-device cache.
    @Default(false) bool fromCache,
  }) = _SearchPage;

  factory SearchPage.fromJson(Map<String, dynamic> json) => _$SearchPageFromJson(json);
}

@freezed
abstract class CatalogAuthorRef with _$CatalogAuthorRef {
  const factory CatalogAuthorRef({String? id, required String name}) = _CatalogAuthorRef;

  factory CatalogAuthorRef.fromJson(Map<String, dynamic> json) => _$CatalogAuthorRefFromJson(json);
}

@freezed
abstract class CatalogSeriesRef with _$CatalogSeriesRef {
  const factory CatalogSeriesRef({
    String? seriesId,
    required String name,
    double? position,
    String? positionLabel,
    @Default(false) bool isPrimary,
  }) = _CatalogSeriesRef;

  factory CatalogSeriesRef.fromJson(Map<String, dynamic> json) => _$CatalogSeriesRefFromJson(json);
}

@freezed
abstract class CatalogEdition with _$CatalogEdition {
  const factory CatalogEdition({
    required String id,
    required String workId,
    @Default('other') String format,
    String? isbn10,
    String? isbn13,
    String? publisher,
    String? publishedDate,
    int? pageCount,
    int? audioDurationSec,
    String? language,
    String? coverUrl,
  }) = _CatalogEdition;

  factory CatalogEdition.fromJson(Map<String, dynamic> json) => _$CatalogEditionFromJson(json);
}

@freezed
abstract class CatalogWork with _$CatalogWork {
  const factory CatalogWork({
    required String id,
    required String title,
    String? subtitle,
    @Default([]) List<CatalogAuthorRef> authors,
    String? description,
    String? firstPublishedDate,
    String? language,
    @Default([]) List<String> genres,
    @Default([]) List<CatalogSeriesRef> series,
    String? coverUrl,
    int? pageCount,
    String? defaultEditionId,
    @Default([]) List<CatalogEdition> editions,
    @Default({}) Map<String, String> providerIds,
    required String refreshedAt,
  }) = _CatalogWork;

  const CatalogWork._();

  factory CatalogWork.fromJson(Map<String, dynamic> json) => _$CatalogWorkFromJson(json);

  CatalogEdition? get defaultEdition {
    for (final e in editions) {
      if (e.id == defaultEditionId) return e;
    }
    return editions.isEmpty ? null : editions.first;
  }

  String get authorLine => authors.map((a) => a.name).join(', ');
}

@freezed
abstract class WorkLookup with _$WorkLookup {
  const factory WorkLookup({required CatalogWork work, String? editionId}) = _WorkLookup;

  factory WorkLookup.fromJson(Map<String, dynamic> json) => _$WorkLookupFromJson(json);
}

@freezed
abstract class CatalogAuthor with _$CatalogAuthor {
  const factory CatalogAuthor({
    required String id,
    required String name,
    String? bio,
    String? photoUrl,
    String? photoCredit,
    String? birthDate,
    String? deathDate,
    @Default([]) List<WorkSummary> works,
  }) = _CatalogAuthor;

  factory CatalogAuthor.fromJson(Map<String, dynamic> json) => _$CatalogAuthorFromJson(json);
}

@freezed
abstract class SeriesEntry with _$SeriesEntry {
  const factory SeriesEntry({
    required WorkSummary work,
    double? position,
    String? positionLabel,
    @Default(false) bool isPrimary,
  }) = _SeriesEntry;

  factory SeriesEntry.fromJson(Map<String, dynamic> json) => _$SeriesEntryFromJson(json);
}

@freezed
abstract class CatalogSeries with _$CatalogSeries {
  const factory CatalogSeries({
    required String id,
    required String name,
    String? description,
    @Default([]) List<SeriesEntry> entries,
    @Default(0) int primaryCount,
  }) = _CatalogSeries;

  factory CatalogSeries.fromJson(Map<String, dynamic> json) => _$CatalogSeriesFromJson(json);
}

/// What to open on the book detail screen: a catalog id, or a provider
/// reference from search results that the server resolves on first view.
sealed class WorkTarget {
  const WorkTarget();
}

final class WorkById extends WorkTarget {
  const WorkById(this.workId);
  final String workId;
}

final class WorkByRef extends WorkTarget {
  const WorkByRef(this.ref);
  final ProviderRef ref;
}
