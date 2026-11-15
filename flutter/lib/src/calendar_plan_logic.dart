class CalendarInterval {
  const CalendarInterval(this.start, this.end);
  final DateTime start;
  final DateTime end;

  bool overlaps(CalendarInterval other) =>
      start.isBefore(other.end) && other.start.isBefore(end);
  int get minutes => end.difference(start).inMinutes;
}

class CalendarWorkHours {
  const CalendarWorkHours({
    this.startHour = 9,
    this.endHour = 18,
    this.daysMask = 127,
    this.lunchBreak = false,
  });
  final int startHour;
  final int endHour;
  final int daysMask;
  final bool lunchBreak;

  factory CalendarWorkHours.fromSettings(Map<String, dynamic>? row) =>
      CalendarWorkHours(
        startHour: (row?['calendarWorkStartHour'] as num?)?.toInt() ?? 9,
        endHour: (row?['calendarWorkEndHour'] as num?)?.toInt() ?? 18,
        daysMask: (row?['calendarWorkDaysMask'] as num?)?.toInt() ?? 127,
        lunchBreak: row?['calendarLunchBreak'] == true,
      );

  Map<String, dynamic> toJson() => {
    'calendarWorkStartHour': startHour,
    'calendarWorkEndHour': endHour,
    'calendarWorkDaysMask': daysMask,
    'calendarLunchBreak': lunchBreak,
  };

  bool worksOn(DateTime day) => daysMask & (1 << (day.weekday % 7)) != 0;
}

