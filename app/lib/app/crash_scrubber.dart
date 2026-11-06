import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'app_config.dart';

/// An error reduced to its type. Error messages can quote reading content: a
/// SQLite failure lists its parameters, and a layout error can quote the text
/// on screen. The stack trace says where it happened, which is what's needed.
@immutable
class ScrubbedError implements Exception {
  const ScrubbedError._(this._type);

  factory ScrubbedError.of(Object error) => ScrubbedError._(error.runtimeType.toString());

  final String _type;

  @override
  String toString() => _type;
}

/// Whether Analytics or Crashlytics may collect (docs/05 §1.5).
bool telemetryEnabled(AppConfig config, {required bool? consent}) =>
    config.telemetryAllowed && (consent ?? false);

/// Sends an unhandled error, scrubbed. Collection is off unless the reader has
/// agreed, and off entirely outside production builds.
void reportFatal(Object error, StackTrace? stack) {
  unawaited(FirebaseCrashlytics.instance.recordError(ScrubbedError.of(error), stack, fatal: true));
}
