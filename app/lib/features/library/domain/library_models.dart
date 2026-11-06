import 'dart:convert';

import 'package:meta/meta.dart';

import '../../progress/domain/progress_mapper.dart';

/// Shelf status of a work in the user's library (docs/03 §5).
enum ReadingStatus {
  none,
  wantToRead,
  reading,
  read,
  dnf;

  static ReadingStatus parse(Object? value) =>
      values.firstWhere((s) => s.name == value, orElse: () => ReadingStatus.none);
}

enum ReadThroughOutcome {
  inProgress,
  finished,
  abandoned;

  static ReadThroughOutcome parse(Object? value) =>
      values.firstWhere((s) => s.name == value, orElse: () => ReadThroughOutcome.inProgress);
}

/// Field names shared by the local LWW documents and Firestore
/// (`users/{uid}/library/{workId}`), validated by firestore.rules.
abstract final class LibraryFields {
  static const status = 'status';
  static const isWishlist = 'isWishlist';
  static const isFavorite = 'isFavorite';
  static const addedAt = 'addedAt';
  static const statusChangedAt = 'statusChangedAt';
  static const activeEditionId = 'activeEditionId';
  static const activeReadThroughId = 'activeReadThroughId';
  static const removed = 'removed';
  static const rating = 'rating';
  static const review = 'review';
  static const title = 'title';
  static const subtitle = 'subtitle';
  static const authorNames = 'authorNames';
  static const coverUrl = 'coverUrl';
  static const pageCount = 'pageCount';
  static const seriesId = 'seriesId';
  static const seriesName = 'seriesName';
  static const seriesPosition = 'seriesPosition';
  static const genres = 'genres';
  static const firstPublishedYear = 'firstPublishedYear';
}

/// Denormalized book summary stored on the library entry so the library and
/// Home render offline without the catalog (docs/03 §5).
@immutable
class BookSummary {
  const BookSummary({
    required this.title,
    this.subtitle,
    this.authorNames = const [],
    this.coverUrl,
    this.pageCount,
    this.seriesId,
    this.seriesName,
    this.seriesPosition,
    this.genres = const [],
    this.firstPublishedYear,
  });

  final String title;
  final String? subtitle;
  final List<String> authorNames;
  final String? coverUrl;
  final int? pageCount;
  final String? seriesId;
  final String? seriesName;
  final double? seriesPosition;
  final List<String> genres;
  final int? firstPublishedYear;

  String get authorLine => authorNames.join(', ');

  Map<String, Object?> toFields() => {
    LibraryFields.title: _trim(title, 500),
    LibraryFields.subtitle: _trimOrNull(subtitle, 500),
    LibraryFields.authorNames: authorNames.take(20).toList(),
    LibraryFields.coverUrl: (coverUrl?.length ?? 0) > 2048 ? null : coverUrl,
    LibraryFields.pageCount: pageCount != null && pageCount! > 0 ? pageCount : null,
    LibraryFields.seriesId: seriesId,
    LibraryFields.seriesName: _trimOrNull(seriesName, 300),
    LibraryFields.seriesPosition: seriesPosition,
    LibraryFields.genres: genres.take(12).toList(),
    LibraryFields.firstPublishedYear: firstPublishedYear,
  };

  static BookSummary fromFields(Map<String, Object?> f) => BookSummary(
    title: f[LibraryFields.title] as String? ?? '',
    subtitle: f[LibraryFields.subtitle] as String?,
    authorNames: _strings(f[LibraryFields.authorNames]),
    coverUrl: f[LibraryFields.coverUrl] as String?,
    pageCount: (f[LibraryFields.pageCount] as num?)?.toInt(),
    seriesId: f[LibraryFields.seriesId] as String?,
    seriesName: f[LibraryFields.seriesName] as String?,
    seriesPosition: (f[LibraryFields.seriesPosition] as num?)?.toDouble(),
    genres: _strings(f[LibraryFields.genres]),
    firstPublishedYear: (f[LibraryFields.firstPublishedYear] as num?)?.toInt(),
  );

  static String _trim(String s, int max) => s.length > max ? s.substring(0, max) : s;
  static String? _trimOrNull(String? s, int max) => s == null ? null : _trim(s, max);
}

/// One work on the user's shelves. Keyed by work id (D1: Work ≠ Edition).
@immutable
class LibraryEntry {
  const LibraryEntry({
    required this.workId,
    required this.status,
    required this.book,
    required this.addedAt,
    this.statusChangedAt,
    this.isWishlist = false,
    this.isFavorite = false,
    this.activeEditionId,
    this.activeReadThroughId,
    this.rating,
    this.review,
  });

  final String workId;
  final ReadingStatus status;
  final BookSummary book;
  final DateTime addedAt;
  final DateTime? statusChangedAt;
  final bool isWishlist;
  final bool isFavorite;
  final String? activeEditionId;
  final String? activeReadThroughId;

  /// 0.5–5 in half stars, or `null`.
  final double? rating;
  final String? review;

  /// A valid rating: 0.5–5 in half-star steps.
  static bool isValidRating(double r) => r >= 0.5 && r <= 5 && (r * 2) == (r * 2).roundToDouble();

  static const maxReviewLength = 20000;

