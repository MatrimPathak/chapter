import 'dart:async';

import 'package:flutter/widgets.dart' show AppLifecycleListener;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../core/error/failure.dart';
import '../../../core/error/result.dart';
import '../../reading/application/session_controller.dart';
import '../data/account_ports.dart';
import 'data_exporter.dart';

enum DeleteAccountResult { deleted, cancelled, failed }

final accountActionsProvider = Provider<AccountActions>(AccountActions.new);

class AccountActions {
  AccountActions(this._ref);

  final Ref _ref;

  /// Builds and shares the export. Offline-safe. Throws on failure.
  Future<void> exportData() async {
    final uid = _ref.read(currentUserIdProvider);
    if (uid == null) return;
    final exporter = DataExporter(
      _ref.read(appDatabaseProvider),
      uid,
      _ref.read(clockProvider).now(),
    );
    await _ref.read(exportSharerProvider).share(await exporter.build());
  }

  /// Deletes the account on the server, then everything on this device.
  ///
  /// Sync stops first, so nothing can be written back behind the deletion. If
  /// the server doesn't confirm, nothing local is touched and sync resumes.
  Future<DeleteAccountResult> deleteAccount() async {
    final uid = _ref.read(currentUserIdProvider);
    if (uid == null) return DeleteAccountResult.failed;
    final auth = _ref.read(authRepositoryProvider);
    final remote = _ref.read(accountRemoteProvider);
    final engine = _ref.read(syncEngineProvider);

    switch (await auth.prepareAccountDeletion()) {
      case Ok():
        break;
      case Err(:final failure):
        return failure is CancelledFailure
            ? DeleteAccountResult.cancelled
            : DeleteAccountResult.failed;
    }

    await engine.halt();
    var deleted = false;
    try {
      var outcome = await remote.deleteAccount();
      if (outcome == DeleteAccountOutcome.needsRecentSignIn) {
        switch (await auth.reauthenticate()) {
          case Ok():
            outcome = await remote.deleteAccount();
          case Err(:final failure):
            return failure is CancelledFailure
                ? DeleteAccountResult.cancelled
                : DeleteAccountResult.failed;
        }
      }
      deleted = outcome == DeleteAccountOutcome.deleted;
      if (!deleted) return DeleteAccountResult.failed;
    } on Object {
      return DeleteAccountResult.failed;
    } finally {
      if (!deleted) engine.resume();
    }

    await _wipeThisDevice(uid);
    return DeleteAccountResult.deleted;
  }

  /// The account was deleted from another device: this copy goes too (W49).
  /// Checked on launch and on returning to the app. Does nothing when offline.
  Future<void> checkAccountStillExists() async {
    final uid = _ref.read(currentUserIdProvider);
    if (uid == null) return;
    if (await _ref.read(authRepositoryProvider).accountStillExists()) return;
    // The auth SDK may already have signed out on its own, taking the signed-in
    // providers with it. The wipe must not depend on any of them.
    try {
      await _ref.read(syncEngineProvider).halt();
    } on Object {
      // Already gone with the sign-out.
    }
    await _wipeThisDevice(uid);
  }

  /// The account is gone. Nothing here may stop the local wipe.
  Future<void> _wipeThisDevice(String uid) async {
    final auth = _ref.read(authRepositoryProvider);
    final wiper = _ref.read(localDataWiperProvider);
    try {
      await wiper.markPending(uid);
    } on Object {
      // Without a marker a kill here would leave the file; the wipe below still runs.
    }
    try {
      // Restores Do Not Disturb and clears notifications and alarms.
      await _ref.read(sessionControllerProvider.future);
      await _ref.read(sessionControllerProvider.notifier).discard();
    } on Object {
      // The database is about to go regardless.
    }
    await auth.signOut();
    // Signing out closes the database through its provider.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    await wiper.finishPending();
  }
}

/// Runs the check on launch and each time the app returns to the foreground.
final accountWatchProvider = Provider<void>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return;
  final actions = ref.read(accountActionsProvider);
  void check() => unawaited(actions.checkAccountStillExists().catchError((Object _) {}));
  final listener = AppLifecycleListener(onResume: check);
  ref.onDispose(listener.dispose);
  check();
});
