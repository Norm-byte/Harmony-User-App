import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/event.dart';
import 'notification_service.dart';
import 'user_service.dart';

class EventService extends ChangeNotifier {
  // Singleton pattern
  static final EventService _instance = EventService._internal();
  factory EventService() => _instance;
  EventService._internal() {
    _init();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const MethodChannel _dormantAlarmChannel = MethodChannel(
    'com.harmonybyintent.harmony_user_app/dormant_alarm',
  );
  StreamSubscription? _eventsSubscription;
  StreamSubscription? _globalEventsSubscription;
  StreamSubscription? _myEventsSubscription;
  Timer? _timer;
  Timer? _dismissTimer; // Hard stop timer
  Timer? _notificationSyncTimer;
  String? _pendingAlarmEventId;
  DateTime? _pendingAlarmEventExpiresAt;
  bool _pendingAlarmForceVideo = false;
  bool? _pendingAlarmVerifiedExists;
  bool _currentEventFromAlarmLaunch = false;
  bool _isAlarmLaunchTransitionActive = false;
  Timer? _alarmLaunchTransitionTimer;
  bool _nativeLaunchPayloadCheckInFlight = false;
  String? _lastKnownAlarmLaunchEventId;
  String? _lastNoticeboardDebugSignature;
  bool _hasLoadedNationalDocs = false;
  bool _hasLoadedGlobalDocs = false;

  List<Event> _events = [];
  List<Event> _nationalEvents = [];
  List<Event> _globalEvents = [];
  List<Event> get events => _events;
  bool get hasLoadedEventSources =>
      _hasLoadedNationalDocs && _hasLoadedGlobalDocs;

  @visibleForTesting
  static bool isPublishedForUserApp(
    Map<String, dynamic> data, {
    required String docId,
  }) {
    final isDraftDoc = data['isDraft'] == true || docId.startsWith('draft_slot_');
    if (isDraftDoc) {
      return false;
    }

    final rawPublished = data['isPublished'];
    final rawPublishedBool = rawPublished == true ||
        rawPublished == 1 ||
        (rawPublished is String && rawPublished.toLowerCase() == 'true');
    return rawPublishedBool;
  }

  @visibleForTesting
  static Event resolveNationalDisplayEvent(
    Event event, {
    required String docId,
    required DateTime now,
  }) {
    final recurrence = (event.recurrenceType ?? '').trim().toLowerCase();
    final isDaily = recurrence == 'daily';
    final isWeekly = recurrence == 'weekly';
    final localNow = now.toLocal();

    final slotIdMatch = RegExp(
      r'^(?:draft_)?slot_(\d{2})(\d{2})_(\d{8})$',
    ).firstMatch(docId);
    int hour = event.startTime.toLocal().hour;
    int minute = event.startTime.toLocal().minute;
    DateTime? slotDocDateLocal;
    if (slotIdMatch != null) {
      hour = int.tryParse(slotIdMatch.group(1) ?? '') ?? hour;
      minute = int.tryParse(slotIdMatch.group(2) ?? '') ?? minute;
      final dateToken = slotIdMatch.group(3);
      if (dateToken != null && dateToken.length == 8) {
        final year = int.tryParse(dateToken.substring(0, 4));
        final month = int.tryParse(dateToken.substring(4, 6));
        final day = int.tryParse(dateToken.substring(6, 8));
        if (year != null && month != null && day != null) {
          slotDocDateLocal = DateTime(year, month, day);
        }
      }
    } else if (event.originTime != null && event.originTime!.contains(':')) {
      final parts = event.originTime!.split(':');
      if (parts.length == 2) {
        hour = int.tryParse(parts[0]) ?? hour;
        minute = int.tryParse(parts[1]) ?? minute;
      }
    }

    DateTime baseDate = event.startTime.toLocal();
    if (isDaily) {
      baseDate = localNow;
    } else if (slotDocDateLocal != null) {
      // Slot docs without recurrence are valid for each day in their own
      // Monday-Sunday week only, then expire. This preserves week-card
      // behavior without reintroducing cross-week ghost events.
      final weekStart = slotDocDateLocal.subtract(
        Duration(days: slotDocDateLocal.weekday - DateTime.monday),
      );
      final weekEndExclusive = weekStart.add(const Duration(days: 7));
      final inSlotWeek =
          !localNow.isBefore(weekStart) && localNow.isBefore(weekEndExclusive);
      if (inSlotWeek) {
        baseDate = localNow;
      }
    }

    DateTime localStart = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      hour,
      minute,
    );

    final duration = event.endTime.difference(event.startTime);
    DateTime localEnd = localStart.add(duration);
    final visibilityAfter = Duration(minutes: event.visibilityAfterMinutes ?? 0);

    if (localEnd.add(visibilityAfter).isBefore(localNow) &&
        (isDaily || isWeekly)) {
      if (isDaily) {
        localStart = localStart.add(const Duration(days: 1));
        localEnd = localStart.add(duration);
      } else if (isWeekly) {
        while (localEnd.isBefore(localNow)) {
          localStart = localStart.add(const Duration(days: 7));
          localEnd = localStart.add(duration);
        }
      }
    }

    return event.copyWith(startTime: localStart, endTime: localEnd);
  }

  @visibleForTesting
  static bool isWithinNoticeboardWindow(Event event, DateTime now) {
    final showBefore = Duration(
      minutes: event.noticeBoardShowBeforeMinutes ?? 60,
    );
    final visibilityAfter = Duration(
      minutes: event.noticeBoardVisibilityAfterMinutes ?? 0,
    );
    final showTime = event.startTime.toLocal().subtract(showBefore);
    final hideTime = event.endTime.toLocal().add(visibilityAfter);
    return !now.isBefore(showTime) && now.isBefore(hideTime);
  }

  List<Event> get visibleNoticeboardEvents {
    final now = DateTime.now();
    final candidates = _dedupeVisibleNoticeboardSlotCollisions(
      _dedupeNationalEvents([
        ..._processDocs(
          _nationalDocs,
          overrideType: EventType.national,
          forDormantScheduling: true,
        ),
        ..._processDocs(
          _globalDocs,
          overrideType: EventType.global,
          forDormantScheduling: true,
        ),
      ]),
    );

    final visible = candidates
        .where((event) => isWithinNoticeboardWindow(event, now))
        .toList();

    visible.sort((a, b) {
      final aShowTime = a.startTime.toLocal().subtract(
        Duration(minutes: a.noticeBoardShowBeforeMinutes ?? 60),
      );
      final bShowTime = b.startTime.toLocal().subtract(
        Duration(minutes: b.noticeBoardShowBeforeMinutes ?? 60),
      );
      return aShowTime.compareTo(bShowTime);
    });

    return visible;
  }

