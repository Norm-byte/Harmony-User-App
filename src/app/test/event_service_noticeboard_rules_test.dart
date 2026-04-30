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
