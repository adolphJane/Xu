import 'dart:convert';

class ReplanChange {
  final String taskId;
  final DateTime scheduledFor;
  final DateTime? dueDate;
  final String reason;
  const ReplanChange(this.taskId, this.scheduledFor, this.dueDate, this.reason);
}

class ReplanProposal {
  final String summary;
  final List<ReplanChange> changes;
  const ReplanProposal(this.summary, this.changes);

  static ReplanProposal parse(String response, Set<String> allowedIds) {
    final start = response.indexOf('{'), end = response.lastIndexOf('}');
    if (start < 0 || end <= start) throw const FormatException('AI 未返回有效规划');
    final data =
        jsonDecode(response.substring(start, end + 1)) as Map<String, dynamic>;
    final raw = data['changes'];
    if (raw is! List || raw.isEmpty) throw const FormatException('规划中没有变更');
    final seen = <String>{};
    final changes = <ReplanChange>[];
    for (final value in raw) {
      final item = Map<String, dynamic>.from(value as Map);
      final id = '${item['taskID'] ?? ''}';
      final date = DateTime.tryParse('${item['newScheduledFor'] ?? ''}');
      final due = item['newDueDate'] == null
          ? null
          : DateTime.tryParse('${item['newDueDate']}');
      if (!allowedIds.contains(id) ||
          !seen.add(id) ||
          date == null ||
          (item['newDueDate'] != null && due == null)) {
        throw const FormatException('AI 规划包含无效任务或日期');
      }
      changes.add(ReplanChange(id, date, due, '${item['reason'] ?? ''}'));
    }
    return ReplanProposal('${data['summary'] ?? ''}', changes);
  }
}

class CapacityOverload {
  final DateTime day;
  final int plannedMinutes;
  final int limitMinutes;
  const CapacityOverload(this.day, this.plannedMinutes, this.limitMinutes);
}

List<CapacityOverload> replanCapacityOverloads(
  List<Map<String, dynamic>> tasks,
  Set<String> changedTaskIds,
  int dailyMinutes,
) {
  if (dailyMinutes < 1 || dailyMinutes > 1440) {
    throw const FormatException('每日可用分钟须在 1～1440 之间');
  }
  final affectedDays = <DateTime>{};
  for (final task in tasks.where(
    (row) => changedTaskIds.contains('${row['id']}'),
  )) {
    final date = DateTime.tryParse('${task['scheduledFor']}')?.toLocal();
    if (date != null) {
      affectedDays.add(DateTime(date.year, date.month, date.day));
    }
  }
  final totals = <DateTime, int>{};
  for (final task in tasks) {
    if (['completed', 'cancelled', 'unscheduled'].contains(task['status'])) {
      continue;
    }
    final date = DateTime.tryParse('${task['scheduledFor']}')?.toLocal();
    if (date == null) continue;
    final day = DateTime(date.year, date.month, date.day);
    if (!affectedDays.contains(day)) continue;
    final raw = task['estimatedMinutes'];
    final minutes = raw is int && raw > 0 ? raw : 30;
    totals[day] = (totals[day] ?? 0) + minutes;
  }
  return [
    for (final day in (totals.keys.toList()..sort()))
      if (totals[day]! > dailyMinutes)
        CapacityOverload(day, totals[day]!, dailyMinutes),
  ];
}

String capacityOverloadMessage(List<CapacityOverload> overloads) => overloads
    .map(
      (item) =>
          '${item.day.year}-${item.day.month.toString().padLeft(2, '0')}-${item.day.day.toString().padLeft(2, '0')} 计划 ${item.plannedMinutes} 分钟，超过每日 ${item.limitMinutes} 分钟',
    )
    .join('；');

List<Map<String, dynamic>> replanHistoryEntries(
  List<Map<String, dynamic>> before,
  List<Map<String, dynamic>> after,
  List<ReplanChange> selected,
) {
  final original = {for (final task in before) '${task['id']}': task};
  final planned = {for (final task in after) '${task['id']}': task};
  return [
    for (final change in selected)
      if (original[change.taskId] != null &&
          planned[change.taskId] != null &&
          (original[change.taskId]!['scheduledFor'] !=
                  planned[change.taskId]!['scheduledFor'] ||
              original[change.taskId]!['dueDate'] !=
                  planned[change.taskId]!['dueDate']))
        {
          'taskID': change.taskId,
          'title': original[change.taskId]!['title'],
          'beforeScheduledFor': original[change.taskId]!['scheduledFor'],
          'afterScheduledFor': planned[change.taskId]!['scheduledFor'],
          'beforeDueDate': original[change.taskId]!['dueDate'],
          'afterDueDate': planned[change.taskId]!['dueDate'],
          'reason': change.reason,
        },
  ];
}

List<Map<String, dynamic>> applyReplanToTasks(
  List<Map<String, dynamic>> source,
  String blueprintId,
  List<ReplanChange> selected,
) {
  final changes = {for (final change in selected) change.taskId: change};
  final result = source.map((row) => Map<String, dynamic>.from(row)).toList();
  final changedIds = <String>{};
  for (final row in result) {
    final id = '${row['id']}';
    final change = changes[id];
    if (change == null ||
        row['blueprintID'] != blueprintId ||
        ['completed', 'cancelled', 'unscheduled'].contains(row['status']) ||
        row['isPlanLocked'] == true) {
      continue;
    }
    row['originalScheduledFor'] ??= row['scheduledFor'];
    row['originalDueDate'] ??= row['dueDate'];
    row['scheduledFor'] = change.scheduledFor.toIso8601String();
    row['dueDate'] = change.dueDate?.toIso8601String();
    changedIds.add(id);
  }
  if (changedIds.isEmpty) throw StateError('没有可应用的计划变更');
  final byId = {for (final row in result) '${row['id']}': row};
  for (var pass = 0; pass < result.length; pass++) {
    var adjusted = false;
    for (final row in result.where((e) => changedIds.contains('${e['id']}'))) {
      final dates = <DateTime>[];
      for (final dependency in row['dependencyIDs'] as List? ?? []) {
        final predecessor = byId['$dependency'];
        if (predecessor == null) continue;
        final date = DateTime.tryParse(
          '${predecessor['dueDate'] ?? predecessor['scheduledFor']}',
        );
        if (date != null) dates.add(date);
      }
      if (dates.isNotEmpty) {
        dates.sort();
        final latest = dates.last;
        final scheduled = DateTime.parse('${row['scheduledFor']}');
        if (scheduled.isBefore(latest)) {
          row['scheduledFor'] = latest.toIso8601String();
          adjusted = true;
        }
      }
      final due = DateTime.tryParse('${row['dueDate']}');
      if (due != null &&
          due.isBefore(DateTime.parse('${row['scheduledFor']}'))) {
        row['dueDate'] = DateTime.parse('${row['scheduledFor']}')
            .add(Duration(minutes: row['estimatedMinutes'] as int? ?? 30))
            .toIso8601String();
      }
    }
    if (!adjusted) break;
  }
  return result;
}
