import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

enum EventType { global, national }

class Event {
  final String id;
  final String title;
  final String description;
  final String? noticeBoardText;
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
  final int? noticeBoardVisibilityAfterMinutes;
  final int? noticeBoardShowBeforeMinutes;
  final String? recurrenceType; // 'None', 'Daily', 'Weekly', 'Monthly'
  final String? originTimeZone;
  final String? originTime; // 'HH:mm' for National events
  final String? soundUrl;
  final String? visualUrl;
  final String? mediaUrl; // Audio or Video URL for the event
  final String? noticeBoardBgImage; // Specific background for notice board
  final String?
  noticeBoardBgColor; // Specific background color for notice board
  final bool isPublished; // Added to filter drafts
  final int? durationSeconds; // Added for guaranteed playback duration

  Event({
    required this.id,
    required this.title,
    required this.description,
    this.noticeBoardText,
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
    this.noticeBoardVisibilityAfterMinutes,
    this.noticeBoardShowBeforeMinutes,
    this.recurrenceType,
    this.originTimeZone,
    this.originTime,
    this.soundUrl,
    this.visualUrl,
    this.mediaUrl,
    this.noticeBoardBgImage,
    this.noticeBoardBgColor,
    this.isPublished = true,
    this.durationSeconds,
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
      debugPrint("Error parsing startTime for event ${json['id']}: $e");
    }

    DateTime end = start.add(const Duration(hours: 1));
    int? durationSecs; // Store locally to pass to constructor

    // ALWAYS try to parse durationSeconds independent of endTime
    if (json['durationSeconds'] != null) {
      durationSecs = json['durationSeconds'] is int
          ? json['durationSeconds'] as int
          : int.tryParse(json['durationSeconds'].toString());

      // Safety check: Ensure minimal reasonable duration if present
      if (durationSecs != null && durationSecs < 1) durationSecs = 1;
    }

    try {
      // 1. Duration takes PRIORITY for National Events (Scheduler) per user request.
      // If we have a duration, End Time = Start + Duration.
      if (durationSecs != null) {
        end = start.add(Duration(seconds: durationSecs));
      }
      // 2. Fallback to explicit endTime if no duration provided
      else if (json['endTime'] != null) {
        if (json['endTime'] is Timestamp) {
          end = (json['endTime'] as Timestamp).toDate();
        } else if (json['endTime'] is String) {
          end = DateTime.parse(json['endTime']);
        }
      } else {
        // Fallback: national slot docs with no stored duration default to
        // 1 hour so they survive the expiry window between publish and playback.
        durationSecs = 3600;
        end = start.add(const Duration(seconds: 3600));
      }
    } catch (e) {
      debugPrint("Error parsing endTime for event ${json['id']}: $e");
    }

    return Event(
      id: json['id'] ?? '',
      title: json['title'] ?? '',
      description: json['description'] ?? '',
      noticeBoardText: json['noticeBoardText'],
      startTime: start,
      endTime: end,
      durationSeconds:
          durationSecs, // Explicitly use the calculated/validated integer
      imageUrl:
          json['visualUrl'] ??
          json['imageUrl'] ??
          '', // Map visualUrl to imageUrl
      isOnline: json['isOnline'] ?? true,
      type: _parseEventType(json['type']),
      mostPopularIntent:
          json['intent'] ?? json['mostPopularIntent'], // Map intent
      learnMoreContent: json['learnMoreContent'],
      learnMoreYoutubeUrl: json['learnMoreYoutubeUrl'],
        participantCount: _asInt(json['participantCount']) ?? 0,
        visibilityAfterMinutes: _asInt(json['visibilityAfterMinutes']),
        showBeforeMinutes: _asInt(json['showBeforeMinutes']),
        noticeBoardVisibilityAfterMinutes:
          _asInt(json['noticeBoardVisibilityAfterMinutes']) ??
          _asInt(json['visibilityAfterMinutes']),
        noticeBoardShowBeforeMinutes:
          _asInt(json['noticeBoardShowBeforeMinutes']) ??
          _asInt(json['showBeforeMinutes']),
      recurrenceType: json['recurrenceType'],
      originTimeZone: json['originTimeZone'],
      originTime: json['originTime'],
      soundUrl: json['soundUrl'] ?? json['audioUrl'],
      visualUrl: json['visualUrl'],
      // Map visualUrl to mediaUrl if mediaUrl/audioUrl is missing, so video plays in overlay
      mediaUrl: json['mediaUrl'] ?? json['audioUrl'] ?? json['visualUrl'],
      noticeBoardBgImage: json['noticeBoardBgImage'],
      noticeBoardBgColor: json['noticeBoardBgColor'],
      // Be defensive: old/manual data may store booleans as strings or ints.
      // Only explicit false-like values should hide events.
      isPublished: _asBool(json['isPublished'], defaultValue: true),
    );
  }

  static bool _asBool(dynamic value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is num) return value != 0;
    if (value is String) {
      final lower = value.trim().toLowerCase();
      if (lower == 'true' || lower == '1' || lower == 'yes') return true;
      if (lower == 'false' || lower == '0' || lower == 'no') return false;
    }
    return defaultValue;
  }

  static int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  // Helper to create a copy with new times
  Event copyWith({DateTime? startTime, DateTime? endTime, EventType? type}) {
    return Event(
      id: id,
      title: title,
      description: description,
      noticeBoardText: noticeBoardText,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      imageUrl: imageUrl,
      isOnline: isOnline,
      type: type ?? this.type,
      mostPopularIntent: mostPopularIntent,
      learnMoreContent: learnMoreContent,
      learnMoreYoutubeUrl: learnMoreYoutubeUrl,
      participantCount: participantCount,
      visibilityAfterMinutes: visibilityAfterMinutes,
      showBeforeMinutes: showBeforeMinutes,
      noticeBoardVisibilityAfterMinutes: noticeBoardVisibilityAfterMinutes,
      noticeBoardShowBeforeMinutes: noticeBoardShowBeforeMinutes,
      recurrenceType: recurrenceType,
      originTimeZone: originTimeZone,
      originTime: originTime,
      soundUrl: soundUrl,
      visualUrl: visualUrl,
      mediaUrl: mediaUrl,
      noticeBoardBgImage: noticeBoardBgImage,
      noticeBoardBgColor: noticeBoardBgColor,
      isPublished: isPublished,
      durationSeconds: durationSeconds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'noticeBoardText': noticeBoardText,
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'durationSeconds': durationSeconds,
      'imageUrl': imageUrl,
      'isOnline': isOnline,
      'type': type.name, // 'global' or 'national'
      'isPublished': isPublished,
      'mostPopularIntent': mostPopularIntent,
      'learnMoreContent': learnMoreContent,
      'learnMoreYoutubeUrl': learnMoreYoutubeUrl,
      'participantCount': participantCount,
      'originTimeZone': originTimeZone,
      'visibilityAfterMinutes': visibilityAfterMinutes,
      'showBeforeMinutes': showBeforeMinutes,
      'noticeBoardVisibilityAfterMinutes': noticeBoardVisibilityAfterMinutes,
      'noticeBoardShowBeforeMinutes': noticeBoardShowBeforeMinutes,
      'recurrenceType': recurrenceType,
      'noticeBoardBgImage': noticeBoardBgImage,
      'noticeBoardBgColor': noticeBoardBgColor,
      'soundUrl': soundUrl,
      'visualUrl': visualUrl,
      'mediaUrl': mediaUrl,
      'originTime': originTime,
    };
  }

  static EventType _parseEventType(String? typeStr) {
    if (typeStr == 'national') {
      return EventType.national;
    }
    return EventType.global;
  }
}
