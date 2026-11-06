package com.chapterreads.chapter

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.SystemClock

/**
 * Gives Do Not Disturb back with no Flutter engine running, so a reading
 * session can't leave DND on if the app is dead when the timer ends.
 *
 * Chapter only ever undoes DND it turned on itself: `applied` is set when
 * enable() actually changed the filter and cleared on restore. If the reader
 * changed DND since (the current filter is no longer the one Chapter set),
 * their setting is left alone.
 */
object FocusRestore {
    private const val PREFS = "chapter_focus"
    private const val KEY_APPLIED = "applied"
    private const val KEY_AT = "restoreAtMillis"
    private const val KEY_FILTER = "restoreFilter"
    private const val REQUEST_CODE = 7003

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun notifications(context: Context) =
        context.getSystemService(NotificationManager::class.java)

    /** Turns DND on unless it is already on. Returns the filter that was active. */
    fun enable(context: Context, filter: Int): Int {
        val manager = notifications(context)
        var previous = manager.currentInterruptionFilter
        if (previous == NotificationManager.INTERRUPTION_FILTER_UNKNOWN) {
            previous = NotificationManager.INTERRUPTION_FILTER_ALL
        }
        // Already on (set by the reader, or by us before a pause): don't take it over.
        if (previous == NotificationManager.INTERRUPTION_FILTER_ALL) {
            manager.setInterruptionFilter(filter)
            prefs(context).edit().putBoolean(KEY_APPLIED, true).apply()
        }
        return previous
    }

    /** Restores [filter] if Chapter's DND is still in place. Safe to call repeatedly. */
    fun restore(context: Context, filter: Int) {
        val manager = notifications(context)
        val applied = prefs(context).getBoolean(KEY_APPLIED, false)
        if (applied &&
            manager.isNotificationPolicyAccessGranted &&
            manager.currentInterruptionFilter == NotificationManager.INTERRUPTION_FILTER_PRIORITY
        ) {
            manager.setInterruptionFilter(filter)
        }
        cancel(context)
        prefs(context).edit().putBoolean(KEY_APPLIED, false).apply()
    }

    /** Persists the restore (for reboots) and arms the alarm. */
    fun schedule(context: Context, atMillis: Long, filter: Int) {
        prefs(context).edit().putLong(KEY_AT, atMillis).putInt(KEY_FILTER, filter).apply()
        arm(context, atMillis)
    }

    fun cancel(context: Context) {
        context.getSystemService(AlarmManager::class.java).cancel(pendingIntent(context))
        prefs(context).edit().remove(KEY_AT).remove(KEY_FILTER).apply()
    }

    /** After a reboot alarms are gone: restore now if overdue, otherwise re-arm. */
    fun onBoot(context: Context) {
        val p = prefs(context)
        if (!p.contains(KEY_AT)) return
        val at = p.getLong(KEY_AT, 0)
        if (at <= System.currentTimeMillis()) {
            onAlarm(context)
        } else {
            arm(context, at)
        }
    }

    fun onAlarm(context: Context) {
        val p = prefs(context)
        if (!p.contains(KEY_FILTER)) return
        restore(context, p.getInt(KEY_FILTER, NotificationManager.INTERRUPTION_FILTER_ALL))
    }

    /**
     * setAndAllowWhileIdle needs no exact-alarm permission. It never fires early
     * but can be late while the device dozes.
     */
    private fun arm(context: Context, atMillis: Long) {
        val delay = (atMillis - System.currentTimeMillis()).coerceAtLeast(0)
        context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(
            AlarmManager.ELAPSED_REALTIME_WAKEUP,
            SystemClock.elapsedRealtime() + delay,
            pendingIntent(context),
        )
    }

    private fun pendingIntent(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        REQUEST_CODE,
        Intent(context, FocusRestoreReceiver::class.java),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}

class FocusRestoreReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED ->
                FocusRestore.onBoot(context)
            else -> FocusRestore.onAlarm(context)
        }
    }
}
