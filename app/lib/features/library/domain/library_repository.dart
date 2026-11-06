import '../../integrations/domain/reading_import.dart';
import '../../progress/domain/progress_event.dart';
import '../../progress/domain/reading_position.dart';
import '../../reading/domain/reading_session.dart';
import 'library_models.dart';

enum AddResult { added, alreadyInLibrary }

/// The user's library, read-throughs, editions and progress log
/// (docs/03 §5–7). Every mutation is local-first: it commits to the on-device
/// database together with its outbox rows and syncs later.
abstract interface class LibraryRepository {
  /// Active (non-removed) entries.
  Stream<List<LibraryEntry>> watchEntries();

  Stream<LibraryEntry?> watchEntry(String workId);

  Stream<List<ReadThrough>> watchReadThroughs(String workId);

  Stream<List<UserEdition>> watchEditions(String workId);

  /// Progress events of one read-through, oldest first.
  Stream<List<ProgressEvent>> watchProgress(String readThroughId);

  /// Latest progress event per read-through id, for list screens.
  Stream<Map<String, ProgressEvent>> watchLatestProgress();

  /// Adds [workId] with [status]; duplicate-safe (returns
  /// [AddResult.alreadyInLibrary] without changing anything).
  Future<AddResult> add({
    required String workId,
    required BookSummary book,
    ReadingStatus status = ReadingStatus.wantToRead,
    UserEdition? edition,
    ReadFinish finish = const ReadFinish.now(),
  });

  /// Applies the status rules: Reading opens a read-through (a reread when
  /// the last one is closed); Read/DNF close it.
  /// [finish] says when the book was finished, for [ReadingStatus.read].
  Future<void> setStatus(
    String workId,
    ReadingStatus status, {
    ReadFinish finish = const ReadFinish.now(),
  });

  /// Whether the book has a read-through in progress, so finishing it now is
  /// the natural answer and there's no need to ask when.
  /// Every entry, with removed books too. For statistics: a removed book's
  /// history is kept, so it still needs its details.
  Stream<List<LibraryEntry>> watchEntriesIncludingRemoved();

  Future<void> setWishlist(String workId, {required bool wishlist});

  /// Saves the reader's corrections to an edition: page count, where the text
  /// starts and ends, audio length, and page-to-time match points.
  Future<void> saveEditionDetails(UserEdition edition);

  Future<bool> hasOpenReadThrough(String workId);

  /// Whether adding this book as Read would only restore an earlier read: it
  /// was removed, and a finished read is on record with none in progress.
  Future<bool> restoresFinishedRead(String workId);

  /// Changes when a finished read-through ended. The book moves to that day in
  /// statistics; its pages stay on the day their progress was logged, because
  /// progress events are never edited.
  Future<void> setFinishDate(String readThroughId, ReadFinish finish);

  /// Records progress in the active edition. Starts reading if needed.
  /// Returns the stored event, or `null` when the position can't be
  /// converted (e.g. a page number in a book of unknown length).
  Future<ProgressEvent?> recordProgress(
    String workId,
    ReadingPosition position, {
    ProgressSource source = ProgressSource.manual,
  });

  /// Switches the edition the user is reading. Existing progress carries
  /// over as a work-level fraction.
  Future<void> setActiveEdition(String workId, UserEdition edition);

  /// Creates or changes an audiobook edition the reader typed, and makes it
  /// active. Recorded progress keeps its fraction of the book.
  Future<void> saveAudiobookEdition(UserEdition edition);

  Future<void> setOwned(UserEdition edition, {required bool owned});

  Future<void> setFavorite(String workId, {required bool favorite});

  /// Tombstones the entry; history (read-throughs, progress) is kept so a
  /// re-add restores it.
  Future<void> remove(String workId);

  /// Sets or clears (`null`) the half-star rating. Returns `false` if invalid.
  Future<bool> setRating(String workId, double? rating);

  /// Sets or clears the review. Returns `false` if it is too long.
  Future<bool> setReview(String workId, String? review);

  /// Everything statistics are computed from.
  Stream<List<ReadThrough>> watchAllReadThroughs();
  Stream<List<UserEdition>> watchAllEditions();
  Stream<List<ProgressEvent>> watchAllProgress();
  Stream<Set<String>> watchDeletedSessionIds();

  /// Deletes a saved session, on every device. Its progress event stays (the
  /// book is still where it is), but it no longer counts in statistics.
  Future<void> deleteSession(String sessionId);

  /// Adds a book from an export. What the reader already has wins: an existing
  /// entry keeps its shelf, and only an empty rating or review is filled. A book
  /// the reader removed stays removed. Safe to repeat, on any device.
  Future<ImportOutcome> importBook({
    required String workId,
    required BookSummary book,
    required ImportedBook imported,
    UserEdition? edition,
  });

  /// Saved sessions, newest first; all books when [workId] is null.
  Stream<List<ReadingSession>> watchSessions({String? workId, int limit = 50});

  /// Saves an *ended* [active] session atomically with its progress event
  /// and (if needed) the move to Reading, and clears the live timer row.
  /// [activeDurationSec] is the (possibly edited) reading time;
  /// [endPosition] the (possibly edited) position reached. Returns `null` if
  /// the book is no longer in the library.
  Future<ReadingSession?> completeSession(
    ActiveSession active, {
    required int activeDurationSec,
    ReadingPosition? endPosition,
  });
}
