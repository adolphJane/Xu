import 'package:flutter/material.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'ai.dart';
import 'ai_blueprint.dart';
import 'workspace.dart';

Future<void> showAiBlueprintDialog(BuildContext context) async {
  var goal = '';
  var minutes = '90';
  var deadline = DateTime.now().add(const Duration(days: 30));
  {
    final request = await showDialog<(String, DateTime, int)>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) => AlertDialog(
          title: const Text('AI 创建蓝图'),
          scrollable: true,
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  onChanged: (value) => goal = value,
                  maxLines: 4,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: '目标描述',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  initialValue: minutes,
                  onChanged: (value) => minutes = value,
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
                final value = int.tryParse(minutes);
                if (goal.trim().isNotEmpty &&
                    value != null &&
                    value >= 15 &&
                    value <= 480) {
                  Navigator.pop(dialog, (goal.trim(), deadline, value));
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
    final overrides = <String, Set<String>>{};
    final entries = draft.taskEntries;
    final titles = <String, String>{};
    var chain = false;
    Future<void> editDraftTask(
      BuildContext context,
      String key,
      Set<String> initial,
    ) async {
      final dependencies = Set.of(initial);
      var title = titles[key] ?? entries[key]!.title;
      final result = await showDialog<(String, Set<String>)>(
        context: context,
        builder: (dialog) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: const Text('编辑任务与前置'),
            content: SizedBox(
              width: 440,
              height: 340,
              child: ListView(
                children: [
                  TextFormField(
                    initialValue: title,
                    decoration: const InputDecoration(labelText: '标题'),
                    onChanged: (value) => update(() => title = value.trim()),
                  ),
                  for (final entry in entries.entries.where(
                    (row) => row.key != key && !excluded.contains(row.key),
                  ))
                    CheckboxListTile(
                      title: Text(titles[entry.key] ?? entry.value.title),
                      value: dependencies.contains(entry.key),
                      onChanged: (value) => update(() {
                        if (value == true) {
                          dependencies.add(entry.key);
                        } else {
                          dependencies.remove(entry.key);
                        }
                      }),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: title.isEmpty
                    ? null
                    : () => Navigator.pop(dialog, (title, dependencies)),
                child: const Text('应用'),
              ),
            ],
          ),
        ),
      );
      if (result != null) {
        titles[key] = result.$1;
        overrides[key] = result.$2;
      }
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) {
          Map<String, Set<String>> edges = {};
          String? error;
          try {
            edges = draft.dependenciesFor(
              excluded: excluded,
              overrides: overrides,
              chainStages: chain,
            );
          } catch (failure) {
            error = '$failure';
          }
          return AlertDialog(
            title: Text('确认蓝图：${draft.name}'),
            content: SizedBox(
              width: 680,
              height: 500,
              child: ListView(
                children: [
                  Text(draft.goal),
                  SwitchListTile(
                    title: const Text('按阶段顺序串联'),
                    subtitle: const Text('将上一阶段出口接到下一阶段入口'),
                    value: chain,
                    onChanged: (value) => setState(() => chain = value),
                  ),
                  if (error != null)
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(dialog).colorScheme.error,
                      ),
                    ),
                  for (final entry in entries.entries)
                    ListTile(
                      leading: Checkbox(
                        value: !excluded.contains(entry.key),
                        onChanged: (value) => setState(() {
                          if (value == true) {
                            excluded.remove(entry.key);
                          } else {
                            excluded.add(entry.key);
                          }
                        }),
                      ),
                      title: Text(titles[entry.key] ?? entry.value.title),
                      subtitle: Text(
                        [
                          '${entry.value.scheduledFor.toLocal().toString().split(' ').first} · ${entry.value.estimatedMinutes} 分钟',
                          if (edges[entry.key]?.isNotEmpty == true)
                            '等待 ${edges[entry.key]!.map((key) => titles[key] ?? entries[key]!.title).join('、')}',
                          if (entry.value.dependencyReason.isNotEmpty)
                            entry.value.dependencyReason,
                        ].join('\n'),
                      ),
                      trailing: IconButton(
                        tooltip: '编辑任务与前置',
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: excluded.contains(entry.key)
                            ? null
                            : () async {
                                final base =
                                    draft.dependenciesFor(
                                      excluded: excluded,
                                    )[entry.key] ??
                                    {};
                                await editDraftTask(
                                  dialog,
                                  entry.key,
                                  overrides[entry.key] ?? base,
                                );
                                if (dialog.mounted) setState(() {});
                              },
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: excluded.length == entries.length || error != null
                    ? null
                    : () => Navigator.pop(dialog, true),
                child: const Text('创建蓝图'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await Get.find<WorkspaceViewModel>().createAiBlueprint(
        draft,
        excludedTaskKeys: excluded,
        dependencyOverrides: overrides,
        taskTitles: titles,
        chainStages: chain,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }
}
