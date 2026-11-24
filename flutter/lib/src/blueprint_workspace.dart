part of 'workspace.dart';

extension BlueprintWorkspace on WorkspaceViewModel {
  BlueprintGraph blueprintGraph(String blueprintId) {
    final blueprint = _requireTask(blueprintId, items('blueprints'));
    return BlueprintGraph(
      blueprint,
      tasks.where((task) => task['blueprintID'] == blueprintId),
    );
  }

  String? _startReason(
    BlueprintTask task,
    List<BlueprintTask> rows,
    List<BlueprintTask> blueprints,
  ) {
    final id = task['blueprintID'];
    if (id == null) {
      if (['inProgress', 'completed'].contains(task['status'])) return '请先恢复任务';
      return TaskRules.blockingReason(task, rows, blueprints);
    }
    final blueprint = blueprints.where((row) => row['id'] == id).firstOrNull;
    if (blueprint == null) return '蓝图不存在';
    return BlueprintGraph(
      blueprint,
      rows.where((row) => row['blueprintID'] == id),
    ).startReason(task['id'] as String);
  }

  Future<void> startBlueprintTasks(String blueprintId, Set<String> ids) =>
      _write(() => _startTasks(ids, blueprintId: blueprintId));

  Future<void> _startTasks(Set<String> ids, {String? blueprintId}) async {
    if (ids.isEmpty) return;
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    final rows = next['tasks']!;
    final selected = ids.map((id) => _requireTask(id, rows)).toList();
    for (final task in selected) {
      if (blueprintId != null && task['blueprintID'] != blueprintId) {
        throw StateError('任务已不属于此蓝图');
      }
      final error = _startReason(task, rows, next['blueprints']!);
      if (error != null) throw StateError('「${task['title']}」：$error');
    }
    final now = DateTime.now();
    for (final task in selected) {
      _setStatus(task, 'inProgress', now);
    }
    await _saveTaskChange(previous, next);
  }

  Future<void> applyBlueprintTaskEdits(
    String blueprintId,
    List<BlueprintTaskEdit> edits,
  ) => _write(() async {
    if (edits.isEmpty) return;
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    final blueprint = _requireTask(blueprintId, next['blueprints']!);
    final rows = next['tasks']!;
    final changedIds = <String>{};
    for (final edit in edits) {
      final id = edit.after['id'] as String;
      final index = rows.indexWhere((row) => row['id'] == id);
      final current = index < 0 ? null : rows[index];
      if (!changedIds.add(id) ||
          !_sameValue(current, edit.before) ||
          edit.after['blueprintID'] != blueprintId) {
        throw StateError('任务已变更，请重新查看关系预览');
      }
      final row = Map<String, dynamic>.from(edit.after);
      _validatePlanLinks('tasks', row, next);
      if (index < 0) {
        rows.add(row);
      } else {
        rows[index] = row;
      }
    }
    final graph = BlueprintGraph(
      blueprint,
      rows.where((row) => row['blueprintID'] == blueprintId),
    );
    for (final id in changedIds) {
      final task = graph.tasks[id]!;
      final error =
          graph.issues[id] ??
          TaskRules.validate(task, rows, next['blueprints']!);
      if (error != null) throw StateError('「${task['title']}」：$error');
    }
    await _saveTaskChange(previous, next);
  });

  Future<void> moveBlueprintNode(String id, double x, double y) =>
      arrangeBlueprintNodes({id: (x: x, y: y)});

  Future<void> arrangeBlueprintNodes(
    Map<String, ({double x, double y})> positions,
  ) => _write(() async {
    if (positions.isEmpty) return;
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    for (final entry in positions.entries) {
      final row = _requireTask(entry.key, next['tasks']!);
      final point = entry.value;
      row['workflowX'] = point.x;
      row['workflowY'] = point.y;
    }
    await repository.commit(next);
    _record(previous);
    revision.value++;
  });

