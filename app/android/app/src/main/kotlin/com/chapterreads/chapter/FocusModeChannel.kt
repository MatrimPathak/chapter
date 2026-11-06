package com.chapterreads.chapter

import android.app.Activity
import android.app.NotificationManager
import android.content.Intent
import android.provider.Settings
import android.view.WindowManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `chapter/focus` channel (docs/04 §5): optional Do Not Disturb during a
 * reading session, and keeping the screen awake on the timer screen.
 *
 * DND uses NotificationManager.setInterruptionFilter, which needs
 * Notification Policy Access granted by the user in system settings. On
 * Android 15+ the system turns such calls into an implicit "Chapter" zen
 * rule that the user can see and switch off. The Dart side stores the
 * previous filter (returned by `enable`) with the session and passes it back
 * to `restore` on every exit path. [FocusRestore] also restores it natively
 * at the planned end, in case the app is dead by then.
 */
class FocusModeChannel(private val activity: Activity) : MethodChannel.MethodCallHandler {
    private val notifications: NotificationManager =
        activity.getSystemService(NotificationManager::class.java)

    private fun hasAccess(): Boolean = notifications.isNotificationPolicyAccessGranted

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "access" -> result.success(if (hasAccess()) "granted" else "denied")

            "openAccessSettings" -> {
                activity.startActivity(Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS))
                result.success(null)
            }

            "enable" -> {
                if (!hasAccess()) {
                    result.error("NO_ACCESS", "Notification policy access not granted", null)
                    return
                }
                val filter = call.argument<Int>("filter") ?: NotificationManager.INTERRUPTION_FILTER_PRIORITY
                result.success(FocusRestore.enable(activity, filter))
            }

            "restore" -> {
                val filter = call.argument<Int>("filter") ?: NotificationManager.INTERRUPTION_FILTER_ALL
                FocusRestore.restore(activity, filter)
                result.success(null)
            }

            "scheduleRestore" -> {
                val at = call.argument<Number>("atMillis")?.toLong()
                val filter = call.argument<Int>("filter")
                if (at == null || filter == null) {
                    result.error("BAD_ARGS", "atMillis and filter are required", null)
                    return
                }
                FocusRestore.schedule(activity, at, filter)
                result.success(null)
            }

            "keepScreenOn" -> {
                val on = call.argument<Boolean>("on") ?: false
                activity.runOnUiThread {
                    if (on) {
                        activity.window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        activity.window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }
}
