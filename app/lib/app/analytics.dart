import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// The only events Chapter sends, for the success metrics in docs/01 §7. They
/// carry no book, note or search content: this enum and a duration bucket are
/// all there is. Collection stays off without consent (telemetry.dart).
enum AppEvent {
  sessionCompleted('session_completed'),
  progressUpdated('progress_updated'),
  bookAdded('book_added'),
  scanAdded('scan_added');

  const AppEvent(this.wireName);

  final String wireName;
}

/// Sessions by rough length, never the exact time.
String durationBucket(Duration d) => switch (d.inMinutes) {
  < 15 => 'under_15',
  < 30 => '15_30',
  < 60 => '30_60',
  _ => 'over_60',
};

final analyticsProvider = Provider<void Function(AppEvent, {Duration? duration})>((ref) {
  final allowed = ref.watch(appConfigProvider).telemetryAllowed;
  return (event, {duration}) {
    if (!allowed) return;
    unawaited(
      FirebaseAnalytics.instance.logEvent(
        name: event.wireName,
        parameters: duration == null ? null : {'duration_bucket': durationBucket(duration)},
      ),
    );
  };
});
