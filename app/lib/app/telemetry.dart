import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'crash_scrubber.dart';
import 'providers.dart';

/// Applies the user's consent to Analytics and Crashlytics (docs/05 §1.5).
///
/// Collection is disabled at startup (see `bootstrap.dart`) and only enabled
/// in production builds after explicit consent. Signing out disables both.
final telemetryControllerProvider = Provider<void>((ref) {
  final config = ref.watch(appConfigProvider);
  final signedIn = ref.watch(currentUserIdProvider) != null;
  final prefs = signedIn ? ref.watch(preferencesProvider).value : null;

  unawaited(
    FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(
      telemetryEnabled(config, consent: prefs?.analyticsConsent),
    ),
  );
  unawaited(
    FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
      telemetryEnabled(config, consent: prefs?.crashConsent),
    ),
  );
});
