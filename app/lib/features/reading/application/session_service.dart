import 'dart:async';

import '../../../core/utils/clock.dart';
import '../../../core/utils/id_generator.dart';
import '../../library/domain/library_models.dart';
import '../../library/domain/library_repository.dart';
import '../../progress/domain/progress_mapper.dart';
import '../../progress/domain/reading_position.dart';
import '../domain/reading_session.dart';
import '../domain/session_clock.dart';
import '../domain/session_ports.dart';

/// Outcome of trying to turn focus mode on.
enum FocusResult { enabled, needsAccess, unsupported, failed }

/// The reading-session lifecycle (docs/05 §2.7):
/// start → pause/resume → end → summary → save or discard.
///
/// Every transition is written to the [ActiveSessionStore] *before* side
/// effects run, so a crash at any point can be recovered by [load]. Every
/// exit path (end, discard, recovery, failure to enable) restores Do Not
/// Disturb if Chapter changed it.
class SessionService {
  SessionService({
    required ActiveSessionStore store,
    required LibraryRepository library,
    required SessionNotifications notifications,
    required FocusMode focus,
    required Clock clock,
    required IdGenerator ids,
  }) : _store = store,
       _library = library,
       _notifications = notifications,
       _focus = focus,
       _clock = clock,
       _ids = ids;

  final ActiveSessionStore _store;
  final LibraryRepository _library;
  final SessionNotifications _notifications;
  final FocusMode _focus;
  final Clock _clock;
  final IdGenerator _ids;

  /// How long a paused session can hold Do Not Disturb past its remaining time.
  static const pausedRestoreLimit = Duration(hours: 1);

  /// Loads the live session at launch and recovers it:
  /// - running past its planned end → ended at the planned end, `recovered`;
  /// - running or paused within time → notifications re-armed;
  /// - ended but unsaved → returned as is (the summary reopens).
  Future<ActiveSession?> load() async {
    final s = await _store.read();
    if (s == null) return null;
    final now = _clock.now();
    if (!s.isEnded && s.clock.isOverdue(now)) {
      final ended = s.copyWith(clock: s.clock.end(now), recovered: true);
      await _store.write(ended);
      return _afterEnd(ended);
    }
    if (s.isEnded) {
      // Killed between End and Save: make sure DND and notifications are off.
      return _afterEnd(s);
    }
    await _arm(s);
    await _armFocus(s);
    return s;
  }

  Future<ActiveSession> start({required String workId, required Duration planned}) async {
    final existing = await _store.read();
    if (existing != null) throw StateError('A session is already active');
    final entry = await _library.watchEntry(workId).first;
    if (entry == null) throw StateError('Book is not in the library');
    final editions = await _library.watchEditions(workId).first;
    final latest = await _library.watchLatestProgress().first;
    final progress = entry.activeReadThroughId == null ? null : latest[entry.activeReadThroughId];
    final edition = editions.where((e) => e.editionId == entry.activeEditionId).firstOrNull;
    final metrics =
        edition?.metrics ?? EditionMetrics(format: 'other', pageCount: entry.book.pageCount);

    ReadingPosition? startPosition;
    if (progress != null) {
      startPosition = progress.editionId == entry.activeEditionId && !progress.isApproximate
          ? progress.position
          : ProgressMapper.fromFraction(progress.fraction, metrics).position;
    }
    final session = ActiveSession(
      id: _ids.newId(),
      workId: workId,
      editionId: entry.activeEditionId,
      clock: SessionClock.start(_clock.now(), planned),
      startPosition: startPosition,
      startFraction: progress?.fraction,
    );
    await _store.write(session);
    unawaited(
      _quietly(() async {
        await _notifications.ensurePermission();
        await _arm(session);
      }),
    );
    return session;
  }

  Future<ActiveSession> pause(ActiveSession s) async {
    final next = s.copyWith(clock: s.clock.pause(_clock.now()));
    await _store.write(next);
    await _arm(next);
    await _armFocus(next);
    return next;
  }

  Future<ActiveSession> resume(ActiveSession s) async {
    final next = s.copyWith(clock: s.clock.resume(_clock.now()));
    await _store.write(next);
    await _arm(next);
    if (next.focusModeOn) {
      // A long pause may have run past the safety limit: put DND back on.
      await _quietly(_focus.enable);
    }
    await _armFocus(next);
    return next;
  }

  /// Ends the session (from the End button or when the timer runs out).
  Future<ActiveSession> end(ActiveSession s) async {
    if (s.isEnded) return s;
    final next = s.copyWith(clock: s.clock.end(_clock.now()));
    await _store.write(next);
    // Ran to the planned end (e.g. ticking in the background): tell the
    // reader. Ended early by the reader: just clear the notifications.
    return _afterEnd(next, notifyCompleted: next.completion == SessionCompletion.completed);
  }

