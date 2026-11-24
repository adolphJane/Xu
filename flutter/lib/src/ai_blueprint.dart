import 'dart:convert';

import 'blueprint_graph.dart';
import 'replan.dart';

class AiBlueprintDraft {
  final String name;
  final String goal;
  final DateTime startDate;
  final DateTime dueDate;
  final List<AiStageDraft> stages;
  const AiBlueprintDraft(
    this.name,
    this.goal,
    this.startDate,
    this.dueDate,
    this.stages,
  );

  static AiBlueprintDraft parse(
    String response,
    int dailyMinutes, {
    DateTime? deadline,
  }) {
    final start = response.indexOf('{'), end = response.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('AI 未返回有效蓝图 JSON');
    }
    final json =
        jsonDecode(response.substring(start, end + 1)) as Map<String, dynamic>;
    DateTime date(Object? value) =>
        DateTime.tryParse('$value') ?? (throw const FormatException('蓝图日期无效'));
    final stagesRaw = json['stages'];
    if (stagesRaw is! List || stagesRaw.length < 2 || stagesRaw.length > 6) {
      throw const FormatException('蓝图须包含 2～6 个阶段');
    }
    final stages = <AiStageDraft>[];
    for (final raw in stagesRaw) {
      final stage = Map<String, dynamic>.from(raw as Map);
      final tasksRaw = stage['tasks'];
      if (tasksRaw is! List || tasksRaw.isEmpty || tasksRaw.length > 8) {
        throw const FormatException('每个阶段须包含 1～8 项任务');
      }
      final tasks = <AiBlueprintTask>[];
      for (final entry in tasksRaw) {
        final item = Map<String, dynamic>.from(entry as Map);
        final planned = date(item['scheduledFor']);
        final due = item['dueDate'] == null ? null : date(item['dueDate']);
        final minutes = item['estimatedMinutes'] is int
            ? item['estimatedMinutes'] as int
            : 30;
        if ('${item['title'] ?? ''}'.trim().isEmpty ||
            minutes < 5 ||
            minutes > 480 ||
            (due != null && due.isBefore(planned))) {
          throw const FormatException('阶段任务标题、时长或日期无效');
        }
        final dependencies = item['dependsOn'];
        if (dependencies != null &&
            (dependencies is! List ||
                dependencies.any((value) => value is! String))) {
          throw const FormatException('AI 草稿的前置任务 ID 无效');
        }
        tasks.add(
          AiBlueprintTask(
            '${item['title']}'.trim(),
            '${item['notes'] ?? ''}',
            planned,
            due,
            minutes,
            switch ('${item['quadrant'] ?? 'schedule'}') {
              'doNow' => 1,
              'schedule' => 2,
              'delegate' => 3,
              'eliminate' => 4,
              _ => throw const FormatException('任务象限无效'),
            },
            draftId: item['id'] as String?,
            dependencies: (dependencies as List?)?.cast<String>() ?? const [],
            dependencyReason: '${item['dependencyReason'] ?? ''}',
          ),
        );
      }
      final first = date(stage['startDate']), last = date(stage['dueDate']);
      if ('${stage['name'] ?? ''}'.trim().isEmpty || last.isBefore(first)) {
        throw const FormatException('阶段名称或日期无效');
      }
      stages.add(
        AiStageDraft(
          '${stage['name']}'.trim(),
          first,
          last,
          '${stage['milestone'] ?? '完成阶段验收'}',
          tasks,
        ),
      );
    }
    final first = date(json['startDate']), last = date(json['dueDate']);
    if ('${json['name'] ?? ''}'.trim().isEmpty || last.isBefore(first)) {
      throw const FormatException('蓝图名称或日期无效');
    }
    if (deadline != null &&
        last.isAfter(
          DateTime(deadline.year, deadline.month, deadline.day, 23, 59, 59),
        )) {
      throw const FormatException('蓝图截止日期超过所选目标日期');
    }
    for (final stage in stages) {
      if (stage.startDate.isBefore(first) ||
          stage.dueDate.isAfter(last) ||
          stage.tasks.any(
            (task) =>
                task.scheduledFor.isBefore(stage.startDate) ||
                task.scheduledFor.isAfter(stage.dueDate),
          )) {
        throw const FormatException('阶段或任务日期超出蓝图范围');
      }
    }
    final draft = AiBlueprintDraft(
      '${json['name']}'.trim(),
      '${json['goal'] ?? ''}',
      first,
      last,
      stages,
    );
    draft.dependenciesFor();
    final preview = draft.tasks
        .map(
          (task) => <String, dynamic>{
            'id': task.title,
            'status': 'pending',
            'scheduledFor': task.scheduledFor.toIso8601String(),
            'estimatedMinutes': task.estimatedMinutes,
          },
        )
        .toList();
    final overloads = replanCapacityOverloads(
      preview,
      preview.map((row) => '${row['id']}').toSet(),
      dailyMinutes,
    );
    if (overloads.isNotEmpty) {
      throw FormatException(capacityOverloadMessage(overloads));
    }
    return draft;
  }

  Iterable<AiBlueprintTask> get tasks => stages.expand((stage) => stage.tasks);

  Map<String, AiBlueprintTask> get taskEntries => {
    for (var stage = 0; stage < stages.length; stage++)
      for (var task = 0; task < stages[stage].tasks.length; task++)
        '$stage:$task': stages[stage].tasks[task],
  };

  Map<String, Set<String>> dependenciesFor({
    Set<String> excluded = const {},
    Map<String, Set<String>> overrides = const {},
    bool chainStages = false,
  }) {
    final entries = taskEntries;
    final byId = <String, String>{};
    for (final entry in entries.entries) {
      final id = entry.value.draftId ?? entry.key;
      if (id.isEmpty || byId.containsKey(id)) {
        throw const FormatException('AI 草稿包含重复或空任务 ID');
      }
      byId[id] = entry.key;
    }
    final selected = entries.keys
        .where((key) => !excluded.contains(key))
        .toSet();
    final result = <String, Set<String>>{};
    for (final key in selected) {
      final task = entries[key]!;
      final dependencies =
          overrides[key] ??
          {
            for (final id in task.dependencies)
              byId[id] ?? (throw const FormatException('AI 草稿引用了不存在的任务')),
          };
      result[key] = dependencies.where(selected.contains).toSet();
    }
    if (chainStages) {
      var previous = <String>{};
      for (var stage = 0; stage < stages.length; stage++) {
        final group = selected
            .where((key) => key.startsWith('$stage:'))
            .toSet();
        if (group.isEmpty) continue;
        final intraSources = {
          for (final key in group) ...result[key]!.where(group.contains),
        };
        for (final key in group) {
          if (!result[key]!.any(group.contains)) result[key]!.addAll(previous);
        }
        previous = group.difference(intraSources);
      }
    }
    final graph = BlueprintGraph({}, [
      for (final entry in result.entries)
        {'id': entry.key, 'dependencyIDs': entry.value.toList()},
    ]);
    if (graph.issues.isNotEmpty) throw const FormatException('AI 草稿包含循环依赖');
    return result;
  }

  static String prompt(String goal, DateTime deadline, int dailyMinutes) =>
      '''你是严谨的项目规划助手。根据目标生成可执行蓝图，只返回 JSON，不要 Markdown。
当前日期：${DateTime.now().toIso8601String()}；截止日期：${deadline.toIso8601String()}；每日可用 $dailyMinutes 分钟。
JSON：{"name":"", "goal":"", "startDate":"ISO8601", "dueDate":"ISO8601", "stages":[{"name":"", "startDate":"ISO8601", "dueDate":"ISO8601", "milestone":"", "tasks":[{"id":"唯一任务ID", "dependsOn":[], "dependencyReason":"", "title":"", "scheduledFor":"ISO8601", "dueDate":null, "estimatedMinutes":30, "quadrant":"doNow|schedule|delegate|eliminate", "notes":""}]}]}
要求 2～6 个阶段，每阶段 1～8 项任务，每日任务时长不超过容量，只填写真实必要的前置任务 ID，支持并行分支和汇合，不因阶段顺序添加全组依赖。不编造外部事实。用户目标：$goal''';
}

class AiStageDraft {
  final String name;
  final DateTime startDate;
  final DateTime dueDate;
  final String milestone;
  final List<AiBlueprintTask> tasks;
  const AiStageDraft(
    this.name,
    this.startDate,
    this.dueDate,
    this.milestone,
    this.tasks,
  );
}

class AiBlueprintTask {
  final String title;
  final String notes;
  final DateTime scheduledFor;
  final DateTime? dueDate;
  final int estimatedMinutes;
  final int quadrant;
  final String? draftId;
  final List<String> dependencies;
  final String dependencyReason;
  const AiBlueprintTask(
    this.title,
    this.notes,
    this.scheduledFor,
    this.dueDate,
    this.estimatedMinutes,
    this.quadrant, {
    this.draftId,
    this.dependencies = const [],
    this.dependencyReason = '',
  });
}
