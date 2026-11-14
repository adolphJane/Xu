import 'package:flutter/material.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'workspace.dart';

String _date(Object? value) {
  final date = DateTime.tryParse('${value ?? ''}')?.toLocal();
  if (date == null) return '未设置';
  return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

Future<void> showPlanHistory(
  BuildContext context,
  String? blueprintId,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('AI 变更历史'),
    content: SizedBox(
      width: 690,
      height: 500,
      child: Obx(() {
        final vm = Get.find<WorkspaceViewModel>();
        vm.revision.value;
        final records =
            vm
                .items('planChanges')
                .where(
                  (row) =>
                      blueprintId == null || row['blueprintID'] == blueprintId,
                )
                .toList()
              ..sort(
                (a, b) => '${b['changedAt'] ?? ''}'.compareTo(
                  '${a['changedAt'] ?? ''}',
                ),
              );
        if (records.isEmpty) return const Center(child: Text('还没有重新规划记录'));
        return ListView(
          children: [
            for (final record in records)
              Card(
                child: ExpansionTile(
                  leading: const Icon(Icons.history),
                  title: Text('${record['title'] ?? 'AI 重新规划'}'),
                  subtitle: Text(_date(record['changedAt'])),
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  children: [
                    if (record['isUndone'] == true)
                      const ListTile(title: Text('已撤销'))
                    else
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed:
                              record['beforeTasks'] is! List &&
                                  record['createdRecords'] is! Map
                              ? null
                              : () async {
                                  try {
                                    await vm.undoPlanChange('${record['id']}');
                                  } catch (error) {
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                            SnackBar(content: Text('$error')),
                                          );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.undo),
                          label: const Text('撤销这次规划'),
                        ),
                      ),
                    if (record['kind'] == 'aiBlueprint' &&
                        record['createdRecords'] is Map)
                      for (final raw
                          in (record['createdRecords'] as Map)['stages']
                                  as List? ??
                              [])
                        ListTile(title: Text('阶段：${(raw as Map)['name']}')),
                    if (record['kind'] == 'aiBlueprint' &&
                        record['createdRecords'] is Map)
                      for (final raw
                          in (record['createdRecords'] as Map)['tasks']
                                  as List? ??
                              [])
                        ListTile(title: Text('任务：${(raw as Map)['title']}')),
                    if (record['kind'] != 'aiBlueprint' &&
                        record['entries'] is! List)
                      const ListTile(title: Text('这条早期记录没有保存任务日期详情。')),
                    for (final raw in record['entries'] as List? ?? [])
                      Builder(
                        builder: (context) {
                          final entry = Map<String, dynamic>.from(raw as Map);
                          return ListTile(
                            title: Text('${entry['title'] ?? '事项'}'),
                            subtitle: SelectableText(
                              '计划：${_date(entry['beforeScheduledFor'])} → ${_date(entry['afterScheduledFor'])}\n'
                              '截止：${_date(entry['beforeDueDate'])} → ${_date(entry['afterDueDate'])}'
                              '${'${entry['reason'] ?? ''}'.trim().isEmpty ? '' : '\n原因：${entry['reason']}'}',
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
          ],
        );
      }),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('关闭'),
      ),
    ],
  ),
);
