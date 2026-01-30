import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ProfanityService extends ChangeNotifier {
  static final ProfanityService _instance = ProfanityService._internal();
  factory ProfanityService() => _instance;
  ProfanityService._internal();

  final List<String> _forbiddenWords = [
    'fuck', 'shit', 'bitch', 'asshole', 'cunt', 'dick', 'pussy', 
    'bastard', 'whore', 'slut', 'faggot', 'nigger', 'spic', 'kike'
  ]; // Basic fallback list

  bool _isLoaded = false;

  Future<void> init() async {
    if (_isLoaded) return;
    
    try {
      print("ProfanityService: Initializing...");
      // Listen to the document where Admin saves the list
      FirebaseFirestore.instance
          .collection('system_settings')
          .doc('profanity_filter')
          .snapshots()
          .listen((snapshot) {
        if (snapshot.exists) {
          final data = snapshot.data();
          if (data != null && data.containsKey('words')) {
             final List<dynamic> loadedWords = data['words'];
             _forbiddenWords.clear();
             _forbiddenWords.addAll(loadedWords.map((e) => e.toString().toLowerCase()));
             print("ProfanityService: Loaded ${_forbiddenWords.length} words from Firestore.");
          }
        }
      });
      _isLoaded = true;
    } catch (e) {
      print("ProfanityService: Error initializing: $e");
    }
  }

  bool hasProfanity(String text) {
    // Normalize text: lowercase
    final normalized = text.toLowerCase();
    
    for (final word in _forbiddenWords) {
      // Check for exact word or word embedded? 
      // Simple containing check is safer but can have false positives (e.g. "scunthorpe")
      // User asked for "International Profanity Lists" so simple contains might be aggressive but 
      // safer for now given the user's focus on blocking "fuck".
      
      // Better approach: Regex word boundary
      // But standard lists often include compound words. 
      // For now, let's use a robust "word boundary" check if possible, or simple contains if specifically requested.
      // Given the user is testing "fuck" and it failed, let's stick to a basic checks first.
      
      // If the forbidden word is short (e.g. 3 chars), strictly use boundaries.
      // If long, maybe contains.
      
      // Let's go with word boundary regex for each forbidden word.
      // Escape the word first to avoid regex errors.
      
      try {
        final pattern = r'\b' + RegExp.escape(word) + r'\b';
        if (RegExp(pattern, caseSensitive: false).hasMatch(normalized)) {
          return true;
        }
      } catch (e) {
        // Fallback to simple contains if regex fails
        if (normalized.contains(word)) return true;
      }
    }
    return false;
  }
}