  /// Called by the UI ticker: ends the session once its time is up.
  Future<ActiveSession> checkOverdue(ActiveSession s) async =>
      s.clock.isOverdue(_clock.now()) ? end(s) : s;

  /// Saves the ended session (atomic with its progress event; the live row
  /// is cleared in the same transaction).
  Future<ReadingSession?> save(
    ActiveSession s, {
    required Duration readingTime,
    ReadingPosition? endPosition,
  }) async {
    final ended = s.isEnded ? s : await end(s);
    final saved = await _library.completeSession(
      ended,
      activeDurationSec: readingTime.inSeconds,
      endPosition: endPosition,
    );
    if (saved == null) await _store.clear(); // book removed meanwhile
    return saved;
  }

  /// Throws the session away. Nothing is written except clearing the row.
  Future<void> discard(ActiveSession s) async {
    await _afterEnd(s);
    await _store.clear();
  }

  /// Turns Do Not Disturb on for [s] (only after the user opted in).
  Future<(ActiveSession, FocusResult)> enableFocus(ActiveSession s) async {
    if (s.focusModeOn || s.isEnded) return (s, FocusResult.enabled);
    switch (await _focus.access()) {
      case FocusAccess.unsupported:
        return (s, FocusResult.unsupported);
      case FocusAccess.denied:
        return (s, FocusResult.needsAccess);
      case FocusAccess.granted:
        break;
    }
    final int? previous;
    try {
      previous = await _focus.enable();
    } on Object {
      return (s, FocusResult.failed);
    }
    if (previous == null) return (s, FocusResult.failed);
    final next = s.copyWith(dndPreviousFilter: () => previous);
    try {
      await _store.write(next);
    } on Object {
      // Couldn't record what to restore: undo immediately.
      await _focus.restore(previous);
      rethrow;
    }
    await _armFocus(next);
    return (next, FocusResult.enabled);
  }

  /// Turns Do Not Disturb back off mid-session.
  Future<ActiveSession> disableFocus(ActiveSession s) async {
    final previous = s.dndPreviousFilter;
    if (previous == null) return s;
    await _focus.restore(previous);
    final next = s.copyWith(dndPreviousFilter: () => null);
    await _store.write(next);
    return next;
  }

  /// Backstop in case the app is dead when DND should end: at the planned end
  /// while running; while paused (no planned end) after [pausedRestoreLimit].
  Future<void> _armFocus(ActiveSession s) async {
    final previous = s.dndPreviousFilter;
    if (previous == null || s.isEnded) return;
    final now = _clock.now();
    final at = s.clock.state == ClockState.paused
        ? now.add(s.clock.remaining(now) + pausedRestoreLimit)
        : s.clock.plannedEndAt(now);
    await _quietly(() => _focus.scheduleRestore(previous, at));
  }

  Future<void> _arm(ActiveSession s) => _quietly(() async {
    final title = await _titleOf(s.workId);
    switch (s.clock.state) {
      case ClockState.running:
        await _notifications.showRunning(title: title, endsAt: s.clock.plannedEndAt(_clock.now()));
      case ClockState.paused:
        await _notifications.showPaused(title: title);
      case ClockState.ended:
        await _notifications.cancelAll();
    }
  });

  /// Exit path: gives Do Not Disturb back *first* (the most important step,
  /// and the end alert must not be silenced by our own DND), then forgets the
  /// stored filter so a later relaunch can't overwrite a setting the reader
  /// has changed since. Notification failures never block this.
  Future<ActiveSession> _afterEnd(ActiveSession s, {bool notifyCompleted = false}) async {
    var out = s;
    final previous = s.dndPreviousFilter;
    if (previous != null) {
      await _focus.restore(previous);
      out = s.copyWith(dndPreviousFilter: () => null);
      await _store.write(out);
    }
    await _focus.keepScreenOn(on: false);
    await _quietly(() async {
      if (notifyCompleted) {
        await _notifications.showCompleted(title: await _titleOf(s.workId));
      } else {
        await _notifications.cancelAll();
      }
    });
    return out;
  }

  /// Notifications are a convenience: the session is safe without them.
  Future<void> _quietly(Future<void> Function() op) async {
    try {
      await op();
    } on Object {
      // Ignored on purpose; recorded time comes from timestamps.
    }
  }

  Future<String> _titleOf(String workId) async {
    final LibraryEntry? e = await _library.watchEntry(workId).first;
    return e?.book.title ?? '';
  }
}