  Future<void> updateBlueprintFields(
    String section,
    BlueprintTask before,
    BlueprintTask fields,
  ) => _write(() async {
    final current = _requireTask(before['id'], items(section));
    if (fields.keys.any((key) => !_sameValue(before[key], current[key]))) {
      throw StateError('相关字段已有更新，请重新打开后编辑');
    }
    if (fields.containsKey('images')) {
      final blueprintId = section == 'blueprints'
          ? current['id']
          : current['blueprintID'];
      final updatedImages = blueprintImages(fields['images']);
      if (updatedImages.any((row) => blueprintImageBytes(row) == null)) {
        throw StateError('有图片无法保存，请先替换或移除');
      }
      final relatedOwners = blueprintId == null
          ? <BlueprintTask>[]
          : [
              ...items('blueprints').where(
                (row) => row['id'] == blueprintId && row['id'] != current['id'],
              ),
              ...tasks.where(
                (row) =>
                    row['blueprintID'] == blueprintId &&
                    row['id'] != current['id'],
              ),
            ];
      final total =
          [
            ...updatedImages,
            for (final owner in relatedOwners)
              ...blueprintImages(owner['images']),
          ].fold<int>(
            0,
            (sum, image) => sum + ((image['data'] as String?)?.length ?? 0),
          );
      if (total > blueprintImagesMaxBytes * 4 / 3) {
        throw StateError('蓝图参考图总大小超过 24 MB');
      }
    }
    await _put(section, {...current, ...fields});
  });
}

extension BlueprintPlanningWorkspace on WorkspaceViewModel {
  BlueprintDelayPreview previewBlueprintMove(
    String blueprintId,
    String taskId,
    DateTime date,
  ) => previewBlueprintDelay(
    graph: blueprintGraph(blueprintId),
    rootId: taskId,
    destination: date,
    workspaceTasks: tasks,
    hours: CalendarWorkHours.fromSettings(
      items('settings').where((row) => row['id'] == 'preferences').firstOrNull,
    ),
  );

  Future<void> saveBlueprintBaseline(String blueprintId) => _write(() async {
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    final blueprint = _requireTask(blueprintId, next['blueprints']!);
    final baseline = {
      'capturedAt': DateTime.now().toIso8601String(),
      'tasks': [
        for (final row in next['tasks']!.where(
          (row) => row['blueprintID'] == blueprintId,
        ))
          {
            for (final field in [
              'id',
              'title',
              'scheduledFor',
              'dueDate',
              'estimatedMinutes',
              'dependencyIDs',
              'timeBlock',
            ])
              field: row[field],
          },
      ],
    };
    if (blueprint['planBaseline'] case final Map previousBaseline) {
      next['planChanges']!.add({
        'id': newId(),
        'blueprintID': blueprintId,
        'kind': 'baseline',
        'title': '更换计划基线',
        'changedAt': baseline['capturedAt'],
        'baseline': previousBaseline,
      });
    }
    blueprint['planBaseline'] = baseline;
    await repository.commit(next);
    _record(previous);
    revision.value++;
  });

  Future<void> commitBlueprintMove(
    String blueprintId,
    BlueprintDelayPreview preview,
    Set<String> selection,
    String reason,
  ) => _write(() async {
    final current = blueprintGraph(blueprintId);
    if (!_sameValue(current.tasks, preview.sourceTasks)) {
      throw StateError('蓝图任务已变更，请重新推演');
    }
    final selected = preview.moves
        .where((edit) => selection.contains(edit.after['id']))
        .toList();
    if (!selected.any((edit) => edit.after['id'] == preview.rootId)) {
      throw StateError('必须保留本次改期的起始任务');
    }
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    final replacements = {
      for (final edit in selected) edit.after['id']: edit.after,
    };
    final oldTasks = next['tasks']!;
    next['tasks'] = [
      for (final task in oldTasks) replacements[task['id']] ?? task,
    ];
    final changes = [
      for (final edit in selected)
        ReplanChange(
          edit.after['id'] as String,
          DateTime.parse(edit.after['scheduledFor'] as String),
          CalendarPlanLogic.parse(edit.after['dueDate']),
          reason.trim(),
        ),
    ];
    final milestoneIds = {
      for (final id in {...selection, ...preview.affected})
        if (current.tasks[id]?['milestoneID'] case final String milestone)
          milestone,
    };
    next['planChanges']!.add({
      'id': newId(),
      'kind': 'manualReplan',
      'blueprintID': blueprintId,
      'title': '调整 ${selected.length} 项任务',
      'changedAt': DateTime.now().toIso8601String(),
      'entries': replanHistoryEntries(oldTasks, next['tasks']!, changes),
      'beforeTasks': selected.map((edit) => edit.before!).toList(),
      'afterTasks': selected.map((edit) => edit.after).toList(),
      'affectedMilestones': [
        for (final row in next['milestones']!.where(
          (row) => milestoneIds.contains(row['id']),
        ))
          row['name'],
      ],
    });
    await _saveTaskChange(previous, next);
  });

