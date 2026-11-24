import 'blueprint_graph.dart';
import 'calendar_plan_logic.dart';

class BlueprintDelayPreview {
  const BlueprintDelayPreview({
    required this.rootId,
    required this.moves,
    required this.affected,
    required this.warnings,
    required this.sourceTasks,
  });

  final String rootId;
  final List<BlueprintTaskEdit> moves;
  final Set<String> affected;
  final Map<String, String> warnings;
  final Map<String, BlueprintTask> sourceTasks;
}

BlueprintDelayPreview previewBlueprintDelay({
  required BlueprintGraph graph,
  required String rootId,
  required DateTime destination,
  required List<BlueprintTask> workspaceTasks,
  required CalendarWorkHours hours,
}) {
  final root = graph.tasks[rootId];
  if (root == null) throw StateError('任务不存在');
  if (CalendarPlanLogic.isLocked(root) || CalendarPlanLogic.isProcessed(root)) {
    throw StateError('已锁定或已处理的任务无法改期');
  }
  if (graph.issues[rootId] case final reason?) throw StateError(reason);
  final affected = graph.downstream(rootId);
  final warnings = <String, String>{};
  final replacements = <String, BlueprintTask>{};

  final nextRoot = {...root};
  CalendarPlanLogic.reschedule(nextRoot, destination);
  replacements[rootId] = nextRoot;
  final endById = <String, DateTime>{};
  DateTime? ending(BlueprintTask task) =>
      CalendarPlanLogic.taskBlock(task)?.end ??
      CalendarPlanLogic.plannedDate(task);
  for (final id in graph.order) {
    final task = graph.tasks[id]!;
    final current = CalendarPlanLogic.plannedDate(task);
    final start = CalendarPlanLogic.taskBlock(task)?.start ?? current;
    final incoming = [
      for (final source in graph.predecessors[id]!)
        ?endById[source],
    ]..sort();
    final earliest = incoming.lastOrNull;
    final ownEnd = ending(replacements[id] ?? task);
    if (graph.children.containsKey(id) && task['status'] != 'completed') {
      final end = [?ownEnd, ?earliest]
        ..sort();
      if (end.isNotEmpty) endById[id] = end.last;
      continue;
    }
    if (task['status'] == 'completed') {
      final finished = CalendarPlanLogic.parse(task['completedAt']) ?? ownEnd;
      if (finished != null) endById[id] = finished;
      continue;
    }
    if (task['status'] == 'cancelled') continue;
    if (ownEnd != null) endById[id] = ownEnd;
    if (!affected.contains(id) ||
        earliest == null ||
        start == null ||
        current == null ||
        !start.isBefore(earliest)) {
      continue;
    }
    if (CalendarPlanLogic.isLocked(task) || task['status'] == 'inProgress') {
      warnings[id] = '当前安排已锁定或任务正在执行，保留原计划';
      continue;
    }
    final days = CalendarPlanLogic.daysBetween(earliest, start);
    var date = CalendarPlanLogic.addDays(current, days);
    if (CalendarPlanLogic.addDays(start, days).isBefore(earliest)) {
      date = CalendarPlanLogic.addDays(date, 1);
    }
    for (var day = 0; day < 7 && !hours.worksOn(date); day++) {
      date = CalendarPlanLogic.addDays(date, 1);
    }
    final adjusted = {...task};
    CalendarPlanLogic.reschedule(adjusted, date);
    replacements[id] = adjusted;
    endById[id] = ending(adjusted)!;
  }
  for (final entry in replacements.entries) {
    final task = entry.value;
    final date = CalendarPlanLogic.plannedDate(task)!;
    final block = CalendarPlanLogic.taskBlock(task);
    final due = CalendarPlanLogic.parse(task['dueDate']);
    final reasons = <String>[
      if (!hours.worksOn(date)) '日期不在设定工作日内',
      if (due != null && (block?.end ?? date).isAfter(due)) '预计超过任务截止',
    ];
    if (block != null) {
      final conflicts = CalendarPlanLogic.executable(workspaceTasks)
          .where((other) => other['id'] != task['id'])
          .map((other) => replacements[other['id']] ?? other)
          .where(
            (other) =>
                !CalendarPlanLogic.isProcessed(other) &&
                CalendarPlanLogic.taskBlock(other)?.overlaps(block) == true,
          )
          .map((other) => other['title']);
      if (conflicts.isNotEmpty) reasons.add('时间块重叠：${conflicts.join('、')}');
    }
    if (reasons.isNotEmpty) warnings[entry.key] = reasons.join(' · ');
  }
  return BlueprintDelayPreview(
    rootId: rootId,
    moves: [
      for (final entry in replacements.entries)
        if (graph.tasks[entry.key]!['scheduledFor'] !=
                entry.value['scheduledFor'] ||
            graph.tasks[entry.key]!['timeBlock'] != entry.value['timeBlock'])
          (before: graph.tasks[entry.key], after: entry.value),
    ],
    affected: affected,
    warnings: warnings,
    sourceTasks: {...graph.tasks},
  );
}

DateTime? blueprintScheduledFinish(
  BlueprintGraph graph,
  Iterable<String> targetIds,
  CalendarWorkHours hours,
) {
  final targets = targetIds.toSet();
  if (targets.isEmpty) return null;
  final scope = {...targets, for (final id in targets) ...graph.upstream(id)};
  if (scope.any(graph.issues.containsKey)) return null;
  final ends = <String, DateTime>{};
  for (final id in graph.order.where(scope.contains)) {
    final task = graph.tasks[id]!;
    if (task['status'] == 'completed') {
      final actual = CalendarPlanLogic.parse(task['completedAt']);
      if (actual != null) ends[id] = actual;
      continue;
    }
    if (task['status'] == 'blocked' || task['status'] == 'cancelled') {
      return null;
    }
    final requiredEnd = [
      for (final source in graph.predecessors[id]!) ?ends[source],
    ]..sort();
    if (graph.children.containsKey(id)) {
      if (requiredEnd.lastOrNull case final end?) ends[id] = end;
      continue;
    }
    final execution = CalendarPlanLogic.taskBlock(task);
    if (execution == null ||
        !hours.worksOn(execution.start) ||
        !hours.worksOn(execution.end) ||
        (requiredEnd.lastOrNull?.isAfter(execution.start) ?? false)) {
      return null;
    }
    ends[id] = execution.end;
  }
  final results = [for (final id in targets) ?ends[id]]..sort();
  return results.length == targets.length ? results.lastOrNull : null;
}
