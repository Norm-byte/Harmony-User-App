import 'dart:io';
import 'package:android_intent_plus/android_intent.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/event.dart';
import 'user_service.dart';

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint("Handling a background message: ${message.messageId}");
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
      return;
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
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        // Handle notification tap
        debugPrint('Notification tapped: ${response.payload}');
      },
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
        _showLocalNotification(message);
      }
    });

    // 4. Subscribe to Topics
    await _subscribeToTopics();

    // 5. Get Token (for debugging)
    String? token = await _firebaseMessaging.getToken();
    debugPrint('FCM_TOKEN: $token');

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

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
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

  Future<void> cancelDormantPlaybackReminders() async {
    final pending = await _localNotifications.pendingNotificationRequests();
    for (final notification in pending) {
      if (notification.payload?.startsWith('harmony_dormant:') ?? false) {
        await _localNotifications.cancel(notification.id);
      }
    }
  }

  Future<void> syncDormantPlaybackReminders({
    required List<Event> events,
    required UserService userService,
  }) async {
    await cancelDormantPlaybackReminders();

    if (!userService.dormantPlaybackEnabled) {
      return;
    }

    final notificationsGranted = await requestNotificationPermission();
    if (!notificationsGranted) {
      debugPrint(
        'Dormant playback reminders skipped: notifications not granted.',
      );
      return;
    }

    final now = DateTime.now();
    final windowEnd = now.add(const Duration(hours: 24));

    for (final event in events) {
      if (event.type != EventType.national) continue;

      final startLocal = event.startTime.toLocal();
      if (startLocal.isBefore(now) || startLocal.isAfter(windowEnd)) continue;
      if (!userService.isChimeEnabledFor(startLocal)) continue;

      final slotMode = userService.playbackModeFor(startLocal);
      final mediaUrl = _preferredMediaUrl(event, slotMode);
      final notificationId =
          event.id.hashCode ^ startLocal.millisecondsSinceEpoch;
      final notificationBody = slotMode == PlaybackMode.video
          ? 'Harmony event starting now. Tap to open video playback.'
          : 'Harmony audio chime is ready for playback.';

      await _localNotifications.zonedSchedule(
        notificationId,
        event.title.isEmpty ? 'Harmony by Intent' : event.title,
        notificationBody,
        tz.TZDateTime.from(startLocal.toUtc(), tz.UTC),
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
        payload: 'harmony_dormant:${event.id}:${mediaUrl ?? ''}',
      );
    }
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
}
