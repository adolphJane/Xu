import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blueprint_graph.dart';
import 'blueprint_images.dart';
import 'blueprint_planning.dart';
import 'calendar_plan_logic.dart';
import 'native.dart';
import 'workspace.dart';

String blueprintDate(Object? value) {
  final date = CalendarPlanLogic.parse(value);
  if (date == null) return '未安排';
  return '${date.year}年${date.month}月${date.day}日';
}

Future<void> showBlueprintMovePreview(
  BuildContext context,
  WorkspaceViewModel vm,
  String blueprintId,
  BlueprintTask task,
) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: CalendarPlanLogic.plannedDate(task) ?? now,
    firstDate: DateTime(1900),
    lastDate: DateTime(2200),
    helpText: '选择要推演的计划日期',
  );
  if (date == null || !context.mounted) return;
  final BlueprintDelayPreview preview;
  try {
    preview = vm.previewBlueprintMove(blueprintId, task['id'] as String, date);
  } catch (error) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('$error')));
    return;
  }

  final checked = {preview.rootId};
  var saving = false;
  var checkingCalendar = false;
  String? calendarMessage;
  var calendarConflicts = <String, List<String>>{};
  final blocks = {
    for (final move in preview.moves)
      move.after['id'] as String: ?CalendarPlanLogic.taskBlock(move.after),
  };
  var reason = '';
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) {
        final milestoneIds = {
          for (final id in {preview.rootId, ...preview.affected})
            if (preview.sourceTasks[id]?['milestoneID'] case final String id)
              id,
        };
        return AlertDialog(
          title: Text('预演改期 · ${task['title']}'),
          content: SizedBox(
            width: 620,
            height: 420,
            child: ListView(
              children: [
                Text(
                  '后继受影响 ${preview.affected.length} 项 · 建议调整 ${preview.moves.length} 项',
                ),
                for (final milestone
                    in vm
                        .items('milestones')
                        .where((row) => milestoneIds.contains(row['id'])))
                  Text(
                    '涉及里程碑 · ${milestone['name']} · ${blueprintDate(milestone['dueDate'])}',
                  ),
                if (blocks.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: checkingCalendar || saving
                          ? null
                          : () async {
                              update(() {
                                checkingCalendar = true;
                                calendarMessage = null;
                              });
                              try {
                                final starts =
                                    blocks.values
                                        .map((block) => block.start)
                                        .toList()
                                      ..sort();
                                final ends =
                                    blocks.values
                                        .map((block) => block.end)
                                        .toList()
                                      ..sort();
                                final events =
                                    await NativeBridge.calendarEvents(
                                      starts.first,
                                      ends.last,
                                    );
                                final conflicts = {
                                  for (final entry in blocks.entries)
                                    entry.key: [
                                      for (final event in events)
                                        if (event['isBusy'] != false &&
                                            CalendarPlanLogic.eventBlock(event)
                                                    ?.overlaps(entry.value) ==
                                                true)
                                          '${event['title'] ?? '系统日程'}',
                                    ],
                                };
                                if (dialog.mounted) {
                                  update(() {
                                    calendarConflicts = conflicts;
                                    calendarMessage =
                                        conflicts.values.any(
                                          (items) => items.isNotEmpty,
                                        )
                                        ? '已标出与系统日历重叠的时间块'
                                        : '没有发现系统日历冲突';
                                  });
                                }
                              } catch (_) {
                                if (dialog.mounted) {
                                  update(() => calendarMessage = '系统日历暂不可用');
                                }
                              } finally {
                                if (dialog.mounted) {
                                  update(() => checkingCalendar = false);
                                }
                              }
                            },
                      icon: const Icon(Icons.event_available_outlined),
                      label: const Text('检查系统日历冲突'),
                    ),
                  ),
                if (calendarMessage != null) Text(calendarMessage!),
                if (preview.moves.isEmpty) const Text('所选日期没有产生计划变化'),
                for (final edit in preview.moves)
                  CheckboxListTile(
                    title: Text('${edit.after['title']}'),
                    subtitle: Text(
                      [
                        '${blueprintDate(edit.before?['scheduledFor'])} → ${blueprintDate(edit.after['scheduledFor'])}',
                        ?preview.warnings[edit.after['id']],
                        if (calendarConflicts[edit.after['id']]
                            case final titles? when titles.isNotEmpty)
                          '系统日历冲突：${titles.join('、')}',
                      ].join('\n'),
                    ),
                    value: checked.contains(edit.after['id']),
                    onChanged: saving || edit.after['id'] == preview.rootId
                        ? null
                        : (value) => update(() {
                            final id = edit.after['id'] as String;
                            if (value == true) {
                              checked.add(id);
                            } else {
                              checked.remove(id);
                            }
                          }),
                  ),
                for (final entry in preview.warnings.entries.where(
                  (entry) => !preview.moves.any(
                    (edit) => edit.after['id'] == entry.key,
                  ),
                ))
                  ListTile(
                    title: Text('${preview.sourceTasks[entry.key]?['title']}'),
                    subtitle: Text(entry.value),
                  ),
                TextFormField(
                  onChanged: (value) => reason = value,
                  decoration: const InputDecoration(labelText: '改期原因'),
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
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving || preview.moves.isEmpty
                  ? null
                  : () async {
                      update(() => saving = true);
                      try {
                        await vm.commitBlueprintMove(
                          blueprintId,
                          preview,
                          checked,
                          reason,
                        );
                        if (dialog.mounted) Navigator.pop(dialog);
                      } catch (failure) {
                        if (dialog.mounted) {
                          update(() {
                            saving = false;
                            error = '$failure';
                          });
                        }
                      }
                    },
              child: Text('保存所选 · ${checked.length}'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showMilestoneAcceptance(
  BuildContext context,
  WorkspaceViewModel vm,
  BlueprintTask milestone,
) {
  final original = (milestone['acceptanceChecks'] as List? ?? [])
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  final evidence = (milestone['acceptanceEvidence'] as List? ?? [])
      .map((row) => Map<String, dynamic>.from(row as Map))
      .toList();
  final linked = vm.milestoneTasks(milestone['id']);
  final checks = [...original];
  var input = '';
  var inputRevision = 0;
  var busy = false;
  String? error;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) {
        Future<void> save(bool accept) async {
          update(() => busy = true);
          try {
            await vm.saveMilestoneAcceptance(
              milestone,
              checks,
              evidence,
              accept: accept,
            );
            if (dialog.mounted) Navigator.pop(dialog);
          } catch (failure) {
            if (dialog.mounted) {
              update(() {
                busy = false;
                error = '$failure';
              });
            }
          }
        }

        return AlertDialog(
          title: Text('${milestone['name']} · 验收'),
          content: SizedBox(
            width: 600,
            height: 420,
            child: ListView(
              children: [
                Text(
                  '关联事项 ${linked.where((task) => task['status'] == 'completed').length}/${linked.length} 已完成',
                ),
                for (final check in checks)
                  Row(
                    key: ValueKey(check['id']),
                    children: [
                      Expanded(
                        child: CheckboxListTile(
                          title: Text('${check['title']}'),
                          value: check['done'] == true,
                          onChanged: busy
                              ? null
                              : (value) => update(() {
                                  final index = checks.indexOf(check);
                                  checks[index] = {
                                    ...check,
                                    'done': value == true,
                                  };
                                }),
                        ),
                      ),
                      IconButton(
                        tooltip: '移除此检查项',
                        onPressed: busy
                            ? null
                            : () => update(() => checks.remove(check)),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        key: ValueKey(inputRevision),
                        onChanged: (value) =>
                            update(() => input = value.trim()),
                        decoration: const InputDecoration(labelText: '新增检查项'),
                        onFieldSubmitted: (_) {
                          if (input.isNotEmpty) {
                            update(() {
                              checks.add({
                                'id': newId(),
                                'title': input,
                                'done': false,
                              });
                              input = '';
                              inputRevision++;
                            });
                          }
                        },
                      ),
                    ),
                    IconButton(
                      tooltip: '添加检查项',
                      icon: const Icon(Icons.add),
                      onPressed: busy || input.isEmpty
                          ? null
                          : () => update(() {
                              checks.add({
                                'id': newId(),
                                'title': input,
                                'done': false,
                              });
                              input = '';
                              inputRevision++;
                            }),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text('成果图', style: Theme.of(context).textTheme.titleMedium),
                for (final task in linked)
                  for (final image in blueprintImages(task['images']))
                    CheckboxListTile(
                      title: Text('${task['title']} · ${image['label']}'),
                      secondary: InkWell(
                        onTap: () => showBlueprintImagePreview(
                          context,
                          [image],
                          0,
                          '${task['title']} · 成果图',
                        ),
                        child: SizedBox(
                          width: 44,
                          child: BlueprintImageView(
                            image: image,
                            thumbnail: true,
                          ),
                        ),
                      ),
                      value: evidence.any(
                        (ref) =>
                            ref['taskID'] == task['id'] &&
                            ref['imageID'] == image['id'],
                      ),
                      onChanged: busy
                          ? null
                          : (value) => update(() {
                              evidence.removeWhere(
                                (ref) =>
                                    ref['taskID'] == task['id'] &&
                                    ref['imageID'] == image['id'],
                              );
                              if (value == true) {
                                evidence.add({
                                  'taskID': task['id'],
                                  'imageID': image['id'],
                                  'label': image['label'],
                                });
                              }
                            }),
                    ),
                if ((milestone['acceptanceHistory'] as List? ?? []).isNotEmpty)
                  ExpansionTile(
                    title: const Text('历史验收'),
                    children: [
                      for (final history
                          in (milestone['acceptanceHistory'] as List)
                              .whereType<Map>()
                              .toList()
                              .reversed)
                        ListTile(
                          title: Text(blueprintDate(history['acceptedAt'])),
                          subtitle: Text(
                            [
                              for (final check
                                  in (history['checks'] as List? ?? [])
                                      .whereType<Map>())
                                '${check['title']}',
                              for (final ref
                                  in (history['evidence'] as List? ?? [])
                                      .whereType<Map>())
                                '${ref['label']}${vm.tasks.any((task) => task['id'] == ref['taskID'] && blueprintImages(task['images']).any((image) => image['id'] == ref['imageID'])) ? '' : '（附件已移除）'}',
                            ].join(' · '),
                          ),
                        ),
                    ],
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
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: busy ? null : () => save(false),
              child: const Text('保存检查项'),
            ),
            FilledButton(
              onPressed:
                  busy ||
                      checks.isEmpty ||
                      checks.any((row) => row['done'] != true) ||
                      linked.any((row) => row['status'] != 'completed')
                  ? null
                  : () => save(true),
              child: const Text('确认验收通过'),
            ),
          ],
        );
      },
    ),
  );
}

Future<void> showBlueprintRetrospective(
  BuildContext context,
  WorkspaceViewModel vm,
  BlueprintGraph graph,
) {
  final blueprint = graph.blueprint;
  final records = vm
      .items('planChanges')
      .where(
        (row) =>
            row['blueprintID'] == blueprint['id'] && row['isUndone'] != true,
      );
  final milestones = vm
      .items('milestones')
      .where(
        (row) =>
            row['blueprintID'] == blueprint['id'] && row['isCompleted'] == true,
      );
  var draft = [
    '# ${blueprint['name']} · 复盘',
    '目标：${blueprint['goal'] ?? ''}',
    '\n## 已完成',
    for (final row in graph.tasks.values.where(
      (row) => row['status'] == 'completed',
    ))
      '- ${row['title']}',
    '\n## 里程碑',
    for (final row in milestones) '- ${row['name']}',
    '\n## 计划变更',
    for (final row in records)
      '- ${row['title']}（${blueprintDate(row['changedAt'])}）',
    '\n## 后续事项',
    for (final row in graph.tasks.values.where(
      (row) => !CalendarPlanLogic.isProcessed(row),
    ))
      '- ${row['title']}',
  ].join('\n');
  var busy = false;
  String? error;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('蓝图复盘'),
        content: SizedBox(
          width: 650,
          height: 420,
          child: Column(
            children: [
              Expanded(
                child: TextFormField(
                  initialValue: draft,
                  onChanged: (value) => draft = value,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  decoration: const InputDecoration(labelText: '复盘草稿'),
                ),
              ),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialog),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: draft)),
            child: const Text('复制 Markdown'),
          ),
          FilledButton(
            onPressed: busy
                ? null
                : () async {
                    update(() => busy = true);
                    try {
                      final now = DateTime.now();
                      final summary = draft.trim();
                      await vm.put('weeklyReviews', {
                        'id': newId(),
                        'blueprintID': blueprint['id'],
                        'summary': summary,
                        'weekStart': DateTime(
                          now.year,
                          now.month,
                          now.day - now.weekday + 1,
                        ).toIso8601String(),
                        'createdAt': now.toIso8601String(),
                      });
                      if (dialog.mounted) Navigator.pop(dialog);
                    } catch (failure) {
                      if (dialog.mounted) {
                        update(() {
                          busy = false;
                          error = '$failure';
                        });
                      }
                    }
                  },
            child: const Text('保存到复盘历史'),
          ),
        ],
      ),
    ),
  );
}

Future<void> showSaveBlueprintTemplate(
  BuildContext context,
  WorkspaceViewModel vm,
  BlueprintTask blueprint,
) {
  var name = '${blueprint['name']}';
  var includeImages = false;
  var busy = false;
  String? error;
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('另存为蓝图模板'),
        content: SizedBox(
          width: 410,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                initialValue: name,
                decoration: const InputDecoration(labelText: '模板名称'),
                onChanged: (value) => update(() => name = value.trim()),
              ),
              SwitchListTile(
                title: const Text('包含蓝图参考图'),
                value: includeImages,
                onChanged: busy
                    ? null
                    : (value) => update(() => includeImages = value),
              ),
              const Text('保留步骤、依赖和相对日期。模板从待办状态开始。'),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: busy || name.isEmpty
                ? null
                : () async {
                    update(() => busy = true);
                    try {
                      await vm.saveBlueprintTemplate(
                        blueprint['id'] as String,
                        name,
                        includeImages: includeImages,
                      );
                      if (dialog.mounted) Navigator.pop(dialog);
                    } catch (failure) {
                      if (dialog.mounted) {
                        update(() {
                          busy = false;
                          error = '$failure';
                        });
                      }
                    }
                  },
            child: const Text('保存模板'),
          ),
        ],
      ),
    ),
  );
}
