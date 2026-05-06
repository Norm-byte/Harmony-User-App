import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

enum PlaybackMode { video, audio }

class UserService extends ChangeNotifier {
  static const String _dormantPlaybackEnabledKey = 'dormant_playback_enabled';
  static const String _dormantPlaybackPreferenceSetKey =
      'dormant_playback_preference_set';

  // Singleton instance
  static final UserService _instance = UserService._internal();
  factory UserService() => _instance;
  UserService._internal() {
    _loadSettings();
  }

  // User Data
  String _userId = '';
  String _userName = 'Guest';
  String? _userPhoto; // URL or null
  String _timeZone = 'Unknown';

  String get userId => _userId;
  String get userName => _userName;
  String? get userPhoto => _userPhoto;
  String get timeZone => _timeZone;

  // Settings
  double _eventVolume = 1.0;
  bool _globalPriority = true; // Added for Global Priority
  bool _autoJoinWorldwide = true; // New Auto-Join setting (Default ON)
  bool _dormantPlaybackEnabled = true;
  bool _settingsLoaded = false;
  Timer? _presenceHeartbeatTimer;
  // 0 = video (active), 1 = audio (active), 2 = off
  List<List<int>> _hourlyChimes = List.generate(
    24,
    (_) => [0, 0, 0, 0],
  );

  List<String> _blockedUsers = []; // Local block list

  double get eventVolume => _eventVolume;
  bool get globalPriority => _globalPriority;
  bool get autoJoinWorldwide => _autoJoinWorldwide;
  bool get dormantPlaybackEnabled => _dormantPlaybackEnabled;
  bool get settingsLoaded => _settingsLoaded;
  List<List<int>> get hourlyChimes => _hourlyChimes;
  List<String> get blockedUsers => _blockedUsers;

  /// Returns the playback mode for the slot matching [dt].
  PlaybackMode playbackModeFor(DateTime dt) {
    final slotIndex = _slotIndexForMinute(dt.minute);
    if (slotIndex == null) return PlaybackMode.video;
    final state = _hourlyChimes[dt.hour][slotIndex];
    return state == 1 ? PlaybackMode.audio : PlaybackMode.video;
  }

  /// Returns the current state for a slot: 0=video, 1=audio, 2=off.
  int getChimeSlotState(int hourIndex, int slotIndex) {
    if (hourIndex < 0 || hourIndex >= 24 || slotIndex < 0 || slotIndex >= 4) {
      return 0;
    }
    return _hourlyChimes[hourIndex][slotIndex];
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _eventVolume = prefs.getDouble('event_volume') ?? 1.0;
    _globalPriority = prefs.getBool('global_priority') ?? true; // Load priority
    _autoJoinWorldwide =
        prefs.getBool('auto_join_worldwide') ??
        true; // Load Auto-Join (Default ON)
    final dormantPlaybackPreferenceSet =
        prefs.getBool(_dormantPlaybackPreferenceSetKey) ?? false;
    if (dormantPlaybackPreferenceSet) {
      _dormantPlaybackEnabled =
          prefs.getBool(_dormantPlaybackEnabledKey) ?? true;
    } else {
      _dormantPlaybackEnabled = true;
      await prefs.setBool(_dormantPlaybackEnabledKey, true);
    }
    _blockedUsers = prefs.getStringList('blocked_users') ?? [];

    final savedChimes = prefs.getString('hourly_chimes_matrix');
    if (savedChimes != null) {
      try {
        final List<dynamic> decoded = jsonDecode(savedChimes);
        _hourlyChimes = decoded.map<List<int>>((row) {
          return (row as List).map<int>((val) {
            if (val is bool) return val ? 0 : 2; // migrate old bool format
            return (val as num).toInt();
          }).toList();
        }).toList();
      } catch (e) {
        debugPrint('Error loading hourly chimes: $e');
      }
    }

    // Prefer Firebase Auth UID as the user identity.
    // Fall back to a locally-generated ID only if not signed in.
    final firebaseUser = FirebaseAuth.instance.currentUser;
    if (firebaseUser != null) {
      _userId = firebaseUser.uid;
      _userName = sanitizePublicDisplayName(
        prefs.getString('user_name') ?? firebaseUser.displayName ?? 'Member',
      );
    } else {
      // Generate a persistent anonymous ID for this installation if not found
      if (!prefs.containsKey('user_id')) {
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final random = Random().nextInt(10000);
        final newId = 'user_${timestamp}_$random';
        await prefs.setString('user_id', newId);
      }
      _userId = prefs.getString('user_id')!;
      _userName = sanitizePublicDisplayName(prefs.getString('user_name') ?? 'Guest');

      // FORCE RESET if ID is "Super Admin" (Debug Cleanup)
      if (_userId == 'Super Admin' || _userId.contains(' ')) {
        debugPrint(
          "HARMONY_DEBUG: Detected invalid ID '$_userId'. Resetting identity...",
        );
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final random = Random().nextInt(10000);
        _userId = 'user_${timestamp}_$random';
        await prefs.setString('user_id', _userId);
        await prefs.setString('user_name', 'Guest');
        _userName = 'Guest';
        debugPrint("HARMONY_DEBUG: New Identity: $_userId");
      }
    }

    // Detect Time Zone
    final now = DateTime.now();
    _timeZone = now.timeZoneName;
    _settingsLoaded = true;

    notifyListeners();

    // Sync to Firestore
    _syncUserToFirestore();
    _startPresenceHeartbeat();

    // If a persisted session skipped login hydration, recover a valid
    // public username from Firestore/auth before chat gates run.
    unawaited(_repairDisplayNameIfNeeded());
  }

