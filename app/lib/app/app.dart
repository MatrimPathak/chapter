import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/design_system/design_system.dart';
import '../features/profile/domain/user_preferences.dart';
import '../l10n/generated/app_localizations.dart';
import 'providers.dart';
import 'router/app_router.dart';
import 'telemetry.dart';

class ChapterApp extends ConsumerWidget {
  const ChapterApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final signedIn = ref.watch(currentUserIdProvider) != null;
    final theme = signedIn ? ref.watch(preferencesProvider.select((p) => p.value?.theme)) : null;

    // Copy display name / photo / email into the synced profile on sign-in.
    ref
      ..listen(authStateProvider, (_, next) {
        final user = next.value;
        if (user != null) {
          unawaited(ref.read(profileRepositoryProvider).syncIdentity(user));
        }
      })
      // Apply telemetry consent whenever it changes.
      ..listen(telemetryControllerProvider, (_, _) {});

    return MaterialApp.router(
      title: 'Chapter',
      debugShowCheckedModeBanner: false,
      theme: ChapterTheme.light(),
      darkTheme: ChapterTheme.dark(),
      themeMode: switch (theme) {
        ThemePreference.light => ThemeMode.light,
        ThemePreference.dark => ThemeMode.dark,
        ThemePreference.system || null => ThemeMode.system,
      },
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      routerConfig: router,
    );
  }
}
