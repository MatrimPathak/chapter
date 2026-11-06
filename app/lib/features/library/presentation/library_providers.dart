import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../catalog/domain/catalog_models.dart';
import '../../progress/domain/progress_event.dart';
import '../../reading/domain/reading_session.dart';
import '../domain/library_models.dart';
import '../domain/library_repository.dart';

/// Runs [build] with the user's repository, or returns [empty] when signed
/// out. Watches only the uid and *reads* the repository: watching the
/// user-scoped chain would make it throw (no uid) while screens are still
/// mounted during the sign-out transition.
Stream<T> userScoped<T>(Ref ref, T empty, Stream<T> Function(LibraryRepository) build) {
  if (ref.watch(currentUserIdProvider) == null) return Stream.value(empty);
  return build(ref.read(libraryRepositoryProvider));
}

/// Safe to watch while signed out: emits nothing-in-library.
final libraryEntriesProvider = StreamProvider<List<LibraryEntry>>(
  (ref) => userScoped(ref, const [], (r) => r.watchEntries()),
);

final libraryEntryProvider = StreamProvider.family<LibraryEntry?, String>(
  (ref, workId) => userScoped(ref, null, (r) => r.watchEntry(workId)),
);

final readThroughsProvider = StreamProvider.family<List<ReadThrough>, String>(
  (ref, workId) => userScoped(ref, const [], (r) => r.watchReadThroughs(workId)),
);

final userEditionsProvider = StreamProvider.family<List<UserEdition>, String>(
  (ref, workId) => userScoped(ref, const [], (r) => r.watchEditions(workId)),
);

/// Latest progress event per read-through id.
final latestProgressProvider = StreamProvider<Map<String, ProgressEvent>>(
  (ref) => userScoped(ref, const {}, (r) => r.watchLatestProgress()),
);

/// Progress log of one read-through, oldest first.
final progressLogProvider = StreamProvider.family<List<ProgressEvent>, String>(
  (ref, readThroughId) => userScoped(ref, const [], (r) => r.watchProgress(readThroughId)),
);

/// Recent sessions across all books, newest first.
final recentSessionsProvider = StreamProvider<List<ReadingSession>>(
  (ref) => userScoped(ref, const [], (r) => r.watchSessions(limit: 20)),
);

/// Sessions of one book, newest first.
final bookSessionsProvider = StreamProvider.family<List<ReadingSession>, String>(
  (ref, workId) => userScoped(ref, const [], (r) => r.watchSessions(workId: workId)),
);

/// An entry with its current progress (if any).
class ShelfItem {
  const ShelfItem(this.entry, this.progress);

  final LibraryEntry entry;
  final ProgressEvent? progress;

  /// Most recent activity: progress or a status change.
  DateTime get lastActivity {
    final p = progress?.recordedAt;
    final s = entry.statusChangedAt ?? entry.addedAt;
    return p != null && p.isAfter(s) ? p : s;
  }
}

/// Joins entries with their active read-through's progress. A function, not
/// a derived provider: chained providers re-notifying during a widget build
/// trip Riverpod's "markNeedsBuild during build" assertion on sign-out.
AsyncValue<List<ShelfItem>> joinShelf(
  AsyncValue<List<LibraryEntry>> entries,
  AsyncValue<Map<String, ProgressEvent>> progress,
) => switch ((entries, progress)) {
  (AsyncData(value: final e), AsyncData(value: final p)) => AsyncData([
    for (final entry in e)
      ShelfItem(entry, entry.activeReadThroughId == null ? null : p[entry.activeReadThroughId]),
  ]),
  (AsyncError(:final error, :final stackTrace), _) ||
  (_, AsyncError(:final error, :final stackTrace)) => AsyncError(error, stackTrace),
  _ => const AsyncLoading(),
};

/// Watches the whole shelf (entries + progress).
AsyncValue<List<ShelfItem>> watchShelf(WidgetRef ref) =>
    joinShelf(ref.watch(libraryEntriesProvider), ref.watch(latestProgressProvider));

/// Home's Continue Reading: books being read, most recent activity first.
List<ShelfItem> continueReading(List<ShelfItem> items) =>
    items.where((i) => i.entry.status == ReadingStatus.reading).toList()
      ..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

/// Library summary of a catalog work (denormalized onto the entry).
BookSummary bookSummaryOf(CatalogWork w) {
  final series = w.series.where((s) => s.isPrimary).firstOrNull ?? w.series.firstOrNull;
  final year = int.tryParse(
    RegExp(r'\d{4}').firstMatch(w.firstPublishedDate ?? '')?.group(0) ?? '',
  );
  return BookSummary(
    title: w.title,
    subtitle: w.subtitle,
    authorNames: [for (final a in w.authors) a.name],
    coverUrl: w.coverUrl,
    pageCount: w.pageCount,
    seriesId: series?.seriesId,
    seriesName: series?.name,
    seriesPosition: series?.position,
    genres: w.genres,
    firstPublishedYear: year,
  );
}

UserEdition userEditionOf(CatalogEdition e, {bool owned = false}) => UserEdition(
  editionId: e.id,
  workId: e.workId,
  format: e.format,
  owned: owned,
  isbn13: e.isbn13,
  publisher: e.publisher,
  coverUrl: e.coverUrl,
  pageCount: e.pageCount,
  audioDurationSec: e.audioDurationSec,
);