class CalendarPlanLogic {
  static DateTime day(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  static DateTime addDays(DateTime value, int days) => DateTime(
    value.year,
    value.month,
    value.day + days,
    value.hour,
    value.minute,
    value.second,
    value.millisecond,
    value.microsecond,
  );

  static int daysBetween(DateTime a, DateTime b) => DateTime.utc(
    a.year,
    a.month,
    a.day,
  ).difference(DateTime.utc(b.year, b.month, b.day)).inDays;

  static DateTime? parse(dynamic value) =>
      value == null ? null : DateTime.tryParse('$value')?.toLocal();

  static DateTime? plannedDate(Map<String, dynamic> task) {
    if (task['status'] == 'unscheduled') return null;
    return parse(task['scheduledFor']);
  }

  static CalendarInterval? taskBlock(Map<String, dynamic> task) {
    final block = task['timeBlock'];
    if (block is! Map) return null;
    final start = parse(block['start']);
    final end = parse(block['end']);
    if (start == null || end == null || !end.isAfter(start)) return null;
    return CalendarInterval(start, end);
  }

  static CalendarInterval? eventBlock(Map<String, dynamic> event) {
    final start = parse(event['start']);
    final end = parse(event['end']);
    if (start == null || end == null || !end.isAfter(start)) return null;
    return CalendarInterval(start, end);
  }

  static bool isProcessed(Map<String, dynamic> task) =>
      task['status'] == 'completed' || task['status'] == 'cancelled';

  static List<Map<String, dynamic>> executable(
    List<Map<String, dynamic>> tasks,
  ) {
    final parentIds = tasks
        .map((task) => task['parentTaskID'])
        .where((id) => id != null)
        .map((id) => '$id')
        .toSet();
    return tasks
        .where(
          (task) =>
              !parentIds.contains('${task['id']}') &&
              task['status'] != 'cancelled',
        )
        .toList();
  }

  static String rootId(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> tasks,
  ) {
    final byId = {for (final row in tasks) '${row['id']}': row};
    var current = task;
    final seen = <String>{'${task['id']}'};
    while (current['parentTaskID'] != null) {
      final parentId = '${current['parentTaskID']}';
      if (!seen.add(parentId) || !byId.containsKey(parentId)) break;
      current = byId[parentId]!;
    }
    return '${current['id']}';
  }

  static List<CalendarInterval> busyOn(
    DateTime date,
    List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> events,
  ) {
    final start = day(date);
    final end = addDays(start, 1);
    final intervals = <CalendarInterval>[
      for (final task in executable(tasks))
        if (!isProcessed(task)) ?taskBlock(task),
      for (final event in events)
        if (event['isBusy'] != false) ?eventBlock(event),
    ];
    return [
      for (final interval in intervals)
        if (interval.start.isBefore(end) && interval.end.isAfter(start))
          CalendarInterval(
            interval.start.isBefore(start) ? start : interval.start,
            interval.end.isAfter(end) ? end : interval.end,
          ),
    ];
  }

  static List<CalendarInterval> freeSlots(
    CalendarInterval window,
    List<CalendarInterval> busy,
  ) {
    if (!window.end.isAfter(window.start)) return [];
    final clipped = <CalendarInterval>[
      for (final item in busy)
        if (item.start.isBefore(window.end) && item.end.isAfter(window.start))
          CalendarInterval(
            item.start.isBefore(window.start) ? window.start : item.start,
            item.end.isAfter(window.end) ? window.end : item.end,
          ),
    ]..sort((a, b) => a.start.compareTo(b.start));
    final result = <CalendarInterval>[];
    var cursor = window.start;
    for (final item in clipped) {
      if (item.start.isAfter(cursor)) {
        result.add(CalendarInterval(cursor, item.start));
      }
      if (item.end.isAfter(cursor)) cursor = item.end;
    }
    if (cursor.isBefore(window.end)) {
      result.add(CalendarInterval(cursor, window.end));
    }
    return result;
  }

  static List<CalendarInterval> availability(
    DateTime date,
    CalendarWorkHours hours,
    List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> events, {
    DateTime? now,
  }) {
    if (!hours.worksOn(date)) return [];
    final start = DateTime(date.year, date.month, date.day, hours.startHour);
    final end = DateTime(date.year, date.month, date.day, hours.endHour);
    final clock = now ?? DateTime.now();
    final window = CalendarInterval(start.isBefore(clock) ? clock : start, end);
    final busy = busyOn(date, tasks, events);
    if (hours.lunchBreak) {
      busy.add(
        CalendarInterval(
          DateTime(date.year, date.month, date.day, 12),
          DateTime(date.year, date.month, date.day, 13),
        ),
      );
    }
    return freeSlots(window, busy);
  }

  static List<String> conflicts(
    CalendarInterval interval,
    String taskId,
    List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> events,
  ) => [
    for (final task in executable(tasks))
      if ('${task['id']}' != taskId && !isProcessed(task))
        if (taskBlock(task) case final block?)
          if (interval.overlaps(block)) '${task['title'] ?? '事项'}',
    for (final event in events)
      if (event['isBusy'] != false)
        if (eventBlock(event) case final block?)
          if (interval.overlaps(block)) '${event['title'] ?? '系统日程'}',
  ];

  static Map<String, (int, int)> lanes(Map<String, CalendarInterval> entries) {
    final sorted = entries.entries.toList()
      ..sort((a, b) => a.value.start.compareTo(b.value.start));
    final result = <String, (int, int)>{};
    var component = <MapEntry<String, CalendarInterval>>[];
    DateTime? componentEnd;
    void finish() {
      final active = <(DateTime, int)>[];
      final assigned = <String, int>{};
      var width = 1;
      for (final entry in component) {
        active.removeWhere((lane) => !lane.$1.isAfter(entry.value.start));
        final occupied = active.map((lane) => lane.$2).toSet();
        var index = 0;
        while (occupied.contains(index)) {
          index++;
        }
        active.add((entry.value.end, index));
        assigned[entry.key] = index;
        if (index + 1 > width) width = index + 1;
      }
      for (final item in assigned.entries) {
        result[item.key] = (item.value, width);
      }
    }

    for (final entry in sorted) {
      if (component.isNotEmpty && !entry.value.start.isBefore(componentEnd!)) {
        finish();
        component = [];
        componentEnd = null;
      }
      component.add(entry);
      if (componentEnd == null || entry.value.end.isAfter(componentEnd)) {
        componentEnd = entry.value.end;
      }
    }
    if (component.isNotEmpty) finish();
    return result;
  }
}
