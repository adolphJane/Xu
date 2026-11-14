import 'package:flutter/material.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'ai.dart';
import 'ai_blueprint.dart';
import 'workspace.dart';

Future<void> showAiBlueprintDialog(BuildContext context) async {
  final goal = TextEditingController();
  final minutes = TextEditingController(text: '90');
  var deadline = DateTime.now().add(const Duration(days: 30));
  try {
    final request = await showDialog<(String, DateTime, int)>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: const Text('AI 创建蓝图'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: goal,
                  maxLines: 4,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '目标描述',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: minutes,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: '每日可用分钟（15～480）',
                  ),
                ),
                TextButton.icon(
                  onPressed: () async {
                    final picked = await showDatePicker(
                      context: dialog,
                      initialDate: deadline,
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) setState(() => deadline = picked);
                  },
                  icon: const Icon(Icons.event),
                  label: Text(
                    '截止日期：${deadline.year}-${deadline.month}-${deadline.day}',
                  ),
                ),
                const Text('生成时会将目标描述、截止日期和每日容量发送给 DeepSeek。'),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final value = int.tryParse(minutes.text);
                if (goal.text.trim().isNotEmpty &&
                    value != null &&
                    value >= 15 &&
                    value <= 480) {
                  Navigator.pop(dialog, (goal.text.trim(), deadline, value));
                }
              },
              child: const Text('生成草稿'),
            ),
          ],
        ),
      ),
    );
    if (request == null || !context.mounted) return;
    AiBlueprintDraft draft;
    try {
      final response = await AiService.complete(
        AiBlueprintDraft.prompt(request.$1, request.$2, request.$3),
      );
      draft = AiBlueprintDraft.parse(
        response,
        request.$3,
        deadline: request.$2,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('AI 蓝图生成失败：$error')));
      }
      return;
    }
    if (!context.mounted) return;
    final excluded = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: Text('确认蓝图：${draft.name}'),
          content: SizedBox(
            width: 680,
            height: 500,
            child: ListView(
              children: [
                Text(draft.goal),
                const SizedBox(height: 12),
                for (
                  var stageIndex = 0;
                  stageIndex < draft.stages.length;
                  stageIndex++
                ) ...[
                  Text(
                    draft.stages[stageIndex].name,
                    style: Theme.of(dialog).textTheme.titleMedium,
                  ),
                  for (
                    var taskIndex = 0;
                    taskIndex < draft.stages[stageIndex].tasks.length;
                    taskIndex++
                  )
                    CheckboxListTile(
                      value: !excluded.contains('$stageIndex:$taskIndex'),
                      onChanged: (value) => setState(() {
                        final key = '$stageIndex:$taskIndex';
                        if (value == true) {
                          excluded.remove(key);
                        } else {
                          excluded.add(key);
                        }
                      }),
                      title: Text(
                        draft.stages[stageIndex].tasks[taskIndex].title,
                      ),
                      subtitle: Text(
                        '${draft.stages[stageIndex].tasks[taskIndex].scheduledFor.toLocal().toString().split(' ').first} · ${draft.stages[stageIndex].tasks[taskIndex].estimatedMinutes} 分钟',
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: excluded.length == draft.tasks.length
                  ? null
                  : () => Navigator.pop(dialog, true),
              child: const Text('创建蓝图'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await Get.find<WorkspaceViewModel>().createAiBlueprint(
        draft,
        excludedTaskKeys: excluded,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  } finally {
    goal.dispose();
    minutes.dispose();
  }
}
