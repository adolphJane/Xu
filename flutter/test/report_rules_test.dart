import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/report_rules.dart';

void main() {
  test('presets and custom ranges use the Swift report limits', () {
    expect(ReportLengthPreset.short.minimum, 125);
    expect(ReportLengthPreset.standard.maximum, 300);
    expect(ReportLengthPreset.detailed.maximum, 500);
    expect(ReportRules.validRange(50, 5000), isTrue);
    expect(ReportRules.validRange(49, 200), isFalse);
    expect(ReportRules.validRange(200, 199), isFalse);
    expect(ReportRules.validRange(3001, 4000), isFalse);
    expect(ReportRules.warning('短', 50, 100), contains('下限'));
  });

  test(
    'prompt includes completed work and groups same project only once per section',
    () {
      final day = DateTime(2026, 11, 7);
      final tasks = [
        {
          'title': '修复登录',
          'project': '桌面端',
          'status': 'completed',
          'completedAt': '2026-11-07T10:00:00',
          'reportCategory': 'projectProgress',
        },
        {
          'title': '检查发布',
          'project': '桌面端',
          'status': 'pending',
          'scheduledFor': '2026-11-07T13:00:00',
          'reportCategory': 'projectProgress',
        },
        {
          'title': '评审方案',
          'project': '桌面端',
          'status': 'completed',
          'scheduledFor': '2026-11-07T14:00:00',
          'reportCategory': 'collaboration',
        },
        {
          'title': '过期事项',
          'status': 'pending',
          'scheduledFor': '2026-11-06T14:00:00',
        },
      ];
      final prompt = ReportRules.prompt(
        tasks,
        day: day,
        supplement: '风险已记录',
        minimum: 125,
        maximum: 180,
      );
      expect(prompt, contains('修复登录'));
      expect(prompt, contains('评审方案'));
      expect(prompt, contains('风险已记录'));
      expect(prompt, isNot(contains('过期事项')));
      final progress = prompt.split('会议/方案/讨论：').last.split('明日重点待办：').first;
      expect(progress.split('【桌面端】').length - 1, 1);
    },
  );

  test(
    'blueprint name fills missing project and short drafts get factual fallback',
    () {
      final day = DateTime(2026, 11, 7);
      final tasks = [
        {
          'id': 't1',
          'title': '检查界面',
          'blueprintID': 'b1',
          'status': 'completed',
          'completedAt': '2026-11-07T10:00:00',
          'quadrant': 1,
          'estimatedMinutes': 30,
        },
      ];
      final blueprints = [
        <String, dynamic>{'id': 'b1', 'name': '桌面版'},
      ];
      final prompt = ReportRules.prompt(
        tasks,
        day: day,
        supplement: '',
        minimum: 125,
        maximum: 180,
        blueprints: blueprints,
      );
      expect(prompt, contains('【桌面版】'));
      expect(prompt, contains('预计30分钟'));
      final fallback = ReportRules.fallback(
        tasks,
        day: day,
        supplement: '',
        blueprints: blueprints,
      );
      expect(fallback, contains('【桌面版】'));
      expect(fallback, contains('检查界面'));
      expect(fallback, contains('当前没有未完成事项'));
      final report = ReportRules.enforceMinimumLength('太短', fallback, 180);
      expect(ReportRules.length(report), greaterThanOrEqualTo(180));
      expect(report, contains('3. 明日重点事项规划'));
    },
  );
}
