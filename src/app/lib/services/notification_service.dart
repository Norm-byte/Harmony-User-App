import 'dart:convert';
import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/event.dart';
import 'user_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
}

@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse response) {
  final service = NotificationService();
  service.queueIosLaunchPayloadFromDormantTap(
    response.payload,
    tappedNotificationId: response.id,
  );
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  static const String _highImportanceChannelId = 'high_importance_channel';
  static const String _dormantPlaybackChannelId = 'dormant_playback_channel';
  static const String _methodChannelName = 'com.harmonybyintent.harmony_user_app/dormant_alarm';
  static const String _iosPendingLaunchPayloadKey =
      'harmony_ios_pending_launch_payload';
  static Map<String, dynamic>? _pendingIosLaunchPayload;
  final MethodChannel _dormantAlarmChannel = const MethodChannel(
    _methodChannelName,
  );

  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    tz_data.initializeTimeZones();

    // Set the background messaging handler early on, as a named top-level function
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 1. Request Permissions
    NotificationSettings settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('User granted permission');
    } else {
      debugPrint('User declined or has not accepted permission');
      // Continue initializing local notifications so dormant scheduling can
      // still work after permissions are granted from system settings.
    }

    // 2. Initialize Local Notifications
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
          requestSoundPermission: false,
          requestBadgePermission: false,
          requestAlertPermission: false,
        );

    final InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await _localNotifications.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) async {
        // Handle notification tap
        debugPrint('Notification tapped: ${response.payload}');
        await queueIosLaunchPayloadFromDormantTap(
          response.payload,
          tappedNotificationId: response.id,
        );
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );

    // Create the channel on the device (Android 8.0+)
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _highImportanceChannelId,
              'High Importance Notifications',
              description: 'This channel is used for important notifications.',
              importance: Importance.max,
            ),
          );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(
            const AndroidNotificationChannel(
              _dormantPlaybackChannelId,
              'Dormant Playback Reminders',
              description:
                  'Timed reminders for Harmony events while your device is idle.',
              importance: Importance.max,
            ),
          );
    }

    // 3. Handle Foreground Messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('Got a message whilst in the foreground!');
      debugPrint('Message data: ${message.data}');

      if (message.notification != null) {
        debugPrint(
          'Message also contained a notification: ${message.notification}',
        );
        // Do not duplicate a heads-up banner while the app is already open.
        // Keep foreground delivery silent and let in-app UI state drive visibility.
      }
    });

    // 4. Subscribe to Topics
    await _subscribeToTopics();


    // 5. Get Token (for debugging). On iOS this can fail early before APNS token is ready.
    try {
      final token = await _firebaseMessaging.getToken();
      debugPrint('FCM_TOKEN: $token');
    } catch (e) {
      final message = e.toString();
      if (Platform.isIOS && message.contains('apns-token-not-set')) {
        debugPrint('FCM_TOKEN_DEFERRED_IOS: APNS token not ready yet; continuing startup.');
      } else {
        debugPrint('FCM_TOKEN_ERROR: $e');
      }
    }

    _isInitialized = true;
  }

  Future<void> _subscribeToTopics() async {
    try {
      // Subscribe everyone to 'all_users'
      await _firebaseMessaging.subscribeToTopic('all_users');
      debugPrint('FCM_SUBSCRIPTION: Subscribed to topic "all_users"');
    } catch (e) {
      debugPrint('FCM_SUBSCRIPTION_ERROR: Could not subscribe to topic: $e');
    }

    // TODO: Subscribe to specific time zone topic if needed
    // String timeZone = ... get from UserService
    // await _firebaseMessaging.subscribeToTopic('zone_$timeZone');
  }

  Future<void> _showLocalNotification(RemoteMessage message) async {
    RemoteNotification? notification = message.notification;

    // We check if notification is not null. We don't strictly need 'android' metadata
    // to show a basic notification, though it's good practice to have it.
    if (notification != null) {
      debugPrint('Showing local notification: ${notification.title}');
      await _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _highImportanceChannelId,
            'High Importance Notifications',
            channelDescription:
                'This channel is used for important notifications.',
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    }
  }

  // Helper to schedule a local reminder (e.g., for an event)
  Future<void> scheduleReminder({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    // Note: For precise scheduling, we need the 'timezone' package.
    // For now, this is a placeholder structure.
    debugPrint("Scheduling reminder '$title' for $scheduledDate");
  }

  Future<bool> requestNotificationPermission() async {
    final settings = await _firebaseMessaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    final fcmGranted =
        settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;

    if (Platform.isIOS) {
      final iosNotifications = _localNotifications
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      final iosGranted = await iosNotifications?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
      if (iosGranted != null) {
        return iosGranted;
      }

      return fcmGranted;
    }

    if (Platform.isAndroid) {
      final androidNotifications = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final granted = await androidNotifications
          ?.requestNotificationsPermission();
      if (granted != null) {
        return granted;
      }
    }

    return fcmGranted;
  }

  Future<Map<String, dynamic>> getNotificationDebugState() async {
    NotificationSettings? settings;
    try {
      settings = await _firebaseMessaging.getNotificationSettings();
    } catch (e) {
      debugPrint('Notification debug: failed to read messaging settings: $e');
    }

    List<PendingNotificationRequest> pending =
        <PendingNotificationRequest>[];
    try {
      pending = await _localNotifications.pendingNotificationRequests();
    } catch (e) {
      debugPrint('Notification debug: failed to read pending notifications: $e');
    }

    List<ActiveNotification> active = <ActiveNotification>[];
    try {
      active = await _localNotifications.getActiveNotifications();
    } catch (e) {
      debugPrint('Notification debug: failed to read active notifications: $e');
    }

    final dormantPending = pending
        .where((n) => n.payload?.startsWith('harmony_dormant:') ?? false)
        .length;
    final dormantActive = active
        .where((n) => n.payload?.startsWith('harmony_dormant:') ?? false)
        .length;

    return {
      'authorizationStatus': settings?.authorizationStatus.name ?? 'unknown',
      'alertSetting': settings?.alert.name ?? 'unknown',
      'badgeSetting': settings?.badge.name ?? 'unknown',
      'soundSetting': settings?.sound.name ?? 'unknown',
      'pendingTotal': pending.length,
      'pendingDormant': dormantPending,
      'activeTotal': active.length,
      'activeDormant': dormantActive,
      'isInitialized': _isInitialized,
    };
  }

  Future<void> openExactAlarmSettings() async {
    if (!Platform.isAndroid) return;

    final intent = AndroidIntent(
      action: 'android.settings.REQUEST_SCHEDULE_EXACT_ALARM',
    );
    await intent.launch();
  }

  Future<void> openBatteryOptimizationSettings() async {
    if (!Platform.isAndroid) return;

    final intent = AndroidIntent(
      action: 'android.settings.IGNORE_BATTERY_OPTIMIZATION_SETTINGS',
    );
    await intent.launch();
  }

  Future<bool> scheduleNativeDebugProbe({int delaySeconds = 15}) async {
    if (!Platform.isAndroid) return false;

    try {
      final ok = await _dormantAlarmChannel.invokeMethod<bool>(
        'schedule_debug_alarm',
        {
          'delay_seconds': delaySeconds,
        },
      );
      return ok ?? false;
    } catch (e) {
      debugPrint('Failed to schedule native debug probe: $e');
      return false;
    }
  }

  Future<Map<String, dynamic>> getNativeDebugState() async {
    if (!Platform.isAndroid) return <String, dynamic>{};

    try {
      final response = await _dormantAlarmChannel.invokeMethod<dynamic>(
        'get_last_alarm_debug',
      );
      if (response is Map) {
        return Map<String, dynamic>.from(response as Map);
      }
      return <String, dynamic>{};
    } catch (e) {
      debugPrint('Failed to read native debug state: $e');
      return <String, dynamic>{};
    }
  }

  Future<String?> consumeLaunchEventId() async {
    if (Platform.isIOS) {
      final payload = await consumeLaunchPayload();
      final eventIdRaw = payload['event_id'];
      if (eventIdRaw is String && eventIdRaw.trim().isNotEmpty) {
        return eventIdRaw.trim();
      }
      return null;
    }

    if (!Platform.isAndroid) return null;

    try {
      final value = await _dormantAlarmChannel.invokeMethod<dynamic>(
        'consume_launch_event_id',
      );
      if (value is String && value.trim().isNotEmpty) {
        return value;
      }
      return null;
    } catch (e) {
      debugPrint('Failed to consume native launch event id: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>> consumeLaunchPayload() async {
    if (Platform.isIOS) {
      if (_pendingIosLaunchPayload != null) {
        final payload = Map<String, dynamic>.from(_pendingIosLaunchPayload!);
        _pendingIosLaunchPayload = null;
        await _clearPersistedIosPendingLaunchPayload();
        return payload;
      }

      final persisted = await _readPersistedIosPendingLaunchPayload();
      if (persisted.isNotEmpty) {
        await _clearPersistedIosPendingLaunchPayload();
        return persisted;
      }

      return const <String, dynamic>{};
    }

    if (!Platform.isAndroid) return const <String, dynamic>{};

    try {
      final response = await _dormantAlarmChannel.invokeMethod<dynamic>(
        'consume_launch_payload',
      );
      if (response is Map) {
        return Map<String, dynamic>.from(response as Map);
      }
      return const <String, dynamic>{};
    } catch (e) {
      debugPrint('Failed to consume launch payload: $e');
      return const <String, dynamic>{};
    }
  }

  Future<bool?> _isIOSDeviceLockedNow() async {
    if (!Platform.isIOS) return null;

    try {
      final locked = await _dormantAlarmChannel.invokeMethod<bool>(
        'is_device_locked',
      );
      return locked;
    } catch (e) {
      debugPrint('Failed to query iOS lock state: $e');
      return null;
    }
  }

  Future<void> restoreLockscreenPresentation() async {
    if (!Platform.isAndroid) return;

    try {
      debugPrint('HARMONY_ALARM: requesting native lockscreen restore');
      final ok = await _dormantAlarmChannel.invokeMethod<dynamic>(
        'restore_lockscreen_presentation',
      );
      debugPrint('HARMONY_ALARM: native lockscreen restore result=$ok');
    } catch (e) {
      debugPrint('Failed to restore lockscreen presentation: $e');
    }
  }

  Future<void> cancelDormantPlaybackReminders() async {
    try {
      // Cancel plugin-scheduled dormant reminders on all platforms.
      final pending = await _localNotifications.pendingNotificationRequests();
      for (final notification in pending) {
        if (notification.payload?.startsWith('harmony_dormant:') ?? false) {
          await _localNotifications.cancel(notification.id);
        }
      }

      // iOS keeps delivered notifications in Notification Center until cleared.
      final active = await _localNotifications.getActiveNotifications();
      for (final notification in active) {
        if (notification.payload?.startsWith('harmony_dormant:') ?? false) {
          final activeId = notification.id;
          if (activeId != null) {
            await _localNotifications.cancel(activeId);
          }
        }
      }
    } catch (e) {
      debugPrint('Error cancelling plugin notifications: $e');
    }

    if (!Platform.isAndroid) return;

    try {
      final purged = await _dormantAlarmChannel.invokeMethod<int>(
        'purge_stale_registered_alarms',
      );
      if ((purged ?? 0) > 0) {
        debugPrint('Dormant reminder native stale purge: removed=$purged');
      }

      final cancelled = await _dormantAlarmChannel.invokeMethod<int>(
        'cancel_all_registered_alarms',
      );
      debugPrint(
        'Dormant reminder native cancel sweep complete: removed=${cancelled ?? 0}',
      );
    } catch (e) {
      debugPrint('Error in native cancel pre-check: $e');
    }
  }

  Future<void> cancelNotificationForEvent(String? eventId) async {
    if (eventId == null || eventId.isEmpty) return;

    try {
      final pending = await _localNotifications.pendingNotificationRequests();
      for (final notification in pending) {
        if (notification.payload == _dormantPayloadForEvent(eventId) ||
            notification.payload?.startsWith(_dormantPayloadPrefix(eventId)) ==
                true) {
          await _localNotifications.cancel(notification.id);
        }
      }

      // Legacy cleanup for older single-id scheduling.
      await _localNotifications.cancel(eventId.hashCode);
    } catch (e) {
      debugPrint('Failed to cancel local notification for $eventId: $e');
    }

    // iOS: also remove already-delivered notifications for this event from the
    // notification centre so they don't linger after the event time has passed.
    if (!Platform.isAndroid) {
      try {
        final active = await _localNotifications.getActiveNotifications();
        for (final notification in active) {
          if (notification.payload == _dormantPayloadForEvent(eventId) ||
              notification.payload?.startsWith(
                    _dormantPayloadPrefix(eventId),
                  ) ==
                  true) {
            final activeId = notification.id;
            if (activeId != null) {
              await _localNotifications.cancel(activeId);
            }
          }
        }
      } catch (e) {
        debugPrint(
          'Failed to clear delivered notifications for $eventId: $e',
        );
      }
    }

    if (!Platform.isAndroid) return;

    try {
      await _dormantAlarmChannel.invokeMethod<bool>(
        'cancel_notification_for_event',
        {'event_id': eventId},
      );
    } catch (e) {
      debugPrint('Failed to cancel native notification for $eventId: $e');
    }
  }

  Future<void> syncDormantPlaybackReminders({
    required List<Event> events,
    required UserService userService,
  }) async {
    final probeNow = DateTime.now();
    final probeWindowEnd = probeNow.add(const Duration(hours: 24));

    if (Platform.isAndroid) {
      final hasAndroidCandidate = events.any((event) {
        final startLocal = event.startTime.toLocal();
        if (startLocal.isAfter(probeWindowEnd)) return false;
        if (startLocal.isBefore(probeNow.subtract(const Duration(seconds: 15)))) {
          return false;
        }
        return true;
      });

      if (!hasAndroidCandidate) {
        // Avoid wiping already-armed native alarms when a transient snapshot
        // provides no schedulable events (e.g. temporary network stream gap).
        debugPrint(
          'Dormant reminder guard: no Android candidates in current snapshot; preserving existing alarms',
        );
        return;
      }
    }

    await cancelDormantPlaybackReminders();

    final notificationsGranted = await requestNotificationPermission();
    if (!notificationsGranted) {
      debugPrint(
        'Dormant playback reminders warning: notifications not confirmed; continuing schedule attempt.',
      );
    }

    final now = DateTime.now();
    final windowEnd = now.add(const Duration(hours: 24));
    int scheduledCount = 0;
    int fallbackCount = 0;
    int attemptCount = 0;
    int iosQueuedAlerts = 0;
    const int iosMaxQueuedAlerts = 8;
    final Set<String> iosScheduledSlotKeys = <String>{};

    final sortedEvents = [...events]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    final beforeDebug = await getNotificationDebugState();
    debugPrint('HARMONY_DORMANT_IOS_DEBUG: before=$beforeDebug');

    for (final event in sortedEvents) {
      final startLocal = event.startTime.toLocal();
      if (startLocal.isAfter(windowEnd)) continue;
      if (startLocal.isBefore(now.subtract(const Duration(seconds: 15)))) {
        continue;
      }

      // Avoid re-arming the same slot while it is already active.
      final slotGuardStart = startLocal.subtract(const Duration(seconds: 2));
      final slotGuardEnd = startLocal.add(const Duration(seconds: 90));
      if (now.isAfter(slotGuardStart) && now.isBefore(slotGuardEnd)) {
        debugPrint(
          'Dormant reminder guard: skipping in-slot reschedule for ${event.id} at $now',
        );
        continue;
      }

      // Skip events whose chime slot the user has set to Off in My Harmony.
      if (!userService.isChimeEnabledFor(startLocal)) {
        debugPrint(
          'Dormant reminder skipped (slot off): ${event.id} at $startLocal',
        );
        continue;
      }

      final slotMode = userService.playbackModeFor(startLocal);
        final slotKey = '${startLocal.year.toString().padLeft(4, '0')}'
          '${startLocal.month.toString().padLeft(2, '0')}'
          '${startLocal.day.toString().padLeft(2, '0')}_'
          '${startLocal.hour.toString().padLeft(2, '0')}'
          '${startLocal.minute.toString().padLeft(2, '0')}';
        final notificationTitle = 'Harmony by Intent';
      final notificationBody = slotMode == PlaybackMode.video
          ? 'Your scheduled event is starting. Tap to view event.'
          : 'Your scheduled event is starting. Tap to listen.';

      // iOS-only: keep one reminder per slot and use lock-state timing:
      // - Device locked now: 15-second lead.
      // - Device unlocked now: 4-second lead.
      if (!Platform.isAndroid) {
        if (iosQueuedAlerts >= iosMaxQueuedAlerts) {
          debugPrint(
            'iOS reminder cap reached ($iosMaxQueuedAlerts alerts); remaining future events skipped.',
          );
          break;
        }

        final iosSlotKey =
            '${startLocal.year.toString().padLeft(4, '0')}'
            '${startLocal.month.toString().padLeft(2, '0')}'
            '${startLocal.day.toString().padLeft(2, '0')}_'
            '${startLocal.hour.toString().padLeft(2, '0')}'
            '${startLocal.minute.toString().padLeft(2, '0')}';

        if (!iosScheduledSlotKeys.add(iosSlotKey)) {
          continue;
        }

        const iosOffsets = <int>[15];
        for (final secondsBefore in iosOffsets) {
          if (iosQueuedAlerts >= iosMaxQueuedAlerts) {
            break;
          }

          final alertTime = startLocal.subtract(Duration(seconds: secondsBefore));
          if (alertTime.isBefore(now)) {
            continue;
          }

          final alertId =
              ((event.id.hashCode ^
                          startLocal.millisecondsSinceEpoch ^
                          (secondsBefore * 1009)) &
                      0x7fffffff);

          final alertBody = slotMode == PlaybackMode.video
              ? 'Your Harmony event starts in $secondsBefore seconds. Tap to view event.'
              : 'Your Harmony event starts in $secondsBefore seconds. Tap to listen.';

          try {
            await _localNotifications.zonedSchedule(
              alertId,
              notificationTitle,
              alertBody,
              tz.TZDateTime.from(alertTime.toUtc(), tz.UTC),
              const NotificationDetails(
                iOS: DarwinNotificationDetails(
                  presentAlert: true,
                  presentBadge: false,
                  presentSound: true,
                ),
              ),
              androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
              uiLocalNotificationDateInterpretation:
                  UILocalNotificationDateInterpretation.absoluteTime,
              payload: _dormantPayloadForWindow(
                event.id,
                startLocal,
                event.endTime.toLocal(),
              ),
            );
            fallbackCount++;
            iosQueuedAlerts++;
          } catch (e) {
            debugPrint(
              'iOS reminder schedule failed for ${event.id} at $alertTime (${secondsBefore}s): $e',
            );
          }
        }
        // iOS path handled above; Android path continues below.
        continue;
      }

      // Use multiple close attempts to improve delivery under OEM idle policies.
      final attempts = <DateTime>[
        startLocal.subtract(const Duration(seconds: 5)),
        startLocal,
        startLocal.add(const Duration(seconds: 7)),
      ];

      for (int i = 0; i < attempts.length; i++) {
        final candidate = attempts[i];
        if (candidate.isAfter(windowEnd)) continue;
        if (candidate.isBefore(now.subtract(const Duration(seconds: 15)))) {
          continue;
        }

        final scheduleLocal = candidate.isBefore(now)
            ? now.add(const Duration(seconds: 1))
            : candidate;

        final alarmId = ((event.id.hashCode ^
                    startLocal.millisecondsSinceEpoch ^
                    ((i + 1) * 9973)) &
                0x7fffffff);

        Future<void> schedulePluginReminder({required String reason}) async {
          await _localNotifications.zonedSchedule(
            alarmId,
            notificationTitle,
            notificationBody,
            tz.TZDateTime.from(scheduleLocal.toUtc(), tz.UTC),
            NotificationDetails(
              android: AndroidNotificationDetails(
                _dormantPlaybackChannelId,
                'Dormant Playback Reminders',
                channelDescription:
                    'Timed reminders for Harmony events while your device is idle.',
                importance: Importance.max,
                priority: Priority.high,
                icon: '@mipmap/ic_launcher',
                category: AndroidNotificationCategory.alarm,
                visibility: NotificationVisibility.public,
                fullScreenIntent: slotMode == PlaybackMode.video,
                playSound: true,
              ),
              iOS: const DarwinNotificationDetails(),
            ),
            androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
            uiLocalNotificationDateInterpretation:
                UILocalNotificationDateInterpretation.absoluteTime,
            payload: 'harmony_dormant:${event.id}:',
          );
          fallbackCount++;
          debugPrint(
            '$reason for ${event.id} attempt=$i at $scheduleLocal (alarm_id=$alarmId)',
          );
        }

        try {
          // Clear any existing native alarm for this ID before scheduling.
          await _dormantAlarmChannel.invokeMethod<bool>(
            'cancel_alarm',
            {
              'alarm_id': alarmId,
            },
          );

          // Call native Android alarm scheduling
          final nativeScheduled = await _dormantAlarmChannel.invokeMethod<bool>(
            'schedule_exact_alarm',
            {
              'alarm_id': alarmId,
              'trigger_time_ms': scheduleLocal.millisecondsSinceEpoch,
              'event_id': event.id,
              'slot_key': slotKey,
              'event_title': notificationTitle,
              'event_body': notificationBody,
              'is_full_screen': slotMode == PlaybackMode.video,
            },
          );

          attemptCount++;
          if (nativeScheduled == true) {
            scheduledCount++;
            debugPrint(
              'Native alarm scheduled for ${event.id} attempt=$i at $scheduleLocal (alarm_id=$alarmId)',
            );
          } else {
            await schedulePluginReminder(
              reason: 'Native alarm rejected; plugin fallback scheduled',
            );
          }
        } catch (e) {
          debugPrint(
            'Native alarm schedule failed for ${event.id} attempt=$i at $scheduleLocal: $e',
          );
          try {
            await schedulePluginReminder(
              reason: 'Native alarm failed; plugin fallback scheduled',
            );
          } catch (fallbackError) {
            debugPrint(
              'Plugin fallback also failed for ${event.id} attempt=$i at $scheduleLocal: $fallbackError',
            );
          }
        }
      }
    }

    debugPrint(
      'Dormant reminder sync complete: attempts=$attemptCount, native=$scheduledCount, fallback=$fallbackCount, iosQueuedAlerts=$iosQueuedAlerts',
    );
    final afterDebug = await getNotificationDebugState();
    debugPrint('HARMONY_DORMANT_IOS_DEBUG: after=$afterDebug');
  }

  String? _preferredMediaUrl(Event event, PlaybackMode playbackMode) {
    if (playbackMode == PlaybackMode.audio) {
      if (event.soundUrl != null && event.soundUrl!.isNotEmpty) {
        return event.soundUrl;
      }
      if (_isAudioUrl(event.mediaUrl)) {
        return event.mediaUrl;
      }
      return null;
    }

    if (event.visualUrl != null && event.visualUrl!.isNotEmpty) {
      return event.visualUrl;
    }
    return event.mediaUrl ?? event.soundUrl;
  }

  bool _isAudioUrl(String? url) {
    if (url == null || url.isEmpty) return false;

    final lower = url.toLowerCase();
    return lower.contains('.mp3') ||
        lower.contains('.wav') ||
        lower.contains('.aac') ||
        lower.contains('.m4a');
  }

  String _dormantPayloadForEvent(String eventId) => 'harmony_dormant:$eventId:';

  String _dormantPayloadPrefix(String eventId) => 'harmony_dormant:$eventId';

  String _dormantPayloadForWindow(
    String eventId,
    DateTime startLocal,
    DateTime endLocal,
  ) {
    return 'harmony_dormant:$eventId:${startLocal.millisecondsSinceEpoch}:${endLocal.millisecondsSinceEpoch}';
  }

  bool _isDormantPayloadExpired(String? payload) {
    if (payload == null || !payload.startsWith('harmony_dormant:')) {
      return false;
    }

    final parts = payload.split(':');
    if (parts.length < 4) return false;

    final endMs = int.tryParse(parts[3]);
    if (endMs == null) return false;

    final endTime = DateTime.fromMillisecondsSinceEpoch(endMs);
    return !DateTime.now().isBefore(endTime);
  }

  Future<void> queueIosLaunchPayloadFromDormantTap(
    String? payload, {
    int? tappedNotificationId,
  }) async {
    if (tappedNotificationId != null) {
      try {
        await _localNotifications.cancel(tappedNotificationId);
      } catch (e) {
        debugPrint('Failed to clear tapped notification id=$tappedNotificationId: $e');
      }
    }

    final eventId = _eventIdFromDormantPayload(payload);
    if (eventId == null) {
      return;
    }

    if (_isDormantPayloadExpired(payload)) {
      await cancelNotificationForEvent(eventId);
      await _clearPersistedIosPendingLaunchPayload();
      return;
    }

    final mapped = <String, dynamic>{
      'event_id': eventId,
      'auto_play_video': false,
      'source': 'ios_local_notification_tap',
      'ts': DateTime.now().toIso8601String(),
    };

    _pendingIosLaunchPayload = mapped;
    await _persistIosPendingLaunchPayload(mapped);
    await cancelNotificationForEvent(eventId);
  }

  Future<void> _persistIosPendingLaunchPayload(Map<String, dynamic> payload) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_iosPendingLaunchPayloadKey, jsonEncode(payload));
    } catch (e) {
      debugPrint('Failed to persist iOS pending launch payload: $e');
    }
  }

  Future<Map<String, dynamic>> _readPersistedIosPendingLaunchPayload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_iosPendingLaunchPayloadKey);
      if (raw == null || raw.trim().isEmpty) {
        return const <String, dynamic>{};
      }
      final decoded = jsonDecode(raw);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (e) {
      debugPrint('Failed to read iOS pending launch payload: $e');
    }
    return const <String, dynamic>{};
  }

  Future<void> _clearPersistedIosPendingLaunchPayload() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_iosPendingLaunchPayloadKey);
    } catch (e) {
      debugPrint('Failed to clear iOS pending launch payload: $e');
    }
  }

  String? _eventIdFromDormantPayload(String? payload) {
    if (payload == null || !payload.startsWith('harmony_dormant:')) {
      return null;
    }

    final parts = payload.split(':');
    if (parts.length < 2 || parts[1].trim().isEmpty) {
      return null;
    }

    return parts[1].trim();
  }
}
