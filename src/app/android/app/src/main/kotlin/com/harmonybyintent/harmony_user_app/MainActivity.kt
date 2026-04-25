package com.harmonybyintent.harmony_user_app

import android.os.Build
import android.os.Bundle
import android.content.Context
import android.app.KeyguardManager
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.harmonybyintent.harmony_user_app/dormant_alarm"
    private val PREFS = "harmony_dormant_debug"
    private val PENDING_LAUNCH_EVENT_ID_KEY = "pending_launch_event_id"
    private val PENDING_LAUNCH_AUTO_PLAY_VIDEO_KEY = "pending_launch_auto_play_video"
    @Volatile
    private var pendingLaunchEventId: String? = null
    @Volatile
    private var pendingLaunchAutoPlayVideo: Boolean = false
    @Volatile
    private var methodChannel: MethodChannel? = null
    @Volatile
    private var notificationTapReceived: Boolean = false
    @Volatile
    private var lastAlarmLaunchedEventId: String? = null
    @Volatile
    private var lastAlarmNotificationId: Int? = null
    @Volatile
    private var lockscreenPresentationApplied: Boolean = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        try {
            window.setWindowAnimations(0)
            overridePendingTransition(0, 0)
        } catch (_: Exception) {
        }
    }

    override fun onStart() {
        super.onStart()
        captureLaunchEventId(intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        captureLaunchEventId(intent)
    }

    private fun captureLaunchEventId(intent: android.content.Intent?) {
        val eventId = intent?.getStringExtra("event_id")
        if (!eventId.isNullOrBlank()) {
            pendingLaunchEventId = eventId
            pendingLaunchAutoPlayVideo = intent.getBooleanExtra("auto_play_video", false)
            // Store the event ID as the authoritative last-alarm-launched ID for native queries
            lastAlarmLaunchedEventId = eventId
            lastAlarmNotificationId = eventId.hashCode()
            getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                .edit()
                .putString(PENDING_LAUNCH_EVENT_ID_KEY, eventId)
                .putBoolean(PENDING_LAUNCH_AUTO_PLAY_VIDEO_KEY, pendingLaunchAutoPlayVideo)
                .apply()
            android.util.Log.d(
                "MainActivity",
                "captureLaunchEventId: stored eventId=$eventId autoPlay=$pendingLaunchAutoPlayVideo (authoritative alarm source)"
            )
            cancelAlarmNotificationForEvent(eventId)
            intent.removeExtra("event_id")
            intent.removeExtra("auto_play_video")
            applyAlarmLockscreenPresentation(enabled = pendingLaunchAutoPlayVideo)
            notificationTapReceived = true
            invokeNotificationTapConsumption()
        }
    }

    private fun invokeNotificationTapConsumption() {
        val channel = methodChannel
        if (channel != null) {
            // Channel is ready, invoke immediately
            try {
                channel.invokeMethod("on_notification_tap_received", null)
            } catch (e: Exception) {
                android.util.Log.d("MainActivity", "onNotificationTapReceived error: ${e.message}")
            }
        } else {
            // Channel not ready yet, set flag to retry after Flutter is configured
            notificationTapReceived = true
        }
    }

    private fun retryPendingNotificationTap() {
        if (notificationTapReceived && methodChannel != null) {
            invokeNotificationTapConsumption()
        }
    }

    private fun peekStoredLaunchEventId(): String? {
        return getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(PENDING_LAUNCH_EVENT_ID_KEY, null)
    }

    private fun peekStoredLaunchAutoPlayVideo(): Boolean {
        return getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(PENDING_LAUNCH_AUTO_PLAY_VIDEO_KEY, false)
    }

    private fun clearStoredLaunchPayload() {
        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .remove(PENDING_LAUNCH_EVENT_ID_KEY)
            .remove(PENDING_LAUNCH_AUTO_PLAY_VIDEO_KEY)
            .apply()
    }

    private fun applyAlarmLockscreenPresentation(enabled: Boolean) {
        lockscreenPresentationApplied = enabled
        if (!enabled) return

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }

    }

    private fun restoreAlarmLockscreenPresentation() {
        android.util.Log.d(
            "MainActivity",
            "restoreAlarmLockscreenPresentation: begin applied=$lockscreenPresentationApplied"
        )

        // Cancel the alarm notification so it doesn't linger in the shade
        val notifId = lastAlarmNotificationId
        if (notifId != null) {
            try {
                androidx.core.app.NotificationManagerCompat.from(this).cancel(notifId)
            } catch (_: Exception) {}
            lastAlarmNotificationId = null
        }

        if (lockscreenPresentationApplied) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
                setShowWhenLocked(false)
                setTurnScreenOn(false)
            }

            @Suppress("DEPRECATION")
            window.clearFlags(
                android.view.WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    android.view.WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )

            // Move app to background so the lockscreen is restored without destroying the task.
            // Keeping the task alive means the next notification tap resumes instantly via
            // onNewIntent() rather than restarting Flutter from scratch (which causes the
            // loading splash to re-appear).
            try {
                moveTaskToBack(true)
            } catch (_: Exception) {
            }
        }

        lockscreenPresentationApplied = false

        android.util.Log.d("MainActivity", "restoreAlarmLockscreenPresentation: complete")
    }

    private fun cancelAlarmNotificationForEvent(eventId: String?) {
        val eventBasedId = eventId?.takeIf { it.isNotBlank() }?.hashCode()
        val fallbackId = lastAlarmNotificationId

        try {
            val manager = androidx.core.app.NotificationManagerCompat.from(this)
            if (eventBasedId != null) {
                manager.cancel(eventBasedId)
            }
            if (fallbackId != null && fallbackId != eventBasedId) {
                manager.cancel(fallbackId)
            }
        } catch (_: Exception) {
        }

        if (eventBasedId == null || eventBasedId == fallbackId) {
            lastAlarmNotificationId = null
        }
    }

    private fun isDeviceLockedNow(): Boolean {
        return try {
            val keyguardManager = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                keyguardManager.isDeviceLocked
            } else {
                keyguardManager.isKeyguardLocked
            }
        } catch (_: Exception) {
            false
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "schedule_exact_alarm" -> {
                    val alarmId = call.argument<Int>("alarm_id") ?: return@setMethodCallHandler result.error("INVALID_ARGUMENT", "Missing alarm_id", null)
                    val triggerTime = call.argument<Long>("trigger_time_ms") ?: return@setMethodCallHandler result.error("INVALID_ARGUMENT", "Missing trigger_time_ms", null)
                    val eventId = call.argument<String>("event_id") ?: return@setMethodCallHandler result.error("INVALID_ARGUMENT", "Missing event_id", null)
                    val slotKey = call.argument<String>("slot_key") ?: eventId
                    val eventTitle = call.argument<String>("event_title") ?: "Harmony by Intent"
                    val eventBody = call.argument<String>("event_body") ?: "Event starting now"
                    val isFullScreen = call.argument<Boolean>("is_full_screen") ?: false

                    try {
                        val scheduled = DormantAlarmReceiver.scheduleExactAlarm(
                            this,
                            alarmId,
                            triggerTime,
                            eventId,
                            slotKey,
                            eventTitle,
                            eventBody,
                            isFullScreen
                        )
                        result.success(scheduled)
                    } catch (e: Exception) {
                        result.error("SCHEDULE_ERROR", e.message, null)
                    }
                }
                "cancel_alarm" -> {
                    val alarmId = call.argument<Int>("alarm_id") ?: return@setMethodCallHandler result.error("INVALID_ARGUMENT", "Missing alarm_id", null)

                    try {
                        DormantAlarmReceiver.cancelAlarm(this, alarmId)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_ERROR", e.message, null)
                    }
                }
                "cancel_all_registered_alarms" -> {
                    try {
                        val cancelled = DormantAlarmReceiver.cancelAllRegisteredAlarms(this)
                        result.success(cancelled)
                    } catch (e: Exception) {
                        result.error("CANCEL_ALL_ERROR", e.message, null)
                    }
                }
                "purge_stale_registered_alarms" -> {
                    try {
                        val purged = DormantAlarmReceiver.purgeStaleRegisteredAlarms(this)
                        result.success(purged)
                    } catch (e: Exception) {
                        result.error("PURGE_STALE_ERROR", e.message, null)
                    }
                }
                "schedule_debug_alarm" -> {
                    val delaySeconds = call.argument<Int>("delay_seconds") ?: 15
                    val alarmId = 0x6A17BEEF.toInt()
                    val triggerAt = System.currentTimeMillis() + (delaySeconds.coerceAtLeast(5) * 1000L)

                    try {
                        val scheduled = DormantAlarmReceiver.scheduleExactAlarm(
                            this,
                            alarmId,
                            triggerAt,
                            "debug_probe",
                            "debug_probe",
                            "Harmony Debug Probe",
                            "If you see this while locked, native alarms are firing.",
                            false
                        )

                        getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                            .edit()
                            .putLong("last_schedule_ms", triggerAt)
                            .putString("last_schedule_event", "debug_probe")
                            .putBoolean("last_schedule_ok", scheduled)
                            .apply()

                        result.success(scheduled)
                    } catch (e: Exception) {
                        result.error("DEBUG_SCHEDULE_ERROR", e.message, null)
                    }
                }
                "get_last_alarm_debug" -> {
                    try {
                        val prefs = getSharedPreferences(PREFS, Context.MODE_PRIVATE)
                        val payload = mapOf(
                            "last_schedule_ms" to prefs.getLong("last_schedule_ms", 0L),
                            "last_schedule_event" to (prefs.getString("last_schedule_event", "") ?: ""),
                            "last_schedule_ok" to prefs.getBoolean("last_schedule_ok", false),
                            "last_receive_ms" to prefs.getLong("last_receive_ms", 0L),
                            "last_receive_event" to (prefs.getString("last_receive_event", "") ?: ""),
                            "last_post_ok" to prefs.getBoolean("last_post_ok", false),
                        )
                        result.success(payload)
                    } catch (e: Exception) {
                        result.error("DEBUG_READ_ERROR", e.message, null)
                    }
                }
                "consume_launch_event_id" -> {
                    try {
                        val value = pendingLaunchEventId
                            ?: intent?.getStringExtra("event_id")
                            ?: peekStoredLaunchEventId()
                        pendingLaunchEventId = null
                        pendingLaunchAutoPlayVideo = false
                        clearStoredLaunchPayload()
                        // Clear Intent extras so repeated calls don't re-read stale data
                        intent?.removeExtra("event_id")
                        intent?.removeExtra("auto_play_video")
                        android.util.Log.d("MainActivity", "consume_launch_event_id: value=$value")
                        result.success(value)
                    } catch (e: Exception) {
                        result.error("LAUNCH_EVENT_READ_ERROR", e.message, null)
                    }
                }
                "consume_launch_payload" -> {
                    try {
                        val eventId = pendingLaunchEventId
                            ?: intent?.getStringExtra("event_id")
                            ?: peekStoredLaunchEventId()
                        val autoPlayVideo = pendingLaunchAutoPlayVideo ||
                            (intent?.getBooleanExtra("auto_play_video", false) ?: false) ||
                            peekStoredLaunchAutoPlayVideo()
                        pendingLaunchEventId = null
                        pendingLaunchAutoPlayVideo = false
                        clearStoredLaunchPayload()
                        // Clear Intent extras so repeated calls don't re-read stale data
                        intent?.removeExtra("event_id")
                        intent?.removeExtra("auto_play_video")
                        android.util.Log.d(
                            "MainActivity",
                            "consume_launch_payload: eventId=${eventId ?: ""} autoPlay=$autoPlayVideo"
                        )
                        val payload = mapOf(
                            "event_id" to (eventId ?: ""),
                            "auto_play_video" to autoPlayVideo,
                        )
                        result.success(payload)
                    } catch (e: Exception) {
                        result.error("LAUNCH_PAYLOAD_READ_ERROR", e.message, null)
                    }
                }
                "restore_lockscreen_presentation" -> {
                    try {
                        restoreAlarmLockscreenPresentation()
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("RESTORE_LOCKSCREEN_ERROR", e.message, null)
                    }
                }
                "cancel_notification_for_event" -> {
                    try {
                        val eventId = call.argument<String>("event_id")
                        cancelAlarmNotificationForEvent(eventId)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("CANCEL_NOTIFICATION_ERROR", e.message, null)
                    }
                }
                "get_last_alarm_launched_event_id" -> {
                    try {
                        val eventId = lastAlarmLaunchedEventId ?: ""
                        android.util.Log.d("MainActivity", "get_last_alarm_launched_event_id: returning $eventId")
                        result.success(eventId)
                    } catch (e: Exception) {
                        result.error("GET_LAST_ALARM_ERROR", e.message, null)
                    }
                }
                "is_device_locked" -> {
                    try {
                        result.success(isDeviceLockedNow())
                    } catch (e: Exception) {
                        result.error("IS_DEVICE_LOCKED_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }
        
        // If a notification tap was received before Flutter was ready, retry now
        retryPendingNotificationTap()
    }
}

