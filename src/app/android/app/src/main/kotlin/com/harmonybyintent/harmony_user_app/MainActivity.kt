package com.harmonybyintent.harmony_user_app

import android.os.Build
import android.content.Context
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterFragmentActivity() {
    private val CHANNEL = "com.harmonybyintent.harmony_user_app/dormant_alarm"
    private val PREFS = "harmony_dormant_debug"
    @Volatile
    private var pendingLaunchEventId: String? = null
    @Volatile
    private var pendingLaunchAutoPlayVideo: Boolean = false

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
            applyAlarmLockscreenPresentation(enabled = true)
        }
    }

    private fun applyAlarmLockscreenPresentation(enabled: Boolean) {
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
        android.util.Log.d("MainActivity", "restoreAlarmLockscreenPresentation: begin")

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

        // Alarm launches are one-shot: aggressively close/background this task
        // so the device keyguard becomes the visible surface again.
        try {
            moveTaskToBack(true)
        } catch (_: Exception) {
        }

        try {
            val homeIntent = android.content.Intent(android.content.Intent.ACTION_MAIN).apply {
                addCategory(android.content.Intent.CATEGORY_HOME)
                flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
            }
            startActivity(homeIntent)
        } catch (_: Exception) {
        }

        try {
            finishAffinity()
        } catch (_: Exception) {
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            finishAndRemoveTask()
        } else {
            @Suppress("DEPRECATION")
            finish()
        }

        android.util.Log.d("MainActivity", "restoreAlarmLockscreenPresentation: complete")
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
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
                        val value = pendingLaunchEventId ?: intent?.getStringExtra("event_id")
                        pendingLaunchEventId = null
                        pendingLaunchAutoPlayVideo = false
                        result.success(value)
                    } catch (e: Exception) {
                        result.error("LAUNCH_EVENT_READ_ERROR", e.message, null)
                    }
                }
                "consume_launch_payload" -> {
                    try {
                        val eventId = pendingLaunchEventId ?: intent?.getStringExtra("event_id")
                        val autoPlayVideo = pendingLaunchAutoPlayVideo ||
                            (intent?.getBooleanExtra("auto_play_video", false) ?: false)
                        pendingLaunchEventId = null
                        pendingLaunchAutoPlayVideo = false
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
                else -> result.notImplemented()
            }
        }
    }
}

