import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:math';

class UserService extends ChangeNotifier {
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

  double get eventVolume => _eventVolume;
  bool get globalPriority => _globalPriority;
  bool get autoJoinWorldwide => _autoJoinWorldwide;

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _eventVolume = prefs.getDouble('event_volume') ?? 1.0;
    _globalPriority = prefs.getBool('global_priority') ?? true; // Load priority
    _autoJoinWorldwide = prefs.getBool('auto_join_worldwide') ?? true; // Load Auto-Join (Default ON)
    
    // Generate a persistent ID for this installation if not found
    if (!prefs.containsKey('user_id')) {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = Random().nextInt(10000);
      final newId = 'user_${timestamp}_$random';
      await prefs.setString('user_id', newId);
    }
    
    _userId = prefs.getString('user_id')!; // Safe bang operator as we just ensured it exists
    _userName = prefs.getString('user_name') ?? 'Guest';
    
    // FORCE RESET if ID is "Super Admin" (Debug Cleanup)
    if (_userId == 'Super Admin' || _userId.contains(' ')) {
      debugPrint("HARMONY_DEBUG: Detected invalid ID '$_userId'. Resetting identity...");
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final random = Random().nextInt(10000);
      _userId = 'user_${timestamp}_$random';
      await prefs.setString('user_id', _userId);
      await prefs.setString('user_name', 'Guest');
      _userName = 'Guest';
      debugPrint("HARMONY_DEBUG: New Identity: $_userId");
    }

    // Detect Time Zone
    final now = DateTime.now();
    _timeZone = now.timeZoneName;
    
    notifyListeners();
    
    // Sync to Firestore
    _syncUserToFirestore();
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
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error syncing user to Firestore: $e');
    }
  }

  Future<void> setUser(String id, String name) async {
    _userId = id;
    _userName = name;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('user_id', id);
    await prefs.setString('user_name', name);
    _syncUserToFirestore();
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
}