  Future<void> saveMilestoneAcceptance(
    BlueprintTask before,
    List<BlueprintTask> checks,
    List<BlueprintTask> evidence, {
    required bool accept,
  }) => _write(() async {
    final milestone = _requireTask(before['id'], items('milestones'));
    for (final key in [
      'acceptanceChecks',
      'acceptanceEvidence',
      'acceptedAt',
    ]) {
      if (!_sameValue(milestone[key], before[key])) {
        throw StateError('验收内容已变更，请重新打开');
      }
    }
    final now = DateTime.now().toIso8601String();
    if (accept &&
        (checks.isEmpty ||
            !checks.every((row) => row['done'] == true) ||
            !milestoneTasks(milestone['id'])
                .every((row) => row['status'] == 'completed'))) {
      throw StateError('请先完成关联事项和全部检查项');
    }
    for (final ref in evidence) {
      final task = _requireTask(ref['taskID'], tasks);
      if (task['milestoneID'] != milestone['id'] ||
          !(task['images'] as List? ?? []).any(
            (image) => image is Map && image['id'] == ref['imageID'],
          )) {
        throw StateError('引用的成果图已失效');
      }
    }
    await _put('milestones', {
      ...milestone,
      'acceptanceChecks': checks,
      'acceptanceEvidence': evidence,
      'acceptedAt': accept ? now : null,
      'acceptanceHistory': [
        ...milestone['acceptanceHistory'] as List? ?? [],
        if (accept) {'acceptedAt': now, 'checks': checks, 'evidence': evidence},
      ],
    });
  });

  Future<void> saveBlueprintTemplate(
    String blueprintId,
    String name, {
    bool includeImages = false,
  }) => _write(() async {
    if (name.trim().isEmpty) throw StateError('模板名称不能为空');
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    final package = exportBlueprint(blueprintId);
    final blueprint = {...package['blueprint'] as Map};
    blueprint.remove('planBaseline');
    blueprint['status'] = 'active';
    if (!includeImages) blueprint.remove('images');
    package['blueprint'] = blueprint;
    package['tasks'] = [
      for (final row in package['tasks'] as List)
        Map<String, dynamic>.from(row as Map)
          ..removeWhere(
            (key, value) => [
              'statusChangedAt',
              'startedAt',
              'completedAt',
              'autoCompletedAt',
              'originalScheduledFor',
              'originalDueDate',
              'postponements',
              'blockReason',
              'images',
              'calendarEventID',
              'remainingMinutes',
            ].contains(key),
          )
          ..['status'] = row['scheduledFor'] == null
              ? 'unscheduled'
              : 'pending',
    ];
    package['milestones'] = [
      for (final row in package['milestones'] as List)
        Map<String, dynamic>.from(row as Map)
          ..removeWhere(
            (key, value) => [
              'acceptedAt',
              'acceptanceHistory',
              'acceptanceEvidence',
              'acceptanceStatus',
            ].contains(key),
          )
          ..['isCompleted'] = false
          ..['acceptanceChecks'] = [
            for (final check in row['acceptanceChecks'] as List? ?? [])
              {...check as Map, 'done': false},
          ],
    ];
    next['blueprintTemplates']!.add({
      'id': newId(),
      'name': name.trim(),
      'package': package,
    });
    await repository.commit(next);
    _record(previous);
    revision.value++;
  });

