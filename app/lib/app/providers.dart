import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode;
import 'package:flutter/widgets.dart' show Locale, WidgetsBinding;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../core/database/app_database.dart';
import '../core/sync/firestore_sync_remote.dart';
import '../core/sync/lww_store.dart';
import '../core/sync/sync_engine.dart';
import '../core/sync/sync_remote.dart';
import '../core/sync/sync_status.dart';
import '../core/utils/clock.dart';
import '../core/utils/id_generator.dart';
import '../features/auth/data/firebase_auth_repository.dart';
import '../features/auth/domain/app_user.dart';
import '../features/auth/domain/auth_repository.dart';
import '../features/catalog/data/catalog_remote.dart';
import '../features/catalog/data/catalog_repository_impl.dart';
import '../features/catalog/domain/catalog_repository.dart';
import '../features/goals/data/lww_goal_repository.dart';
import '../features/integrations/application/import_runner.dart';
import '../features/integrations/data/import_queue.dart';
import '../features/integrations/data/platform_ports.dart';
import '../features/integrations/data/spotify_remote.dart';
import '../features/integrations/domain/integration.dart';
import '../features/library/data/lww_library_repository.dart';
import '../features/library/domain/library_repository.dart';
import '../features/notes/data/lww_notes_repository.dart';
import '../features/profile/data/account_ports.dart';
import '../features/profile/data/lww_profile_repository.dart';
import '../features/profile/domain/profile_repository.dart';
import '../features/profile/domain/user_preferences.dart';
import '../features/reading/application/session_service.dart';
import '../features/reading/data/channel_focus_mode.dart';
import '../features/reading/data/drift_active_session_store.dart';
import '../features/reading/data/local_session_notifications.dart';
import '../features/reading/domain/session_ports.dart';
import '../features/shelves/data/lww_shelf_repository.dart';
import '../l10n/generated/app_localizations.dart';
import 'app_config.dart';

// ─── Configuration & infrastructure (overridden in bootstrap and tests) ───

final appConfigProvider = Provider<AppConfig>(
  (ref) => throw UnimplementedError('appConfigProvider must be overridden'),
);

final clockProvider = Provider<Clock>((ref) => const SystemClock());

final idGeneratorProvider = Provider<IdGenerator>((ref) => const UuidV7Generator());

final firebaseAuthProvider = Provider<FirebaseAuth>((ref) => FirebaseAuth.instance);

final firestoreProvider = Provider<FirebaseFirestore>((ref) => FirebaseFirestore.instance);

final functionsProvider = Provider<FirebaseFunctions>(
  (ref) => FirebaseFunctions.instanceFor(region: functionsRegion),
);

/// Connectivity hint for the sync engine. `true` when any network is up.
final connectivityProvider = StreamProvider<bool>((ref) async* {
  final connectivity = Connectivity();
  bool online(List<ConnectivityResult> r) => r.any((c) => c != ConnectivityResult.none);
  yield online(await connectivity.checkConnectivity());
  yield* connectivity.onConnectivityChanged.map(online);
});

// ─── Auth ───

final authRepositoryProvider = Provider<AuthRepository>((ref) {
  final config = ref.watch(appConfigProvider);
  return FirebaseAuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    googleSignIn: GoogleSignIn.instance,
    usingEmulators: config.useEmulators,
    googleServerClientId: config.googleServerClientId,
  );
});

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// The signed-in user's uid, or `null`. User-scoped providers depend on this
/// so they are disposed and rebuilt on sign-out / sign-in.
final currentUserIdProvider = Provider<String?>(
  (ref) => ref.watch(authStateProvider.select((s) => s.value?.uid)),
);

String _requireUid(Ref ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) throw StateError('No signed-in user');
  return uid;
}

// ─── User-scoped data (one database per uid) ───

final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.forUser(_requireUid(ref));
  ref.onDispose(db.close);
  return db;
});

