import 'dart:async';
import 'dart:math' show min;

import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../catalog/domain/catalog_repository.dart';
import '../../library/domain/library_models.dart';
import '../../library/domain/library_repository.dart';
import '../../library/presentation/library_providers.dart' show bookSummaryOf, userEditionOf;
import '../data/import_queue.dart';
import '../domain/csv_parser.dart';
import '../domain/kindle_clippings.dart';
import '../domain/reading_import.dart';

enum _Outcome { done, unmatched, rateLimited, retryLater }

/// Works through the import queue. Everything here is contained: a failure
/// pauses the import and never reaches the rest of the app.
///
/// Matching is strict on purpose: the ISBN, or the exact title and an author in
/// common. A missed book is listed for the reader; a wrong book would corrupt
/// their history.
class ImportRunner {
  ImportRunner({
    required ImportQueue queue,
    required CatalogRepository catalog,
    required LibraryRepository library,
    Future<void> Function(Duration)? wait,
    this.rateLimitPause = const Duration(seconds: 60),
    this.firstRetryPause = const Duration(seconds: 30),
    this.retryPause = const Duration(minutes: 5),
  }) : _queue = queue,
       _catalog = catalog,
       _library = library,
       _wait = wait ?? Future<void>.delayed;

  final ImportQueue _queue;
  final CatalogRepository _catalog;
  final LibraryRepository _library;
  final Future<void> Function(Duration) _wait;
  final Duration rateLimitPause;
  final Duration firstRetryPause;

  /// The longest wait between attempts while lookups keep failing.
  final Duration retryPause;

  /// Lookups at once. The server limits lookups per minute anyway.
  static const concurrency = 3;

  Future<void>? _running;
  bool _disposed = false;

  void dispose() => _disposed = true;

  /// Runs until the queue is empty or something asks it to stop. Safe to call
  /// at any time; a call during a run just joins it.
  Future<void> run() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    var failures = 0;
    try {
      while (!_disposed) {
        final rows = await _queue.next(concurrency);
        if (rows.isEmpty) return;
        final outcomes = await Future.wait(rows.map(_process));
        if (_disposed) return;
        if (outcomes.contains(_Outcome.retryLater)) {
          // Offline or the catalog is down: leave the rest queued. Often it's
          // brief (a slow cold start), so wait little at first, up to retryPause.
          failures++;
          final pause = firstRetryPause * (1 << min(failures - 1, 16));
          await _wait(pause < retryPause ? pause : retryPause);
          continue;
        }
        failures = 0;
        if (outcomes.contains(_Outcome.rateLimited)) await _wait(rateLimitPause);
      }
    } on Object {
      // The local database failed. The queue is intact; the next run resumes it.
    }
  }

  Future<_Outcome> _process(ImportedBook book) async {
    final _Outcome outcome;
    try {
      outcome = await _resolve(book);
    } on Object {
      return _Outcome.retryLater;
    }
    if (outcome == _Outcome.unmatched) await _queue.markUnmatched(book.key);
    return outcome;
  }

  Future<_Outcome> _resolve(ImportedBook book) async {
    final isbn = book.isbn;
    if (isbn != null) {
      switch (await _catalog.lookupIsbn(isbn)) {
        case Ok(:final value):
          await _add(book, value.work, value.editionId);
          return _Outcome.done;
        case Err(:final failure):
          // Not known by ISBN: try the title. Anything else is temporary.
          if (failure is! NotFoundFailure && failure is! ValidationFailure) {
            return _temporary(failure);
          }
      }
    }
    return _resolveByTitle(book);
  }

  Future<_Outcome> _resolveByTitle(ImportedBook book) async {
    final author = book.authors.firstOrNull ?? '';
    final SearchPage page;
    switch (await _catalog.search('${book.title} $author'.trim())) {
      case Ok(:final value):
        page = value;
      case Err(:final failure):
        return failure is NotFoundFailure || failure is ValidationFailure
            ? _Outcome.unmatched
            : _temporary(failure);
    }
    final title = normalizeTitle(book.title);
    final match = page.results.where((s) {
      if (normalizeTitle(s.title) != title) return false;
      return author.isEmpty || sharesAuthor(author, s.authors);
    }).firstOrNull;
    if (match == null) return _Outcome.unmatched;

    final id = match.id;
    final target = id != null ? WorkById(id) : WorkByRef(match.ref);
    switch (await _catalog.getWork(target)) {
      case Ok(:final value):
        await _add(book, value, null);
        return _Outcome.done;
      case Err(:final failure):
        return failure is NotFoundFailure ? _Outcome.unmatched : _temporary(failure);
    }
  }

  static _Outcome _temporary(Failure failure) =>
      failure is RateLimitedFailure ? _Outcome.rateLimited : _Outcome.retryLater;

  Future<void> _add(ImportedBook book, CatalogWork work, String? editionId) async {
    final summary = bookSummaryOf(work);
    final edition = work.editions.where((e) => e.id == editionId).firstOrNull;
    final outcome = await _library.importBook(
      workId: work.id,
      book: BookSummary(
        title: summary.title,
        subtitle: summary.subtitle,
        authorNames: summary.authorNames,
        coverUrl: summary.coverUrl,
        pageCount: summary.pageCount ?? book.pageCount,
        seriesId: summary.seriesId,
        seriesName: summary.seriesName,
        seriesPosition: summary.seriesPosition,
        genres: summary.genres,
        firstPublishedYear: summary.firstPublishedYear,
      ),
      imported: book,
      edition: edition == null ? null : userEditionOf(edition, owned: book.owned),
    );
    await _queue.markDone(book.key, outcome);
  }
}
