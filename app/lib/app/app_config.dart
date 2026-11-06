import 'package:flutter/foundation.dart';

enum Flavor { dev, prod }

/// Build-time configuration selected by the entry point (`main_dev.dart`,
/// `main_prod.dart`). Values that differ per machine come from
/// `--dart-define`, never from source.
@immutable
class AppConfig {
  const AppConfig({
    required this.flavor,
    required this.useEmulators,
    required this.emulatorHost,
    this.googleServerClientId,
  });

  /// Development: Firebase Emulator Suite with the offline `demo-chapter`
  /// project. No cloud resources are touched.
  factory AppConfig.dev() => AppConfig(
    flavor: Flavor.dev,
    useEmulators: const bool.fromEnvironment('USE_EMULATORS', defaultValue: true),
    emulatorHost: const String.fromEnvironment('EMULATOR_HOST').isNotEmpty
        ? const String.fromEnvironment('EMULATOR_HOST')
        // The Android emulator reaches the host machine via 10.0.2.2.
        : (defaultTargetPlatform == TargetPlatform.android ? '10.0.2.2' : 'localhost'),
    googleServerClientId: _optional(const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID')),
  );

  factory AppConfig.prod() => AppConfig(
    flavor: Flavor.prod,
    useEmulators: false,
    emulatorHost: '',
    googleServerClientId: _optional(const String.fromEnvironment('GOOGLE_SERVER_CLIENT_ID')),
  );

  final Flavor flavor;
  final bool useEmulators;
  final String emulatorHost;

  /// OAuth web client id used by Google Sign-In on Android to obtain an ID
  /// token for Firebase. Public identifier, not a secret.
  final String? googleServerClientId;

  /// Telemetry is only ever sent from production builds, and only with
  /// consent (docs/05 §1.5).
  bool get telemetryAllowed => flavor == Flavor.prod && !kDebugMode;

  static String? _optional(String value) => value.isEmpty ? null : value;
}