final lwwStoreProvider = Provider<LwwStore>(
  (ref) => LwwStore(
    db: ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

final syncRemoteProvider = Provider<SyncRemote>(
  (ref) => FirestoreSyncRemote(ref.watch(firestoreProvider)),
);

final syncEngineProvider = Provider<SyncEngine>((ref) {
  final uid = _requireUid(ref);
  final engine = SyncEngine(
    db: ref.watch(appDatabaseProvider),
    store: ref.watch(lwwStoreProvider),
    remote: ref.watch(syncRemoteProvider),
  )..start();
  engine.watchDocument('users/$uid');
  ref
    ..listen(connectivityProvider, (_, next) {
      final online = next.value;
      if (online != null) engine.setOnline(online);
    })
    ..onDispose(() => unawaited(engine.dispose()));
  return engine;
});

/// Safe to watch while signed out (screens may still be mounted during the
/// sign-out transition): reports "synced" when there is no user.
final syncStatusProvider = StreamProvider<SyncStatus>((ref) async* {
  if (ref.watch(currentUserIdProvider) == null) {
    yield const SyncSynced();
    return;
  }
  final engine = ref.watch(syncEngineProvider);
  yield engine.status;
  yield* engine.statusStream;
});

// ─── Profile ───

final profileRepositoryProvider = Provider<ProfileRepository>((ref) {
  final engine = ref.watch(syncEngineProvider);
  return LwwProfileRepository(
    store: ref.watch(lwwStoreProvider),
    uid: _requireUid(ref),
    onLocalWrite: engine.nudge,
  );
});

/// Safe to watch while signed out: emits defaults when there is no user.
final preferencesProvider = StreamProvider<UserPreferences>((ref) {
  if (ref.watch(currentUserIdProvider) == null) {
    return Stream.value(const UserPreferences());
  }
  return ref.watch(profileRepositoryProvider).watchPreferences();
});

/// Waits briefly for the server's copy of the profile, so a second device
/// doesn't repeat onboarding (W5). Never fails: offline or slow means carrying on.
final initialProfileProvider = FutureProvider<void>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return;
  final store = ref.read(lwwStoreProvider);
  final remote = ref.read(syncRemoteProvider);
  final path = 'users/$uid';
  try {
    final doc = await remote.watch(path).first.timeout(const Duration(seconds: 4));
    if (doc != null) await store.mergeRemote(path, doc);
  } on Object {
    // Offline or slow: onboarding shows, and converges by LWW later.
  }
});

// ─── Catalog (Phase 3) ───

final catalogRemoteProvider = Provider<CatalogRemote>(
  (ref) => FunctionsCatalogRemote(ref.watch(functionsProvider)),
);

/// User-scoped because the on-device cache lives in the user's database.
final catalogRepositoryProvider = Provider<CatalogRepository>(
  (ref) => CatalogRepositoryImpl(
    remote: ref.watch(catalogRemoteProvider),
    db: ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
  ),
);

// ─── Library, editions, read-throughs, progress (Phase 4) ───

