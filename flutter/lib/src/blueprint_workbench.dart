import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'blueprint_graph.dart';
import 'blueprint_images.dart';
import 'blueprint_planning.dart';
import 'blueprint_tools.dart';
import 'calendar_plan_logic.dart';
import 'design_system/components/xu_shell.dart';
import 'plan_history.dart';
import 'task_rules.dart';
import 'workflow.dart';
import 'workspace.dart';

typedef BlueprintEditor = Future<void> Function(
  BuildContext context,
  String section, {
  BlueprintTask? existing,
  BlueprintTask? defaults,
});

enum _View { list, canvas, details }

enum _Scope { all, ready, running, waiting, overdue }

enum _Inspector { task, relations, images }

enum _AddMode { chain, parallel, insert, split }

class BlueprintWorkbench extends StatefulWidget {
  const BlueprintWorkbench({
    super.key,
    required this.id,
    required this.vm,
    required this.edit,
    required this.replan,
    this.initialTaskId,
  });

  final String id;
  final WorkspaceViewModel vm;
  final String? initialTaskId;
  final BlueprintEditor edit;
  final Future<void> Function(BuildContext context, BlueprintTask blueprint)
  replan;

  @override
  State<BlueprintWorkbench> createState() => _BlueprintWorkbenchState();
}

class _BlueprintWorkbenchState extends State<BlueprintWorkbench> {
  _View view = _View.canvas;
  _Scope scope = _Scope.all;
  _Inspector inspector = _Inspector.task;
  late String? selectedId = widget.initialTaskId;
  String? linkSource;
  late String? focusId = widget.initialTaskId;
  int focusRevision = 0;
  String? milestoneFocus;
  String? stageFocus;
  final checked = <String>{};
  bool busy = false;
  String? message;

  WorkspaceViewModel get vm => widget.vm;

  Future<void> perform(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => message = '$error');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void select(String? id, {bool openDetails = false}) => setState(() {
    selectedId = id;
    milestoneFocus = null;
    if (openDetails) view = _View.details;
  });

  void _focusTask(String id) => setState(() {
    selectedId = id;
    milestoneFocus = null;
    focusId = id;
    focusRevision++;
    view = _View.canvas;
  });

  void _startLink(String id) {
    _focusTask(id);
    setState(() => linkSource = id);
  }

  void _selectNode(
    BlueprintGraph graph,
    BlueprintTask task, {
    required bool wide,
  }) {
    if (linkSource case final source?) {
      if (source != task['id']) unawaited(_previewLink(graph, source, task));
      return;
    }
    select(task['id'] as String, openDetails: !wide && view != _View.canvas);
  }

  Future<void> _previewLink(
    BlueprintGraph graph,
    String source,
    BlueprintTask target,
  ) async {
    if (busy || !graph.tasks.containsKey(source)) return;
    final ids = (target['dependencyIDs'] as List? ?? [])
        .map((id) => '$id')
        .toSet();
    if (!ids.add(source)) ids.remove(source);
    setState(() => linkSource = null);
    _focusTask(target['id'] as String);
    await _confirmBlueprintEdits(context, graph, [
      (before: target, after: {...target, 'dependencyIDs': ids.toList()}),
    ], (edits) => vm.applyBlueprintTaskEdits(widget.id, edits));
  }

  List<WorkflowNodeAction> _nodeActions(
    BlueprintGraph graph,
    BlueprintTask task,
  ) {
    if (busy || linkSource != null) return const [];
    final id = task['id'] as String;
    return [
      (
        label: '编辑任务',
        icon: Icons.edit_outlined,
        run: () => widget.edit(context, 'tasks', existing: task),
      ),
      (label: '从此任务连接后继', icon: Icons.add_link, run: () => _startLink(id)),
      (
        label: '管理前置连线',
        icon: Icons.alt_route,
        run: () => _editPredecessors(task, graph),
      ),
      (
        label: '追加串行任务',
        icon: Icons.arrow_forward,
        run: () => compose(graph, anchor: task),
      ),
      (
        label: '添加并行分支',
        icon: Icons.call_split,
        run: () => compose(graph, anchor: task, mode: _AddMode.parallel),
      ),
      if ((graph.successors[id] ?? const <String>{}).any(
        (target) =>
            (graph.tasks[target]?['dependencyIDs'] as List? ?? []).contains(id),
      ))
        (
          label: '插入中间任务',
          icon: Icons.add_road,
          run: () => compose(graph, anchor: task, mode: _AddMode.insert),
        ),
      (
        label: '任务参考图',
        icon: Icons.image_outlined,
        run: () => editBlueprintImages(context, vm, 'tasks', task),
      ),
    ];
  }

