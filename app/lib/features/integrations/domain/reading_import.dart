import 'package:meta/meta.dart';

import '../../library/domain/library_models.dart';
import '../../scanner/domain/isbn.dart';
import 'csv_parser.dart';

/// What importing one book did.
enum ImportOutcome { added, alreadyInLibrary, removedEarlier }

enum ImportSource { goodreads, storygraph }

/// One book from an export, before it is matched to the catalog.
@immutable
class ImportedBook {
  const ImportedBook({
    required this.key,
    required this.source,
    required this.title,
    required this.status,
    this.authors = const [],
    this.isbn,
    this.pageCount,
    this.rating,
    this.review,
    this.dateAdded,
    this.finishedOn = const [],
    this.undatedReads = 0,
    this.owned = false,
  });

  /// Stable across imports and devices.
  final String key;
  final ImportSource source;
  final String title;
  final List<String> authors;
  final String? isbn;
  final int? pageCount;
  final ReadingStatus status;

  /// Half-star steps, or `null`.
  final double? rating;
  final String? review;
  final DateTime? dateAdded;

  /// Finish date of each dated read, oldest first.
  final List<DateTime> finishedOn;

  /// Reads the export counts but gives no date for.
  final int undatedReads;
  final bool owned;

  Map<String, Object?> toJson() => {
    'key': key,
    'source': source.name,
    'title': title,
    'authors': authors,
    'isbn': isbn,
    'pageCount': pageCount,
    'status': status.name,
    'rating': rating,
    'review': review,
    'dateAdded': dateAdded?.toIso8601String(),
    'finishedOn': [for (final d in finishedOn) d.toIso8601String()],
    'undatedReads': undatedReads,
    'owned': owned,
  };

  static ImportedBook fromJson(Map<String, Object?> j) => ImportedBook(
    key: j['key']! as String,
    source: ImportSource.values.byName(j['source']! as String),
    title: j['title']! as String,
    authors: [for (final a in j['authors']! as List) a as String],
    isbn: j['isbn'] as String?,
    pageCount: (j['pageCount'] as num?)?.toInt(),
    status: ReadingStatus.parse(j['status']),
    rating: (j['rating'] as num?)?.toDouble(),
    review: j['review'] as String?,
    dateAdded: DateTime.tryParse(j['dateAdded'] as String? ?? ''),
    finishedOn: [for (final d in j['finishedOn']! as List) DateTime.parse(d as String)],
    undatedReads: (j['undatedReads'] as num?)?.toInt() ?? 0,
    owned: j['owned'] == true,
  );
}

@immutable
class ImportPreview {
  const ImportPreview({required this.source, required this.books, required this.skippedRows});

  final ImportSource source;
  final List<ImportedBook> books;

  /// Rows that couldn't be read (no title).
  final int skippedRows;

  int count(ReadingStatus status) => books.where((b) => b.status == status).length;
}

/// Reads a Goodreads or StoryGraph export, by header name. Returns `null` for
/// any other file. Never throws on malformed content.
ImportPreview? parseReadingExport(String content) {
  final rows = parseCsv(content);
  if (rows.isEmpty) return null;
  final headers = {for (var i = 0; i < rows.first.length; i++) rows.first[i].trim(): i};
  final ImportSource source;
  if (headers.containsKey('Exclusive Shelf')) {
    source = ImportSource.goodreads;
  } else if (headers.containsKey('Read Status')) {
    source = ImportSource.storygraph;
  } else {
    return null;
  }
  if (!headers.containsKey('Title')) return null;

  final byKey = <String, ImportedBook>{};
  var skipped = 0;
  for (final row in rows.skip(1)) {
    String? cell(String name) {
      final i = headers[name];
      if (i == null || i >= row.length) return null;
      final v = row[i].trim();
      return v.isEmpty ? null : v;
    }

    final book = source == ImportSource.goodreads ? _goodreads(cell) : _storygraph(cell);
    if (book == null) {
      skipped++;
    } else {
      byKey[book.key] = book; // a repeated row replaces itself
    }
  }
  return ImportPreview(source: source, books: byKey.values.toList(), skippedRows: skipped);
}

typedef _Cell = String? Function(String name);

