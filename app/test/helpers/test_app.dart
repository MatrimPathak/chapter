import 'package:chapter/app/app.dart';
import 'package:chapter/app/app_config.dart';
import 'package:chapter/app/providers.dart';
import 'package:chapter/app/telemetry.dart';
import 'package:chapter/core/database/app_database.dart';
import 'package:chapter/core/utils/clock.dart';
import 'package:chapter/features/catalog/domain/catalog_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_repository.dart';
import 'fake_catalog.dart';
import 'fake_session_ports.dart';
import 'fake_sync_remote.dart';

/// Pumps the real [ChapterApp] with Firebase, plugins and the database
/// replaced by in-memory fakes.
Future<FakeAuthRepository> pumpChapterApp(
  WidgetTester tester, {
  FakeAuthRepository? auth,
  AppConfig? config,
  CatalogRepository? catalog,
  FakeClock? clock,
  AppDatabase? database,
  FakeSessionNotifications? notifications,
  FakeFocusMode? focus,
  List<Override> extraOverrides = const [],
}) async {
  final fakeAuth = auth ?? FakeAuthRepository();
  final remote = FakeSyncRemote();
  addTearDown(remote.dispose);
  await tester.pumpWidget(
    ProviderScope(
      retry: (retryCount, error) => null,
      overrides: [
        ...extraOverrides,
        appConfigProvider.overrideWithValue(config ?? AppConfig.dev()),
        authRepositoryProvider.overrideWithValue(fakeAuth),
        syncRemoteProvider.overrideWithValue(remote),
        connectivityProvider.overrideWith((ref) => Stream.value(true)),
        telemetryControllerProvider.overrideWith((ref) {}),
        catalogRepositoryProvider.overrideWithValue(catalog ?? FakeCatalogRepository()),
        clockProvider.overrideWithValue(clock ?? FakeClock(DateTime(2026, 11, 4, 9))),
        sessionNotificationsProvider.overrideWithValue(notifications ?? FakeSessionNotifications()),
        focusModeProvider.overrideWithValue(focus ?? FakeFocusMode()),
        appDatabaseProvider.overrideWith((ref) {
          ref.watch(currentUserIdProvider);
          if (database != null) return database; // shared across "launches"
          final db = AppDatabase(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
      ],
      child: const ChapterApp(),
    ),
  );
  await settle(tester);
  return fakeAuth;
}

/// Lets streams, Drift queries and the router settle.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Unmounts the app so Drift streams and the sync engine shut down, then
/// flushes the zero-length timers Drift schedules when streams close.
/// Call at the end of every test that used [pumpChapterApp].
Future<void> unmountApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await settle(tester);
}
