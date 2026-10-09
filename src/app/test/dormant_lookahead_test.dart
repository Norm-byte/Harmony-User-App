import 'package:flutter_test/flutter_test.dart';
import 'package:harmony_user_app/models/event.dart';
import 'package:harmony_user_app/services/event_service.dart';

void main() {
  Event event(String id, DateTime start) => Event(
        id: id,
        title: 'Test',
        description: '',
        type: EventType.national,
        startTime: start,
        endTime: start.add(const Duration(seconds: 30)),
      );

  test('daily slots retain local clock across seven-day lookahead', () {
    final now = DateTime(2026, 10, 9, 12);
    final result = EventService.buildDormantLookahead(now, (probe) => [
          event('daily', DateTime(probe.year, probe.month, probe.day, 15, 30)),
        ]);
    expect(result.length, 7);
    expect(result.every((e) => e.startTime.hour == 15 && e.startTime.minute == 30), isTrue);
    expect(result.last.startTime, DateTime(2026, 10, 15, 15, 30));
  });

  test('one-off events deduplicate and expired/out-of-window entries are excluded', () {
    final now = DateTime(2026, 10, 9, 12);
    final once = event('once', now.add(const Duration(days: 2)));
    final result = EventService.buildDormantLookahead(now, (_) => [
          once,
          event('expired', now.subtract(const Duration(hours: 1))),
          event('later', now.add(const Duration(days: 8))),
        ]);
    expect(result.map((e) => e.id), ['once']);
  });
}