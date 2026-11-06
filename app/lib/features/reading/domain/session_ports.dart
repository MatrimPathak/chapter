import 'reading_session.dart';

/// Persists the singleton live session (`active_session` table).
abstract interface class ActiveSessionStore {
  Future<ActiveSession?> read();
  Future<void> write(ActiveSession session);
  Future<void> clear();
}

/// Session notifications: an ongoing notification while the timer runs and
/// an end notification scheduled for the planned end (fires even if the app
/// is killed).
abstract interface class SessionNotifications {
  /// Asks for notification permission where the OS needs it (Android 13+,
  /// iOS). Returns whether notifications can be shown.
  Future<bool> ensurePermission();

  /// Shows the ongoing notification and (re)schedules the end notification.
  Future<void> showRunning({required String title, required DateTime endsAt});

  /// Shows a paused ongoing notification; no end notification while paused.
  Future<void> showPaused({required String title});

  /// The timer ran out: replaces the ongoing notification with the
  /// "session complete" alert (same id as the scheduled one, so it never
  /// shows twice).
  Future<void> showCompleted({required String title});

  /// Removes the ongoing notification and the scheduled end notification.
  Future<void> cancelAll();
}

enum FocusAccess {
  /// Notification Policy Access granted (Android).
  granted,

  /// The user must grant access in system settings first.
  denied,

  /// The platform can't change Do Not Disturb (iOS).
  unsupported,
}

/// Do Not Disturb and screen wake control (docs/04 §5).
abstract interface class FocusMode {
  Future<FocusAccess> access();

  /// Opens the system's Notification Policy Access screen. Only ever called
  /// from an explicit user tap.
  Future<void> openAccessSettings();

  /// Turns Do Not Disturb on (priority only). Returns the previous
  /// interruption filter to restore later, or `null` if nothing changed.
  Future<int?> enable();

  /// Restores [previousFilter] if Chapter's Do Not Disturb is still in place
  /// (a setting the reader changed since is left alone). Also cancels any
  /// scheduled restore. Safe to call more than once.
  Future<void> restore(int previousFilter);

  /// Arranges for [previousFilter] to be restored at [at] by the platform,
  /// even if the app is dead by then. Replaces any earlier schedule.
  Future<void> scheduleRestore(int previousFilter, DateTime at);

  Future<void> keepScreenOn({required bool on});
}
