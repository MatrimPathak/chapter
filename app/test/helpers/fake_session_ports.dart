import 'package:chapter/features/reading/domain/session_ports.dart';

/// Records what the session layer asked the OS to show.
class FakeSessionNotifications implements SessionNotifications {
  bool permission = true;
  final calls = <String>[];
  DateTime? scheduledEnd;
  bool ongoing = false;

  @override
  Future<bool> ensurePermission() async {
    calls.add('permission');
    return permission;
  }

  @override
  Future<void> showRunning({required String title, required DateTime endsAt}) async {
    final error = failWith;
    if (error != null) throw error;
    calls.add('running');
    scheduledEnd = endsAt;
    ongoing = true;
  }

  @override
  Future<void> showPaused({required String title}) async {
    calls.add('paused');
    scheduledEnd = null;
    ongoing = true;
  }

  bool completedShown = false;

  /// Runs when the end alert is shown (to observe the DND state then).
  void Function()? onCompleted;

  /// When set, every notification call throws.
  Object? failWith;

  @override
  Future<void> showCompleted({required String title}) async {
    final error = failWith;
    if (error != null) throw error;
    onCompleted?.call();
    calls.add('completed');
    completedShown = true;
    scheduledEnd = null;
    ongoing = false;
  }

  @override
  Future<void> cancelAll() async {
    final error = failWith;
    if (error != null) throw error;
    calls.add('cancel');
    scheduledEnd = null;
    ongoing = false;
  }
}

/// Simulates Android's interruption filter. 1 = all (DND off), 2 = priority.
class FakeFocusMode implements FocusMode {
  FocusAccess accessState = FocusAccess.granted;
  int filter = 1;
  bool screenOn = false;
  bool throwOnEnable = false;
  int openedSettings = 0;

  @override
  Future<FocusAccess> access() async => accessState;

  @override
  Future<void> openAccessSettings() async => openedSettings++;

  /// Mirrors FocusRestore.kt: only undoes DND that Chapter turned on.
  bool applied = false;
  (int, DateTime)? scheduledRestore;

  @override
  Future<int?> enable() async {
    if (throwOnEnable) throw StateError('policy access revoked');
    final previous = filter;
    if (previous == 1) {
      filter = 2;
      applied = true;
    }
    return previous;
  }

  @override
  Future<void> restore(int previousFilter) async {
    if (applied && filter == 2) filter = previousFilter;
    applied = false;
    scheduledRestore = null;
  }

  @override
  Future<void> scheduleRestore(int previousFilter, DateTime at) async =>
      scheduledRestore = (previousFilter, at);

  /// What the native alarm does when it fires.
  Future<void> fireScheduledRestore() => restore(scheduledRestore!.$1);

  @override
  Future<void> keepScreenOn({required bool on}) async => screenOn = on;
}
