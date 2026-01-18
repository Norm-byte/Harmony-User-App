import 'package:cloud_firestore/cloud_firestore.dart';

enum EventType { global, national }

class Event {
  final String id;
  final String title;
  final String description;
  final DateTime startTime;
  final DateTime endTime;
  final String imageUrl;
  final bool isOnline;
  final EventType type;
  final String? mostPopularIntent; // Only for Global events
  final String? learnMoreContent; // Only for Global events
  final String? learnMoreYoutubeUrl; // Only for Global events
  final int participantCount;
  final int? visibilityAfterMinutes;
  final int? showBeforeMinutes;
  final String? recurrenceType; // 'None', 'Daily', 'Weekly', 'Monthly'
  final String? originTime; // 'HH:mm' for National events
  final String? mediaUrl; // Audio or Video URL for the event
  final String? noticeBoardBgImage; // Specific background for notice board
  final String? noticeBoardBgColor; // Specific background color for notice board
  final bool isPublished; // Added to filter drafts

  Event({
    required this.id,
    required this.title,
    required this.description,
    required this.startTime,
    required this.endTime,
    this.imageUrl = '',
    this.isOnline = true,
    this.type = EventType.global,
    this.mostPopularIntent,
    this.learnMoreContent,
    this.learnMoreYoutubeUrl,
    this.participantCount = 0,
    this.visibilityAfterMinutes,
    this.showBeforeMinutes,
    this.recurrenceType,
    this.originTime,
    this.mediaUrl,
    this.noticeBoardBgImage,
    this.noticeBoardBgColor,
    this.isPublished = true,
  });

  factory Event.fromJson(Map<String, dynamic> json) {
    // Handle Admin App's date format (ISO String or Firestore Timestamp)
    DateTime start = DateTime.now();
    
    try {
      if (json['startTimeUTC'] != null) {
        start = DateTime.parse(json['startTimeUTC']);
      } else if (json['startTime'] != null) {
        if (json['startTime'] is Timestamp) {
          start = (json['startTime'] as Timestamp).toDate();
        } else if (json['startTime'] is String) {
          start = DateTime.parse(json['startTime']);
        }
      }
    } catch (e) {
      print("Error parsing startTime for event ${json['id']}: $e");
    }

    DateTime end = start.add(const Duration(hours: 1));
    try {
      if (json['endTime'] != null) {
        if (json['endTime'] is Timestamp) {
          end = (json['endTime'] as Timestamp).toDate();
        } else if (json['endTime'] is String) {
          end = DateTime.parse(json['endTime']);
        }
      } else if (json['durationSeconds'] != null) {
        // Calculate endTime from durationSeconds if available
        int durationSecs = json['durationSeconds'] is int 
            ? json['durationSeconds'] as int 
            : int.tryParse(json['durationSeconds'].toString()) ?? 3600;
        
        // Safety check: Ensure minimum duration of 5 seconds (was 300)
        if (durationSecs < 5) durationSecs = 5;
            
        end = start.add(Duration(seconds: durationSecs));
      }
    } catch (e) {
      print("Error parsing endTime for event ${json['id']}: $e");
    }

    return Event(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      // Map noticeBoardText to description. Default to empty if missing.
      // We removed learnMoreContent fallback to avoid showing URLs/Markdown in the card.
      description: json['noticeBoardText'] ?? json['description'] ?? '',
      startTime: start,
      endTime: end,
      imageUrl: json['visualUrl'] ?? json['imageUrl'] ?? '', // Map visualUrl to imageUrl
      isOnline: json['isOnline'] ?? true,
      type: _parseEventType(json['type']),
      mostPopularIntent: json['intent'] ?? json['mostPopularIntent'], // Map intent
      learnMoreContent: json['learnMoreContent'],
      learnMoreYoutubeUrl: json['learnMoreYoutubeUrl'],
      participantCount: json['participantCount'] ?? 0,
      visibilityAfterMinutes: json['visibilityAfterMinutes'] ?? json['noticeBoardVisibilityAfterMinutes'], // Support both keys
      showBeforeMinutes: json['showBeforeMinutes'] ?? json['noticeBoardShowBeforeMinutes'],
      recurrenceType: json['recurrenceType'],
      originTime: json['originTime'],
      // Map visualUrl to mediaUrl if mediaUrl/audioUrl is missing, so video plays in overlay
      mediaUrl: json['mediaUrl'] ?? json['audioUrl'] ?? json['visualUrl'],
      noticeBoardBgImage: json['noticeBoardBgImage'],
      noticeBoardBgColor: json['noticeBoardBgColor'],
      isPublished: json['isPublished'] ?? true,
    );
  }

  // Helper to create a copy with new times
  Event copyWith({DateTime? startTime, DateTime? endTime}) {
    return Event(
      id: id,
      title: title,
      description: description,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      imageUrl: imageUrl,
      isOnline: isOnline,
      type: type,
      mostPopularIntent: mostPopularIntent,
      learnMoreContent: learnMoreContent,
      learnMoreYoutubeUrl: learnMoreYoutubeUrl,
      participantCount: participantCount,
      visibilityAfterMinutes: visibilityAfterMinutes,
      showBeforeMinutes: showBeforeMinutes,
      recurrenceType: recurrenceType,
      mediaUrl: mediaUrl,
      noticeBoardBgImage: noticeBoardBgImage,
      noticeBoardBgColor: noticeBoardBgColor,
      isPublished: isPublished,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'imageUrl': imageUrl,
      'isOnline': isOnline,
      'type': type.name, // 'global' or 'national'
      'mostPopularIntent': mostPopularIntent,
      'learnMoreContent': learnMoreContent,
      'learnMoreYoutubeUrl': learnMoreYoutubeUrl,
      'participantCount': participantCount,
      'noticeBoardBgImage': noticeBoardBgImage,
      'noticeBoardBgColor': noticeBoardBgColor,
      'mediaUrl': mediaUrl,
    };
  }

  static EventType _parseEventType(String? typeStr) {
    if (typeStr == 'national') {
      return EventType.national;
    }
    return EventType.global;
  }
}