  /// `null` for documents that are absent or tombstoned.
  static LibraryEntry? fromFields(
    String workId,
    Map<String, Object?> f, {
    bool includeRemoved = false,
  }) {
    if (f.isEmpty || (!includeRemoved && f[LibraryFields.removed] == true)) return null;
    final added = _date(f[LibraryFields.addedAt]);
    if (added == null) return null; // partial doc (e.g. only a remote favourite flag)
    return LibraryEntry(
      workId: workId,
      status: ReadingStatus.parse(f[LibraryFields.status]),
      book: BookSummary.fromFields(f),
      addedAt: added,
      statusChangedAt: _date(f[LibraryFields.statusChangedAt]),
      isWishlist: f[LibraryFields.isWishlist] == true,
      isFavorite: f[LibraryFields.isFavorite] == true,
      activeEditionId: f[LibraryFields.activeEditionId] as String?,
      activeReadThroughId: f[LibraryFields.activeReadThroughId] as String?,
      rating: (f[LibraryFields.rating] as num?)?.toDouble(),
      review: f[LibraryFields.review] as String?,
    );
  }
}

/// When a book was finished. Only a known date counts in statistics.
@immutable
class ReadFinish {
  /// Finished right now.
  const ReadFinish.now() : date = null, isUnknown = false;

  /// Finished on [date] (a future date is treated as now).
  const ReadFinish.on(DateTime this.date) : isUnknown = false;

  /// Read at some point; the reader doesn't remember when.
  const ReadFinish.unknown() : date = null, isUnknown = true;

  final DateTime? date;
  final bool isUnknown;

  /// The finish time, or `null` when unknown.
  DateTime? resolve(DateTime now) {
    if (isUnknown) return null;
    final d = date;
    return d == null || d.isAfter(now) ? now : d;
  }
}

@immutable
class ReadThrough {
  const ReadThrough({
    required this.id,
    required this.workId,
    required this.ordinal,
    required this.outcome,
    this.startedAt,
    this.finishedAt,
  });

  final String id;
  final String workId;

  /// 1 for the first read, 2 for the first reread, …
  final int ordinal;
  final ReadThroughOutcome outcome;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  static ReadThrough? fromFields(String id, Map<String, Object?> f) {
    final workId = f['workId'] as String?;
    if (workId == null) return null;
    return ReadThrough(
      id: id,
      workId: workId,
      ordinal: (f['ordinal'] as num?)?.toInt() ?? 1,
      outcome: ReadThroughOutcome.parse(f['outcome']),
      startedAt: _date(f['startedAt']),
      finishedAt: _date(f['finishedAt']),
    );
  }
}

/// The user's relationship with one edition (owned, overrides, calibration).
@immutable
class UserEdition {
  const UserEdition({
    required this.editionId,
    required this.workId,
    required this.format,
    this.owned = false,
    this.isbn13,
    this.publisher,
    this.coverUrl,
    this.pageCount,
    this.audioDurationSec,
    this.pageCountOverride,
    this.audioDurationOverride,
    this.contentStartPage,
    this.contentEndPage,
    this.calibration = const [],
  });

  final String editionId;
  final String workId;
  final String format;
  final bool owned;
  final String? isbn13;
  final String? publisher;
  final String? coverUrl;
  final int? pageCount;
  final int? audioDurationSec;
  final int? pageCountOverride;
  final int? audioDurationOverride;
  final int? contentStartPage;
  final int? contentEndPage;
  final List<CalibrationPoint> calibration;

  int? get effectivePageCount => pageCountOverride ?? pageCount;
  int? get effectiveAudioDuration => audioDurationOverride ?? audioDurationSec;

  EditionMetrics get metrics => EditionMetrics(
    format: format,
    pageCount: effectivePageCount,
    audioDurationSec: effectiveAudioDuration,
    contentStartPage: contentStartPage,
    contentEndPage: contentEndPage,
    calibration: calibration,
  );

  static UserEdition? fromFields(String id, Map<String, Object?> f) {
    final workId = f['workId'] as String?;
    if (workId == null) return null;
    return UserEdition(
      editionId: id,
      workId: workId,
      format: f['format'] as String? ?? 'other',
      owned: f['owned'] == true,
      isbn13: f['isbn13'] as String?,
      publisher: f['publisher'] as String?,
      coverUrl: f['coverUrl'] as String?,
      pageCount: (f['pageCount'] as num?)?.toInt(),
      audioDurationSec: (f['audioDurationSec'] as num?)?.toInt(),
      pageCountOverride: (f['pageCountOverride'] as num?)?.toInt(),
      audioDurationOverride: (f['audioDurationOverride'] as num?)?.toInt(),
      contentStartPage: (f['contentStartPage'] as num?)?.toInt(),
      contentEndPage: (f['contentEndPage'] as num?)?.toInt(),
      calibration: CalibrationCodec.decode(f['calibrationJson'] as String?),
    );
  }
}

abstract final class CalibrationCodec {
  static String encode(List<CalibrationPoint> points) =>
      jsonEncode([for (final p in points) p.toJson()]);

  static List<CalibrationPoint> decode(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final list = jsonDecode(json);
      if (list is! List) return const [];
      return [for (final item in list) ?CalibrationPoint.fromJson(item)];
    } on FormatException {
      return const [];
    }
  }
}

List<String> _strings(Object? value) => value is List
    ? [
        for (final v in value)
          if (v is String) v,
      ]
    : const [];

DateTime? _date(Object? value) => value is String ? DateTime.tryParse(value) : null;
