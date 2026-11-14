import 'package:flutter/material.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'workspace.dart';
import 'weekly_review_rules.dart';

class WeeklyReviewsSection extends StatelessWidget {
  const WeeklyReviewsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final reviews = [...Get.find<WorkspaceViewModel>().items('weeklyReviews')]
      ..sort(
        (a, b) =>
            '${b['weekStart'] ?? ''}'.compareTo('${a['weekStart'] ?? ''}'),
      );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('周复盘', style: Theme.of(context).textTheme.titleLarge),
            OutlinedButton.icon(
              onPressed: () => showWeeklyReviewEditor(context),
              icon: const Icon(Icons.calendar_month_outlined),
              label: const Text('本周复盘'),
            ),
          ],
        ),
        if (reviews.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('还没有周复盘。'),
          ),
        for (final review in reviews)
          Card(
            child: ListTile(
              leading: const Icon(Icons.event_note_outlined),
              title: Text('${_displayDate(review['weekStart'])} 当周'),
              subtitle: Text(
                '${review['summary'] ?? ''}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showWeeklyReviewDetail(context, review),
            ),
          ),
      ],
    );
  }
}

String _displayDate(Object? value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  return date == null ? '未知日期' : '${date.year}年${date.month}月${date.day}日';
}

Future<void> showWeeklyReviewDetail(
  BuildContext context,
  Map<String, dynamic> review,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text('${_displayDate(review['weekStart'])} 当周复盘'),
    content: SizedBox(
      width: 560,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('本周总结', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText('${review['summary'] ?? ''}'),
            const SizedBox(height: 20),
            Text('下周重点', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            SelectableText('${review['nextWeekFocus'] ?? ''}'),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  ),
);

Future<void> showWeeklyReviewEditor(BuildContext context) async {
  final vm = Get.find<WorkspaceViewModel>();
  final summary = TextEditingController();
  final focus = TextEditingController();
  var saving = false;
  String? error;
  try {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('本周复盘'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '本周完成 ${WeeklyReviewRules.completedThisWeek(vm.tasks, DateTime.now())} 项，当前阻塞 ${WeeklyReviewRules.blockedNow(vm.tasks)} 项。',
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: summary,
                    autofocus: true,
                    maxLines: 5,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: '本周总结',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: focus,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '下周重点',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (error != null)
                    Text(
                      error!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving || summary.text.trim().isEmpty
                  ? null
                  : () async {
                      setState(() {
                        saving = true;
                        error = null;
                      });
                      try {
                        final now = DateTime.now();
                        await vm.put('weeklyReviews', {
                          'id': newId(),
                          'weekStart': WeeklyReviewRules.weekStart(now)
                              .toIso8601String(),
                          'summary': summary.text.trim(),
                          'nextWeekFocus': focus.text.trim(),
                          'createdAt': now.toIso8601String(),
                        });
                        if (context.mounted) Navigator.pop(context);
                      } catch (e) {
                        if (context.mounted) setState(() => error = '$e');
                      } finally {
                        if (context.mounted) setState(() => saving = false);
                      }
                    },
              child: const Text('保存周复盘'),
            ),
          ],
        ),
      ),
    );
  } finally {
    summary.dispose();
    focus.dispose();
  }
}
