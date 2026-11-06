import 'dart:io' show Platform;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../../core/utils/clock.dart';
import '../domain/session_ports.dart';

/// [SessionNotifications] with `flutter_local_notifications`.
///
/// The end notification is scheduled for an absolute UTC instant, so it
/// fires even if the app is killed and needs no device time-zone lookup.
/// Exact alarms are used only when the system already allows them (Google
/// Play restricts the exact-alarm permission to alarm apps); otherwise the
/// notification may be slightly late, but the *recorded* time never is,
/// because it comes from timestamps (PROJECT_STATUS TD-29).
class LocalSessionNotifications implements SessionNotifications {
  LocalSessionNotifications({
    required this.endTitle,
    required this.endBody,
    required this.runningBody,
    required this.pausedBody,
    required this.channelName,
    required Clock clock,
    FlutterLocalNotificationsPlugin? plugin,
  }) : _clock = clock,
       _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  final Clock _clock;

  /// Localized strings, resolved by the caller.
  final String endTitle;
  final String endBody;
  final String runningBody;
  final String pausedBody;
  final String channelName;

  static const _ongoingId = 7001;
  static const _endId = 7002;
  static const _ongoingChannel = 'session_ongoing';
  static const _endChannel = 'session_end';

  bool _initialized = false;

  Future<void> _init() async {
    if (_initialized) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
      ),
    );
    _initialized = true;
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  @override
  Future<bool> ensurePermission() async {
    await _init();
    if (Platform.isAndroid) return await _android?.requestNotificationsPermission() ?? false;
    if (Platform.isIOS) {
      return await _plugin
              .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
              ?.requestPermissions(alert: true, sound: true) ??
          false;
    }
    return false;
  }

  @override
  Future<void> showRunning({required String title, required DateTime endsAt}) async {
    await _init();
    await _plugin.show(
      id: _ongoingId,
      title: title,
      body: runningBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _ongoingChannel,
          channelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          when: endsAt.millisecondsSinceEpoch,
          // Clears itself at the planned end even if the process has died.
          timeoutAfter: endsAt.difference(_clock.now()).inMilliseconds.clamp(1, 1 << 31),
          usesChronometer: true,
          chronometerCountDown: true,
          category: AndroidNotificationCategory.progress,
        ),
      ),
    );
    await _plugin.cancel(id: _endId);
    final exact = Platform.isAndroid && (await _android?.canScheduleExactNotifications() ?? false);
    await _plugin.zonedSchedule(
      id: _endId,
      title: endTitle,
      body: endBody,
      scheduledDate: tz.TZDateTime.from(endsAt.toUtc(), tz.UTC),
      androidScheduleMode: exact
          ? AndroidScheduleMode.exactAllowWhileIdle
          : AndroidScheduleMode.inexactAllowWhileIdle,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _endChannel,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
    );
  }

  @override
  Future<void> showPaused({required String title}) async {
    await _init();
    await _plugin.cancel(id: _endId);
    await _plugin.show(
      id: _ongoingId,
      title: title,
      body: pausedBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _ongoingChannel,
          channelName,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          showWhen: false,
        ),
      ),
    );
  }

  @override
  Future<void> showCompleted({required String title}) async {
    await _init();
    await _plugin.cancel(id: _ongoingId);
    await _plugin.show(
      id: _endId,
      title: endTitle,
      body: endBody,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _endChannel,
          channelName,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.alarm,
        ),
        iOS: const DarwinNotificationDetails(presentSound: true),
      ),
    );
  }

  @override
  Future<void> cancelAll() async {
    await _init();
    await _plugin.cancel(id: _ongoingId);
    await _plugin.cancel(id: _endId);
  }
}