final _lwwLibraryRepositoryProvider = Provider<LwwLibraryRepository>((ref) {
  final engine = ref.watch(syncEngineProvider);
  final repo = LwwLibraryRepository(
    store: ref.watch(lwwStoreProvider),
    db: ref.watch(appDatabaseProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    uid: _requireUid(ref),
    onLocalWrite: engine.nudge,
  );
  // Pull the user's collections for as long as the repository lives (it
  // lives with the signed-in user: Home and Library watch it).
  unawaited(repo.attachSync(engine));
  unawaited(ref.watch(goalRepositoryProvider).attachSync(engine));
  unawaited(ref.watch(shelfRepositoryProvider).attachSync(engine));
  unawaited(ref.watch(notesRepositoryProvider).attachSync(engine));
  return repo;
});

final shelfRepositoryProvider = Provider<LwwShelfRepository>(
  (ref) => LwwShelfRepository(
    store: ref.watch(lwwStoreProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    uid: _requireUid(ref),
    onLocalWrite: ref.watch(syncEngineProvider).nudge,
  ),
);

final goalRepositoryProvider = Provider<LwwGoalRepository>(
  (ref) => LwwGoalRepository(
    store: ref.watch(lwwStoreProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    uid: _requireUid(ref),
    onLocalWrite: ref.watch(syncEngineProvider).nudge,
  ),
);

final notesRepositoryProvider = Provider<LwwNotesRepository>(
  (ref) => LwwNotesRepository(
    store: ref.watch(lwwStoreProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
    uid: _requireUid(ref),
    onLocalWrite: ref.watch(syncEngineProvider).nudge,
  ),
);

final libraryRepositoryProvider = Provider<LibraryRepository>(
  (ref) => ref.watch(_lwwLibraryRepositoryProvider),
);

// ─── Reading sessions (Phase 5) ───

final activeSessionStoreProvider = Provider<ActiveSessionStore>(
  (ref) => DriftActiveSessionStore(ref.watch(appDatabaseProvider), ref.watch(clockProvider)),
);

/// Overridden in tests with a fake.
final sessionNotificationsProvider = Provider<SessionNotifications>((ref) {
  final locale = WidgetsBinding.instance.platformDispatcher.locale;
  final l10n = AppLocalizations.supportedLocales.any((l) => l.languageCode == locale.languageCode)
      ? lookupAppLocalizations(Locale(locale.languageCode))
      : lookupAppLocalizations(const Locale('en'));
  final db = ref.watch(appDatabaseProvider);
  const permissionFlag = 'notification_permission_asked';
  return LocalSessionNotifications(
    permissionAsked: () => db.hasFlag(permissionFlag),
    markPermissionAsked: () => db.setFlag(permissionFlag),
    endTitle: l10n.sessionNotifEndTitle,
    endBody: l10n.sessionNotifEndBody,
    runningBody: l10n.sessionNotifRunning,
    pausedBody: l10n.sessionNotifPaused,
    channelName: l10n.sessionNotifChannel,
    clock: ref.watch(clockProvider),
  );
});

/// Overridden in tests with a fake.
final focusModeProvider = Provider<FocusMode>((ref) => ChannelFocusMode());

final sessionServiceProvider = Provider<SessionService>(
  (ref) => SessionService(
    store: ref.watch(activeSessionStoreProvider),
    library: ref.watch(libraryRepositoryProvider),
    notifications: ref.watch(sessionNotificationsProvider),
    focus: ref.watch(focusModeProvider),
    clock: ref.watch(clockProvider),
    ids: ref.watch(idGeneratorProvider),
  ),
);

// ─── Integrations (Phase 7) ───

/// Overridden in tests, including with integrations that fail on purpose.
final integrationsProvider = Provider<List<Integration>>((ref) => defaultIntegrations);

final linkOpenerProvider = Provider<LinkOpener>((ref) => const UrlLauncherLinkOpener());

final spotifyRemoteProvider = Provider<SpotifyRemote>(
  (ref) => CallableSpotifyRemote(ref.watch(catalogRemoteProvider)),
);

final textFilePickerProvider = Provider<TextFilePicker>((ref) => const SystemTextFilePicker());

final importQueueProvider = Provider<ImportQueue>(
  (ref) => ImportQueue(ref.watch(appDatabaseProvider), ref.watch(clockProvider)),
);

/// Resumes any unfinished import when the app starts or the connection returns.
/// Watches only the uid (TD-27), so it stays quiet through sign-out.
final importRunnerProvider = Provider<ImportRunner?>((ref) {
  if (ref.watch(currentUserIdProvider) == null) return null;
  // The shell watches this, so nothing here may be able to take the app down.
  final ImportRunner runner;
  try {
    runner = ImportRunner(
      queue: ref.read(importQueueProvider),
      catalog: ref.read(catalogRepositoryProvider),
      library: ref.read(libraryRepositoryProvider),
    );
  } on Object catch (e) {
    if (kDebugMode) debugPrint('Import unavailable: $e');
    return null;
  }
  ref
    ..listen(connectivityProvider, (_, next) {
      if (next.value ?? false) unawaited(runner.run());
    })
    ..onDispose(runner.dispose);
  unawaited(runner.run());
  return runner;
});

// ─── Account (Phase 8) ───

final accountRemoteProvider = Provider<AccountRemote>(
  (ref) => CallableAccountRemote(ref.watch(functionsProvider)),
);

final localDataWiperProvider = Provider<LocalDataWiper>((ref) => const FileLocalDataWiper());

final exportSharerProvider = Provider<ExportSharer>((ref) => const SystemExportSharer());
