import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/event.dart';
import 'user_service.dart';

class EventService extends ChangeNotifier {
  // Singleton pattern
  static final EventService _instance = EventService._internal();
  factory EventService() => _instance;
  EventService._internal() {
    _init();
  }

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  StreamSubscription? _eventsSubscription;
  StreamSubscription? _globalEventsSubscription;
  StreamSubscription? _myEventsSubscription;
  Timer? _timer;
  Timer? _dismissTimer; // Hard stop timer

  List<Event> _events = [];
  List<Event> _nationalEvents = [];
  List<Event> _globalEvents = [];
  List<Event> get events => _events;

  // My Events (History)
  List<Map<String, dynamic>> _myEvents = [];
  List<Map<String, dynamic>> get myEvents => _myEvents;

  bool _isEventActive = false;
  bool _isWorldwide = false;
  String _currentEventTitle = '';
  String _currentEventDescription = '';
  String? _currentEventMediaUrl;
  String? _currentEventId; // Track ID for dismissal logic
  DateTime? _currentEventEndTime; // Track End Time for auto-dismissal
  final Duration _eventGracePeriod = Duration.zero; // STRICT TIMER: No extra seconds allowed
  // Track dismissed events by ID and StartTime to allow re-triggering if time changes
  final Map<String, String> _dismissedEventStartTimes = {};

  bool get isEventActive => _isEventActive;
  bool get isWorldwide => _isWorldwide;
  String get currentEventTitle => _currentEventTitle;
  String get currentEventDescription => _currentEventDescription;
  String? get currentEventMediaUrl => _currentEventMediaUrl;

  // Shared User Intent State
  String _userIntent = '';
  String get userIntent => _userIntent;

  void setUserIntent(String intent) {
    _userIntent = intent;
    notifyListeners();
  }

  Future<String> joinEvent(String eventId, String eventTitle, String intent, EventType type, DateTime startTime, DateTime endTime, {int visibilityAfterMinutes = 0}) async {
    _userIntent = intent;
    notifyListeners();

    try {
      // Use UserService instead of FirebaseAuth
      final userId = UserService().userId;
      print("HARMONY_DEBUG: joinEvent called for user '$userId', event '$eventTitle'");

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
          'visibilityAfterMinutes': visibilityAfterMinutes, // Store visibility preference
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
       'Harmony', 'Peace', 'Love', 'Joy', 'Gratitude', 'Compassion', 'Faith', 'Trust', 
       'Mindfulness', 'Kindness', 'Hope', 'Freedom', 'Unity', 'Patience', 'Courage', 
       'Wisdom', 'Truth', 'Healing', 'Abundance', 'Clarity', 'Focus', 'Balance', 
       'Strength', 'Respect', 'Forgiveness', 'Acceptance', 'Presence'
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
        if (userService.userId.isNotEmpty && userService.userId != _currentListenedUserId) {
           print("HARMONY_DEBUG: UserService ID changed to ${userService.userId}");
           _listenToMyEvents(userService.userId);
        }
    });

