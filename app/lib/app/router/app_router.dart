import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/presentation/sign_in_screen.dart';
import '../../features/auth/presentation/splash_screen.dart';
import '../../features/catalog/presentation/author_screen.dart';
import '../../features/catalog/presentation/book_detail_screen.dart';
import '../../features/catalog/presentation/series_screen.dart';
import '../../features/goals/presentation/goals_screen.dart';
import '../../features/home/presentation/home_screen.dart';
import '../../features/insights/presentation/insights_screen.dart';
import '../../features/integrations/presentation/import_screens.dart';
import '../../features/integrations/presentation/integrations_screen.dart';
import '../../features/library/presentation/library_screen.dart';
import '../../features/notes/presentation/notes_screen.dart';
import '../../features/profile/presentation/about_screen.dart';
import '../../features/profile/presentation/delete_account_screen.dart';
import '../../features/profile/presentation/onboarding_screen.dart';
import '../../features/profile/presentation/profile_screen.dart';
import '../../features/reading/presentation/read_screen.dart';
import '../../features/reading/presentation/session_screen.dart';
import '../../features/scanner/presentation/scan_screen.dart';
import '../../features/search/presentation/search_screen.dart';
import '../../features/shelves/presentation/shelf_screen.dart';
import '../../features/shelves/presentation/shelves_screen.dart';
import 'routes.dart';
import 'scaffold_with_nav.dart';
import 'session_phase.dart';

final _rootKey = GlobalKey<NavigatorState>(debugLabel: 'root');

final appRouterProvider = Provider<GoRouter>((ref) {
  final phase = ValueNotifier<SessionPhase>(ref.read(sessionPhaseProvider));
  ref
    ..listen(sessionPhaseProvider, (_, next) => phase.value = next)
    ..onDispose(phase.dispose);

  final router = GoRouter(
    navigatorKey: _rootKey,
    initialLocation: AppRoutes.splash,
    refreshListenable: phase,
    redirect: (context, state) => redirectFor(phase.value, state.uri),
    routes: [
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      GoRoute(path: AppRoutes.signIn, builder: (_, _) => const SignInScreen()),
      GoRoute(path: AppRoutes.onboarding, builder: (_, _) => const OnboardingScreen()),
      // Global detail routes on the root navigator (docs/02 §6).
      GoRoute(
        path: AppRoutes.integrations,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const IntegrationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.importCsv,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const CsvImportScreen(),
      ),
      GoRoute(
        path: AppRoutes.importClippings,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ClippingsImportScreen(),
      ),
      GoRoute(
        path: AppRoutes.about,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const AboutScreen(),
      ),
      GoRoute(
        path: AppRoutes.privacy,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const PrivacyPolicyScreen(),
      ),
      GoRoute(
        path: AppRoutes.deleteAccount,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const DeleteAccountScreen(),
      ),
      GoRoute(
        path: AppRoutes.goals,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const GoalsScreen(),
      ),
      GoRoute(
        path: AppRoutes.notes,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const NotesScreen(),
      ),
      GoRoute(
        path: AppRoutes.insights,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const InsightsScreen(),
      ),
      GoRoute(
        path: AppRoutes.session,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SessionScreen(),
      ),
      GoRoute(
        path: AppRoutes.scan,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const ScanScreen(),
      ),
      GoRoute(
        path: AppRoutes.bookPattern,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => BookDetailScreen(
          workKey: state.pathParameters['key']!,
          editionId: state.uri.queryParameters['edition'],
        ),
      ),
      GoRoute(
        path: AppRoutes.authorPattern,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => AuthorScreen(authorKey: state.pathParameters['key']!),
      ),
      GoRoute(
        path: AppRoutes.search,
        parentNavigatorKey: _rootKey,
        builder: (_, _) => const SearchScreen(),
      ),
      GoRoute(
        path: AppRoutes.shelfPattern,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => ShelfScreen(shelfId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.seriesPattern,
        parentNavigatorKey: _rootKey,
        builder: (_, state) => SeriesScreen(seriesId: state.pathParameters['id']!),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => ScaffoldWithNav(shell: shell),
        branches: [
          _branch(AppRoutes.home, const HomeScreen()),
          _branch(AppRoutes.library, const LibraryScreen()),
          _branch(AppRoutes.shelves, const ShelvesScreen()),
          _branch(AppRoutes.read, const ReadScreen()),
          _branch(AppRoutes.profile, const ProfileScreen()),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

StatefulShellBranch _branch(String path, Widget screen) => StatefulShellBranch(
  routes: [GoRoute(path: path, builder: (_, _) => screen)],
);