  Event? get activeNoticeboardEvent {
    final now = DateTime.now();
    final active = visibleNoticeboardEvents;

    if (active.isEmpty) {
      if (_lastNoticeboardDebugSignature != 'none') {
        _lastNoticeboardDebugSignature = 'none';
        debugPrint(
          'HARMONY_NOTICEBOARD: none active at ${now.toIso8601String()}',
        );
      }
      return null;
    }

    final selected = active.first;
    final selectedShowBefore = Duration(
      minutes: selected.noticeBoardShowBeforeMinutes ?? 60,
    );
    final selectedVisibilityAfter = Duration(
      minutes: selected.noticeBoardVisibilityAfterMinutes ?? 0,
    );
    final selectedShowTime = selected.startTime.toLocal().subtract(
      selectedShowBefore,
    );
    final selectedHideTime = selected.endTime.toLocal().add(
      selectedVisibilityAfter,
    );
    final signature =
        '${selected.id}|${selectedShowTime.toIso8601String()}|${selectedHideTime.toIso8601String()}';

    if (_lastNoticeboardDebugSignature != signature) {
      _lastNoticeboardDebugSignature = signature;
      debugPrint(
        'HARMONY_NOTICEBOARD: selected=${selected.id} '
        'show=${selectedShowTime.toIso8601String()} '
        'hide=${selectedHideTime.toIso8601String()} '
        'nbShowBefore=${selected.noticeBoardShowBeforeMinutes ?? 60} '
        'nbAfter=${selected.noticeBoardVisibilityAfterMinutes ?? 0}',
      );
    }

    return selected;
  }

  // My Events (History)
  List<Map<String, dynamic>> _myEvents = [];
  List<Map<String, dynamic>> get myEvents => _myEvents;

  bool _isEventActive = false;
  bool _isAppInForeground = true;
  bool _isWorldwide = false;
  String _currentEventTitle = '';
  String _currentEventDescription = '';
  String? _currentEventMediaUrl;
  String? _currentEventId; // Track ID for dismissal logic
  DateTime? _currentEventStartTime; // Track Start Time for valid dismissal key
  DateTime? _currentEventEndTime; // Track End Time for auto-dismissal
  final Duration _eventGracePeriod = const Duration(
    seconds: 1,
  ); // Buffer: Reduced to 1s to match playback safety
  // Track dismissed events by ID and StartTime to allow re-triggering if time changes
  final Map<String, String> _dismissedEventStartTimes = {};
  // New: Robust cooldown map to prevent immediate re-triggering of the same event ID within a short window
  final Map<String, DateTime> _recentlyDismissedIds = {};

  bool get isEventActive => _isEventActive;
  bool get isAlarmLaunchTransitionActive => _isAlarmLaunchTransitionActive;
  bool get isWorldwide => _isWorldwide;
  String get currentEventTitle => _currentEventTitle;
  String get currentEventDescription => _currentEventDescription;
  String? get currentEventMediaUrl => _currentEventMediaUrl;
  DateTime? get currentEventStartTime => _currentEventStartTime;
  DateTime? get currentEventEndTime => _currentEventEndTime;

  void setAppInForegroundState(bool isForeground) {
    _isAppInForeground = isForeground;
  }

  // Track Auto-Join processing to prevent spamming Firestore
  final Set<String> _autoJoinInProgress = {};

  // Shared User Intent State
  String _userIntent = '';
  String get userIntent => _userIntent;

  void setUserIntent(String intent) {
    _userIntent = intent;
    notifyListeners();
  }

  Future<String> joinEvent(
    String eventId,
    String eventTitle,
    String intent,
    EventType type,
    DateTime startTime,
    DateTime endTime, {
    int visibilityAfterMinutes = 0,
  }) async {
    _userIntent = intent;
    notifyListeners();

    try {
      // Use UserService instead of FirebaseAuth
      final userId = UserService().userId;
      print(
        "HARMONY_DEBUG: joinEvent called for user '$userId', event '$eventTitle'",
      );

      // 1. Check for Duplicates
      bool isAlreadyJoined = _myEvents.any((doc) => doc['eventId'] == eventId);
      if (isAlreadyJoined) {
        print("HARMONY_DEBUG: User already joined event $eventId");
        // Update intent locally if re-joining logic was desired, but for now just return
        return "Already Joined";
      }

      // 2. Add to User History (Full User Input)
      if (userId.isNotEmpty) {
        // Ensure listener is active for this user
        if (_currentListenedUserId != userId) {
          _listenToMyEvents(userId);
        }

        await _firestore
            .collection('users')
            .doc(userId)
            .collection('registered_events')
            .add({
              'eventId': eventId,
              'eventTitle': eventTitle,
              'intent': intent,
              'timestamp': FieldValue.serverTimestamp(),
              'startTime': startTime,
              'endTime': endTime,
              'visibilityAfterMinutes':
                  visibilityAfterMinutes, // Store visibility preference
              'status': 'registered',
            });

        print("HARMONY_DEBUG: Event joined successfully in Firestore");
        return "Success: $userId";
      } else {
        print("HARMONY_DEBUG: Error: No User ID found in UserService");
        return "Error: No User ID";
      }
    } catch (e) {
      print("Error joining event: $e");
      return "Error: $e";
    }
  }

  // Helper to extract core intent concept from user sentence
  String _extractCoreIntent(String text) {
    const coreIntents = [
      'Harmony',
      'Peace',
      'Love',
      'Joy',
      'Gratitude',
      'Compassion',
      'Faith',
      'Trust',
      'Mindfulness',
      'Kindness',
      'Hope',
      'Freedom',
      'Unity',
      'Patience',
      'Courage',
      'Wisdom',
      'Truth',
      'Healing',
      'Abundance',
      'Clarity',
      'Focus',
      'Balance',
      'Strength',
      'Respect',
      'Forgiveness',
      'Acceptance',
      'Presence',
    ];

    final lowerText = text.toLowerCase();
    for (final core in coreIntents) {
      if (lowerText.contains(core.toLowerCase())) {
        return core;
      }
    }
    return text; // Fallback to full text if no core concept found
  }

  List<QueryDocumentSnapshot> _nationalDocs = [];
  List<QueryDocumentSnapshot> _globalDocs = [];

  // Track current subscribed ID to prevent unnecessary reconnections
  String? _currentListenedUserId;

  void _init() {
    // Set up MethodChannel listener for immediate payload consumption
    _dormantAlarmChannel.setMethodCallHandler((call) async {
      if (call.method == 'on_notification_tap_received') {
        print('HARMONY_ALARM: MethodChannel onNotificationTapReceived called');
        // Immediately consume the payload without waiting for the periodic loop
        await _checkNativeLaunchPayloadIfAny();
        return {'success': true};
      }
      return null;
    });

    // Audit Auth State for My Events
    final userService = UserService();

    // Initial check
    if (userService.userId.isNotEmpty) {
      _listenToMyEvents(userService.userId);
    } else {
      print("HARMONY_DEBUG: UserService ID is empty on init");
    }

    // Listen for changes
    userService.addListener(() {
      if (userService.userId.isNotEmpty &&
          userService.userId != _currentListenedUserId) {
        print("HARMONY_DEBUG: UserService ID changed to ${userService.userId}");
        _listenToMyEvents(userService.userId);
      }

      _scheduleDormantPlaybackSync();
    });

    // Start periodic check - Check every 1 second for precision
    _timer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => checkForEvents(),
    );

