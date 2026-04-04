package com.harmonybyintent.harmony_user_app

import android.app.AlarmManager
import android.app.ActivityManager
import android.app.KeyguardManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.media.RingtoneManager
import android.os.Build
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

class DormantAlarmReceiver : BroadcastReceiver() {
    companion object {
        private const val NOTIFICATION_CHANNEL_ID = "dormant_playback_channel"
        private const val ACTION_DORMANT_ALARM = "com.harmonybyintent.harmony_user_app.DORMANT_ALARM"
        private const val PREFS = "harmony_dormant_debug"
        private const val DEDUPE_WINDOW_MS = 90_000L
        private const val ALARM_REGISTRY_KEY = "registered_alarm_entries"
        private const val STALE_ALARM_WINDOW_MS = 2 * 60 * 60 * 1000L

        private fun loadRegistry(context: Context): MutableMap<Int, Long> {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val entries = prefs.getStringSet(ALARM_REGISTRY_KEY, emptySet()) ?: emptySet()
            val map = mutableMapOf<Int, Long>()
            for (entry in entries) {
                val parts = entry.split(':')
                if (parts.size != 2) continue
                val id = parts[0].toIntOrNull() ?: continue
                val trigger = parts[1].toLongOrNull() ?: continue
                map[id] = trigger
            }
            return map
        }

        private fun saveRegistry(context: Context, registry: Map<Int, Long>) {
            val encoded = registry.entries.map { "${it.key}:${it.value}" }.toSet()
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putStringSet(ALARM_REGISTRY_KEY, encoded)
                .apply()
        }

        private fun registerAlarm(context: Context, alarmId: Int, triggerTimeMillis: Long) {
            val registry = loadRegistry(context)
            registry[alarmId] = triggerTimeMillis
            saveRegistry(context, registry)
        }

        private fun unregisterAlarm(context: Context, alarmId: Int) {
            val registry = loadRegistry(context)
            if (registry.remove(alarmId) != null) {
                saveRegistry(context, registry)
            }
        }

        fun purgeStaleRegisteredAlarms(context: Context): Int {
            val now = System.currentTimeMillis()
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val registry = loadRegistry(context)
            if (registry.isEmpty()) return 0

            var cancelled = 0
            val updated = registry.toMutableMap()
            for ((alarmId, triggerAt) in registry) {
                if (triggerAt < now - STALE_ALARM_WINDOW_MS) {
                    val intent = Intent(context, DormantAlarmReceiver::class.java).apply {
                        action = ACTION_DORMANT_ALARM
                    }
                    val pendingIntent = PendingIntent.getBroadcast(
                        context,
                        alarmId,
                        intent,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                    alarmManager.cancel(pendingIntent)
                    updated.remove(alarmId)
                    cancelled++
                }
            }

            if (cancelled > 0) {
                saveRegistry(context, updated)
            }
            return cancelled
        }

        fun cancelAllRegisteredAlarms(context: Context): Int {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val registry = loadRegistry(context)
            if (registry.isEmpty()) return 0

            for (alarmId in registry.keys) {
                val intent = Intent(context, DormantAlarmReceiver::class.java).apply {
                    action = ACTION_DORMANT_ALARM
                }
                val pendingIntent = PendingIntent.getBroadcast(
                    context,
                    alarmId,
                    intent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
                alarmManager.cancel(pendingIntent)
            }

            saveRegistry(context, emptyMap())
            return registry.size
        }

        fun scheduleExactAlarm(
            context: Context,
            alarmId: Int,
            triggerTimeMillis: Long,
            eventId: String,
            slotKey: String,
            eventTitle: String,
            eventBody: String,
            isFullScreen: Boolean
        ): Boolean {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

            val intent = Intent(context, DormantAlarmReceiver::class.java).apply {
                action = ACTION_DORMANT_ALARM
                putExtra("alarm_id", alarmId)
                putExtra("event_id", eventId)
                putExtra("slot_key", slotKey)
                putExtra("event_title", eventTitle)
                putExtra("event_body", eventBody)
                putExtra("is_full_screen", isFullScreen)
            }

            val pendingIntent = PendingIntent.getBroadcast(
                context,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val showIntent = PendingIntent.getActivity(
                context,
                alarmId,
                context.packageManager.getLaunchIntentForPackage(context.packageName)
                    ?: Intent(context, MainActivity::class.java),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    // AlarmClock is exempt from most idle batching and is generally more reliable on OEM-tuned devices.
                    alarmManager.setAlarmClock(
                        AlarmManager.AlarmClockInfo(triggerTimeMillis, showIntent),
                        pendingIntent
                    )
                    registerAlarm(context, alarmId, triggerTimeMillis)
                    android.util.Log.d("DormantAlarmReceiver", "Scheduled alarm clock for $eventId at $triggerTimeMillis")
                    return true
                } else {
                    // Pre-Android 12
                    alarmManager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        triggerTimeMillis,
                        pendingIntent
                    )
                    registerAlarm(context, alarmId, triggerTimeMillis)
                    android.util.Log.d("DormantAlarmReceiver", "Scheduled exact alarm for $eventId at $triggerTimeMillis")
                    return true
                }
            } catch (e: SecurityException) {
                android.util.Log.e("DormantAlarmReceiver", "SecurityException scheduling alarm: ${e.message}")
                return false
            } catch (e: Exception) {
                android.util.Log.e("DormantAlarmReceiver", "Exception scheduling alarm: ${e.message}")
                return false
            }
        }

        fun cancelAlarm(context: Context, alarmId: Int) {
            val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
            val intent = Intent(context, DormantAlarmReceiver::class.java).apply {
                action = ACTION_DORMANT_ALARM
            }
            val pendingIntent = PendingIntent.getBroadcast(
                context,
                alarmId,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            try {
                alarmManager.cancel(pendingIntent)
                unregisterAlarm(context, alarmId)
                android.util.Log.d("DormantAlarmReceiver", "Cancelled alarm $alarmId")
            } catch (e: Exception) {
                android.util.Log.e("DormantAlarmReceiver", "Error cancelling alarm: ${e.message}")
            }
        }
    }

    override fun onReceive(context: Context?, intent: Intent?) {
        if (context == null || intent == null) return
        if (intent.action != ACTION_DORMANT_ALARM) return

        val wakeLock = try {
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "harmony:DormantAlarmWakeLock"
            ).apply {
                setReferenceCounted(false)
                acquire(15_000L)
            }
        } catch (_: Exception) {
            null
        }

        val eventId = intent.getStringExtra("event_id") ?: "Unknown"
        val alarmId = intent.getIntExtra("alarm_id", Int.MIN_VALUE)
        if (alarmId != Int.MIN_VALUE) {
            unregisterAlarm(context, alarmId)
        }
        val slotKey = intent.getStringExtra("slot_key") ?: eventId
        val eventTitle = intent.getStringExtra("event_title") ?: "Harmony by Intent"
        val eventBody = intent.getStringExtra("event_body") ?: "Event starting now"
        val isFullScreen = intent.getBooleanExtra("is_full_screen", false)
        val now = System.currentTimeMillis()
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

        val lastHandledEvent = prefs.getString("last_handled_event", null)
        val lastHandledSlot = prefs.getString("last_handled_slot", null)
        val lastHandledMs = prefs.getLong("last_handled_ms", 0L)
        if ((lastHandledSlot == slotKey || lastHandledEvent == eventId) &&
            (now - lastHandledMs) in 0 until DEDUPE_WINDOW_MS
        ) {
            android.util.Log.d(
                "DormantAlarmReceiver",
                "Duplicate alarm suppressed for event=$eventId slot=$slotKey within ${DEDUPE_WINDOW_MS}ms window"
            )
            try {
                wakeLock?.release()
            } catch (_: Exception) {
            }
            return
        }

        android.util.Log.d("DormantAlarmReceiver", "Alarm received for event: $eventId")

        prefs
            .edit()
            .putLong("last_receive_ms", now)
            .putString("last_receive_event", eventId)
            .putString("last_receive_slot", slotKey)
            .putLong("last_handled_ms", now)
            .putString("last_handled_event", eventId)
            .putString("last_handled_slot", slotKey)
            .apply()

        val appInForeground = isAppInForeground(context)
        val deviceLocked = isDeviceLocked(context)

        if (appInForeground) {
            // App is open: launch for auto-play, but skip notification (user doesn't need tap prompt).
            launchAppForEvent(context, eventId, isFullScreen)
            android.util.Log.d("DormantAlarmReceiver", "App in foreground: skipping notification, launching auto-play for $eventId")
        } else if (deviceLocked) {
            // Device is locked: post notification so full-screen intent can legitimately wake/launch playback.
            postNotification(context, eventId, eventTitle, eventBody, isFullScreen)
            android.util.Log.d("DormantAlarmReceiver", "Device locked: posting notification for lockscreen auto-play for $eventId")
        } else {
            // Device unlocked in another app: post notification so user can choose to tap in.
            postNotification(context, eventId, eventTitle, eventBody, isFullScreen)
            android.util.Log.d("DormantAlarmReceiver", "App backgrounded and unlocked: posting notification for $eventId")
        }

        try {
            wakeLock?.release()
        } catch (_: Exception) {
        }
    }

    private fun postNotification(
        context: Context,
        eventId: String,
        eventTitle: String,
        eventBody: String,
        isFullScreen: Boolean
    ) {
        try {
            ensureDormantChannel(context)

            val notificationId = eventId.hashCode()
            
            // Create intent to launch the app
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            launchIntent.putExtra("event_id", eventId)
            launchIntent.putExtra("auto_play_video", isFullScreen)

            val contentPendingIntent = PendingIntent.getActivity(
                context,
                eventId.hashCode(),
                launchIntent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

            val soundUri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM)

            val notificationBuilder = NotificationCompat.Builder(context, NOTIFICATION_CHANNEL_ID)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setContentTitle(eventTitle)
                .setContentText(eventBody)
                .setAutoCancel(true)
                .setContentIntent(contentPendingIntent)
                .setSound(soundUri)
                .setVibrate(longArrayOf(0, 500, 250, 500))
                .setPriority(NotificationCompat.PRIORITY_MAX)
                .setCategory(NotificationCompat.CATEGORY_ALARM)
                .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)

            if (isFullScreen) {
                notificationBuilder.setFullScreenIntent(contentPendingIntent, true)
            }

            val notification = notificationBuilder.build()
            
            NotificationManagerCompat.from(context).apply {
                notify(notificationId, notification)
                android.util.Log.d("DormantAlarmReceiver", "Notification posted for $eventId")
            }

            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean("last_post_ok", true)
                .apply()
        } catch (e: Exception) {
            android.util.Log.e("DormantAlarmReceiver", "Error posting notification: ${e.message}")
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putBoolean("last_post_ok", false)
                .apply()
        }
    }