  Future<void> _repairDisplayNameIfNeeded() async {
    if (isRecognizedPublicDisplayName(_userName)) {
      return;
    }

    final recoveredName = await ensureRecognizedPublicDisplayName();
    if (recoveredName != null) {
      debugPrint('HARMONY_IDENTITY: recovered display name=$recoveredName');
    } else {
      debugPrint('HARMONY_IDENTITY: could not recover a recognized display name');
    }
  }

  void _startPresenceHeartbeat() {
    _presenceHeartbeatTimer?.cancel();
    _presenceHeartbeatTimer = Timer.periodic(const Duration(hours: 1), (_) {
      _syncUserToFirestore();
    });
  }

  Future<void> _syncUserToFirestore() async {
    try {
      final now = DateTime.now();
      await FirebaseFirestore.instance.collection('users').doc(_userId).set({
        'name': _userName,
        'lastActive': FieldValue.serverTimestamp(),
        'timeZone': _timeZone,
        'timeZoneOffset': now.timeZoneOffset.inHours,
        'platform': defaultTargetPlatform.toString(),
        'autoJoinWorldwide': _autoJoinWorldwide,
        'dormantPlaybackEnabled': _dormantPlaybackEnabled,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error syncing user to Firestore: $e');
    }
  }

  Future<void> setUser(String id, String name) async {
    _userId = id;
    _userName = sanitizePublicDisplayName(name);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', id);
    await prefs.setString('user_name', _userName);
    _syncUserToFirestore();
  }

  static String sanitizePublicDisplayName(String? rawName) {
    final input = (rawName ?? '').trim();
    if (input.isEmpty) return 'Member';

    var sanitized = input;
    final atIndex = sanitized.indexOf('@');
    if (atIndex > 0) {
      sanitized = sanitized.substring(0, atIndex);
    }

    sanitized = sanitized.replaceAll(RegExp(r'[^A-Za-z0-9_. -]'), '').trim();
    sanitized = sanitized.replaceAll(RegExp(r'\s+'), ' ');

    if (sanitized.isEmpty) return 'Member';
    if (sanitized.length > 24) {
      sanitized = sanitized.substring(0, 24).trim();
    }
    return sanitized;
  }

  static bool isRecognizedPublicDisplayName(String? rawName) {
    final sanitized = sanitizePublicDisplayName(rawName);
    final normalized = sanitized.trim().toLowerCase();
    return normalized.isNotEmpty && normalized != 'member' && normalized != 'guest';
  }

  Future<String?> ensureRecognizedPublicDisplayName() async {
    final current = sanitizePublicDisplayName(_userName);

    final firebaseUser = FirebaseAuth.instance.currentUser;
    final emailPrefix = (firebaseUser?.email?.contains('@') == true)
        ? firebaseUser!.email!.split('@').first.trim()
        : null;
    final currentLooksLikeEmailPrefix =
        emailPrefix != null &&
        current.toLowerCase() == sanitizePublicDisplayName(emailPrefix).toLowerCase();

    if (isRecognizedPublicDisplayName(current) && !currentLooksLikeEmailPrefix) {
      return current;
    }

    final effectiveUid = _userId.isNotEmpty ? _userId : (firebaseUser?.uid ?? '');
    if (effectiveUid.isEmpty) {
      return null;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(effectiveUid)
          .get();
      final userData = userDoc.data();
      if (userData?['isSuperAdmin'] == true) {
        const fallbackAdminName = 'Admin 1';
        await setUser(effectiveUid, fallbackAdminName);
        return fallbackAdminName;
      }
        final docEmailPrefix = (userData?['email'] as String?)?.contains('@') == true
          ? (userData!['email'] as String).split('@').first.trim()
          : emailPrefix;

      final candidates = <String?>[
        userData?['username'] as String?,
        userData?['userName'] as String?,
        userData?['name'] as String?,
        userData?['displayName'] as String?,
        firebaseUser?.displayName,
      ];

      for (final candidate in candidates) {
        final sanitized = sanitizePublicDisplayName(candidate);
        if (isRecognizedPublicDisplayName(sanitized)) {
          await setUser(effectiveUid, sanitized);
          return sanitized;
        }
      }

      final sanitizedEmail = sanitizePublicDisplayName(docEmailPrefix);
      if (isRecognizedPublicDisplayName(sanitizedEmail)) {
        await setUser(effectiveUid, sanitizedEmail);
        return sanitizedEmail;
      }
    } catch (e) {
      debugPrint('HARMONY_IDENTITY: failed to recover display name: $e');
    }

    return null;
  }

  Future<void> clearUser() async {
    _userId = '';
    _userName = 'Guest';
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('user_id');
    await prefs.remove('user_name');
  }

  Future<void> setEventVolume(double volume) async {
    _eventVolume = volume;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('event_volume', volume);
  }

  Future<void> setGlobalPriority(bool enabled) async {
    _globalPriority = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('global_priority', enabled);
  }

  Future<void> setAutoJoinWorldwide(bool enabled) async {
    _autoJoinWorldwide = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('auto_join_worldwide', enabled);
    _syncUserToFirestore();
  }

  Future<void> setDormantPlaybackEnabled(bool enabled) async {
    _dormantPlaybackEnabled = enabled;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_dormantPlaybackEnabledKey, enabled);
    await prefs.setBool(_dormantPlaybackPreferenceSetKey, true);
    _syncUserToFirestore();
  }

  Future<void> cycleChimeSlot(int hourIndex, int slotIndex) async {
    if (hourIndex < 0 || hourIndex >= 24 || slotIndex < 0 || slotIndex >= 4) {
      return;
    }
    // Cycle: 0 (video) → 1 (audio) → 2 (off) → 0 (video)
    _hourlyChimes[hourIndex][slotIndex] =
        (_hourlyChimes[hourIndex][slotIndex] + 1) % 3;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('hourly_chimes_matrix', jsonEncode(_hourlyChimes));
  }

  bool isChimeEnabledFor(DateTime dateTime) {
    final slotIndex = _slotIndexForMinute(dateTime.minute);
    if (slotIndex == null) return true;
    return _hourlyChimes[dateTime.hour][slotIndex] != 2;
  }

  int? _slotIndexForMinute(int minute) {
    switch (minute) {
      case 0:
        return 0;
      case 15:
        return 1;
      case 30:
        return 2;
      case 45:
        return 3;
      default:
        return null;
    }
  }

  Future<void> blockUser(String userId) async {
    if (!_blockedUsers.contains(userId)) {
      _blockedUsers.add(userId);
      notifyListeners();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList('blocked_users', _blockedUsers);
      debugPrint("HARMONY_BLOCK: Blocked user $userId");
    }
  }

  Future<void> reportContent(
    String reportedUserId,
    String content,
    String reason,
    String context,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('moderation_queue').add({
        'reporterId': _userId,
        'reportedUserId': reportedUserId,
        'content': content,
        'reason': reason,
        'context': context, // e.g., "Chat Room (Event X)"
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'pending',
      });
      debugPrint("HARMONY_REPORT: Report sent successfully.");
    } catch (e) {
      debugPrint("HARMONY_REPORT_ERROR: $e");
    }
  }
}
