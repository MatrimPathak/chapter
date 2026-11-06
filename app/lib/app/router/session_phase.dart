import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'routes.dart';

/// Where the user is in the app lifecycle; drives the router guard.
enum SessionPhase { loading, signedOut, needsOnboarding, ready }

final sessionPhaseProvider = Provider<SessionPhase>((ref) {
  final auth = ref.watch(authStateProvider);
  if (auth.isLoading && !auth.hasValue) return SessionPhase.loading;
  if (auth.value == null) return SessionPhase.signedOut;
  final prefs = ref.watch(preferencesProvider);
  return switch (prefs.value) {
    null => SessionPhase.loading,
    // On a new device the profile may be on its way: don't ask again too soon.
    final p when !p.onboardingDone && ref.watch(initialProfileProvider).isLoading =>
      SessionPhase.loading,
    final p when !p.onboardingDone => SessionPhase.needsOnboarding,
    _ => SessionPhase.ready,
  };
});

/// Pure redirect logic (unit-tested). Returns the location to redirect to,
/// or `null` to stay. Deep links survive sign-in via the `from` parameter.
String? redirectFor(SessionPhase phase, Uri location) {
  final path = location.path;
  final from = location.queryParameters['from'];
  final isGate = AppRoutes.gateRoutes.contains(path);
  String withFrom(String target) => isGate
      ? (from == null ? target : Uri(path: target, queryParameters: {'from': from}).toString())
      : Uri(path: target, queryParameters: {'from': location.toString()}).toString();

  switch (phase) {
    case SessionPhase.loading:
      return path == AppRoutes.splash ? null : withFrom(AppRoutes.splash);
    case SessionPhase.signedOut:
      return path == AppRoutes.signIn ? null : withFrom(AppRoutes.signIn);
    case SessionPhase.needsOnboarding:
      return path == AppRoutes.onboarding ? null : withFrom(AppRoutes.onboarding);
    case SessionPhase.ready:
      if (!isGate) return null;
      return (from != null && from.startsWith('/') && !_isGatePath(from)) ? from : AppRoutes.home;
  }
}

bool _isGatePath(String location) => AppRoutes.gateRoutes.contains(Uri.parse(location).path);