ImportedBook? _goodreads(_Cell cell) {
  final title = cell('Title');
  if (title == null) return null;
  final authors = [
    ?cell('Author'),
    ...(cell('Additional Authors') ?? '')
        .split(',')
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty),
  ];
  // Goodreads wraps ISBNs as ="9781..." to stop spreadsheets mangling them.
  final isbn = _isbn(cell('ISBN13')) ?? _isbn(cell('ISBN'));
  final status = _status(cell('Exclusive Shelf'));
  final dated = [?_date(cell('Date Read'))];
  final readCount = int.tryParse(cell('Read Count') ?? '') ?? 0;
  final total = status == ReadingStatus.read ? (readCount < 1 ? 1 : readCount) : 0;
  final undated = total > dated.length ? total - dated.length : 0;
  final finished = status == ReadingStatus.read ? dated : <DateTime>[];
  return ImportedBook(
    key: _key(ImportSource.goodreads, cell('Book Id') ?? isbn ?? _titleKey(title, authors)),
    source: ImportSource.goodreads,
    title: title,
    authors: authors,
    isbn: isbn,
    pageCount: _positive(cell('Number of Pages')),
    status: status,
    rating: _rating(cell('My Rating')),
    review: _review(cell('My Review')),
    dateAdded: _date(cell('Date Added')),
    finishedOn: finished,
    undatedReads: undated > _maxReads ? _maxReads : undated,
    owned: (int.tryParse(cell('Owned Copies') ?? '') ?? 0) > 0,
  );
}

ImportedBook? _storygraph(_Cell cell) {
  final title = cell('Title');
  if (title == null) return null;
  final authors = (cell('Authors') ?? '')
      .split(',')
      .map((a) => a.trim())
      .where((a) => a.isNotEmpty)
      .toList();
  final isbn = _isbn(cell('ISBN/UID'));
  final status = _status(cell('Read Status'));
  // "2021/05/01-2021/05/20, 2023/01/02-2023/01/09": one start and end per read.
  final finished = <DateTime>[
    if (status == ReadingStatus.read)
      for (final read in (cell('Dates Read') ?? '').split(','))
        if (_dateRe.allMatches(read).lastOrNull case final m?) ?_date(m.group(0)),
  ];
  final last = _date(cell('Last Date Read'));
  if (status == ReadingStatus.read && finished.isEmpty && last != null) finished.add(last);
  finished.sort();
  final readCount = int.tryParse(cell('Read Count') ?? '') ?? 0;
  final total = status == ReadingStatus.read ? (readCount < 1 ? 1 : readCount) : 0;
  final undated = total > finished.length ? total - finished.length : 0;
  return ImportedBook(
    key: _key(ImportSource.storygraph, isbn ?? cell('ISBN/UID') ?? _titleKey(title, authors)),
    source: ImportSource.storygraph,
    title: title,
    authors: authors,
    isbn: isbn,
    status: status,
    rating: _rating(cell('Star Rating')),
    review: _review(cell('Review')),
    dateAdded: _date(cell('Date Added')),
    finishedOn: finished,
    undatedReads: undated > _maxReads ? _maxReads : undated,
    owned: cell('Owned?')?.toLowerCase().startsWith('y') ?? false,
  );
}

const _maxReads = 50;
final _dateRe = RegExp(r'\d{4}[/-]\d{1,2}[/-]\d{1,2}');

String _key(ImportSource source, String id) => '${source.name}_${stableHash(id)}';

String _titleKey(String title, List<String> authors) =>
    '${normalizeTitle(title)}|${normalizeText(authors.firstOrNull ?? '')}';

String? _isbn(String? raw) {
  if (raw == null) return null;
  final digits = raw.replaceAll(RegExp(r'[="\s-]'), '').toUpperCase();
  return Isbn.isValid13(digits) || Isbn.isValid10(digits) ? digits : null;
}

ReadingStatus _status(String? shelf) {
  final s = normalizeText(shelf ?? '');
  if (s == 'read') return ReadingStatus.read;
  if (s == 'currently reading' || s == 'paused') return ReadingStatus.reading;
  if (s == 'did not finish' || s == 'dnf' || s == 'abandoned') return ReadingStatus.dnf;
  return ReadingStatus.wantToRead; // to-read and custom shelves
}

/// Chapter rates in half stars; StoryGraph allows quarters, so round to nearest.
double? _rating(String? raw) {
  final v = double.tryParse(raw ?? '');
  if (v == null || !v.isFinite || v <= 0) return null;
  final half = (v * 2).round() / 2;
  return LibraryEntry.isValidRating(half) ? half : (half > 5 ? 5.0 : 0.5);
}

String? _review(String? raw) {
  if (raw == null) return null;
  final text = raw
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]+>'), '')
      .trim();
  if (text.isEmpty) return null;
  return text.length > LibraryEntry.maxReviewLength
      ? text.substring(0, LibraryEntry.maxReviewLength)
      : text;
}

int? _positive(String? raw) {
  final v = int.tryParse(raw ?? '');
  return v != null && v > 0 && v <= 100000 ? v : null;
}

/// Local midday, so the date holds in nearby time zones (TD-38).
DateTime? _date(String? raw) {
  final m = _dateRe.firstMatch(raw ?? '');
  if (m == null) return null;
  final parts = m.group(0)!.split(RegExp('[/-]')).map(int.parse).toList();
  final (y, mo, d) = (parts[0], parts[1], parts[2]);
  if (y < 1000 || mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final date = DateTime(y, mo, d, 12);
  return date.month == mo ? date : null; // rejects Feb 31
}
