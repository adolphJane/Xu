import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/weekly_review_rules.dart';

void main() {
  test('week starts on Monday and counts only this week completions', () {
    final now = DateTime(2026, 11, 7);
    expect(WeeklyReviewRules.weekStart(now), DateTime(2026, 11, 2));
    final tasks = [
      {'status': 'completed', 'completedAt': '2026-11-02T09:00:00'},
      {'status': 'completed', 'completedAt': '2026-11-08T23:00:00'},
      {'status': 'completed', 'completedAt': '2026-11-09T00:00:00'},
      {'status': 'blocked'},
    ];
    expect(WeeklyReviewRules.completedThisWeek(tasks, now), 2);
    expect(WeeklyReviewRules.blockedNow(tasks), 1);
  });

  test('weekly review requires a date and a nonempty summary', () {
    expect(
      WeeklyReviewRules.validate({'weekStart': 'bad', 'summary': '完成'}),
      contains('日期'),
    );
    expect(
      WeeklyReviewRules.validate({'weekStart': '2026-11-02', 'summary': '  '}),
      contains('总结'),
    );
    expect(
      WeeklyReviewRules.validate({'weekStart': '2026-11-02', 'summary': '完成'}),
      isNull,
    );
  });
}
