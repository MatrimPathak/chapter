import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/app_config.dart';
import 'app/crash_scrubber.dart';
import 'app/providers.dart';
import 'features/profile/data/account_ports.dart';

/// Shared start-up for every flavor.
Future<void> bootstrap(AppConfig config, FirebaseOptions options) async {
  WidgetsFlutterBinding.ensureInitialized();
  // Shown under About, Open source licences.
  for (final (name, file) in const [
    ('Newsreader', 'OFL-Newsreader'),
    ('Plus Jakarta Sans', 'OFL-PlusJakartaSans'),
  ]) {
    LicenseRegistry.addLicense(() async* {
      yield LicenseEntryWithLineBreaks([
        name,
      ], await rootBundle.loadString('assets/fonts/$file.txt'));
    });
  }
  // Before anything can open a database that is due to be wiped.
  await const FileLocalDataWiper().finishPending();
  await Firebase.initializeApp(options: options);

  // Drift is the local source of truth (TD-4); Firestore's own cache would
  // duplicate it.
  FirebaseFirestore.instance.settings = const Settings(persistenceEnabled: false);

  if (config.useEmulators) {
    await FirebaseAuth.instance.useAuthEmulator(config.emulatorHost, 9099);
    FirebaseFirestore.instance.useFirestoreEmulator(config.emulatorHost, 8080);
    FirebaseFunctions.instanceFor(
      region: functionsRegion,
    ).useFunctionsEmulator(config.emulatorHost, 5001);
  } else {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  }

  // Telemetry is off until consent is known (applied by telemetry.dart).
  await FirebaseAnalytics.instance.setAnalyticsCollectionEnabled(false);
  await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(false);
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    reportFatal(details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    reportFatal(error, stack);
    return true;
  };

  runApp(
    ProviderScope(
      // No automatic provider retries: screens offer an explicit "Try again",
      // and silent retry loops would burn the catalog rate limits.
      retry: (retryCount, error) => null,
      overrides: [appConfigProvider.overrideWithValue(config)],
      child: const ChapterApp(),
    ),
  );
}