    // Listen to National Events
    _eventsSubscription = _firestore
        .collection('events')
      .where('isPublished', isEqualTo: true)
        .snapshots()
        .listen(
          (snapshot) {
            _hasLoadedNationalDocs = true;
            _nationalDocs = snapshot.docs;
            _refreshEvents();
          },
          onError: (e) {
            print("Error listening to national events: $e");
          },
        );

    // Listen to Global Events
    _globalEventsSubscription = _firestore
        .collection('global_events')
      .where('isPublished', isEqualTo: true)
        .snapshots()
        .listen(
          (snapshot) {
            _hasLoadedGlobalDocs = true;
            _globalDocs = snapshot.docs;
            _refreshEvents();
          },
          onError: (e) {
            print("Error listening to global events: $e");
          },
        );
  }

  void _listenToMyEvents(String userId) {
    if (userId.isEmpty) return;

    print(
      "HARMONY_DEBUGGING: Starting stream for users/$userId/registered_events",
    );
    _currentListenedUserId = userId; // Update tracker

    _myEventsSubscription?.cancel();
    _myEventsSubscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('registered_events')
        // Removing orderBy temporarily to rule out Indexing/Null issues
        // .orderBy('timestamp', descending: true)
        .snapshots()
        .listen(
          (snapshot) {
            print(
              "HARMONY_DEBUGGING: Received ${snapshot.docs.length} my_events docs for user $userId",
            );
            _myEvents = snapshot.docs.map((doc) => doc.data()).toList();
            // Manual sort since we removed orderBy
            _myEvents.sort((a, b) {
              final tA = a['timestamp'] as Timestamp?; // Using Timestamp? cast
              final tB = b['timestamp'] as Timestamp?;
              if (tA == null) return -1;
              if (tB == null) return 1;
              return tB.compareTo(tA);
            });
            notifyListeners();
          },
          onError: (e) {
            print("HARMONY_DEBUGGING: Error listening to my events: $e");
          },
        );
  }

  void _refreshEvents() {
    _nationalEvents = _processDocs(
      _nationalDocs,
      overrideType: EventType.national,
    );
    _globalEvents = _processDocs(_globalDocs, overrideType: EventType.global);
    _mergeEvents();
  }

  // Synchronously peek at SharedPreferences for a stored launch payload from MainActivity.
  // If found, set _pendingAlarmEventId so the next checkForEvents can trigger it with fromAlarmLaunch=true.
  // This completes BEFORE any event triggering, preventing the race condition where the event starts before we mark it as from-alarm.
  void _peekAndSetPendingAlarmFromSharedPreferences() {
    try {
      final prefs = SharedPreferences.getInstance().then((p) => p);
      // Note: SharedPreferences.getInstance is Future-based, we can't make it sync in Dart
      // So we use a different approach: trigger consumption via asyc task but set a flag
      // to indicate we should mark the NEXT matching event as from-alarm
      _tryConsumeStoredLaunchPayload();
    } catch (e) {
      // Silent fail - this is a best-effort peek
    }
  }

  // Try to consume the stored launch payload from the MethodChannel.
  // Unlike _checkNativeLaunchPayloadIfAny, this doesn't try to trigger the event,
  // it just populates _pendingAlarmEventId so that _attemptPendingAlarmPlayback can find it.
  void _tryConsumeStoredLaunchPayload() async {
    try {
      if (_nativeLaunchPayloadCheckInFlight) return;
      _nativeLaunchPayloadCheckInFlight = true;

      final payload = await NotificationService().consumeLaunchPayload();
      String? eventId;
      bool autoPlayVideo = false;

      final eventIdRaw = payload['event_id'];
      if (eventIdRaw is String && eventIdRaw.trim().isNotEmpty) {
        eventId = eventIdRaw.trim();
      }
      autoPlayVideo = payload['auto_play_video'] == true;

      if (eventId == null) {
        eventId = await NotificationService().consumeLaunchEventId();
      }

      if (eventId != null && eventId.isNotEmpty) {
        // Don't re-queue if this event was already played and dismissed this session.
        // This prevents the spam loop when Intent extras persist and native keeps
        // returning the same ID on every 1-second cycle.
        if (_dismissedEventStartTimes.containsKey(eventId) ||
            (_recentlyDismissedIds.containsKey(eventId))) {
          return;
        }
        // Found a pending alarm launch - queue it as pending so the next cycle triggers it with fromAlarmLaunch=true
        print(
          'HARMONY_ALARM: found stored launch payload eventId=$eventId, queuing as pending alarm',
        );
        _lastKnownAlarmLaunchEventId = eventId;
        _pendingAlarmEventId = eventId;
        _pendingAlarmEventExpiresAt = DateTime.now().add(
          const Duration(minutes: 5),
        );
        _pendingAlarmForceVideo = autoPlayVideo;
        _pendingAlarmVerifiedExists = null;
        _verifyPendingAlarmEventStillPublished(eventId);
      }
    } catch (e) {
      print('HARMONY_ALARM: _tryConsumeStoredLaunchPayload failed: $e');
    } finally {
      _nativeLaunchPayloadCheckInFlight = false;
    }
  }

  void requestImmediateAlarmPlayback(
    String eventId, {
    Duration holdFor = const Duration(minutes: 5),
    bool forceVideo = false,
  }) {
    if (eventId.trim().isEmpty) return;

    _pendingAlarmEventId = eventId.trim();
    _pendingAlarmEventExpiresAt = DateTime.now().add(holdFor);
    _pendingAlarmForceVideo = forceVideo;
    _pendingAlarmVerifiedExists = null;
    _alarmLaunchTransitionTimer?.cancel();
    _isAlarmLaunchTransitionActive = true;
    notifyListeners();
    print('HARMONY_ALARM: queued immediate playback for $_pendingAlarmEventId');
    _verifyPendingAlarmEventStillPublished(_pendingAlarmEventId!);
    _attemptPendingAlarmPlayback(forceWindow: true);
  }

  void _clearPendingAlarmPlayback({
    String? reason,
    bool restoreNativePresentation = true,
  }) {
    final shouldRestoreNativePresentation =
        _pendingAlarmForceVideo || _currentEventFromAlarmLaunch;
    if (reason != null && reason.isNotEmpty) {
      print('HARMONY_ALARM: clearing pending playback ($reason)');
    }
    _pendingAlarmEventId = null;
    _pendingAlarmEventExpiresAt = null;
    _pendingAlarmForceVideo = false;
    _pendingAlarmVerifiedExists = null;
    if (!_isEventActive && _isAlarmLaunchTransitionActive) {
      _alarmLaunchTransitionTimer?.cancel();
      _isAlarmLaunchTransitionActive = false;
      notifyListeners();
    }
    if (restoreNativePresentation && shouldRestoreNativePresentation) {
      NotificationService().restoreLockscreenPresentation();
    }
  }

  Future<void> _verifyPendingAlarmEventStillPublished(String eventId) async {
    try {
      final national = await _firestore.collection('events').doc(eventId).get();
      final global = await _firestore
          .collection('global_events')
          .doc(eventId)
          .get();

      bool existsAndPublished(DocumentSnapshot<Map<String, dynamic>> doc) {
        if (!doc.exists) return false;
        final data = doc.data();
        if (data == null) return false;
        final isPublished = data['isPublished'] == true;
        final isDraft = data['isDraft'] == true;
        final isDraftId = doc.id.startsWith('draft_slot_');
        return isPublished && !isDraft && !isDraftId;
      }

      final stillPublished =
          existsAndPublished(national) || existsAndPublished(global);

      // Ignore verification result if pending ID changed mid-flight.
      if (_pendingAlarmEventId != eventId) return;

      _pendingAlarmVerifiedExists = stillPublished;

      if (!stillPublished) {
        await NotificationService().cancelNotificationForEvent(eventId);
        _clearPendingAlarmPlayback(
          reason: 'stale alarm dropped for deleted/unpublished event $eventId',
        );
      }
    } catch (e) {
      // Keep pending state when verification fails transiently; next cycle retries.
      if (_pendingAlarmEventId == eventId) {
        _pendingAlarmVerifiedExists = null;
      }
      print('HARMONY_ALARM: verify pending event failed for $eventId: $e');
    }
  }

  bool _attemptPendingAlarmPlayback({bool forceWindow = false}) {
    final pendingId = _pendingAlarmEventId;
    final expiresAt = _pendingAlarmEventExpiresAt;
    final forceVideo = _pendingAlarmForceVideo;
    if (pendingId == null || pendingId.isEmpty || expiresAt == null) {
      return false;
    }

    final now = DateTime.now();
    if (now.isAfter(expiresAt)) {
      _clearPendingAlarmPlayback(
        reason: 'pending playback expired for $pendingId',
      );
      print('HARMONY_ALARM: pending playback expired for $pendingId');
      return false;
    }

    // Do not allow alarm playback until we confirm the event still exists in Firestore.
    if (_pendingAlarmVerifiedExists == null) {
      _verifyPendingAlarmEventStillPublished(pendingId);
      return false;
    }

    if (_pendingAlarmVerifiedExists == false) {
      _clearPendingAlarmPlayback(
        reason: 'pending event no longer exists in Firestore ($pendingId)',
      );
      return false;
    }

    Event? target;
    for (final event in _events) {
      if (event.id == pendingId) {
        target = event;
        break;
      }
    }

    if (target == null) {
      return false;
    }

    if (_isEventActive && _currentEventId == target.id) {
      _currentEventFromAlarmLaunch = true;
      _clearPendingAlarmPlayback(
        reason: 'pending target already active (${target.id})',
        restoreNativePresentation: false,
      );
      print(
        'HARMONY_ALARM: target ${target.id} already active; upgraded to alarm launch and skipping retrigger',
      );
      return true;
    }

    final startLocal = target.startTime.toLocal();
    final endLocal = target.endTime.toLocal();
    final inWindow =
        now.isAfter(startLocal.subtract(const Duration(minutes: 2))) &&
        now.isBefore(endLocal.add(const Duration(minutes: 5)));

    if (!forceWindow && !inWindow) {
      return false;
    }

    // ── MISSED = MISSED enforcement ─────────────────────────────────────────
    // Compute how much of the event window is still remaining. The event ends
    // at endLocal; anything past that is completely missed — no replay ever.
    final remaining = endLocal.difference(DateTime.now());

    if (remaining.inSeconds <= 0) {
      // Event has already ended — user missed it. Drop silently.
      print(
        'HARMONY_ALARM: late tap dropped — event ${target.id} already ended '
        '(ended ${endLocal.toIso8601String()}, now ${DateTime.now().toIso8601String()})',
      );
      NotificationService().cancelNotificationForEvent(target.id);
      _clearPendingAlarmPlayback(
        reason: 'event already ended, late tap dropped for ${target.id}',
      );
      return false;
    }

    // Cap playback duration to whatever time is left in the event window.
    // The user sees only what there is still to see — no full replay.
    final cappedSeconds = remaining.inSeconds.clamp(
      1,
      target.durationSeconds ?? 3600,
    );
    if (cappedSeconds < (target.durationSeconds ?? 3600)) {
      print(
        'HARMONY_ALARM: late tap for ${target.id} — capping duration to '
        '${cappedSeconds}s (${(target.durationSeconds ?? 3600) - cappedSeconds}s missed)',
      );
    }
    // ─────────────────────────────────────────────────────────────────────────

    _dismissedEventStartTimes.remove(target.id);
    _recentlyDismissedIds.remove(target.id);

    print(
      'HARMONY_ALARM: forcing playback for ${target.id} from launch intent',
    );
    final forcedStart = DateTime.now();
    final forcedMedia = forceVideo
        ? _selectPlaybackMediaForForcedVideo(target)
        : _selectPlaybackMedia(target);
    _triggerEvent(
      id: target.id,
      title: target.title,
      description: target.description,
      isWorldwide: target.type == EventType.global,
      mediaUrl: forcedMedia,
      intent: target.mostPopularIntent,
      fromAlarmLaunch: true,
      startTime: forcedStart,
      durationSeconds: cappedSeconds,
    );

    _clearPendingAlarmPlayback(
      reason: 'pending alarm playback consumed',
      restoreNativePresentation: false,
    );
    return true;
  }

  void _mergeEvents() {
    final oldEvents = [..._events];
    _events = _dedupeNationalEvents([..._nationalEvents, ..._globalEvents]);
    _events.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Only notify if the list actually changed to avoid unnecessary rebuilds
    if (!_areEventListsEqual(oldEvents, _events)) {
      // Rebuild dormant reminders only when event content actually changes.
      // This avoids cancel/recreate churn right around trigger times.
      _scheduleDormantPlaybackSync();
      notifyListeners();
    }
  }

  List<Event> _dedupeNationalEvents(List<Event> events) {
    final Map<String, Event> deduped = {};
    final now = DateTime.now();

    for (final event in events) {
      if (event.type != EventType.national) {
        deduped['global:${event.id}'] = event;
        continue;
      }

      final localStart = event.startTime.toLocal();
      final slotKey = event.originTime != null && event.originTime!.isNotEmpty
          ? event.originTime!
          : '${localStart.hour.toString().padLeft(2, '0')}:${localStart.minute.toString().padLeft(2, '0')}';
        final dateKey =
          '${localStart.year}-${localStart.month.toString().padLeft(2, '0')}-${localStart.day.toString().padLeft(2, '0')}';
        final dedupeKey = 'national:$slotKey:$dateKey';
      final existing = deduped[dedupeKey];

      if (existing == null) {
        deduped[dedupeKey] = event;
        continue;
      }

      final eventUpdatedAt = event.updatedAt;
      final existingUpdatedAt = existing.updatedAt;
      if (eventUpdatedAt != null && existingUpdatedAt != null) {
        if (eventUpdatedAt.isAfter(existingUpdatedAt)) {
          deduped[dedupeKey] = event;
          continue;
        }
        if (existingUpdatedAt.isAfter(eventUpdatedAt)) {
          continue;
        }
      } else if (eventUpdatedAt != null && existingUpdatedAt == null) {
        deduped[dedupeKey] = event;
        continue;
      } else if (existingUpdatedAt != null && eventUpdatedAt == null) {
        continue;
      }

      final eventHasVisual =
          (event.visualUrl != null && event.visualUrl!.isNotEmpty) ||
          event.imageUrl.isNotEmpty;
      final existingHasVisual =
          (existing.visualUrl != null && existing.visualUrl!.isNotEmpty) ||
          existing.imageUrl.isNotEmpty;

      final eventIsCanonicalSlot = event.id.startsWith('slot_');
      final existingIsCanonicalSlot = existing.id.startsWith('slot_');

      if (eventIsCanonicalSlot && !existingIsCanonicalSlot) {
        deduped[dedupeKey] = event;
        continue;
      }

      if (event.durationSeconds != null && existing.durationSeconds == null) {
        deduped[dedupeKey] = event;
        continue;
      }

      if (eventHasVisual && !existingHasVisual) {
        deduped[dedupeKey] = event;
        continue;
      }

      final eventDistance = event.startTime.difference(now).inSeconds.abs();
      final existingDistance = existing.startTime
          .difference(now)
          .inSeconds
          .abs();

      if (eventDistance < existingDistance) {
        deduped[dedupeKey] = event;
        continue;
      }

      if (eventDistance == existingDistance &&
          event.startTime.isBefore(existing.startTime)) {
        deduped[dedupeKey] = event;
      }
    }

    return deduped.values.toList();
  }

  List<Event> _dedupeVisibleNoticeboardSlotCollisions(List<Event> events) {
    final Map<String, Event> slotWinners = {};

    for (final event in events) {
      if (event.type != EventType.national) {
        final key = 'global:${event.id}';
        final existing = slotWinners[key];
        if (existing == null || _preferEvent(event, existing)) {
          slotWinners[key] = event;
        }
        continue;
      }

      final localStart = event.startTime.toLocal();
      final slotKey = event.originTime != null && event.originTime!.isNotEmpty
          ? event.originTime!
          : '${localStart.hour.toString().padLeft(2, '0')}:${localStart.minute.toString().padLeft(2, '0')}';
      final dateKey =
          '${localStart.year}-${localStart.month.toString().padLeft(2, '0')}-${localStart.day.toString().padLeft(2, '0')}';
      final key = 'national:$slotKey:$dateKey';

      final existing = slotWinners[key];
      if (existing == null || _preferEvent(event, existing)) {
        slotWinners[key] = event;
      }
    }

    return slotWinners.values.toList();
  }

  bool _preferEvent(Event candidate, Event current) {
    final candidateUpdatedAt = candidate.updatedAt;
    final currentUpdatedAt = current.updatedAt;
    if (candidateUpdatedAt != null && currentUpdatedAt != null) {
      if (candidateUpdatedAt.isAfter(currentUpdatedAt)) return true;
      if (currentUpdatedAt.isAfter(candidateUpdatedAt)) return false;
    } else if (candidateUpdatedAt != null && currentUpdatedAt == null) {
      return true;
    } else if (currentUpdatedAt != null && candidateUpdatedAt == null) {
      return false;
    }

    final candidateIsCanonicalSlot = candidate.id.startsWith('slot_');
    final currentIsCanonicalSlot = current.id.startsWith('slot_');
    if (candidateIsCanonicalSlot != currentIsCanonicalSlot) {
      return candidateIsCanonicalSlot;
    }

    final candidateHasVisual =
        (candidate.visualUrl != null && candidate.visualUrl!.isNotEmpty) ||
            candidate.imageUrl.isNotEmpty;
    final currentHasVisual =
        (current.visualUrl != null && current.visualUrl!.isNotEmpty) ||
            current.imageUrl.isNotEmpty;
    if (candidateHasVisual != currentHasVisual) {
      return candidateHasVisual;
    }

    if (candidate.durationSeconds != null && current.durationSeconds == null) {
      return true;
    }
    if (current.durationSeconds != null && candidate.durationSeconds == null) {
      return false;
    }

    return candidate.startTime.isAfter(current.startTime);
  }

  void _scheduleDormantPlaybackSync() {
    _notificationSyncTimer?.cancel();
    _notificationSyncTimer = Timer(const Duration(milliseconds: 300), () {
      final dormantEvents = [
        ..._processDocs(
          _nationalDocs,
          overrideType: EventType.national,
          forDormantScheduling: true,
        ),
        ..._processDocs(
          _globalDocs,
          overrideType: EventType.global,
          forDormantScheduling: true,
        ),
      ];

      dormantEvents.sort((a, b) => a.startTime.compareTo(b.startTime));

      NotificationService().syncDormantPlaybackReminders(
        events: dormantEvents,
        userService: UserService(),
      );

      print(
        'HARMONY_DORMANT: sync requested with ${dormantEvents.length} candidate events',
      );
    });
  }

  bool _areEventListsEqual(List<Event> a, List<Event> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].startTime != b[i].startTime ||
          a[i].endTime != b[i].endTime)
        return false;
    }
    return true;
  }

  List<Event> _processDocs(
    List<QueryDocumentSnapshot> docs, {
    EventType? overrideType,
    bool forDormantScheduling = false,
  }) {
    final now = DateTime.now();
    List<Event> processedEvents = [];

    for (var doc in docs) {
      try {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        final rawEvent = Event.fromJson(data);
        final event = overrideType != null
            ? rawEvent.copyWith(type: overrideType)
            : rawEvent;

        // National schedule is slot-based. Ignore legacy/non-slot docs so
        // stale historical records cannot reappear as noticeboard cards.
        if (event.type == EventType.national && !doc.id.startsWith('slot_')) {
          continue;
        }

        if (event.type == EventType.national) {
          print(
            "DEBUG: National Event '${event.title}': DurationSecs(RAW)=${data['durationSeconds']}, Start=${event.startTime}, End=${event.endTime}, Duration=${event.endTime.difference(event.startTime).inSeconds}s",
          );
        }

        // Keep blank titles: admins may intentionally publish empty title cards.
        // Do not drop these events, otherwise stale titled events can appear to
        // "replace" intended blank slots in the noticeboard UI.

        if (!isPublishedForUserApp(data, docId: doc.id)) {
          continue;
        }

        final recurrence = (event.recurrenceType ?? '').trim().toLowerCase();
        final isDaily = recurrence == 'daily';
        final isWeekly = recurrence == 'weekly';
        final isMonthly = recurrence == 'monthly';
        final hasNoRecurrence = recurrence.isEmpty || recurrence == 'none';

        // Handle Recurrence
        Event displayEvent = event;

        if (event.type == EventType.national) {
          displayEvent = resolveNationalDisplayEvent(
            event,
            docId: doc.id,
            now: now,
          );
        } else {
          if (!hasNoRecurrence) {
            final duration = event.endTime.difference(event.startTime);
            final nextStart = _getNextOccurrence(
              event.startTime,
              recurrence,
              duration,
            );

            if (nextStart != event.startTime) {
              displayEvent = event.copyWith(
                startTime: nextStart,
                endTime: nextStart.add(duration),
              );
            }
          }
        }

        // 1. Check visibility-after window.
        // For noticeboard/dormant candidate generation we must respect
        // noticeBoardVisibilityAfterMinutes so cards are not dropped too early.
        final effectiveVisibilityAfterMinutes = forDormantScheduling
            ? (displayEvent.noticeBoardVisibilityAfterMinutes ??
                displayEvent.visibilityAfterMinutes ??
                0)
            : (displayEvent.visibilityAfterMinutes ?? 0);
        final visibilityAfter = Duration(
          minutes: effectiveVisibilityAfterMinutes,
        );
        final localEndTime = displayEvent.endTime.toLocal();

        if (now.isAfter(localEndTime.add(visibilityAfter))) {
          continue; // Too old
        }

        if (!forDormantScheduling) {
          // 2. Check Show Before Event (UI visibility window only)
          int defaultShowBefore = 60;
          final showBefore = Duration(
            minutes: displayEvent.showBeforeMinutes ?? defaultShowBefore,
          );
          final localStartTime = displayEvent.startTime.toLocal();
          final showTime = localStartTime.subtract(showBefore);

          if (now.isBefore(showTime)) {
            continue; // Too early to show
          }
        }

        processedEvents.add(displayEvent);
      } catch (e) {
        print("DEBUG: Error processing event doc ${doc.id}: $e");
      }
    }
    return processedEvents;
  }

  DateTime _getNextOccurrence(
    DateTime start,
    String recurrenceType,
    Duration duration,
  ) {
    final now = DateTime.now();
    if (start.add(duration).isAfter(now)) return start;

    final normalized = recurrenceType.trim().toLowerCase();
    DateTime next = start;
    while (next.add(duration).isBefore(now)) {
      switch (normalized) {
        case 'daily':
          next = next.add(const Duration(days: 1));
          break;
        case 'weekly':
          next = next.add(const Duration(days: 7));
          break;
        case 'monthly':
          next = DateTime(
            next.year,
            next.month + 1,
            next.day,
            next.hour,
            next.minute,
          );
          break;
        default:
          return start;
      }
    }
    return next;
  }

  @override
  void dispose() {
    _timer?.cancel();
    _notificationSyncTimer?.cancel();
    _alarmLaunchTransitionTimer?.cancel();
    _eventsSubscription?.cancel();
    _globalEventsSubscription?.cancel();
    _myEventsSubscription?.cancel();
    super.dispose();
  }

  // DEBUGGING METHODS
  void debugForceRefresh() {
    print("HARMONY_DEBUG: Force Refresh Triggered");
    final userService = UserService();
    if (userService.userId.isNotEmpty) {
      _listenToMyEvents(userService.userId);
    } else {
      print("HARMONY_DEBUG: Cannot refresh, userId empty");
    }
  }

  Future<void> debugAddDummyEvent() async {
    print("HARMONY_DEBUG: Debug Add Dummy Event Triggered");
    await joinEvent(
      'debug_event_${DateTime.now().millisecondsSinceEpoch}',
      'Debug Event',
      'Debug Intent',
      EventType.national,
      DateTime.now(),
      DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  String getDebugInfo() {
    return "UID: ${_currentListenedUserId ?? 'None'}\n"
        "Sub Active: ${_myEventsSubscription != null}\n"
        "Docs: ${_myEvents.length}\n"
        "UserSvcID: ${UserService().userId}";
  }

  // Check for events
  void checkForEvents() {
    final now = DateTime.now();

    _refreshEvents();

    if (_attemptPendingAlarmPlayback()) {
      return;
    }

    if (_isEventActive) {
      if (_currentEventEndTime != null &&
          now.isAfter(_currentEventEndTime!.add(_eventGracePeriod))) {
        dismissEvent();
        return;
      }

      if (_currentEventId != null && _currentEventEndTime == null) {
        try {
          final currentEvent = _events.firstWhere(
            (e) => e.id == _currentEventId,
          );
          if (now.isAfter(
            currentEvent.endTime.toLocal().add(_eventGracePeriod),
          )) {
            dismissEvent();
            return;
          }
        } catch (e) {
          dismissEvent();
          return;
        }
      }
    }

    Event? bestEventToTrigger;

    for (final event in _events) {
      // AUTO-JOIN LOGIC (New Feature)
      if (event.type == EventType.global) {
        final userService = UserService();
        if (userService.autoJoinWorldwide) {
          // Check memory cache first to avoid async spam checks
          bool alreadyJoined = _myEvents.any(
            (doc) => doc['eventId'] == event.id,
          );

          // Check if we are already processing this join to avoid race condition in 1s loop
          bool pending = _autoJoinInProgress.contains(event.id);

          if (!alreadyJoined && !pending) {
            _autoJoinInProgress.add(event.id);
            print(
              "HARMONY_AUTO_JOIN: Initiating auto-join for ${event.title} (${event.id})",
            );

            joinEvent(
              event.id,
              event.title,
              event.mostPopularIntent ?? 'Harmony',
              event.type,
              event.startTime,
              event.endTime,
              visibilityAfterMinutes: event.visibilityAfterMinutes ?? 0,
            ).then((_) {
              // Remove from pending after some time or immediately?
              // Ideally keep it in pending until _myEvents updates?
              // Actually, if we remove it, the next tick might try again if _myEvents hasn't updated.
              // So we relying on _myEvents eventually updating.
              // We'll clear it after 10 seconds just to be safe it doesn't block forever if write fails.
              Future.delayed(const Duration(seconds: 10), () {
                _autoJoinInProgress.remove(event.id);
              });
            });
          }
        }
      }

      if (event.type == EventType.national &&
          !UserService().isChimeEnabledFor(event.startTime.toLocal())) {
        continue;
      }

      final startLocal = event.startTime.toLocal();
      final endLocal = event.endTime.toLocal();
      final isActive = now.isAfter(startLocal) && now.isBefore(endLocal);

      bool isDismissed = false;

      // 1. Check strict cooldown (Robust anti-loop)
      if (_recentlyDismissedIds.containsKey(event.id)) {
        final dismissedAt = _recentlyDismissedIds[event.id]!;
        if (now.difference(dismissedAt).inMinutes < 2) {
          // If dismissed less than 2 minutes ago, consider it dismissed regardless of start time string matching
          isDismissed = true;
          // print("DEBUG: Event ${event.id} suppressed by cooldown.");
        }
      }

      // 2. Check legacy Start Time matching (if cooldown passed or not present)
      if (!isDismissed && _dismissedEventStartTimes.containsKey(event.id)) {
        // Compare using toLocal() to ensure consistency with _triggerEvent which converts to local
        if (_dismissedEventStartTimes[event.id] ==
            event.startTime.toLocal().toIso8601String()) {
          isDismissed = true;
        }
      }

      if (isActive && !isDismissed) {
        if (bestEventToTrigger == null) {
          bestEventToTrigger = event;
        } else {
          // 1. Prefer Closer Start Time (Newest)
          if (startLocal.isAfter(bestEventToTrigger!.startTime.toLocal())) {
            bestEventToTrigger = event;
          }
          // 2. Same Start Time? Check Global Priority
          else if (startLocal.isAtSameMomentAs(
            bestEventToTrigger!.startTime.toLocal(),
          )) {
            final userService = UserService();
            bool preferGlobal = userService.globalPriority;
            bool currentIsGlobal = event.type == EventType.global;
            bool bestIsGlobal = bestEventToTrigger!.type == EventType.global;

            if (preferGlobal) {
              // If we prefer global, and current IS global but best IS NOT, switch to current
              if (currentIsGlobal && !bestIsGlobal) {
                bestEventToTrigger = event;
              }
            } else {
              // If we prefer national (not global), and current IS NOT global (National) but best IS global, switch to current
              if (!currentIsGlobal && bestIsGlobal) {
                bestEventToTrigger = event;
              }
            }
          }
        }
      }
    }

    if (bestEventToTrigger != null) {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      final isResumed = lifecycleState == AppLifecycleState.resumed;

      // Do not auto-trigger regular timeline playback while the app is in the
      // background. Backgrounded playback can lose the video surface and
      // degrade into audio-only. Alarm-launch playback still uses the pending
      // alarm path above.
      if (!_isAppInForeground || !isResumed) {
        print(
          'HARMONY_STRICT_V3: Skipping background auto-trigger for ${bestEventToTrigger.id}',
        );
        return;
      }

      // ABSOLUTE STRICT CHECK: If this exact ID is active, DO NOTHING.
      if (_isEventActive && _currentEventId == bestEventToTrigger.id) {
        print(
          "HARMONY_STRICT_V3: Event ${bestEventToTrigger.id} is already playing. IGNORING.",
        );
        return;
      }

      // While one event is active, do not switch to another event in the same
      // slot window. This prevents duplicate/retrigger loops from stale docs.
      if (_isEventActive) {
        print(
          "HARMONY_STRICT_V3: event already active ($_currentEventId), skipping retrigger for ${bestEventToTrigger.id}",
        );
        return;
      }

      print(
        "HARMONY_STRICT_V3: Selecting New Event: ${bestEventToTrigger.title} (${bestEventToTrigger.id})",
      );

      _triggerEvent(
        id: bestEventToTrigger.id,
        title: bestEventToTrigger.title,
        description: bestEventToTrigger.description,
        isWorldwide: bestEventToTrigger.type == EventType.global,
        mediaUrl: _selectPlaybackMedia(bestEventToTrigger),
        intent: bestEventToTrigger.mostPopularIntent,
        fromAlarmLaunch: false,
        startTime: bestEventToTrigger.startTime.toLocal(),
        // We do NOT pass endTime to trigger anymore to avoid confusion. Logic is purely duration based.
        // endTime: bestEventToTrigger.endTime.toLocal(),
        durationSeconds: bestEventToTrigger.durationSeconds,
      );
    }
  }

  void _triggerEvent({
    String? id,
    required String title,
    required String description,
    required bool isWorldwide,
    String? mediaUrl,
    String? intent,
    bool fromAlarmLaunch = false,
    DateTime? startTime,
    // DateTime? endTime, // REMOVED to prevent accidental usage
    int? durationSeconds,
  }) {
    final effectiveFromAlarmLaunch =
        fromAlarmLaunch || (id != null && id == _lastKnownAlarmLaunchEventId);

    if (!effectiveFromAlarmLaunch) {
      final lifecycleState = WidgetsBinding.instance.lifecycleState;
      if (lifecycleState != AppLifecycleState.resumed) {
        print(
          "HARMONY_STRICT_V3: blocked non-alarm trigger while lifecycle=$lifecycleState for id=${id ?? 'unknown'}",
        );
        return;
      }
    }

    print(
      "HARMONY_STRICT_V3: Triggering Event '$title' with Duration: $durationSeconds",
    );

    _alarmLaunchTransitionTimer?.cancel();
    _isAlarmLaunchTransitionActive = false;

    _isEventActive = true;
    _currentEventId = id;
    NotificationService().cancelNotificationForEvent(id);
    _currentEventStartTime = startTime;
    _currentEventEndTime =
        null; // Explicitly nullify this. use STRICT timer only.
    _currentEventTitle = title;

    if (description.isEmpty &&
        intent != null &&
        intent.isNotEmpty &&
        intent != 'Intent') {
      _currentEventDescription = intent;
    } else {
      _currentEventDescription = description.isNotEmpty
          ? description
          : 'Join us for a moment of shared intention...';
    }

    _isWorldwide = isWorldwide;
    _currentEventMediaUrl = mediaUrl;
    _currentEventFromAlarmLaunch = effectiveFromAlarmLaunch;

    if (effectiveFromAlarmLaunch && id != null) {
      print('HARMONY_ALARM: trigger marked as alarm launch for id=$id');
    }

    // Async verify: ask native for the last alarm-launched event ID.
    // Native now returns this as a one-shot consume token to avoid stale IDs
    // leaking into later foreground events.
    if (!effectiveFromAlarmLaunch && id != null) {
      final checkId = id;
      _dormantAlarmChannel
          .invokeMethod<String>('get_last_alarm_launched_event_id')
          .then((nativeId) {
            if (nativeId != null &&
                nativeId.isNotEmpty &&
                nativeId == checkId &&
                _currentEventId == checkId) {
              _currentEventFromAlarmLaunch = true;
              _lastKnownAlarmLaunchEventId = nativeId;
              print(
                'HARMONY_ALARM: async alarm launch verified for $checkId (native=$nativeId)',
              );
            }
          })
          .catchError((_) {});
    }

    _dismissTimer?.cancel();

    // STRICT TIME ENFORCEMENT V3
    // NO FALLBACKS. NO CALCULATIONS. NO "WINDOW".
    int finalSeconds = durationSeconds ?? 10;
    // Allow short durations if user specifically requested (removed 5s floor)
    if (finalSeconds < 1) finalSeconds = 1;

    // Explicitly set the service-level End Time so checkForEvents knows when to stop it.
    // This is crucial for the watchdog loop.
    if (_currentEventStartTime != null) {
      _currentEventEndTime = _currentEventStartTime!.add(
        Duration(seconds: finalSeconds),
      );
    } else {
      // Fallback if start time missing (unlikely)
      _currentEventEndTime = DateTime.now().add(
        Duration(seconds: finalSeconds),
      );
    }

    print("HARMONY_STRICT_V3: Setting Hard Timer for $finalSeconds seconds");

    _dismissTimer = Timer(Duration(seconds: finalSeconds), () {
      print("HARMONY_STRICT_V3: Timer Expired ($finalSeconds s). Dismissing.");
      dismissEvent();
    });

    notifyListeners();
  }

  void dismissEvent() {
    print(
      "DEBUG: dismissEvent called for ID: $_currentEventId [restore-v3-sync]",
    );
    final currentEventId = _currentEventId;
    bool shouldRestoreLockscreen = _currentEventFromAlarmLaunch;

    // Always attempt to cancel any matching alarm notification on dismiss.
    NotificationService().cancelNotificationForEvent(currentEventId);

    // Sync fallback: compare against the last known alarm launch id captured earlier.
    if (!shouldRestoreLockscreen && currentEventId != null) {
      final lastAlarmEventId = _lastKnownAlarmLaunchEventId;
      if (lastAlarmEventId != null && lastAlarmEventId.isNotEmpty) {
        shouldRestoreLockscreen = lastAlarmEventId == currentEventId;
        print(
          'HARMONY_ALARM: dismiss cached launch id check lastAlarmId=$lastAlarmEventId current=$currentEventId => restore=$shouldRestoreLockscreen',
        );
      }
    }

    print(
      'HARMONY_ALARM: dismiss restore decision id=$currentEventId fromAlarm=$_currentEventFromAlarmLaunch => restore=$shouldRestoreLockscreen',
    );
    _dismissTimer?.cancel();
    _dismissTimer = null;

    if (_currentEventId != null && _currentEventStartTime != null) {
      // Use stored start time which is reliable, instead of lookup
      _dismissedEventStartTimes[_currentEventId!] = _currentEventStartTime!
          .toIso8601String();
      // Add to cooldown map
      _recentlyDismissedIds[_currentEventId!] = DateTime.now();
      print(
        "DEBUG: Marked $_currentEventId as dismissed for time: ${_currentEventStartTime!.toIso8601String()}",
      );
    } else if (_currentEventId != null) {
      // Fallback if start time wasn't captured (legacy support)
      try {
        final event = _events.firstWhere((e) => e.id == _currentEventId);
        _dismissedEventStartTimes[_currentEventId!] = event.startTime
            .toIso8601String();
        // Add to cooldown map
        _recentlyDismissedIds[_currentEventId!] = DateTime.now();
        print(
          "DEBUG: (Fallback) Marked $_currentEventId as dismissed from lookup",
        );
      } catch (e) {
        print("DEBUG: Could not mark event dismissed (not found in list): $e");
      }
    }

    _isEventActive = false;
    _currentEventMediaUrl = null;
    _currentEventId = null;
    _currentEventEndTime = null;
    _currentEventStartTime = null;
    _currentEventFromAlarmLaunch = false;

    // Alarm launch IDs are one-shot markers. Clear after dismiss when consumed,
    // so foreground/non-alarm playback of later events doesn't inherit restore behavior.
    if (currentEventId != null &&
        _lastKnownAlarmLaunchEventId == currentEventId) {
      _lastKnownAlarmLaunchEventId = null;
    }

    if (shouldRestoreLockscreen) {
      _alarmLaunchTransitionTimer?.cancel();
      _isAlarmLaunchTransitionActive = true;
      print('HARMONY_ALARM: requesting post-event lockscreen restore (v2)');
      NotificationService().restoreLockscreenPresentation();

      _alarmLaunchTransitionTimer = Timer(
        const Duration(milliseconds: 700),
        () {
          if (!_isEventActive && _isAlarmLaunchTransitionActive) {
            _isAlarmLaunchTransitionActive = false;
            notifyListeners();
          }
        },
      );
    } else {
      _alarmLaunchTransitionTimer?.cancel();
      _isAlarmLaunchTransitionActive = false;
    }

    notifyListeners();
  }

  Future<void> _checkNativeLaunchPayloadIfAny() async {
    if (_nativeLaunchPayloadCheckInFlight) return;
    _nativeLaunchPayloadCheckInFlight = true;

    try {
      final payload = await NotificationService().consumeLaunchPayload();
      String? eventId;
      bool autoPlayVideo = false;

      final eventIdRaw = payload['event_id'];
      if (eventIdRaw is String && eventIdRaw.trim().isNotEmpty) {
        eventId = eventIdRaw.trim();
      }
      autoPlayVideo = payload['auto_play_video'] == true;

      if (eventId == null) {
        eventId = await NotificationService().consumeLaunchEventId();
      }

      if (eventId == null || eventId.isEmpty) {
        return;
      }

      _lastKnownAlarmLaunchEventId = eventId;

      // If event already started by scheduler path, upgrade it so dismiss uses alarm restore.
      if (_isEventActive && _currentEventId == eventId) {
        _currentEventFromAlarmLaunch = true;
        print(
          'HARMONY_ALARM: upgraded active event to alarm launch for $eventId',
        );
        return;
      }

      requestImmediateAlarmPlayback(eventId, forceVideo: autoPlayVideo);
    } catch (e) {
      print('HARMONY_ALARM: live launch payload consume failed: $e');
    } finally {
      _nativeLaunchPayloadCheckInFlight = false;
    }
  }

  void triggerEventFromModel(
    String title,
    String description,
    bool isWorldwide, {
    String? mediaUrl,
    String? intent,
  }) {
    _triggerEvent(
      title: title,
      description: description,
      isWorldwide: isWorldwide,
      mediaUrl: mediaUrl,
      intent: intent,
    );
  }

  String? _selectPlaybackMedia(Event event) {
    final userService = UserService();
    final mode = userService.playbackModeFor(event.startTime.toLocal());

    if (mode == PlaybackMode.audio) {
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

  String? _selectPlaybackMediaForForcedVideo(Event event) {
    if (event.visualUrl != null && event.visualUrl!.isNotEmpty) {
      return event.visualUrl;
    }

    if (!_isAudioUrl(event.mediaUrl)) {
      return event.mediaUrl;
    }

    return event.soundUrl ?? event.mediaUrl;
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