    // Start periodic check - Check every 1 second for precision
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => checkForEvents());

    // Listen to National Events
    _eventsSubscription = _firestore
        .collection('events')
        .snapshots()
        .listen((snapshot) {
      _nationalDocs = snapshot.docs;
      _refreshEvents();
    }, onError: (e) {
      print("Error listening to national events: $e");
    });

    // Listen to Global Events
    _globalEventsSubscription = _firestore
        .collection('global_events')
        .snapshots()
        .listen((snapshot) {
      _globalDocs = snapshot.docs;
      _refreshEvents();
    }, onError: (e) {
      print("Error listening to global events: $e");
    });
  }

  void _listenToMyEvents(String userId) {
    if (userId.isEmpty) return;
    
    print("HARMONY_DEBUGGING: Starting stream for users/$userId/registered_events");
    _currentListenedUserId = userId; // Update tracker

    _myEventsSubscription?.cancel();
    _myEventsSubscription = _firestore
        .collection('users')
        .doc(userId)
        .collection('registered_events')
        // Removing orderBy temporarily to rule out Indexing/Null issues
        // .orderBy('timestamp', descending: true) 
        .snapshots()
        .listen((snapshot) {
      print("HARMONY_DEBUGGING: Received ${snapshot.docs.length} my_events docs for user $userId");
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
    }, onError: (e) {
      print("HARMONY_DEBUGGING: Error listening to my events: $e");
    });
  }

  void _refreshEvents() {
    _nationalEvents = _processDocs(_nationalDocs);
    _globalEvents = _processDocs(_globalDocs);
    _mergeEvents();
  }

  void _mergeEvents() {
    final oldEvents = [..._events];
    _events = [..._nationalEvents, ..._globalEvents];
    _events.sort((a, b) => a.startTime.compareTo(b.startTime));

    // Only notify if the list actually changed to avoid unnecessary rebuilds
    if (!_areEventListsEqual(oldEvents, _events)) {
      notifyListeners();
    }
  }

  bool _areEventListsEqual(List<Event> a, List<Event> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          a[i].startTime != b[i].startTime ||
          a[i].endTime != b[i].endTime) return false;
    }
    return true;
  }
  List<Event> _processDocs(List<QueryDocumentSnapshot> docs) {
    final now = DateTime.now();
    List<Event> processedEvents = [];

    for (var doc in docs) {
        try {
          final data = doc.data() as Map<String, dynamic>;
          data['id'] = doc.id;
          final event = Event.fromJson(data);

          // Filter out invalid events
          if (event.title.trim().isEmpty || event.title.length < 2) {
            continue;
          }

          if (!event.isPublished) {
            continue;
          }

          // Handle Recurrence
          Event displayEvent = event;

          if (event.type == EventType.national) {
            final localNow = DateTime.now();
            int hour = event.startTime.hour;
            int minute = event.startTime.minute;

            if (event.originTime != null && event.originTime!.contains(':')) {
              final parts = event.originTime!.split(':');
              if (parts.length == 2) {
                hour = int.tryParse(parts[0]) ?? hour;
                minute = int.tryParse(parts[1]) ?? minute;
              }
            }

            DateTime localStart = DateTime(
              localNow.year,
              localNow.month, 
              localNow.day,
              hour,
              minute
            );

            final duration = event.endTime.difference(event.startTime);
            DateTime localEnd = localStart.add(duration);

            if (localEnd.isBefore(localNow) && (event.recurrenceType == 'Daily' || event.recurrenceType == 'Weekly')) {
               if (event.recurrenceType == 'Daily') {
                  localStart = localStart.add(const Duration(days: 1));
                  localEnd = localStart.add(duration);
               }
            }

            displayEvent = event.copyWith(
              startTime: localStart,
              endTime: localEnd,
            );

          } else {
            if (event.recurrenceType != null && event.recurrenceType != 'None') {
              final duration = event.endTime.difference(event.startTime);
              final nextStart = _getNextOccurrence(event.startTime, event.recurrenceType!, duration);
              
              if (nextStart != event.startTime) {
                 displayEvent = event.copyWith(
                   startTime: nextStart,
                   endTime: nextStart.add(duration),
                 );
              }
            }
          }

          // 1. Check Visibility After Event
          final visibilityAfter = Duration(minutes: displayEvent.visibilityAfterMinutes ?? 0);
          final localEndTime = displayEvent.endTime.toLocal();

          if (now.isAfter(localEndTime.add(visibilityAfter))) {
            continue; // Too old
          }

          // 2. Check Show Before Event
          int defaultShowBefore = 60;
          final showBefore = Duration(minutes: displayEvent.showBeforeMinutes ?? defaultShowBefore);
          final localStartTime = displayEvent.startTime.toLocal();
          final showTime = localStartTime.subtract(showBefore);

          if (now.isBefore(showTime)) {
            continue; // Too early to show
          }

          processedEvents.add(displayEvent);
        } catch (e) {
          print("DEBUG: Error processing event doc ${doc.id}: $e");
        }
      }
      return processedEvents;
  }

  DateTime _getNextOccurrence(DateTime start, String recurrenceType, Duration duration) {
    final now = DateTime.now();
    if (start.add(duration).isAfter(now)) return start;

    DateTime next = start;
    while (next.add(duration).isBefore(now)) {
      switch (recurrenceType) {
        case 'Daily':
          next = next.add(const Duration(days: 1));
          break;
        case 'Weekly':
          next = next.add(const Duration(days: 7));
          break;
        case 'Monthly':
          next = DateTime(next.year, next.month + 1, next.day, next.hour, next.minute);
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
      DateTime.now().add(const Duration(minutes: 5))
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

    if (_isEventActive) {
      if (_currentEventEndTime != null && now.isAfter(_currentEventEndTime!.add(_eventGracePeriod))) {
          dismissEvent();
          return;
      }

      if (_currentEventId != null && _currentEventEndTime == null) {
        try {
          final currentEvent = _events.firstWhere((e) => e.id == _currentEventId);
          if (now.isAfter(currentEvent.endTime.toLocal().add(_eventGracePeriod))) {
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
      final startLocal = event.startTime.toLocal();
      final endLocal = event.endTime.toLocal();
      final isActive = now.isAfter(startLocal) && now.isBefore(endLocal);

      bool isDismissed = false;
      if (_dismissedEventStartTimes.containsKey(event.id)) {
        if (_dismissedEventStartTimes[event.id] == event.startTime.toIso8601String()) {
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
             else if (startLocal.isAtSameMomentAs(bestEventToTrigger!.startTime.toLocal())) {
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
         _triggerEvent(
           id: bestEventToTrigger.id,
           title: bestEventToTrigger.title,
           description: bestEventToTrigger.description,
           isWorldwide: bestEventToTrigger.type == EventType.global,
           mediaUrl: bestEventToTrigger.mediaUrl,
           intent: bestEventToTrigger.mostPopularIntent,
           endTime: bestEventToTrigger.endTime.toLocal(),
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
    DateTime? endTime,
  }) {
    // If the same event (by ID) is already active, check if we need to update the timer
    if (_isEventActive && _currentEventId == id) {
       // If the end time has changed significantly (e.g. updated duration), update the timer
       if (_currentEventEndTime != null && endTime != null && _currentEventEndTime != endTime) {
          // Fall through to update timer
          print("DEBUG: Updating active event timer. New End: $endTime");
       } else {
          return; // No change needed
       }
    } else if (_isEventActive && _currentEventTitle == title) {
       // If ID is different but Title is same (e.g. duplicates), we SHOULD strictly enforce the new event's params
       // So we DO NOT return here, we allow overwriting.
       print("DEBUG: Overwriting event with same title but different ID/Params");
    }

    print("DEBUG: Triggering Event: $title, Duration: ${endTime?.difference(DateTime.now()).inSeconds}s");

    _isEventActive = true;
    _currentEventId = id;
    _currentEventEndTime = endTime;
    _currentEventTitle = title;

    if (description.isEmpty && intent != null && intent.isNotEmpty && intent != 'Intent') {
       _currentEventDescription = intent;
    } else {
        _currentEventDescription = description.isNotEmpty ? description : 'Join us for a moment of shared intention...';
    }

    _isWorldwide = isWorldwide;
    _currentEventMediaUrl = mediaUrl;

    _dismissTimer?.cancel();
    if (endTime != null) {
      final now = DateTime.now();
      final duration = endTime.difference(now);
      
      // Add grace period to timer
      final timerDuration = duration + _eventGracePeriod;
      
      if (timerDuration > Duration.zero) {
        _dismissTimer = Timer(timerDuration, () {
          dismissEvent();
        });
      } else {
        dismissEvent();
        return;
      }
    }

    notifyListeners();
  }

  void dismissEvent() {
    _dismissTimer?.cancel();
    _dismissTimer = null;

    if (_currentEventId != null) {
      try {
        final event = _events.firstWhere((e) => e.id == _currentEventId);
        _dismissedEventStartTimes[_currentEventId!] = event.startTime.toIso8601String();
      } catch (_) {
      }
    }
    _isEventActive = false;
    _currentEventMediaUrl = null;
    _currentEventId = null;
    _currentEventEndTime = null;
    notifyListeners();
  }

  void triggerEventFromModel(String title, String description, bool isWorldwide, {String? mediaUrl, String? intent}) {
    _triggerEvent(title: title, description: description, isWorldwide: isWorldwide, mediaUrl: mediaUrl, intent: intent);
  }
}
