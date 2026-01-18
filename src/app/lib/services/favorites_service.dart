import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_service.dart';

class FavoritesService extends ChangeNotifier {
  List<Map<String, dynamic>> _favorites = [];
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  String get _userId => UserService().userId; // Use the singleton user ID

  List<Map<String, dynamic>> get favorites => List.unmodifiable(_favorites);

  FavoritesService() {
    _init();
  }

  void _init() {
    // Listen to Firestore changes for real-time updates
    _firestore
        .collection('users')
        .doc(_userId)
        .collection('favorites')
        .snapshots()
        .listen((snapshot) {
      debugPrint('FavoritesService: Fetched ${snapshot.docs.length} favorites for user $_userId');
      _favorites = snapshot.docs.map((doc) {
        final data = doc.data();
        // Ensure all values are strings or compatible types
        return data;
      }).toList();
      notifyListeners();
    }, onError: (e) {
      debugPrint('Error listening to favorites: $e');
      // Fallback to local if Firestore fails (optional, but good for offline)
      _loadLocalFavorites();
    });
  }

  Future<void> _loadLocalFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String? favoritesJson = prefs.getString('favorites');
    if (favoritesJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(favoritesJson);
        _favorites = decoded.map((item) => Map<String, dynamic>.from(item)).toList();
        notifyListeners();
      } catch (e) {
        debugPrint('Error loading local favorites: $e');
      }
    }
  }

  bool isFavorite(String url) {
    return _favorites.any((item) => item['youtubeUrl'] == url || item['url'] == url);
  }

  Future<void> toggleFavorite(Map<String, dynamic> topic) async {
    final url = topic['youtubeUrl'] ?? topic['url'];
    if (url == null || url.isEmpty) return;

    // Ensure consistency
    final data = Map<String, dynamic>.from(topic);
    if (!data.containsKey('youtubeUrl')) {
      data['youtubeUrl'] = url;
    }

    if (isFavorite(url)) {
      // Optimistic update: Remove locally first
      _favorites.removeWhere((item) => item['youtubeUrl'] == url || item['url'] == url);
      notifyListeners();
      _saveLocalFavorites();

      await removeFavorite(url);
    } else {
      // Optimistic update: Add locally first
      _favorites.add(data);
      notifyListeners();
      _saveLocalFavorites();

      await _addFavorite(data);
    }
  }

  Future<void> _saveLocalFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final String encoded = jsonEncode(_favorites);
    await prefs.setString('favorites', encoded);
  }

  Future<void> _addFavorite(Map<String, dynamic> data) async {
    try {
      await _firestore
          .collection('users')
          .doc(_userId)
          .collection('favorites')
          .add(data);
    } catch (e) {
      debugPrint("Error adding favorite: $e");
    }
  }

  Future<void> removeFavorite(String url) async {
    try {
      final snapshot = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('favorites')
          .where('youtubeUrl', isEqualTo: url)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }
      
      // Also check for 'url' field just in case
      final snapshot2 = await _firestore
          .collection('users')
          .doc(_userId)
          .collection('favorites')
          .where('url', isEqualTo: url)
          .get();
          
      for (var doc in snapshot2.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint("Error removing favorite: $e");
    }
  }
}
