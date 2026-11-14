class TaskRules {
  static String? validate(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> blueprints,
  ) {
    final id = '${task['id']}';
    final blueprintId = task['blueprintID'];
    final byId = {for (final t in tasks) '${t['id']}': t};
    final parentId = task['parentTaskID'];
    if (parentId != null) {
      final parent = byId['$parentId'];
      if (parent == null ||
          parentId == id ||
          parent['blueprintID'] != blueprintId) {
        return '父任务无效或不属于同一蓝图';
      }
      final seen = <String>{id};
      Map<String, dynamic>? current = parent;
      while (current != null) {
        if (!seen.add('${current['id']}')) return '子任务层级不能形成循环';
        final next = current['parentTaskID'];
        current = next == null ? null : byId['$next'];
      }
    }
    if (tasks.any(
      (child) =>
          child['parentTaskID'] == id && child['blueprintID'] != blueprintId,
    )) {
      return '父任务与子任务必须属于同一蓝图';
    }
    if (task['status'] == 'completed' &&
        tasks.any(
          (child) =>
              child['parentTaskID'] == id && child['status'] != 'completed',
        )) {
      return '请先完成子任务';
    }
    final dependencies = List<String>.from(
      (task['dependencyIDs'] as List?)?.map((e) => '$e') ?? [],
    );
    if (dependencies.toSet().length != dependencies.length) return '前置任务不能重复';
    if (dependencies.isNotEmpty && blueprintId == null) return '请先将任务归入蓝图';
    for (final dependency in dependencies) {
      if (dependency == id) return '任务不能依赖自身';
      final predecessor = byId[dependency];
      if (predecessor == null || predecessor['blueprintID'] != blueprintId) {
        return '前置任务必须属于同一蓝图';
      }
      if (_reaches(dependency, id, byId, <String>{})) return '这条连线会形成循环依赖';
      if (['inProgress', 'completed'].contains(task['status']) &&
          predecessor['status'] != 'completed') {
        return '进行中或已完成的任务不能新增未完成的前置任务';
      }
    }
    if (task['status'] == 'completed' || task['status'] == 'inProgress') {
      return blockingReason(task, tasks, blueprints);
    }
    return null;
  }

  static bool _reaches(
    String from,
    String target,
    Map<String, Map<String, dynamic>> byId,
    Set<String> seen,
  ) {
    if (from == target) return true;
    if (!seen.add(from)) return false;
    for (final id in (byId[from]?['dependencyIDs'] as List? ?? [])) {
      if (_reaches('$id', target, byId, seen)) return true;
    }
    return false;
  }

  static String? blockingReason(
    Map<String, dynamic> task,
    List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> blueprints,
  ) {
    if (task['status'] == 'cancelled') return '任务已取消，请先恢复';
    if (task['status'] == 'blocked') return '任务已阻塞，请先解除阻塞';
    final blueprintId = task['blueprintID'];
    if (blueprintId != null) {
      final matches = blueprints.where((b) => b['id'] == blueprintId);
      if (matches.isEmpty ||
          (matches.first['status'] ?? 'active') != 'active') {
        return '蓝图未处于执行中';
      }
    }
    final byId = {for (final task in tasks) '${task['id']}': task};
    for (final id in (task['dependencyIDs'] as List? ?? [])) {
      final dependency = byId['$id'];
      if (dependency == null || dependency['blueprintID'] != blueprintId) {
        return '存在失效的前置任务';
      }
      if (dependency['status'] != 'completed') {
        return '等待“${dependency['title']}”完成';
      }
    }
    return null;
  }

  static Set<String> descendants(String id, List<Map<String, dynamic>> tasks) {
    final found = <String>{};
    var frontier = <String>[id];
    while (frontier.isNotEmpty) {
      final current = frontier.removeLast();
      for (final task in tasks.where(
        (t) => '${t['parentTaskID']}' == current,
      )) {
        final childId = '${task['id']}';
        if (found.add(childId)) frontier.add(childId);
      }
    }
    return found;
  }
}
