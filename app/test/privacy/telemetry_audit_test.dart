import 'dart:io';

import 'package:chapter/app/analytics.dart';
import 'package:chapter/app/app_config.dart';
import 'package:chapter/app/crash_scrubber.dart';
import 'package:flutter_test/flutter_test.dart';

/// The promise on the consent screen: no reading content leaves in telemetry
/// (docs/05 §1.5).
void main() {
  test('crash reports keep the error type and lose its message', () {
    const secret = 'my private note about The Deal';
    final errors = <Object>[
      StateError('INSERT failed with parameters: [$secret]'),
      const FormatException('Bad data', secret),
      Exception(secret),
      '$secret as a thrown string',
    ];
    for (final e in errors) {
      final scrubbed = ScrubbedError.of(e);
      expect(scrubbed.toString(), isNot(contains('private note')));
      expect(scrubbed.toString(), isNot(contains('The Deal')));
      expect(scrubbed.toString(), e.runtimeType.toString());
    }
  });

  test('telemetry needs a production build and consent', () {
    expect(telemetryEnabled(AppConfig.dev(), consent: true), isFalse);
    expect(telemetryEnabled(AppConfig.dev(), consent: false), isFalse);
    expect(telemetryEnabled(AppConfig.prod(), consent: false), isFalse);
    expect(telemetryEnabled(AppConfig.prod(), consent: null), isFalse);
  });

  List<File> dartFiles(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .where((f) => !f.path.contains('generated') && !f.path.endsWith('.g.dart'))
      .toList();

  test('no code sends events or attaches user data to telemetry', () {
    // Only analytics.dart, whose events are a closed enum with a bucket.
    final calls = RegExp(
      r'logEvent|logScreenView|setUserId|setUserProperty|setCustomKey|setCurrentScreen|'
      r'FirebaseAnalyticsObserver|Crashlytics\.instance\.log\(',
    );
    final offenders = [
      for (final f in dartFiles('lib'))
        if (calls.hasMatch(f.readAsStringSync()) && !f.path.endsWith('analytics.dart')) f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('events carry nothing but their name and a coarse bucket', () {
    final source = File('lib/app/analytics.dart').readAsStringSync();
    expect('logEvent'.allMatches(source), hasLength(1));
    expect('duration_bucket'.allMatches(source), hasLength(1));
    expect(AppEvent.values.map((e) => e.wireName).toSet(), {
      'session_completed',
      'progress_updated',
      'book_added',
      'scan_added',
    });
    expect(durationBucket(const Duration(minutes: 5)), 'under_15');
    expect(durationBucket(const Duration(minutes: 45)), '30_60');
    expect(durationBucket(const Duration(hours: 3)), 'over_60');
  });

  test('errors reach Crashlytics only through the scrubber', () {
    final direct = RegExp(r'Crashlytics\.instance\s*\.\s*record');
    final offenders = [
      for (final f in dartFiles('lib'))
        if (direct.hasMatch(f.readAsStringSync()) && !f.path.endsWith('crash_scrubber.dart'))
          f.path,
    ];
    expect(offenders, isEmpty);
  });

  test('the Android manifest starts with collection off and backup off', () {
    final manifest = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(manifest, contains('android:allowBackup="false"'));
    for (final key in [
      'firebase_analytics_collection_enabled',
      'firebase_crashlytics_collection_enabled',
      'google_analytics_adid_collection_enabled',
    ]) {
      expect(
        manifest,
        matches(RegExp('android:name="$key"\\s+android:value="false"')),
        reason: key,
      );
    }
  });

  test('the emulator test account can\'t exist in a production build', () {
    final prod = AppConfig.prod();
    expect(prod.useEmulators, isFalse);
    expect(File('android/app/src/main/res/xml/network_security_config.xml').existsSync(), isFalse);
  });
}