  Future<void> _findTask(BlueprintGraph graph, {bool link = false}) async {
    var query = '';
    final id = await showDialog<String>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(link ? '选择要连接的后继' : '定位工作流事项'),
          content: SizedBox(
            width: 500,
            height: 360,
            child: Column(
              children: [
                TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: '搜索任务标题',
                  ),
                  onChanged: (value) =>
                      update(() => query = value.trim().toLowerCase()),
                ),
                Expanded(
                  child: ListView(
                    children: [
                      for (final entry in graph.tasks.entries.where(
                        (entry) =>
                            (!link || entry.key != linkSource) &&
                            '${entry.value['title']}'.toLowerCase().contains(
                              query,
                            ),
                      ))
                        ListTile(
                          title: Text('${entry.value['title']}'),
                          onTap: () => Navigator.pop(dialog, entry.key),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('关闭'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || id == null) return;
    if ((link && linkSource != null ? graph.tasks[id] : null)
        case final target?) {
      await _previewLink(graph, linkSource!, target);
    } else {
      _focusTask(id);
    }
  }

  @override
  Widget build(BuildContext context) => Obx(() {
    vm.revision.value;
    final blueprint = vm
        .items('blueprints')
        .where((row) => row['id'] == widget.id)
        .firstOrNull;
    if (blueprint == null) {
      return Dialog(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('蓝图已不存在'),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
            ],
          ),
        ),
      );
    }
    final graph = vm.blueprintGraph(widget.id);
    final selection = graph.tasks[selectedId];
    final ready = graph.readyIds.toSet();
    final now = DateTime.now();
    final focusedStage = vm
        .items('stages')
        .where((row) => row['id'] == stageFocus)
        .firstOrNull;
    final stageTasks = graph.tasks.values.where((task) {
      if (focusedStage != null && task['stageID'] != focusedStage['id']) {
        return false;
      }
      return true;
    }).toList();
    final visibleReady = ready
        .where((id) => stageTasks.any((task) => task['id'] == id))
        .toSet();
    final scoped = stageTasks.where((task) {
      final id = task['id'] as String;
      return switch (scope) {
        _Scope.all => true,
        _Scope.ready => ready.contains(id),
        _Scope.running => task['status'] == 'inProgress',
        _Scope.waiting =>
          !ready.contains(id) &&
              !graph.children.containsKey(id) &&
              !CalendarPlanLogic.isProcessed(task) &&
              task['status'] != 'inProgress',
        _Scope.overdue => _isOverdue(task, now),
      };
    }).toList();
    final focusedMilestone = vm
        .items('milestones')
        .where((row) => row['id'] == milestoneFocus)
        .firstOrNull;
    final targets = focusedMilestone != null
        ? vm.milestoneTasks(milestoneFocus).map((row) => row['id'] as String)
        : selection != null
        ? [selection['id'] as String]
        : graph.tasks.keys.where(
            (id) =>
                graph.successors[id]?.isNotEmpty != true &&
                graph.tasks[id]!['status'] != 'cancelled',
          );
    final forecast = graph.forecast(targets);
    final hours = CalendarWorkHours.fromSettings(
      vm
          .items('settings')
          .where((row) => row['id'] == 'preferences')
          .firstOrNull,
    );
    final finish = blueprintScheduledFinish(graph, targets, hours);
    final milestoneDue = CalendarPlanLogic.parse(
      focusedMilestone?['dueDate'] ?? focusedMilestone?['date'],
    );
    final effort = graph.remainingEffort({
      for (final id in targets) ...{id, ...graph.upstream(id)},
    });
    final forecastLines = [
      if (focusedMilestone != null) '里程碑：${focusedMilestone['name']}',
      if (effort.missing == 0 && effort.minutes > 0)
        '总剩余投入 ${effort.minutes} 分钟'
      else if (effort.minutes > 0)
        '已估算投入 ${effort.minutes} 分钟 · ${effort.missing} 项待补工时',
      _forecastLabel(graph, forecast),
      if (finish != null)
        '当前排期预计完成：${blueprintDate(finish.toIso8601String())}'
            '${milestoneDue != null && finish.isAfter(milestoneDue) ? ' · 有延期风险' : ''}'
      else if (targets.isNotEmpty && forecast.criticalIds.isNotEmpty)
        '尚缺可用的执行时间块，暂无法预计完成日期',
    ];
    return Dialog.fullscreen(
      child: Scaffold(
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 1080;
              final compact =
                  constraints.maxWidth < 560 || constraints.maxHeight < 400;
              final details = _details(blueprint, selection, graph, ready);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(blueprint, graph, compact: compact),
                  if (busy) const LinearProgressIndicator(),
                  if (message != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 6,
                      ),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          message!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                  const Divider(height: 1),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  20,
                                  14,
                                  20,
                                  10,
                                ),
                                child: Wrap(
                                  spacing: 10,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    ChoiceChip(
                                      avatar: const Icon(
                                        Icons.view_list_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('执行列表'),
                                      selected: view == _View.list,
                                      onSelected: (_) =>
                                          setState(() => view = _View.list),
                                    ),
                                    ChoiceChip(
                                      avatar: const Icon(
                                        Icons.account_tree_outlined,
                                        size: 16,
                                      ),
                                      label: const Text('工作流'),
                                      selected: view == _View.canvas,
                                      onSelected: (_) =>
                                          setState(() => view = _View.canvas),
                                    ),
                                    if (!wide)
                                      ChoiceChip(
                                        avatar: const Icon(
                                          Icons.view_sidebar_outlined,
                                          size: 16,
                                        ),
                                        label: const Text('详情'),
                                        selected: view == _View.details,
                                        onSelected: (_) => setState(
                                          () => view = _View.details,
                                        ),
                                      ),
                                    PopupMenuButton<String>(
                                      tooltip: '定位阶段或里程碑',
                                      icon: const Icon(Icons.flag_outlined),
                                      onSelected: (key) => setState(() {
                                        final (type, id) = (
                                          key.substring(0, 1),
                                          key.substring(1),
                                        );
                                        selectedId = null;
                                        if (type == 's') {
                                          stageFocus = id;
                                          view = _View.list;
                                          scope = _Scope.all;
                                          checked.clear();
                                        } else {
                                          milestoneFocus = id;
                                          view = _View.canvas;
                                        }
                                      }),
                                      itemBuilder: (_) => [
                                        for (final row
                                            in vm
                                                .items('stages')
                                                .where(
                                                  (row) =>
                                                      row['blueprintID'] ==
                                                      widget.id,
                                                ))
                                          PopupMenuItem(
                                            value: 's${row['id']}',
                                            child: Text('阶段 · ${row['name']}'),
                                          ),
                                        for (final row
                                            in vm
                                                .items('milestones')
                                                .where(
                                                  (row) =>
                                                      row['blueprintID'] ==
                                                      widget.id,
                                                ))
                                          PopupMenuItem(
                                            value: 'm${row['id']}',
                                            child: Text('里程碑 · ${row['name']}'),
                                          ),
                                        if (![
                                          ...vm.items('stages'),
                                          ...vm.items('milestones'),
                                        ].any(
                                          (row) =>
                                              row['blueprintID'] == widget.id,
                                        ))
                                          const PopupMenuItem(
                                            enabled: false,
                                            child: Text('在蓝图概览中添加阶段或里程碑'),
                                          ),
                                      ],
                                    ),
                                    if (view == _View.canvas &&
                                        graph.tasks.isNotEmpty)
                                      TextButton.icon(
                                        onPressed: () => _findTask(graph),
                                        icon: const Icon(Icons.search),
                                        label: const Text('定位事项'),
                                      ),
                                    if (view == _View.canvas &&
                                        selection != null &&
                                        linkSource == null)
                                      TextButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => _startLink(
                                                selection['id'] as String,
                                              ),
                                        icon: const Icon(Icons.add_link),
                                        label: const Text('连接后继'),
                                      ),
                                    if (visibleReady.isNotEmpty)
                                      TextButton(
                                        onPressed: busy
                                            ? null
                                            : () => setState(() {
                                                checked
                                                  ..clear()
                                                  ..addAll(visibleReady);
                                                view = _View.list;
                                                scope = _Scope.ready;
                                              }),
                                        child: Text(
                                          '全选可开始 · ${visibleReady.length}',
                                        ),
                                      ),
                                    if (focusedStage != null)
                                      InputChip(
                                        label: Text('${focusedStage['name']}'),
                                        onDeleted: () =>
                                            setState(() => stageFocus = null),
                                      ),
                                    if (checked.isNotEmpty)
                                      FilledButton.icon(
                                        onPressed: busy
                                            ? null
                                            : () => perform(() async {
                                                await vm.startBlueprintTasks(
                                                  widget.id,
                                                  Set.of(checked),
                                                );
                                                if (mounted) {
                                                  setState(checked.clear);
                                                }
                                              }),
                                        icon: const Icon(Icons.play_arrow),
                                        label: Text('开始选中 · ${checked.length}'),
                                      ),
                                  ],
                                ),
                              ),
                              if (graph.tasks[linkSource] case final source?)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    20,
                                    0,
                                    20,
                                    8,
                                  ),
                                  child: Wrap(
                                    spacing: 10,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                        '连线起点：${source['title']}。选择画布上的后继以预览变更。',
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            _findTask(graph, link: true),
                                        child: const Text('从列表选择后继'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            setState(() => linkSource = null),
                                        child: const Text('结束连线'),
                                      ),
                                    ],
                                  ),
                                ),
                              if (view != _View.details || wide)
                                Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    24,
                                    0,
                                    24,
                                    8,
                                  ),
                                  child: Text(
                                    forecastLines.join('\n'),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ),
                              Expanded(
                                child: IndexedStack(
                                  index: view == _View.details && wide
                                      ? 0
                                      : view.index,
                                  sizing: StackFit.expand,
                                  children: [
                                    _taskList(graph, scoped, ready, now, wide),
                                    WorkflowCanvas(
                                      tasks: graph.tasks.values.toList(),
                                      dependencyLayout: true,
                                      selectedId: selectedId,
                                      highlightedIds: forecast.criticalIds,
                                      statusLabel: (task) =>
                                          _status(task, ready),
                                      focusId: focusId,
                                      focusRevision: focusRevision,
                                      linkSource: linkSource,
                                      nodeActions: (task) =>
                                          _nodeActions(graph, task),
                                      onArrange: busy
                                          ? null
                                          : () => perform(() async {
                                              final layout = automaticPositions(
                                                graph.tasks.values.toList(),
                                                includeHierarchy: false,
                                                useSavedPositions: false,
                                              );
                                              await vm.arrangeBlueprintNodes(
                                                layout.map(
                                                  (id, point) => MapEntry(id, (
                                                    x: point.dx,
                                                    y: point.dy,
                                                  )),
                                                ),
                                              );
                                            }),
                                      onEdit: (task) =>
                                          _selectNode(graph, task, wide: wide),
                                      onMove: (task, point) =>
                                          vm.moveBlueprintNode(
                                            task['id'] as String,
                                            point.dx,
                                            point.dy,
                                          ),
                                      onPreview: (task) => _preview(task),
                                    ),
                                    if (!wide)
                                      details
                                    else
                                      const SizedBox.shrink(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (wide) ...[
                          const VerticalDivider(width: 1),
                          SizedBox(width: 372, child: details),
                        ],
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  });

  Future<void> _saveBaseline(BlueprintTask blueprint) async {
    final existing = blueprint['planBaseline'] != null;
    if (existing) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('更换计划基线'),
          content: const Text('原基线会保留在规划历史中。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('更换'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    await perform(() => vm.saveBlueprintBaseline(widget.id));
  }

  Widget _header(
    BlueprintTask blueprint,
    BlueprintGraph graph, {
    required bool compact,
  }) {
    final total = graph.tasks.length;
    final completed = graph.tasks.values
        .where((row) => row['status'] == 'completed')
        .length;
    final theme = Theme.of(context);
    final title = '${blueprint['name']}';
    final progress = '$completed 项已完成 · $total 项事项';
    final menu = PopupMenuButton<String>(
      tooltip: '蓝图操作',
      onSelected: (action) {
        switch (action) {
          case 'undo':
            perform(vm.undo);
          case 'redo':
            perform(vm.redo);
          case 'overview':
            select(null, openDetails: true);
          case 'history':
            showPlanHistory(context, widget.id);
          case 'ai':
            widget.replan(context, blueprint);
          case 'adopt':
            _adopt();
          case 'template':
            showSaveBlueprintTemplate(context, vm, blueprint);
          case 'review':
            showBlueprintRetrospective(context, vm, graph);
          case 'baseline':
            _saveBaseline(blueprint);
          case 'close':
            perform(() => vm.closeBlueprint(widget.id));
          case 'export':
            perform(() async {
              await FilePicker.saveFile(
                fileName: '蓝图-${blueprint['name']}.json',
                bytes: Uint8List.fromList(
                  utf8.encode(
                    const JsonEncoder.withIndent('  ')
                        .convert(vm.exportBlueprint(widget.id)),
                  ),
                ),
              );
            });
        }
      },
      itemBuilder: (context) => [
        if (compact) ...[
          PopupMenuItem(
            value: 'undo',
            enabled: !busy && vm.undoCount.value > 0,
            child: const Text('撤销蓝图操作'),
          ),
          PopupMenuItem(
            value: 'redo',
            enabled: !busy && vm.redoCount.value > 0,
            child: const Text('重做蓝图操作'),
          ),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(value: 'overview', child: Text('蓝图概览')),
        const PopupMenuItem(value: 'adopt', child: Text('加入已有事项')),
        const PopupMenuItem(value: 'baseline', child: Text('设为计划基线')),
        const PopupMenuItem(value: 'history', child: Text('规划历史')),
        const PopupMenuItem(value: 'review', child: Text('蓝图复盘')),
        const PopupMenuItem(value: 'close', child: Text('完成蓝图')),
        const PopupMenuItem(value: 'template', child: Text('另存为模板')),
        const PopupMenuItem(value: 'ai', child: Text('AI 重新规划')),
        const PopupMenuItem(value: 'export', child: Text('导出蓝图')),
      ],
    );
    final back = IconButton(
      tooltip: '关闭蓝图',
      onPressed: () => Navigator.pop(context),
      icon: const Icon(Icons.arrow_back_rounded),
    );
    final create = busy ? null : () => compose(graph);
    if (compact) {
      return ColoredBox(
        color: theme.colorScheme.surface,
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(4, 4, 4, 8),
          child: Row(
            children: [
              back,
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    Text(progress, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              IconButton.filledTonal(
                tooltip: '添加事项',
                onPressed: create,
                icon: const Icon(Icons.add),
              ),
              menu,
            ],
          ),
        ),
      );
    }

    return ColoredBox(
      color: theme.colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 18, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            back,
            const SizedBox(width: 8),
            Expanded(
              child: XuPageHeader(
                title: title,
                description: progress,
                actions: [
                  IconButton(
                    tooltip: '撤销蓝图操作',
                    onPressed: busy || vm.undoCount.value == 0
                        ? null
                        : () => perform(vm.undo),
                    icon: const Icon(Icons.undo),
                  ),
                  IconButton(
                    tooltip: '重做蓝图操作',
                    onPressed: busy || vm.redoCount.value == 0
                        ? null
                        : () => perform(vm.redo),
                    icon: const Icon(Icons.redo),
                  ),
                  FilledButton.icon(
                    onPressed: create,
                    icon: const Icon(Icons.add),
                    label: const Text('添加事项'),
                  ),
                  menu,
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _taskList(
    BlueprintGraph graph,
    List<BlueprintTask> rows,
    Set<String> ready,
    DateTime now,
    bool wide,
  ) {
    final running = graph.tasks.values
        .where((r) => r['status'] == 'inProgress')
        .length;
    final waiting = graph.tasks.values
        .where(
          (r) =>
              !CalendarPlanLogic.isProcessed(r) &&
              r['status'] != 'inProgress' &&
              !ready.contains(r['id']) &&
              !graph.children.containsKey(r['id']),
        )
        .length;
    final labels = {
      _Scope.all: '全部',
      _Scope.ready: '可开始 ${ready.length}',
      _Scope.running: '进行中 $running',
      _Scope.waiting: '等待 $waiting',
      _Scope.overdue:
          '逾期 ${graph.tasks.values.where((row) => _isOverdue(row, now)).length}',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              for (final entry in labels.entries)
                FilterChip(
                  label: Text(entry.value),
                  selected: scope == entry.key,
                  onSelected: (_) => setState(() => scope = entry.key),
                ),
            ],
          ),
        ),
        Expanded(
          child: rows.isEmpty
              ? Center(
                  child: Text(
                    graph.tasks.isEmpty ? '添加第一项任务，开始编排蓝图' : '该筛选下没有任务',
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  itemCount: rows.length,
                  itemBuilder: (context, index) {
                    final task = rows[index];
                    final id = task['id'] as String;
                    final reason = graph.startReason(id);
                    final label = _status(task, ready);
                    final imageCount = blueprintImages(task['images']).length;
                    final canCheck = ready.contains(id);
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        selected: id == selectedId,
                        leading: Checkbox(
                          semanticLabel: '选择 ${task['title']}',
                          value: checked.contains(id),
                          onChanged:
                              busy || (!canCheck && !checked.contains(id))
                              ? null
                              : (value) => setState(() {
                                  if (value == true) {
                                    checked.add(id);
                                  } else {
                                    checked.remove(id);
                                  }
                                }),
                        ),
                        title: Text('${task['title']}'),
                        subtitle: Text(
                          [
                            label,
                            if (reason != null && label == '等待') reason,
                            if (_isOverdue(task, now)) '已逾期',
                          ].join(' · '),
                        ),
                        trailing: imageCount > 0
                            ? IconButton(
                                tooltip: '预览 $imageCount 张参考图',
                                icon: const Icon(Icons.image_outlined),
                                onPressed: () => _preview(task),
                              )
                            : null,
                        onTap: () => select(id, openDetails: !wide),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _details(
    BlueprintTask blueprint,
    BlueprintTask? task,
    BlueprintGraph graph,
    Set<String> ready,
  ) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
      children: task == null
          ? _overview(blueprint)
          : _taskDetails(task, graph, ready),
    );
  }

  List<Widget> _overview(BlueprintTask blueprint) {
    final stages = vm
        .items('stages')
        .where((row) => row['blueprintID'] == widget.id);
    final milestones = vm
        .items('milestones')
        .where((row) => row['blueprintID'] == widget.id);
    return [
      Text('蓝图概览', style: Theme.of(context).textTheme.titleLarge),
      if ('${blueprint['goal'] ?? ''}'.trim().isNotEmpty)
        Text('${blueprint['goal']}'),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          TextButton(
            onPressed: () =>
                widget.edit(context, 'blueprints', existing: blueprint),
            child: const Text('编辑蓝图'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => perform(
                    () => vm.updateBlueprintFields('blueprints', blueprint, {
                      'status': !['active', null].contains(blueprint['status'])
                          ? 'active'
                          : 'paused',
                    }),
                  ),
            child: Text(
              !['active', null].contains(blueprint['status']) ? '恢复蓝图' : '暂停蓝图',
            ),
          ),
        ],
      ),
      if (blueprint['planBaseline'] case final Map baseline)
        Text(
          '计划基线 · ${blueprintDate(baseline['capturedAt'])} · ${(baseline['tasks'] as List? ?? []).length} 项',
        ),
      _imageSection('蓝图参考图', blueprint, 'blueprints'),
      const Divider(),
      _sectionHeader(
        '阶段',
        () => widget.edit(
          context,
          'stages',
          defaults: {'blueprintID': widget.id},
        ),
      ),
      for (final row in stages) _structureRow('stages', row),
      _sectionHeader(
        '里程碑',
        () => widget.edit(
          context,
          'milestones',
          defaults: {'blueprintID': widget.id},
        ),
      ),
      for (final row in milestones) _structureRow('milestones', row),
    ];
  }

  Widget _sectionHeader(String name, VoidCallback onAdd) => Row(
    children: [
      Expanded(
        child: Text(name, style: Theme.of(context).textTheme.titleMedium),
      ),
      IconButton(
        tooltip: '添加$name',
        icon: const Icon(Icons.add),
        onPressed: onAdd,
      ),
    ],
  );

  Widget _structureRow(String section, BlueprintTask row) => ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text('${row['name']}'),
    subtitle: section == 'milestones'
        ? Text(
            row['isCompleted'] == true
                ? '已完成'
                : row['acceptanceStatus'] == 'ready'
                ? '待验收'
                : '待完成',
          )
        : null,
    leading:
        section == 'milestones' &&
            vm.milestoneTasks(row['id']).isEmpty &&
            (row['acceptanceChecks'] as List? ?? []).isEmpty
        ? Checkbox(
            semanticLabel: '完成里程碑 ${row['name']}',
            value: row['isCompleted'] == true,
            onChanged: busy
                ? null
                : (value) => perform(
                    () => vm.setMilestoneCompleted(row['id'], value == true),
                  ),
          )
        : null,
    onTap: () => widget.edit(context, section, existing: row),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (section == 'stages')
          IconButton(
            tooltip: '查看此阶段的事项',
            icon: const Icon(Icons.filter_alt_outlined),
            onPressed: () => setState(() {
              stageFocus = row['id'] as String;
              view = _View.list;
              scope = _Scope.all;
              checked.clear();
            }),
          ),
        if (section == 'milestones')
          IconButton(
            tooltip: '查看里程碑关键路径',
            icon: const Icon(Icons.alt_route),
            onPressed: () => setState(() {
              selectedId = null;
              milestoneFocus = row['id'] as String;
              view = _View.canvas;
            }),
          ),
        if (section == 'milestones')
          IconButton(
            tooltip: '验收里程碑',
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => showMilestoneAcceptance(context, vm, row),
          ),
        IconButton(
          tooltip: '删除${section == 'stages' ? '阶段' : '里程碑'}',
          icon: const Icon(Icons.delete_outline),
          onPressed: busy
              ? null
              : () async {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: Text('删除「${row['name']}」'),
                      content: const Text('关联事项会保留，可从工作区撤销此操作。'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialog),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(dialog, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                  if (confirmed == true && mounted) {
                    await perform(
                      () => vm.remove(section, row['id'] as String),
                    );
                  }
                },
        ),
      ],
    ),
  );

  List<Widget> _taskDetails(
    BlueprintTask task,
    BlueprintGraph graph,
    Set<String> ready,
  ) {
    final id = task['id'] as String;
    final successors = graph.successors[id] ?? const <String>{};
    final parallel = graph.parallelWith(id).toList();
    final reason = graph.startReason(id);
    final status = _status(task, ready);
    return [
      Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => select(null),
          icon: const Icon(Icons.arrow_back),
          label: const Text('蓝图概览'),
        ),
      ),
      Text('${task['title']}', style: Theme.of(context).textTheme.titleLarge),
      Text(status),
      if (status == '等待' && reason != null) Text(reason),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          if (ready.contains(id))
            FilledButton(
              onPressed: busy
                  ? null
                  : () =>
                        perform(() => vm.startBlueprintTasks(widget.id, {id})),
              child: const Text('开始'),
            ),
          if (task['status'] == 'inProgress' || ready.contains(id))
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() => vm.setTaskStatus(task, 'completed')),
              child: const Text('完成'),
            ),
          if (['completed', 'blocked', 'cancelled'].contains(task['status']))
            OutlinedButton(
              onPressed: busy
                  ? null
                  : () => perform(() => vm.setTaskStatus(task, 'pending')),
              child: const Text('恢复待办'),
            ),
          TextButton(
            onPressed: () => widget.edit(context, 'tasks', existing: task),
            child: const Text('编辑事项'),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final (section, label) in [
            (_Inspector.task, '任务信息'),
            (_Inspector.relations, '关系编排'),
            (_Inspector.images, '参考图'),
          ])
            ChoiceChip(
              label: Text(label),
              selected: inspector == section,
              onSelected: (_) => setState(() => inspector = section),
            ),
        ],
      ),
      const SizedBox(height: 8),
      if (inspector == _Inspector.task) ...[
        if (vm
                .items('stages')
                .where((stage) => stage['id'] == task['stageID'])
                .firstOrNull
            case final stage?)
          Text('阶段 · ${stage['name']}'),
        if (vm
                .items('milestones')
                .where((milestone) => milestone['id'] == task['milestoneID'])
                .firstOrNull
            case final milestone?)
          Text('里程碑 · ${milestone['name']}'),
        Text('计划 · ${blueprintDate(task['scheduledFor'])}'),
        if (task['dueDate'] != null)
          Text('截止 · ${blueprintDate(task['dueDate'])}'),
        if (task['estimatedMinutes'] case final int minutes)
          Text('预计工时 · $minutes 分钟'),
        if ('${task['notes'] ?? ''}'.trim().isNotEmpty)
          Text('${task['notes']}'),
        if (graph.blueprint['planBaseline'] case final Map baseline)
          for (final row
              in (baseline['tasks'] as List? ?? []).whereType<Map>().where(
                (row) => row['id'] == id,
              ))
            Text(
              '基线计划：${blueprintDate(row['scheduledFor'])} · 当前：${blueprintDate(task['scheduledFor'])}',
            ),
        if (!CalendarPlanLogic.isProcessed(task) &&
            !CalendarPlanLogic.isLocked(task))
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () =>
                  showBlueprintMovePreview(context, vm, widget.id, task),
              icon: const Icon(Icons.event_outlined),
              label: const Text('预演调整'),
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : () => _deleteTask(task, graph),
            icon: const Icon(Icons.delete_outline),
            label: const Text('删除事项'),
          ),
        ),
      ],
      if (inspector == _Inspector.images) _imageSection('任务参考图', task, 'tasks'),
      if (inspector == _Inspector.relations) ...[
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: busy ? null : () => _startLink(id),
            icon: const Icon(Icons.add_link),
            label: const Text('从此任务连接后继'),
          ),
        ),
        Text('依赖与分支', style: Theme.of(context).textTheme.titleMedium),
        _related('前置任务链', graph.upstream(id), graph),
        _related('后续受影响', graph.downstream(id), graph),
        _related('流程上可并行', parallel, graph),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            TextButton(
              onPressed: busy ? null : () => _editPredecessors(task, graph),
              child: const Text('编辑前置或汇合'),
            ),
            TextButton(
              onPressed: busy ? null : () => compose(graph, anchor: task),
              child: const Text('添加串行下一步'),
            ),
            TextButton(
              onPressed: busy
                  ? null
                  : () => compose(graph, anchor: task, mode: _AddMode.parallel),
              child: const Text('添加并行分支'),
            ),
            if (!CalendarPlanLogic.isProcessed(task))
              TextButton(
                onPressed: busy
                    ? null
                    : () => compose(graph, anchor: task, mode: _AddMode.split),
                child: const Text('拆分为子任务'),
              ),
            if (successors.any(
              (target) => (graph.tasks[target]?['dependencyIDs'] as List? ?? [])
                  .contains(id),
            ))
              TextButton(
                onPressed: busy
                    ? null
                    : () => compose(graph, anchor: task, mode: _AddMode.insert),
                child: const Text('插入中间任务'),
              ),
          ],
        ),
      ],
    ];
  }

  Future<void> _deleteTask(BlueprintTask task, BlueprintGraph graph) async {
    final id = task['id'] as String;
    final removed = {
      id,
      ...TaskRules.descendants(id, graph.tasks.values.toList()),
    };
    final impacted = graph.tasks.values
        .where(
          (row) =>
              !removed.contains(row['id']) &&
              (row['dependencyIDs'] as List? ?? []).any(removed.contains),
        )
        .toList();
    var reconnect = false;
    final choice = await showDialog<bool>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('删除「${task['title']}」'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('将删除 ${removed.length} 项事项及其参考图，可从工作区撤销。'),
                  if (impacted.isNotEmpty)
                    Text(
                      '直接影响：${impacted.map((row) => row['title']).join('、')}',
                    ),
                  if (impacted.isNotEmpty)
                    SwitchListTile(
                      title: const Text('把原有前置接到后继'),
                      subtitle: const Text('关闭时移除指向被删除事项的连线'),
                      value: reconnect,
                      onChanged: (value) => update(() => reconnect = value),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, reconnect),
              child: const Text('确认删除'),
            ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return;
    await perform(() async {
      await vm.deleteBlueprintNode(widget.id, id, reconnect: choice);
      if (mounted) select(null);
    });
  }

  Widget _related(String title, Iterable<String> ids, BlueprintGraph graph) {
    if (ids.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final id in ids)
                ActionChip(
                  label: Text('${graph.tasks[id]?['title'] ?? id}'),
                  onPressed: () => _focusTask(id),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _imageSection(String heading, BlueprintTask owner, String section) {
    final images = blueprintImages(owner['images']);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          heading,
          () => editBlueprintImages(context, vm, section, owner),
        ),
        if (images.isNotEmpty)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < images.length; i++)
                Tooltip(
                  message: '预览第 ${i + 1} 张参考图',
                  child: InkWell(
                    onTap: () => _preview(owner, index: i),
                    child: SizedBox(
                      width: 86,
                      height: 60,
                      child: BlueprintImageView(
                        image: images[i],
                        thumbnail: true,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        if (images.isNotEmpty)
          TextButton(
            onPressed: () => editBlueprintImages(context, vm, section, owner),
            child: const Text('管理参考图'),
          ),
      ],
    );
  }

  Future<void> _preview(BlueprintTask owner, {int index = 0}) =>
      showBlueprintImagePreview(
        context,
        blueprintImages(owner['images']),
        index,
        '${owner['title'] ?? owner['name']} · 参考图',
      );

  Future<void> compose(
    BlueprintGraph graph, {
    BlueprintTask? anchor,
    _AddMode mode = _AddMode.chain,
  }) => _showBlueprintComposer(
    context,
    graph,
    anchor,
    mode,
    (edits) => vm.applyBlueprintTaskEdits(widget.id, edits),
  );

  Future<void> _editPredecessors(
    BlueprintTask task,
    BlueprintGraph graph,
  ) async {
    final selected = (task['dependencyIDs'] as List? ?? [])
        .map((value) => '$value')
        .toSet();
    final next = await showDialog<Set<String>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('「${task['title']}」的前置任务'),
          content: SizedBox(
            width: 480,
            height: 380,
            child: ListView(
              children: [
                const Text('所有前置任务完成后才可开始。'),
                for (final id in {
                  ...selected,
                  ...graph.tasks.keys,
                }..remove(task['id']))
                  CheckboxListTile(
                    title: Text('${graph.tasks[id]?['title'] ?? '已失效的前置任务'}'),
                    value: selected.contains(id),
                    onChanged: (value) => update(() {
                      if (value == true) {
                        selected.add(id);
                      } else {
                        selected.remove(id);
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
              onPressed: () => Navigator.pop(dialog, selected),
              child: const Text('查看变更'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || next == null) return;
    await _confirmBlueprintEdits(context, graph, [
      (before: task, after: {...task, 'dependencyIDs': next.toList()}),
    ], (edits) => vm.applyBlueprintTaskEdits(widget.id, edits));
  }

  Future<void> _adopt() async {
    final available = vm.tasks
        .where(
          (row) => row['blueprintID'] == null && row['parentTaskID'] == null,
        )
        .toList();
    final selected = await showDialog<BlueprintTask>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('加入已有事项'),
        content: SizedBox(
          width: 480,
          height: 340,
          child: ListView(
            children: [
              if (available.isEmpty) const Text('没有未归属蓝图的事项'),
              for (final task in available)
                ListTile(
                  title: Text('${task['title']}'),
                  onTap: () => Navigator.pop(dialog, task),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final ids = {
      selected['id'],
      ...TaskRules.descendants(selected['id'] as String, vm.tasks),
    };
    await _confirmBlueprintEdits(context, vm.blueprintGraph(widget.id), [
      for (final task in vm.tasks.where((row) => ids.contains(row['id'])))
        (before: task, after: {...task, 'blueprintID': widget.id}),
    ], (edits) => vm.applyBlueprintTaskEdits(widget.id, edits));
  }
}

bool _isOverdue(BlueprintTask task, DateTime now) =>
    !CalendarPlanLogic.isProcessed(task) &&
    CalendarPlanLogic.parse(task['dueDate'])?.isBefore(now) == true;

String _status(BlueprintTask task, Set<String> ready) =>
    switch (task['status']) {
      'inProgress' => '进行中',
      'completed' => '已完成',
      'cancelled' => '已取消',
      'blocked' => '手动阻塞',
      _ => ready.contains(task['id']) ? '可开始' : '等待',
    };

String _forecastLabel(BlueprintGraph graph, BlueprintForecast forecast) {
  if (graph.tasks.isEmpty) return '按交付顺序连接任务，可在中间安排并行分支';
  if (forecast.blockedIds.isNotEmpty) {
    return '流程受阻 · ${forecast.blockedIds.length} 项有阻塞或依赖异常';
  }
  if (forecast.missingIds.isNotEmpty) {
    return '待补估时 · ${forecast.missingIds.length} 项缺少剩余工时';
  }
  final minutes = forecast.minutes;
  if (minutes == null) return '请选择要分析的任务';
  final names = graph.order
      .where(forecast.criticalIds.contains)
      .map((id) => graph.tasks[id]!['title'])
      .join('、');
  return names.isEmpty ? '当前没有剩余工时' : '按依赖估算至少 $minutes 分钟 · 关键路径：$names';
}

Future<void> _showBlueprintComposer(
  BuildContext context,
  BlueprintGraph graph,
  BlueprintTask? anchor,
  _AddMode initialMode,
  Future<void> Function(List<BlueprintTaskEdit>) commit,
) async {
  var input = '';
  var mode = initialMode;
  String? joinId;
  final root = anchor?['id'] as String?;
  final result = await showDialog<List<BlueprintTaskEdit>>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) {
        final targets = mode == _AddMode.insert
            ? graph.tasks.keys.where(
                (id) => (graph.tasks[id]!['dependencyIDs'] as List? ?? [])
                    .contains(root),
              )
            : root == null
            ? <String>[]
            : graph.downstream(root);
        final titles = input
            .split(RegExp(r'\r?\n'))
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty)
            .toList();
        return AlertDialog(
          title: Text(switch (mode) {
            _AddMode.chain => '添加串行任务',
            _AddMode.parallel => '添加并行任务',
            _AddMode.insert => '插入中间任务',
            _AddMode.split => '拆分子任务',
          }),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (anchor != null) Text('当前事项 · ${anchor['title']}'),
                  TextFormField(
                    autofocus: true,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(labelText: '一行一项任务'),
                    onChanged: (value) => update(() => input = value),
                  ),
                  if (initialMode == _AddMode.chain ||
                      initialMode == _AddMode.parallel)
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('并行执行'),
                      value: mode == _AddMode.parallel,
                      onChanged: (value) => update(() {
                        mode = value ? _AddMode.parallel : _AddMode.chain;
                        joinId = null;
                      }),
                    ),
                  if (targets.isNotEmpty &&
                      (mode == _AddMode.parallel || mode == _AddMode.insert))
                    DropdownButtonFormField<String>(
                      initialValue: joinId ?? '',
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: mode == _AddMode.insert
                            ? '插入到此后续事项之前'
                            : '汇合到已有后续事项（可选）',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('选择后续事项'),
                        ),
                        for (final id in targets)
                          DropdownMenuItem(
                            value: id,
                            child: Text(
                              '${graph.tasks[id]!['title']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          update(() => joinId = value == '' ? null : value),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed:
                  titles.isEmpty || (mode == _AddMode.insert && joinId == null)
                  ? null
                  : () {
                      final incoming = <BlueprintTask>[];
                      for (final title in titles) {
                        final predecessors = switch (mode) {
                          _AddMode.parallel => [
                            ...anchor?['dependencyIDs'] as List? ?? [],
                          ],
                          _AddMode.split => <String>[],
                          _ =>
                            incoming.isNotEmpty
                                ? [incoming.last['id'] as String]
                                : root == null
                                ? <String>[]
                                : [root],
                        };
                        incoming.add({
                          'id': newId(),
                          'title': title,
                          'status': 'unscheduled',
                          'createdAt': DateTime.now().toIso8601String(),
                          'blueprintID': graph.blueprint['id'],
                          'stageID': anchor?['stageID'],
                          'milestoneID': anchor?['milestoneID'],
                          if (mode == _AddMode.split) 'parentTaskID': root,
                          'dependencyIDs': predecessors,
                        });
                      }
                      final target = graph.tasks[joinId];
                      Navigator.pop(dialog, <BlueprintTaskEdit>[
                        for (final row in incoming) (before: null, after: row),
                        if (target != null)
                          (
                            before: target,
                            after: {
                              ...target,
                              'dependencyIDs': {
                                for (final dep
                                    in target['dependencyIDs'] as List? ?? [])
                                  if (mode != _AddMode.insert || dep != root)
                                    dep,
                                if (mode == _AddMode.parallel)
                                  ...incoming.map((row) => row['id'])
                                else
                                  incoming.last['id'],
                              }.toList(),
                            },
                          ),
                      ]);
                    },
              child: const Text('预览关系'),
            ),
          ],
        );
      },
    ),
  );
  if (result == null || !context.mounted) return;
  await _confirmBlueprintEdits(context, graph, result, commit);
}

Future<void> _confirmBlueprintEdits(
  BuildContext context,
  BlueprintGraph graph,
  List<BlueprintTaskEdit> edits,
  Future<void> Function(List<BlueprintTaskEdit>) commit,
) async {
  final next = {
    ...graph.tasks,
    for (final edit in edits) edit.after['id'] as String: edit.after,
  };
  final preview = BlueprintGraph(graph.blueprint, next.values);
  final affected = {
    for (final edit in edits) ...preview.downstream(edit.after['id'] as String),
  };
  final failures = [
    for (final edit in edits)
      if (preview.issues[edit.after['id']] ??
              TaskRules.validate(edit.after, next.values.toList(), [
                graph.blueprint,
              ])
          case final reason?)
        '${edit.after['title']}：$reason',
  ];
  var saving = false;
  String? error;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialog) => StatefulBuilder(
      builder: (context, update) => AlertDialog(
        title: const Text('关系变更预览'),
        content: SizedBox(
          width: 540,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final edit in edits) ...[
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('${edit.after['title']}'),
                    subtitle: Text(edit.before == null ? '新增任务' : '更新任务关系'),
                  ),
                  for (final id in edit.after['dependencyIDs'] as List? ?? [])
                    if (!(edit.before?['dependencyIDs'] as List? ?? [])
                        .contains(id))
                      Text(
                        '新增 ${next[id]?['title'] ?? id} → ${edit.after['title']}',
                      ),
                  for (final id in edit.before?['dependencyIDs'] as List? ?? [])
                    if (!(edit.after['dependencyIDs'] as List? ?? []).contains(
                      id,
                    ))
                      Text(
                        '移除 ${graph.tasks[id]?['title'] ?? id} → ${edit.after['title']}',
                      ),
                  if ((edit.before == null ? edit.after['parentTaskID'] : null)
                      case final String parent)
                    Text('父任务 · ${next[parent]?['title']}'),
                ],
                if (affected.isNotEmpty)
                  Text(
                    '后续受影响 · ${affected.map((id) => next[id]?['title']).join('、')}',
                  ),
                for (final failure in failures)
                  Text(
                    failure,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: saving || failures.isNotEmpty
                ? null
                : () async {
                    update(() => saving = true);
                    try {
                      await commit(edits);
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
            child: const Text('确认保存'),
          ),
        ],
      ),
    ),
  );
}