    private fun ensureDormantChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val existing = manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID)
        if (existing != null) return

        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Dormant Playback Reminders",
            NotificationManager.IMPORTANCE_HIGH
        ).apply {
            description = "Timed reminders for Harmony events while your device is idle."
            lockscreenVisibility = NotificationCompat.VISIBILITY_PUBLIC
            setBypassDnd(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                null
            )
            enableVibration(true)
            vibrationPattern = longArrayOf(0, 500, 250, 500)
        }

        manager.createNotificationChannel(channel)
    }

    private fun launchAppForEvent(context: Context, eventId: String, autoPlayVideo: Boolean) {
        try {
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?: Intent(context, MainActivity::class.java)
            launchIntent.flags = Intent.FLAG_ACTIVITY_NEW_TASK or
                Intent.FLAG_ACTIVITY_SINGLE_TOP or
                Intent.FLAG_ACTIVITY_CLEAR_TOP
            launchIntent.putExtra("event_id", eventId)
            launchIntent.putExtra("auto_play_video", autoPlayVideo)
            context.startActivity(launchIntent)
            android.util.Log.d("DormantAlarmReceiver", "Launch intent fired for $eventId")
        } catch (e: Exception) {
            android.util.Log.e("DormantAlarmReceiver", "Error launching app for alarm: ${e.message}")
        }
    }

    private fun isAppInForeground(context: Context): Boolean {
        return try {
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val running = activityManager.runningAppProcesses ?: return false
            running.any {
                it.processName == context.packageName &&
                    it.importance <= ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
            }
        } catch (_: Exception) {
            false
        }
    }

    private fun isDeviceLocked(context: Context): Boolean {
        return try {
            val keyguardManager = context.getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                keyguardManager.isDeviceLocked
            } else {
                keyguardManager.isKeyguardLocked
            }
        } catch (_: Exception) {
            false
        }
    }
}
