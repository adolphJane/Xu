import 'task_rules.dart';

class BlueprintTransfer {
  static Map<String, dynamic> export(
    Map<String, dynamic> snapshot,
    String blueprintId,
  ) {
    final blueprints = snapshot['blueprints'] as List? ?? [];
    final matches = blueprints.where((e) => e is Map && e['id'] == blueprintId);
    if (matches.isEmpty) throw StateError('蓝图不存在');
    List<dynamic> related(String section) => (snapshot[section] as List? ?? [])
        .where((e) => e is Map && e['blueprintID'] == blueprintId)
        .toList();
    return {
      'formatVersion': 1,
      'blueprint': matches.first,
      'stages': related('stages'),
      'milestones': related('milestones'),
      'tasks': related('tasks'),
    };
  }

  static Map<String, dynamic> import(
    Map<String, dynamic> snapshot,
    Map<String, dynamic> package,
    String Function() createId,
  ) {
    if (package['formatVersion'] != 1 || package['blueprint'] is! Map) {
      throw const FormatException('蓝图包格式无效');
    }
    final blueprint = Map<String, dynamic>.from(package['blueprint'] as Map);
    final oldBlueprintId = '${blueprint['id']}';
    if (oldBlueprintId.isEmpty || oldBlueprintId == 'null') {
      throw const FormatException('蓝图 ID 无效');
    }
    final sections = ['stages', 'milestones', 'tasks'];
    final incoming = <String, List<Map<String, dynamic>>>{};
    final ids = <String>{oldBlueprintId};
    for (final section in sections) {
      final raw = package[section];
      if (raw is! List) throw FormatException('$section 无效');
      final rows = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      for (final row in rows) {
        if (row['blueprintID'] != oldBlueprintId || !ids.add('${row['id']}')) {
          throw const FormatException('蓝图关联关系无效或 ID 重复');
        }
      }
      incoming[section] = rows;
    }
    final map = {for (final old in ids) old: createId()};
    String? remap(dynamic value) => value == null ? null : map['$value'];
    blueprint['id'] = map[oldBlueprintId];
    final result = Map<String, dynamic>.from(snapshot);
    result['blueprints'] = [
      ...(snapshot['blueprints'] as List? ?? []),
      blueprint,
    ];
    for (final section in sections) {
      final rows = incoming[section]!.map((original) {
        final row = Map<String, dynamic>.from(original);
        row['id'] = map['${row['id']}'];
        row['blueprintID'] = map[oldBlueprintId];
        for (final field in ['stageID', 'milestoneID', 'parentTaskID']) {
          if (row[field] != null) {
            final id = remap(row[field]);
            if (id == null) throw const FormatException('蓝图包含失效关联');
            row[field] = id;
          }
        }
        if (row['dependencyIDs'] is List) {
          row['dependencyIDs'] = (row['dependencyIDs'] as List)
              .map((e) => remap(e) ?? (throw const FormatException('蓝图包含失效依赖')))
              .toList();
        }
        return row;
      }).toList();
      result[section] = [...(snapshot[section] as List? ?? []), ...rows];
    }
    final tasks = (result['tasks'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    final blueprints = (result['blueprints'] as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
    for (final task in tasks.where(
      (e) => e['blueprintID'] == map[oldBlueprintId],
    )) {
      final error = TaskRules.validate(task, tasks, blueprints);
      if (error != null) throw FormatException(error);
    }
    return result;
  }
}
