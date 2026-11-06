import 'package:flutter/services.dart';

import '../domain/session_ports.dart';

/// [FocusMode] over the `chapter/focus` platform channel
/// (`FocusModeChannel.kt` on Android, `AppDelegate.swift` on iOS).
///
/// Android: Do Not Disturb through `NotificationManager.setInterruptionFilter`
/// (Android 15+ shows it as a Chapter rule automatically). iOS: no public
/// API exists, so [access] reports [FocusAccess.unsupported]; only the
/// screen-wake part works.
class ChannelFocusMode implements FocusMode {
  ChannelFocusMode([MethodChannel? channel])
    : _channel = channel ?? const MethodChannel('chapter/focus');

  final MethodChannel _channel;

  /// `INTERRUPTION_FILTER_PRIORITY` on Android.
  static const priorityFilter = 2;

  @override
  Future<FocusAccess> access() async {
    try {
      final r = await _channel.invokeMethod<String>('access');
      return switch (r) {
        'granted' => FocusAccess.granted,
        'denied' => FocusAccess.denied,
        _ => FocusAccess.unsupported,
      };
    } on MissingPluginException {
      return FocusAccess.unsupported;
    } on PlatformException {
      return FocusAccess.unsupported;
    }
  }

  @override
  Future<void> openAccessSettings() => _channel.invokeMethod<void>('openAccessSettings');

  @override
  Future<int?> enable() => _channel.invokeMethod<int>('enable', {'filter': priorityFilter});

  @override
  Future<void> restore(int previousFilter) async {
    try {
      await _channel.invokeMethod<void>('restore', {'filter': previousFilter});
    } on PlatformException {
      // Access revoked meanwhile: nothing we can change; the user's setting
      // stays whatever the system has.
    }
  }

  @override
  Future<void> scheduleRestore(int previousFilter, DateTime at) => _channel.invokeMethod<void>(
    'scheduleRestore',
    {'filter': previousFilter, 'atMillis': at.millisecondsSinceEpoch},
  );

  @override
  Future<void> keepScreenOn({required bool on}) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } on MissingPluginException {
      // Platforms without the channel (tests, desktop) ignore it.
    }
  }
}
