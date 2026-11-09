import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../goals/domain/goal.dart';
import '../../library/domain/library_models.dart';
import '../../library/presentation/library_providers.dart';
import '../../notes/domain/note.dart';
import '../../progress/domain/progress_event.dart';
import '../../reading/domain/reading_session.dart';
import '../domain/stats_engine.dart';

/// Removed books included: their reads still count (W32).
final statsEntriesProvider = StreamProvider<List<LibraryEntry>>(
  (ref) => userScoped(ref, const [], (r) => r.watchEntriesIncludingRemoved()),
);

final allReadThroughsProvider = StreamProvider<List<ReadThrough>>(
  (ref) => userScoped(ref, const [], (r) => r.watchAllReadThroughs()),
);

final allEditionsProvider = StreamProvider<List<UserEdition>>(
  (ref) => userScoped(ref, const [], (r) => r.watchAllEditions()),
);

final allProgressProvider = StreamProvider<List<ProgressEvent>>(
  (ref) => userScoped(ref, const [], (r) => r.watchAllProgress()),
);

final allSessionsProvider = StreamProvider<List<ReadingSession>>(
  (ref) => userScoped(ref, const [], (r) => r.watchSessions(limit: 1 << 30)),
);

final deletedSessionIdsProvider = StreamProvider<Set<String>>(
  (ref) => userScoped(ref, const {}, (r) => r.watchDeletedSessionIds()),
);

/// Goals, newest period first. Watches only the uid and reads the repository
/// (see `userScoped`).
final goalsProvider = StreamProvider<List<Goal>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Stream.value(const []);
  return ref.read(goalRepositoryProvider).watchGoals();
});

final bookNotesProvider = StreamProvider.family<List<Note>, String>((ref, workId) {
  if (ref.watch(currentUserIdProvider) == null) return Stream.value(const []);
  return ref.read(notesRepositoryProvider).watchNotes(workId);
});

/// Every note, newest first.
final allNotesProvider = StreamProvider<List<Note>>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return Stream.value(const []);
  return ref.read(notesRepositoryProvider).watchAllNotes();
});

/// Statistics over the whole local history, or `null` while it loads. Built in
/// the widget rather than a derived provider (TD-27), and reused until any of
/// the underlying lists actually changes.
StatsEngine? watchStats(WidgetRef ref) {
  final entries = ref.watch(statsEntriesProvider).value;
  final throughs = ref.watch(allReadThroughsProvider).value;
  final sessions = ref.watch(allSessionsProvider).value;
  final events = ref.watch(allProgressProvider).value;
  final editions = ref.watch(allEditionsProvider).value;
  final deleted = ref.watch(deletedSessionIdsProvider).value;
  if (entries == null ||
      throughs == null ||
      sessions == null ||
      events == null ||
      editions == null ||
      deleted == null) {
    return null;
  }
  final last = _last;
  if (last != null &&
      identical(last.input.entries, entries) &&
      identical(last.input.readThroughs, throughs) &&
      identical(last.input.sessions, sessions) &&
      identical(last.input.events, events) &&
      identical(last.input.editions, editions) &&
      identical(last.input.deletedSessionIds, deleted)) {
    return last;
  }
  return _last = StatsEngine(
    StatsInput(
      entries: entries,
      readThroughs: throughs,
      sessions: sessions,
      events: events,
      editions: editions,
      deletedSessionIds: deleted,
    ),
  );
}

StatsEngine? _last;
