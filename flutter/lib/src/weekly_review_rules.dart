class WeeklyReviewRules {
  static DateTime weekStart(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    return date.subtract(Duration(days: date.weekday - DateTime.monday));
  }

  static int completedThisWeek(List<Map<String, dynamic>> tasks, DateTime day) {
    final start = weekStart(day);
    final end = start.add(const Duration(days: 7));
    return tasks.where((task) {
      if (task['status'] != 'completed') return false;
      final date = DateTime.tryParse('${task['completedAt']}')?.toLocal();
      return date != null && !date.isBefore(start) && date.isBefore(end);
    }).length;
  }

  static int blockedNow(List<Map<String, dynamic>> tasks) =>
      tasks.where((task) => task['status'] == 'blocked').length;

  static String? validate(Map<String, dynamic> review) {
    if (DateTime.tryParse('${review['weekStart']}') == null) {
      return '周起始日期无效';
    }
    if ('${review['summary'] ?? ''}'.trim().isEmpty) {
      return '请填写本周总结';
    }
    return null;
  }
}
