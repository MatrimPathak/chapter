import 'package:meta/meta.dart';

/// User-visible sync state (docs/05 §2.6).
sealed class SyncStatus {
  const SyncStatus();
}

final class SyncSynced extends SyncStatus {
  const SyncSynced();
}

final class SyncSyncing extends SyncStatus {
  const SyncSyncing();
}

@immutable
final class SyncPending extends SyncStatus {
  const SyncPending(this.count);
  final int count;

  @override
  bool operator ==(Object other) => other is SyncPending && other.count == count;

  @override
  int get hashCode => count.hashCode;
}

final class SyncOffline extends SyncStatus {
  const SyncOffline();
}

/// Some changes were permanently rejected (dead-lettered) and need attention.
@immutable
final class SyncError extends SyncStatus {
  const SyncError(this.deadLetterCount);
  final int deadLetterCount;

  @override
  bool operator ==(Object other) => other is SyncError && other.deadLetterCount == deadLetterCount;

  @override
  int get hashCode => deadLetterCount.hashCode;
}
