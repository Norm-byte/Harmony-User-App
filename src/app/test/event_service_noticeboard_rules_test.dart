import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_user_app/models/event.dart';
import 'package:harmony_user_app/services/event_service.dart';

void main() {
  group('EventService noticeboard rules', () {
    Event buildNationalEvent({
      required DateTime startTime,
      required Duration duration,
      String? originTime,
      String? recurrenceType,
      int? noticeBoardShowBeforeMinutes,
      int? noticeBoardVisibilityAfterMinutes,
      int? visibilityAfterMinutes,
    }) {
      return Event(
        id: 'event-id',
        title: 'Test Slot',
        description: 'Test',
        type: EventType.national,
        startTime: startTime,
        endTime: startTime.add(duration),
        originTime: originTime,
        recurrenceType: recurrenceType,
        visibilityAfterMinutes: visibilityAfterMinutes,
        noticeBoardShowBeforeMinutes: noticeBoardShowBeforeMinutes,
        noticeBoardVisibilityAfterMinutes: noticeBoardVisibilityAfterMinutes,
        isPublished: true,
      );
    }

    Event buildThumbprint({String? visualUrl, String? mediaUrl, String? soundUrl}) {
      final start = DateTime(2026, 9, 26, 12, 0);
      return Event(
        id: 'thumbprint-id',
        title: '',
        description: '',
        startTime: start,
        endTime: start.add(const Duration(seconds: 14)),
        type: EventType.national,
        visualUrl: visualUrl,
        mediaUrl: mediaUrl,
        soundUrl: soundUrl,
        durationSeconds: 14,
        isThumbprintEvent: true,
      );
    }

    test('published gate requires explicit published=true and rejects drafts/legacy docs', () {
      expect(
        EventService.isPublishedForUserApp({'isPublished': true}, docId: 'slot_1815_20260428'),
        isTrue,
      );
      expect(
        EventService.isPublishedForUserApp({}, docId: 'slot_1815_20260428'),
        isFalse,
      );
      expect(
        EventService.isPublishedForUserApp({'isPublished': false}, docId: 'slot_1815_20260428'),
        isFalse,
      );
      expect(
        EventService.isPublishedForUserApp({'isDraft': true, 'isPublished': true}, docId: 'slot_1815_20260428'),
        isFalse,
      );
      expect(
        EventService.isPublishedForUserApp({'isPublished': true}, docId: 'draft_slot_1815_20260428'),
        isFalse,
      );
    });

    test('Thumbprint thank-you duration parses, clamps, and survives copyWith', () {
      final event = Event.fromJson({
        'id': 'thumbprint-test',
        'title': 'Test',
        'description': '',
        'startTimeUTC': '2026-09-25T20:00:00Z',
        'durationSeconds': 10,
        'isPublished': true,
        'isThumbprintEvent': true,
        'thankYouDisplaySeconds': 75,
      });

      expect(event.thankYouDisplaySeconds, 60);
      expect(event.copyWith().thankYouDisplaySeconds, 60);
      expect(
        Event.fromJson({
          'id': 'thumbprint-default',
          'title': 'Test',
          'description': '',
          'startTimeUTC': '2026-09-25T20:00:00Z',
          'durationSeconds': 10,
          'isPublished': true,
        }).thankYouDisplaySeconds,
        3,
      );
    });

    test('Thumbprint video mode selects visual media while audio remains separate', () {
      final event = buildThumbprint(
        visualUrl: 'https://example.com/background.mp4',
        mediaUrl: 'https://example.com/background.mp4',
        soundUrl: 'https://example.com/chime.mp3',
      );

      expect(
        EventService.resolveThumbprintVisualMedia(event, audioOnly: false),
        'https://example.com/background.mp4',
      );
    });

    test('Thumbprint audio-only mode suppresses visual media', () {
      final event = buildThumbprint(
        visualUrl: 'https://example.com/background.mp4',
        soundUrl: 'https://example.com/chime.mp3',
      );

      expect(
        EventService.resolveThumbprintVisualMedia(event, audioOnly: true),
        isNull,
      );
    });

    test('Thumbprint standalone audio is never duplicated as visual media', () {
      final event = buildThumbprint(
        mediaUrl: 'https://example.com/chime.mp3',
        soundUrl: 'https://example.com/chime.mp3',
      );

      expect(
        EventService.resolveThumbprintVisualMedia(event, audioOnly: false),
        isNull,
      );
    });

    test('Thumbprint image and YouTube backgrounds remain visual media', () {
      expect(
        EventService.resolveThumbprintVisualMedia(
          buildThumbprint(mediaUrl: 'https://example.com/background.jpg'),
          audioOnly: false,
        ),
        'https://example.com/background.jpg',
      );
      expect(
        EventService.resolveThumbprintVisualMedia(
          buildThumbprint(mediaUrl: 'https://youtu.be/video-id'),
          audioOnly: false,
        ),
        'https://youtu.be/video-id',
      );
    });

    test('slot doc with no recurrence keeps original date (no implicit daily)', () {
      final now = DateTime(2026, 4, 29, 17, 20);
      final originalStart = DateTime(2026, 4, 20, 9, 0);
      final event = buildNationalEvent(
        startTime: originalStart,
        duration: const Duration(minutes: 15),
        originTime: '18:15',
      );

      final resolved = EventService.resolveNationalDisplayEvent(
        event,
        docId: 'slot_1815_20260420',
        now: now,
      );

      expect(resolved.startTime, DateTime(2026, 4, 20, 18, 15));
      expect(resolved.endTime, DateTime(2026, 4, 20, 18, 30));
    });

    test('slot doc with no recurrence projects to today inside same Monday-Sunday week', () {
      final now = DateTime(2026, 5, 3, 17, 20); // Sunday
      final originalStart = DateTime(2026, 5, 2, 9, 0); // Saturday same week
      final event = buildNationalEvent(
        startTime: originalStart,
        duration: const Duration(minutes: 15),
        originTime: '18:00',
      );

      final resolved = EventService.resolveNationalDisplayEvent(
        event,
        docId: 'slot_1800_20260502',
        now: now,
      );

      expect(resolved.startTime, DateTime(2026, 5, 3, 18, 0));
      expect(resolved.endTime, DateTime(2026, 5, 3, 18, 15));
    });

    test('slot doc with no recurrence expires after its week ends', () {
      final now = DateTime(2026, 5, 4, 9, 0); // Monday next week
      final originalStart = DateTime(2026, 5, 2, 9, 0); // Prior week Saturday
      final event = buildNationalEvent(
        startTime: originalStart,
        duration: const Duration(minutes: 15),
        originTime: '18:00',
      );

      final resolved = EventService.resolveNationalDisplayEvent(
        event,
        docId: 'slot_1800_20260502',
        now: now,
      );

      expect(resolved.startTime, DateTime(2026, 5, 2, 18, 0));
      expect(resolved.endTime, DateTime(2026, 5, 2, 18, 15));
    });

    test('non-slot national doc with no recurrence does not become implicit daily', () {
      final now = DateTime(2026, 4, 29, 17, 20);
      final originalStart = DateTime(2026, 4, 20, 9, 0);
      final event = buildNationalEvent(
        startTime: originalStart,
        duration: const Duration(minutes: 15),
        originTime: '18:15',
      );

      final resolved = EventService.resolveNationalDisplayEvent(
        event,
        docId: 'legacy_event_id',
        now: now,
      );

      expect(resolved.startTime, DateTime(2026, 4, 20, 18, 15));
      expect(resolved.endTime, DateTime(2026, 4, 20, 18, 30));
    });

    test('daily recurrence rolls to next day once today slot has ended', () {
      final now = DateTime(2026, 4, 29, 19, 0);
      final event = buildNationalEvent(
        startTime: DateTime(2026, 4, 28, 7, 0),
        duration: const Duration(minutes: 15),
        recurrenceType: 'daily',
      );

      final resolved = EventService.resolveNationalDisplayEvent(
        event,
        docId: 'slot_1815_20260428',
        now: now,
      );

      expect(resolved.startTime, DateTime(2026, 4, 30, 18, 15));
      expect(resolved.endTime, DateTime(2026, 4, 30, 18, 30));
    });

    test('default noticeboard window is one hour before start', () {
      final event = buildNationalEvent(
        startTime: DateTime(2026, 4, 29, 18, 15),
        duration: const Duration(minutes: 15),
      );

      expect(
        EventService.isWithinNoticeboardWindow(
          event,
          DateTime(2026, 4, 29, 17, 14),
        ),
        isFalse,
      );
      expect(
        EventService.isWithinNoticeboardWindow(
          event,
          DateTime(2026, 4, 29, 17, 15),
        ),
        isTrue,
      );
    });

    test('custom noticeboard slider overrides the default one hour window', () {
      final event = buildNationalEvent(
        startTime: DateTime(2026, 4, 29, 18, 15),
        duration: const Duration(minutes: 15),
        noticeBoardShowBeforeMinutes: 15,
      );

      expect(
        EventService.isWithinNoticeboardWindow(
          event,
          DateTime(2026, 4, 29, 17, 59),
        ),
        isFalse,
      );
      expect(
        EventService.isWithinNoticeboardWindow(
          event,
          DateTime(2026, 4, 29, 18, 0),
        ),
        isTrue,
      );
    });

    test('noticeboard visibility-after keeps the card visible after end', () {
      final event = buildNationalEvent(
        startTime: DateTime(2026, 4, 29, 18, 15),
        duration: const Duration(minutes: 15),
        noticeBoardVisibilityAfterMinutes: 10,
      );

      expect(
        EventService.isWithinNoticeboardWindow(
          event,
          DateTime(2026, 4, 29, 18, 35),
        ),
        isTrue,
      );
      expect(
        EventService.isWithinNoticeboardWindow(
          event,
          DateTime(2026, 4, 29, 18, 40),
        ),
        isFalse,
      );
    });
  });
}
