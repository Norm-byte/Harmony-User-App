import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'user_service.dart';

class GroupService extends ChangeNotifier {
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> get myGroups => _myGroups;
  String? _currentListenedUserId;

  GroupService() {
    debugPrint('GroupService: Initializing...');
    _init();
  }

  void _init() {
    // Use UserService instead of FirebaseAuth
    final userService = UserService();
    
    // Initial check
    if (userService.userId.isNotEmpty) {
       _listenToGroups(userService.userId);
    }
    
    // Listen for changes
    userService.addListener(() {
        if (userService.userId.isNotEmpty && userService.userId != _currentListenedUserId) {
           debugPrint('GroupService: ID changed to ${userService.userId}');
           _listenToGroups(userService.userId);
        }
    });
  }

  void _listenToGroups(String userId) {
    if (userId.isEmpty) return;
    _currentListenedUserId = userId;

    FirebaseFirestore.instance
        .collection('users')
        .doc(userId)
        .collection('joined_groups')
        .snapshots()
        .listen((snapshot) {
      _myGroups = snapshot.docs.map((doc) {
         final data = doc.data();
         // Ensure ID is passed for consistency
         data['id'] = doc.id; 
         return data;
      }).toList();
      
      debugPrint('GroupService: Loaded ${_myGroups.length} groups for user $userId');
      notifyListeners();
    }, onError: (e) {
      debugPrint('GroupService: Error listening to groups: $e');
    });
  }

  Future<void> joinGroup(Map<String, dynamic> group) async {
    final userId = UserService().userId;
    if (userId.isEmpty) {
      debugPrint('GroupService: No UserService ID found. Cannot join.');
      return;
    }

    // Check if group has an ID. If not, generate one from the name (fallback, though ID is preferred)
    final String groupId = group['id'] ?? group['name'].toString().toLowerCase().replaceAll(' ', '_');
    final String name = group['name'];

    if (isJoined(name)) { // Still check by name or ID to avoid duplicates in UI
      debugPrint('GroupService: Already joined $name, skipping.');
      return;
    }

    // Prepare data for Firestore
    final newGroup = Map<String, dynamic>.from(group);
    
    // Ensure ID is set in the data
    newGroup['id'] = groupId;

    // Handle IconData serialization
    if (newGroup['icon'] is IconData) {
       newGroup['iconCode'] = (newGroup['icon'] as IconData).codePoint;
       newGroup.remove('icon');
    }

    // Handle Color serialization
    if (newGroup['color'] is Color) {
       newGroup['colorValue'] = (newGroup['color'] as Color).value;
       newGroup.remove('color');
    }
    
    // Add join timestamp
    newGroup['joinedAt'] = FieldValue.serverTimestamp();

    try {
      // Use set with merge to be safe
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('joined_groups')
          .doc(groupId)
          .set(newGroup, SetOptions(merge: true));

      debugPrint('GroupService: Added $name to Firestore for user $userId');

      // Update global member count in Firestore
      await FirebaseFirestore.instance
            .collection('community_groups')
            .doc(groupId)
            .update({'memberCount': FieldValue.increment(1)});

    } catch (e) {
      debugPrint('GroupService: Error joining group: $e');
    }
  }

  Future<void> leaveGroup(String groupName) async {
    final userId = UserService().userId;
    if (userId.isEmpty) return;

    // Find the group object to get its ID
    final groupToRemove = _myGroups.firstWhere(
      (g) => g['name'] == groupName, 
      orElse: () => {}
    );

    if (groupToRemove.isEmpty) {
      debugPrint('GroupService: Could not find group $groupName to leave.');
      return;
    }
    
    final String groupId = groupToRemove['id'];

    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(userId)
          .collection('joined_groups')
          .doc(groupId)
          .delete();
      
      debugPrint('GroupService: Removed $groupName from Firestore for user $userId');

      // Update global member count
      await FirebaseFirestore.instance
          .collection('community_groups')
          .doc(groupId)
          .update({'memberCount': FieldValue.increment(-1)});

    } catch (e) {
      debugPrint('GroupService: Error leaving group: $e');
    }
  }

  bool isJoined(String groupName) {
    return _myGroups.any((g) => g['name'] == groupName);
  }
}