  Future<void> createFromSavedBlueprintTemplate(
    String templateId,
    DateTime date,
  ) => _write(() async {
    final template = _requireTask(templateId, items('blueprintTemplates'));
    final package = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(template['package'])) as Map,
    );
    final blueprint = package['blueprint'] as Map;
    final rows = [
      blueprint,
      ...package['stages'] as List,
      ...package['milestones'] as List,
      ...package['tasks'] as List,
    ];
    final dates = [
      for (final row in rows)
        for (final field in ['startDate', 'scheduledFor', 'dueDate', 'date'])
          ?CalendarPlanLogic.parse((row as Map)[field]),
    ]..sort();
    final origin =
        CalendarPlanLogic.parse(blueprint['startDate']) ??
        dates.firstOrNull ??
        date;
    final delta = CalendarPlanLogic.daysBetween(date, origin);
    void shift(Map row, String field) {
      if (CalendarPlanLogic.parse(row[field]) case final value?) {
        row[field] = CalendarPlanLogic.addDays(value, delta).toIso8601String();
      }
    }

    for (final raw in rows.cast<Map>()) {
      for (final field in ['startDate', 'scheduledFor', 'dueDate', 'date']) {
        shift(raw, field);
      }
      if (raw['timeBlock'] case final Map block) {
        shift(block, 'start');
        shift(block, 'end');
      }
    }
    final previous = _copySnapshot();
    final next = BlueprintTransfer.import(previous, package, newId);
    await repository.importSnapshot(next);
    _record(previous);
    revision.value++;
    await updateMenu();
    await syncCalendar();
  });
}

extension BlueprintStructureWorkspace on WorkspaceViewModel {
  Future<void> deleteBlueprintNode(
    String blueprintId,
    String taskId, {
    required bool reconnect,
  }) => _write(() async {
    final graph = blueprintGraph(blueprintId);
    final root = graph.tasks[taskId];
    if (root == null) throw StateError('任务已不存在');
    final removed = {taskId, ...TaskRules.descendants(taskId, tasks)};
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    final rows = next['tasks']!;
    final affected = <String>{};
    final inherited = {
      for (final id in removed)
        ...((graph.tasks[id]?['dependencyIDs'] as List? ?? []).where(
          (dep) => !removed.contains(dep),
        )),
    };
    for (final row in rows.where((row) => !removed.contains(row['id']))) {
      final prerequisites = row['dependencyIDs'] as List? ?? [];
      if (!prerequisites.any(removed.contains)) continue;
      final repaired = {
        ...prerequisites.where((id) => !removed.contains(id)),
        if (reconnect) ...inherited,
      };
      row['dependencyIDs'] = repaired.toList();
      affected.add(row['id'] as String);
    }
    rows.removeWhere((row) => removed.contains(row['id']));
    final amended = BlueprintGraph(
      graph.blueprint,
      rows.where((r) => r['blueprintID'] == blueprintId),
    );
    for (final id in affected) {
      final row = _requireTask(id, rows);
      final error =
          amended.issues[id] ??
          TaskRules.validate(row, rows, next['blueprints']!);
      if (error != null) throw StateError('「${row['title']}」：$error');
    }
    await _saveTaskChange(previous, next);
  });

  Future<void> closeBlueprint(String blueprintId) => _write(() async {
    final graph = blueprintGraph(blueprintId);
    if (graph.tasks.isEmpty ||
        graph.tasks.values.any(
          (task) => !CalendarPlanLogic.isProcessed(task),
        )) {
      throw StateError('请先处理所有剩余事项');
    }
    if (items('milestones').any(
      (row) => row['blueprintID'] == blueprintId && row['isCompleted'] != true,
    )) {
      throw StateError('还有未完成的里程碑');
    }
    await _put('blueprints', {
      ...graph.blueprint,
      'status': 'completed',
      'completedAt': DateTime.now().toIso8601String(),
    });
  });
}
