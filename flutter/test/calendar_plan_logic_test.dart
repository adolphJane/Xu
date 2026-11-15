import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/calendar_plan_logic.dart';

void main() {
  final day = DateTime(2026, 11, 16);
  Map<String, dynamic> task(
    String id,
    DateTime start,
    DateTime end, {
    String? parent,
    String status = 'pending',
  }) => {
    'id': id,
    'title': id,
    'parentTaskID': parent,
    'status': status,
    'scheduledFor': CalendarPlanLogic.day(start).toIso8601String(),
    'timeBlock': {
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
    },
  };

  test('only executable leaves and busy system events occupy time', () {
    final tasks = [
      task('parent', DateTime(2026, 11, 16, 9), DateTime(2026, 11, 16, 17)),
      task(
        'child',
        DateTime(2026, 11, 16, 10),
        DateTime(2026, 11, 16, 11),
        parent: 'parent',
      ),
      task(
        'done',
        DateTime(2026, 11, 16, 12),
        DateTime(2026, 11, 16, 13),
        status: 'completed',
      ),
      {'id': 'date-only', 'status': 'pending', 'scheduledFor': '2026-11-16'},
    ];
    final events = [
      {
        'start': '2026-11-16T14:00:00',
        'end': '2026-11-16T15:00:00',
        'isBusy': true,
      },
      {
        'start': '2026-11-16T16:00:00',
        'end': '2026-11-16T17:00:00',
        'isBusy': false,
      },
    ];
    final busy = CalendarPlanLogic.busyOn(day, tasks, events);
    expect(busy, hasLength(2));
    expect(busy.map((block) => block.start.hour), [10, 14]);
    final slots = CalendarPlanLogic.availability(
      day,
      const CalendarWorkHours(),
      tasks,
      events,
      now: DateTime(2026, 11, 15),
    );
    expect(slots.map((slot) => slot.minutes), [60, 180, 180]);
  });

  test(
    'overlapping busy intervals merge, touching endpoints do not conflict',
    () {
      final slots = CalendarPlanLogic.freeSlots(
        CalendarInterval(DateTime(2026, 11, 16, 9), DateTime(2026, 11, 16, 18)),
        [
          CalendarInterval(
            DateTime(2026, 11, 16, 10),
            DateTime(2026, 11, 16, 12),
          ),
          CalendarInterval(
            DateTime(2026, 11, 16, 11),
            DateTime(2026, 11, 16, 13),
          ),
        ],
      );
      expect(slots.map((slot) => slot.minutes), [60, 300]);
      expect(
        CalendarPlanLogic.conflicts(
          CalendarInterval(
            DateTime(2026, 11, 16, 13),
            DateTime(2026, 11, 16, 14),
          ),
          'new',
          [task('a', DateTime(2026, 11, 16, 12), DateTime(2026, 11, 16, 13))],
          [],
        ),
        isEmpty,
      );
    },
  );

  test('work days and lunch reduce availability', () {
    const hours = CalendarWorkHours(daysMask: 1 << 1, lunchBreak: true);
    expect(hours.worksOn(day), isTrue);
    expect(hours.worksOn(DateTime(2026, 11, 15)), isFalse);
    final slots = CalendarPlanLogic.availability(
      day,
      hours,
      [],
      [],
      now: DateTime(2026, 11, 15),
    );
    expect(slots.map((slot) => slot.minutes), [180, 300]);
  });

  test('overlapping items receive separate lanes', () {
    final lanes = CalendarPlanLogic.lanes({
      'a': CalendarInterval(
        DateTime(2026, 11, 16, 9),
        DateTime(2026, 11, 16, 11),
      ),
      'b': CalendarInterval(
        DateTime(2026, 11, 16, 10),
        DateTime(2026, 11, 16, 12),
      ),
      'c': CalendarInterval(
        DateTime(2026, 11, 16, 12),
        DateTime(2026, 11, 16, 13),
      ),
    });
    expect(lanes['a'], (0, 2));
    expect(lanes['b'], (1, 2));
    expect(lanes['c'], (0, 1));
  });
}
