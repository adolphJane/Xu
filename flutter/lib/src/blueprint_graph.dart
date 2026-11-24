import 'dart:collection';
import 'dart:math' as math;

import 'task_rules.dart';

typedef BlueprintTask = Map<String, dynamic>;
typedef BlueprintTaskEdit = ({BlueprintTask? before, BlueprintTask after});

class BlueprintForecast {
  const BlueprintForecast(
    this.minutes,
    this.criticalIds,
    this.missingIds,
    this.blockedIds,
  );

  final int? minutes;
  final Set<String> criticalIds;
  final Set<String> missingIds;
  final Set<String> blockedIds;
}

class BlueprintGraph {
  BlueprintGraph(this.blueprint, Iterable<BlueprintTask> rows)
    : tasks = {for (final row in rows) row['id'] as String: row} {
    for (final row in tasks.entries) {
      final id = row.key;
      final task = row.value;
      final dependencyIds = (task['dependencyIDs'] as List? ?? [])
          .map((value) => '$value')
          .toList();
      final unique = dependencyIds.toSet();
      if (unique.length != dependencyIds.length) issues[id] = '存在重复前置任务';
      predecessors[id] = unique.where(tasks.containsKey).toSet();
      if (unique.any((other) => !tasks.containsKey(other))) {
        issues[id] = '存在缺失或不属于此蓝图的前置任务';
      }
      final parent = task['parentTaskID'];
      if (parent is String) children.putIfAbsent(parent, () => {}).add(id);
    }
    for (final id in tasks.keys) {
      predecessors[id]!.addAll(children[id] ?? const {});
      for (final source in predecessors[id]!) {
        successors.putIfAbsent(source, () => {}).add(id);
      }
    }
    final counts = predecessors.map(
      (id, sources) => MapEntry(id, sources.length),
    );
    final queue = Queue.of(counts.keys.where((id) => counts[id] == 0));
    while (queue.isNotEmpty) {
      final id = queue.removeFirst();
      order.add(id);
      for (final target in successors[id] ?? const <String>{}) {
        final count = counts.update(target, (count) => count - 1);
        if (count == 0) queue.add(target);
      }
    }
    for (final entry in counts.entries) {
      if (entry.value > 0) issues[entry.key] = '存在循环等待或依赖循环中的任务';
    }
    final invalidSources = issues.keys.toSet();
    for (final id in invalidSources) {
      for (final target in reachable(id, successors)) {
        issues.putIfAbsent(target, () => '前置链含失效关系');
      }
    }
  }

  final BlueprintTask blueprint;
  final Map<String, BlueprintTask> tasks;
  final Map<String, Set<String>> predecessors = {};
  final Map<String, Set<String>> successors = {};
  final Map<String, Set<String>> children = {};
  final Map<String, String> issues = {};
  final List<String> order = [];

  Set<String> upstream(String id) => reachable(id, predecessors);
  Set<String> downstream(String id) => reachable(id, successors);

  static Set<String> reachable(String id, Map<String, Set<String>> edges) {
    final visited = {id};
    final queue = Queue.of(edges[id] ?? const <String>{});
    while (queue.isNotEmpty) {
      final next = queue.removeFirst();
      if (visited.add(next)) queue.addAll(edges[next] ?? const <String>{});
    }
    return visited..remove(id);
  }

  Iterable<String> parallelWith(String id) {
    if (issues.containsKey(id) || children.containsKey(id)) return const [];
    final related = {id, ...upstream(id), ...downstream(id)};
    return tasks.keys.where(
      (other) =>
          !related.contains(other) &&
          !issues.containsKey(other) &&
          !children.containsKey(other),
    );
  }

  String? startReason(String id) {
    final task = tasks[id];
    if (task == null) return '任务已不存在';
    if (children.containsKey(id)) return '请开始可执行的子任务';
    if (issues[id] case final reason?) return reason;
    final status = task['status'] ?? 'pending';
    if (status == 'inProgress') return '任务已经开始';
    if (status == 'completed') return '请先恢复已完成任务';
    if (![
      'pending',
      'postponed',
      'unscheduled',
      'blocked',
      'cancelled',
    ].contains(status)) {
      return '当前状态无法开始';
    }
    return TaskRules.blockingReason(task, tasks.values.toList(), [blueprint]);
  }

  List<String> get readyIds =>
      tasks.keys.where((id) => startReason(id) == null).toList();

  ({int minutes, int missing}) remainingEffort(Iterable<String> ids) {
    var minutes = 0;
    var missing = 0;
    for (final id in ids.toSet()) {
      final row = tasks[id];
      if (row == null ||
          children.containsKey(id) ||
          ['completed', 'cancelled'].contains(row['status'])) {
        continue;
      }
      final estimate =
          row[row['status'] == 'inProgress'
              ? 'remainingMinutes'
              : 'estimatedMinutes'];
      if (estimate is int && estimate >= 0) {
        minutes += estimate;
      } else {
        missing++;
      }
    }
    return (minutes: minutes, missing: missing);
  }

  BlueprintForecast forecast(Iterable<String> targetIds) {
    final targets = targetIds.where(tasks.containsKey).toSet();
    final relevant = {...targets, for (final id in targets) ...upstream(id)};
    final blocked = <String>{...relevant.where(issues.containsKey)};
    final missing = <String>{};
    final totals = <String, int>{};
    final longestSources = <String, Set<String>>{};
    for (final id in order.where(relevant.contains)) {
      final task = tasks[id]!;
      if (task['status'] == 'completed') {
        totals[id] = 0;
        continue;
      }
      if (task['status'] == 'blocked' || task['status'] == 'cancelled') {
        blocked.add(id);
      }
      final sources = predecessors[id]!.where(totals.containsKey);
      final maximum = sources.fold(
        0,
        (value, source) => math.max(value, totals[source]!),
      );
      longestSources[id] = sources
          .where((source) => totals[source] == maximum)
          .toSet();
      final summary = children.containsKey(id);
      final estimate =
          task[task['status'] == 'inProgress'
              ? 'remainingMinutes'
              : 'estimatedMinutes'];
      if (!summary && (estimate is! int || estimate < 0)) missing.add(id);
      totals[id] =
          maximum + (summary || estimate is! int ? 0 : math.max(0, estimate));
    }
    final longest = targets.fold(
      0,
      (value, target) => math.max(value, totals[target] ?? 0),
    );
    final critical = <String>{};
    if (blocked.isEmpty && missing.isEmpty) {
      for (final target in targets.where(
        (target) => totals[target] == longest,
      )) {
        critical.addAll({target, ...reachable(target, longestSources)});
      }
      critical.removeWhere((id) => tasks[id]!['status'] == 'completed');
    }
    return BlueprintForecast(
      targets.isEmpty || blocked.isNotEmpty || missing.isNotEmpty
          ? null
          : longest,
      critical,
      missing,
      blocked,
    );
  }
}
