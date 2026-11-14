import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'workspace.dart';
import 'native.dart';
import 'ai.dart';
import 'updates.dart';
import 'workflow.dart';
import 'blueprint_templates.dart';
import 'replan.dart';
import 'reports.dart';
import 'plan_history.dart';
import 'ai_blueprint_dialog.dart';
import 'anniversary_cover.dart';
import 'design_system/xu_theme.dart';
import 'design_system/components/xu_shell.dart';

const pages = <String, (String, IconData)>{
  'today': ('今日', Icons.wb_sunny_outlined),
  'inbox': ('收集箱', Icons.inbox_outlined),
  'tasks': ('事项', Icons.checklist),
  'blueprints': ('蓝图', Icons.account_tree_outlined),
  'quadrants': ('四象限', Icons.grid_view_outlined),
  'calendar': ('日历计划', Icons.calendar_month_outlined),
  'categories': ('分类', Icons.label_outline),
  'anniversaries': ('纪念日', Icons.favorite_border),
  'processed': ('已处理', Icons.check_circle_outline),
  'reports': ('日报', Icons.description_outlined),
  'settings': ('设置', Icons.settings_outlined),
};

class XuApp extends StatelessWidget {
  const XuApp({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = Get.find<WorkspaceViewModel>();
    return Obx(
      () => GetMaterialApp(
        title: '序',
        debugShowCheckedModeBanner: false,
        themeMode: vm.themeMode.value,
        theme: XuTheme.build(Brightness.light),
        darkTheme: XuTheme.build(Brightness.dark),
        home: HomePage(),
      ),
    );
  }
}

class HomePage extends BasePage<WorkspaceViewModel> {
  HomePage({super.key});
  final Set<String> _expandedSeries = <String>{};
  final RxInt _seriesRevision = 0.obs;
  final RxBool _showArchivedBlueprints = false.obs;
  final RxString _taskScope = 'active'.obs;
  @override
  void preBuild() {
    NativeBridge.listen(
      onAddTask: () {
        final context = Get.context;
        if (context != null) showEditor(context, 'tasks');
      },
      onToggleTask: (id) async {
        final task = controller.tasks
            .where((t) => '${t['id']}' == id)
            .firstOrNull;
        if (task != null) await controller.toggleTask(task);
      },
      onShowAnniversaries: () => controller.section.value = 'anniversaries',
      onStartTask: (id) => _runWidgetTask(id, 'inProgress'),
      onCompleteTask: (id) => _runWidgetTask(id, 'completed'),
      onCancelTask: (id) => _runWidgetTask(id, 'cancelled'),
      onAddCompletedTask: () {
        final context = Get.context;
        if (context != null) {
          showEditor(context, 'tasks', defaults: {'status': 'completed'});
        }
      },
      onAddAiTask: () {
        final context = Get.context;
        if (context != null) showAiTaskDraft(context);
      },
      onShowCommandPalette: () {
        final context = Get.context;
        if (context != null) _showCommandPalette(context);
      },
      onShowSettings: () => controller.section.value = 'settings',
    );
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => controller.updateMenu(),
    );
  }

  void _runWidgetTask(String id, String status) {
    final task = controller.tasks
        .where((row) => '${row['id']}' == id)
        .firstOrNull;
    if (task == null) return;
    unawaited(
      controller.setTaskStatus(task, status).catchError((Object error) {
        debugPrint('桌面小组件任务操作失败：$error');
      }),
    );
  }

  Future<void> _showCommandPalette(BuildContext context) async {
    final action = await showDialog<String>(
      context: context,
      builder: (dialog) => SimpleDialog(
        title: const Text('命令面板'),
        children: [
          for (final (label, key) in [
            ('添加事项', 'add'),
            ('添加已完成事项', 'completed'),
            ('用 AI 添加事项', 'ai'),
            ('创建蓝图', 'blueprint'),
            ('AI 创建蓝图', 'aiBlueprint'),
            ('打开设置', 'settings'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(dialog, key),
              child: Text(label),
            ),
        ],
      ),
    );
    if (!context.mounted) return;
    switch (action) {
      case 'add':
        await showEditor(context, 'tasks');
      case 'completed':
        await showEditor(context, 'tasks', defaults: {'status': 'completed'});
      case 'ai':
        await showAiTaskDraft(context);
      case 'blueprint':
        controller.section.value = 'blueprints';
        await showEditor(context, 'blueprints');
      case 'aiBlueprint':
        controller.section.value = 'blueprints';
        await showAiBlueprintDialog(context);
      case 'settings':
        controller.section.value = 'settings';
    }
  }

  Future<void> _showSearch(BuildContext context) async {
    final searchInput = TextEditingController(text: controller.search.value);
    await showDialog<void>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('搜索事项'),
        content: TextField(
          autofocus: true,
          controller: searchInput,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search),
            hintText: '输入事项名称或备注',
          ),
          onChanged: (value) => controller.search.value = value,
        ),
        actions: [
          TextButton(
            onPressed: () {
              controller.search.value = '';
              Navigator.pop(dialog);
            },
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('完成'),
          ),
        ],
      ),
    );
    searchInput.dispose();
  }

  @override
  Widget pageScaffold(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
            const _AddIntent(),
      },
      child: Actions(
        actions: {
          _AddIntent: CallbackAction<_AddIntent>(
            onInvoke: (_) {
              showEditor(context, 'tasks');
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Material(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Row(
              children: [
                Obx(
                  () => XuSidebar(
                    items: [
                      for (final entry in pages.entries)
                        XuNavigationItem(
                          entry.key,
                          entry.value.$1,
                          entry.value.$2,
                        ),
                    ],
                    selected: controller.section.value,
                    onSelect: (key) => controller.section.value = key,
                  ),
                ),
                Expanded(
                  child: Obx(() {
                    controller.revision.value;
                    return _content(context, controller.section.value);
                  }),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, String page) {
    final vm = controller;
    final title = pages[page]!.$1;
    final actions = <Widget>[
      if (page == 'tasks')
        Obx(
          () => PopupMenuButton<String>(
            tooltip: '批量操作',
            enabled: controller.selectedTaskIds.isNotEmpty,
            onSelected: (action) async {
              if (action == 'delete') {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('批量删除事项'),
                    content: Text(
                      '确定删除选中的 ${controller.selectedTaskIds.length} 项事项及其子任务吗？',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dialog, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(dialog, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true || !context.mounted) return;
              }
              try {
                await controller.applyTaskBatch(action);
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'complete', child: Text('批量完成')),
              PopupMenuItem(value: 'cancel', child: Text('批量取消')),
              PopupMenuItem(value: 'today', child: Text('批量安排今天')),
              PopupMenuItem(value: 'delete', child: Text('批量删除')),
            ],
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Text('批量操作（${controller.selectedTaskIds.length}）'),
            ),
          ),
        ),
      if (page == 'blueprints')
        TextButton.icon(
          onPressed: () => showPlanHistory(context, null),
          icon: const Icon(Icons.history),
          label: const Text('AI 变更记录'),
        ),
      if (page == 'blueprints')
        TextButton.icon(
          onPressed: () => showAiBlueprintDialog(context),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('AI 创建蓝图'),
        ),
      if (page == 'blueprints')
        TextButton.icon(
          onPressed: () => showTemplateDialog(context),
          icon: const Icon(Icons.auto_fix_high),
          label: const Text('从模板创建'),
        ),
      if (page == 'blueprints')
        TextButton.icon(
          onPressed: () async {
            try {
              final files = await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['json'],
              );
              if (files.isEmpty || files.single.path == null) return;
              final package = jsonDecode(
                await File(files.single.path!).readAsString(),
              ) as Map<String, dynamic>;
              await controller.importBlueprint(package);
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          },
          icon: const Icon(Icons.file_open_outlined),
          label: const Text('导入蓝图'),
        ),
      if (page == 'tasks' || page == 'inbox' || page == 'processed')
        SizedBox(
          width: 210,
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜索事项',
              isDense: true,
            ),
            onChanged: (value) => controller.search.value = value,
          ),
        ),
      if (page == 'tasks' || page == 'inbox')
        TextButton.icon(
          onPressed: () => showAiTaskDraft(context),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('AI 草稿'),
        ),
      if (page != 'settings' && (page != 'today' || vm.todayTasks.isNotEmpty))
        IconButton(
          tooltip: '添加',
          onPressed: () => page == 'categories'
              ? showCategoryEditor(context)
              : page == 'reports'
              ? showReportEditor(context)
              : showEditor(
                  context,
                  page == 'blueprints'
                      ? 'blueprints'
                      : page == 'anniversaries'
                      ? 'anniversaries'
                      : 'tasks',
                ),
          icon: const Icon(Icons.add),
        ),
    ];
    final primaryAction = actions.isEmpty ? null : actions.removeLast();
    return Column(
      children: [
        XuTopBar(
          section:
              const {
                'inbox',
                'anniversaries',
                'processed',
                'reports',
              }.contains(page)
              ? '记录'
              : '工作区',
          title: title,
          onSearch: () => _showSearch(context),
          onPalette: () => _showCommandPalette(context),
        ),
        if (vm.repository.loadError != null)
          MaterialBanner(
            content: Text(vm.repository.loadError!),
            actions: [
              TextButton(
                onPressed: () => vm.section.value = 'settings',
                child: const Text('查看数据设置'),
              ),
            ],
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 20, 28, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (page == 'today') ...[
                Text(
                  '${DateTime.now().month}月${DateTime.now().day}日 星期${'一二三四五六日'[DateTime.now().weekday - 1]}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
              ],
              Row(
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const Spacer(),
                  ?primaryAction,
                ],
              ),
              if (actions.isNotEmpty) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: actions,
                  ),
                ),
              ],
              if (page == 'today') ...[
                const SizedBox(height: 24),
                const Divider(height: 1),
              ],
            ],
          ),
        ),
        Expanded(
          child: switch (page) {
            'today' => _todayPage(context),
            'inbox' => _taskList(
              context,
              vm.tasks
                  .where(
                    (t) =>
                        t['status'] != 'completed' && t['blueprintID'] == null,
                  )
                  .toList(),
              empty: '收集箱为空',
            ),
            'tasks' => _tasksWorkbench(context),
            'processed' => _taskList(
              context,
              vm.tasks
                  .where(
                    (t) =>
                        t['status'] == 'completed' ||
                        t['status'] == 'cancelled',
                  )
                  .toList(),
              empty: '暂无已处理事项',
            ),
            'quadrants' => _quadrants(context),
            'calendar' => _calendar(context),
            'categories' => _categories(context),
            'blueprints' => _blueprintWorkbench(context),
            'anniversaries' => _records(context, 'anniversaries', '还没有纪念日'),
            'reports' => const ReportsPage(),
            _ => _settings(context),
          },
        ),
      ],
    );
  }

  Widget _empty(String text) =>
      XuEmptyState(icon: Icons.inbox_outlined, title: text);

  Widget _tasksWorkbench(BuildContext context) => Obx(() {
    final all = controller.tasks;
    final byId = {for (final task in all) '${task['id']}': task};
    Map<String, dynamic> rootOf(Map<String, dynamic> task) {
      var current = task;
      final seen = <String>{};
      while (current['parentTaskID'] != null && seen.add('${current['id']}')) {
        final parent = byId['${current['parentTaskID']}'];
        if (parent == null) break;
        current = parent;
      }
      return current;
    }

    final filtered = all.where((task) {
      final root = rootOf(task);
      final status = '${root['status'] ?? 'pending'}';
      return switch (_taskScope.value) {
        'active' => status != 'completed' && status != 'cancelled',
        'inbox' =>
          status != 'completed' &&
              status != 'cancelled' &&
              root['scheduledFor'] == null,
        'processed' => status == 'completed' || status == 'cancelled',
        _ => true,
      };
    }).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 12),
          child: Row(
            children: [
              for (final (label, scope) in [
                ('待处理', 'active'),
                ('收集箱', 'inbox'),
                ('已处理', 'processed'),
                ('全部', 'all'),
              ]) ...[
                ChoiceChip(
                  label: Text(label),
                  selected: _taskScope.value == scope,
                  onSelected: (_) {
                    _taskScope.value = scope;
                    _expandedSeries.clear();
                    _seriesRevision.value++;
                  },
                ),
                const SizedBox(width: 8),
              ],
              const Spacer(),
              Text(
                '${filtered.length} 项匹配',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(child: _taskList(context, filtered, empty: '这个范围还没有事项')),
      ],
    );
  });

  Widget _todayPage(BuildContext context) {
    final visible = controller
        .items('anniversaries')
        .where((row) => row['showOnHome'] != false)
        .toList();
    return Column(
      children: [
        if (visible.isNotEmpty)
          FutureBuilder<List<(Map<String, dynamic>, DateTime)>>(
            future:
                Future.wait(
                  visible.map((row) async {
                    final source = DateTime.tryParse('${row['date']}');
                    if (source == null) return null;
                    try {
                      final next = await NativeBridge.anniversaryNextOccurrence(
                        source,
                        repeatYearly: row['repeatYearly'] == true,
                        lunar: row['calendar'] == 'lunar',
                      );
                      return next == null ? null : (row, next);
                    } catch (_) {
                      return null;
                    }
                  }),
                ).then(
                  (rows) =>
                      rows.nonNulls.toList()
                        ..sort((left, right) => left.$2.compareTo(right.$2)),
                ),
            builder: (context, snapshot) {
              if (snapshot.data?.isEmpty != false) {
                return const SizedBox.shrink();
              }
              final (row, next) = snapshot.data!.first;
              final days = DateTime.utc(next.year, next.month, next.day)
                  .difference(
                    DateTime.utc(
                      DateTime.now().year,
                      DateTime.now().month,
                      DateTime.now().day,
                    ),
                  )
                  .inDays;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: Card(
                  child: ListTile(
                    leading: const Icon(Icons.cake_outlined),
                    title: Text(
                      row['privacyMode'] == true ? '重要日子' : '${row['name']}',
                    ),
                    subtitle: Text(days == 0 ? '就是今天' : '还有 $days 天'),
                    onTap: () => controller.section.value = 'anniversaries',
                  ),
                ),
              );
            },
          ),
        Expanded(
          child:
              controller.todayTasks.isEmpty && controller.search.value.isEmpty
              ? XuEmptyState(
                  icon: Icons.wb_twilight_outlined,
                  title: '今天还没有安排事项',
                  description: '从一件重要的事开始，安排好今天的节奏。',
                  actionLabel: '添加事项',
                  shortcutHint: '⌘  N   快速添加',
                  onAction: () => showEditor(context, 'tasks'),
                )
              : _taskList(context, controller.todayTasks, empty: '没有匹配的事项'),
        ),
      ],
    );
  }

  Widget _taskList(
    BuildContext context,
    List<Map<String, dynamic>> tasks, {
    required String empty,
  }) {
    final query = controller.search.value.trim().toLowerCase();
    if (query.isNotEmpty) {
      tasks = tasks
          .where(
            (task) => ['title', 'notes', 'project', 'category'].any(
              (field) => '${task[field] ?? ''}'.toLowerCase().contains(query),
            ),
          )
          .toList();
    }
    if (tasks.isEmpty) return _empty(empty);
    final matched = tasks;
    final ids = matched.map((task) => '${task['id']}').toSet();
    final roots = matched
        .where((task) => !ids.contains('${task['parentTaskID']}'))
        .toList();
    return Obx(() {
      _seriesRevision.value;
      final expandedIds = _expandedSeries.toSet();
      return ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        itemCount: roots.length,
        itemBuilder: (context, i) {
          final task = roots[i];
          final rootId = '${task['id']}';
          final descendants = <Map<String, dynamic>>[];
          void collect(String parentId) {
            for (final child in matched.where(
              (row) => '${row['parentTaskID']}' == parentId,
            )) {
              descendants.add(child);
              collect('${child['id']}');
            }
          }

          collect(rootId);
          final expanded = expandedIds.contains(rootId);
          final completed = descendants
              .where((row) => row['status'] == 'completed')
              .length;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: expanded
                    ? Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.45)
                    : Theme.of(context).colorScheme.outlineVariant,
              ),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      descendants.isEmpty ? '独立事项' : '任务系列',
                      style: Theme.of(context).textTheme.labelSmall,
                    ),
                  ),
                ),
                ListTile(
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (descendants.isNotEmpty)
                        IconButton(
                          tooltip: expanded ? '收起子任务' : '展开子任务',
                          onPressed: () {
                            if (_expandedSeries.contains(rootId)) {
                              _expandedSeries.remove(rootId);
                            } else {
                              _expandedSeries.add(rootId);
                            }
                            _seriesRevision.value++;
                          },
                          icon: Icon(
                            expanded
                                ? Icons.keyboard_arrow_down
                                : Icons.keyboard_arrow_right,
                          ),
                        ),
                      Checkbox(
                        value: task['status'] == 'completed',
                        onChanged: (_) async {
                          try {
                            await controller.toggleTask(task);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                      ),
                    ],
                  ),
                  title: Text(
                    '${task['title'] ?? ''}',
                    style: TextStyle(
                      decoration: task['status'] == 'completed'
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                  subtitle: Text(
                    [
                      const {
                            'pending': '待办',
                            'inProgress': '进行中',
                            'blocked': '阻塞',
                            'completed': '已完成',
                            'cancelled': '已取消',
                            'unscheduled': '未安排',
                          }['${task['status']}'] ??
                          '待办',
                      task['project'],
                      task['category'],
                      task['scheduledFor']?.toString().split('T').first,
                      if (descendants.isNotEmpty)
                        '$completed/${descendants.length} 项子任务完成',
                    ].where((x) => x != null && '$x'.isNotEmpty).join(' · '),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Obx(
                        () => IconButton(
                          tooltip:
                              controller.selectedTaskIds.contains(
                                '${task['id']}',
                              )
                              ? '取消选择'
                              : '选择事项',
                          icon: Icon(
                            controller.selectedTaskIds.contains('${task['id']}')
                                ? Icons.check_box
                                : Icons.check_box_outline_blank,
                          ),
                          onPressed: () {
                            final id = '${task['id']}';
                            if (!controller.selectedTaskIds.add(id)) {
                              controller.selectedTaskIds.remove(id);
                            }
                          },
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (action) async {
                          if (action == 'edit') {
                            showEditor(context, 'tasks', existing: task);
                            return;
                          }
                          try {
                            if (action == 'delete') {
                              await controller.remove('tasks', '${task['id']}');
                            }
                            if (action == 'child' && context.mounted) {
                              final input = TextEditingController();
                              final name = await showDialog<String>(
                                context: context,
                                builder: (dialog) => AlertDialog(
                                  title: const Text('添加子任务'),
                                  content: TextField(
                                    controller: input,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      labelText: '标题',
                                    ),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(dialog),
                                      child: const Text('取消'),
                                    ),
                                    FilledButton(
                                      onPressed: () => Navigator.pop(
                                        dialog,
                                        input.text.trim(),
                                      ),
                                      child: const Text('添加'),
                                    ),
                                  ],
                                ),
                              );
                              input.dispose();
                              if (name != null && name.isNotEmpty) {
                                await controller.addChild(task, name);
                              }
                            }
                            if (action == 'start') {
                              await controller.setTaskStatus(
                                task,
                                'inProgress',
                              );
                            }
                            if (action == 'block') {
                              await controller.setTaskStatus(
                                task,
                                'blocked',
                                reason: '手动标记',
                              );
                            }
                            if (action == 'cancel') {
                              await controller.setTaskStatus(task, 'cancelled');
                            }
                            if (action == 'restore') {
                              await controller.setTaskStatus(task, 'pending');
                            }
                            if (action == 'today') {
                              await controller.put('tasks', {
                                ...task,
                                'scheduledFor': DateTime.now()
                                    .toIso8601String(),
                              });
                            }
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'edit', child: Text('编辑')),
                          PopupMenuItem(value: 'child', child: Text('添加子任务')),
                          PopupMenuItem(value: 'start', child: Text('开始')),
                          PopupMenuItem(value: 'block', child: Text('标记阻塞')),
                          PopupMenuItem(value: 'cancel', child: Text('取消任务')),
                          PopupMenuItem(value: 'restore', child: Text('恢复待办')),
                          PopupMenuItem(value: 'today', child: Text('安排今天')),
                          PopupMenuItem(value: 'delete', child: Text('删除')),
                        ],
                      ),
                    ],
                  ),
                  onTap: () => showEditor(context, 'tasks', existing: task),
                ),
                if (expanded) ...[
                  const Divider(height: 1),
                  for (final child in descendants)
                    ListTile(
                      contentPadding: const EdgeInsets.only(
                        left: 48,
                        right: 20,
                      ),
                      leading: Checkbox(
                        value: child['status'] == 'completed',
                        onChanged: (_) async {
                          try {
                            await controller.toggleTask(child);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                      ),
                      title: Text(
                        '${child['title'] ?? ''}',
                        style: TextStyle(
                          decoration: child['status'] == 'completed'
                              ? TextDecoration.lineThrough
                              : null,
                        ),
                      ),
                      subtitle: Text('${child['status'] ?? 'pending'}'),
                      onTap: () =>
                          showEditor(context, 'tasks', existing: child),
                    ),
                ],
              ],
            ),
          );
        },
      );
    });
  }

  Widget _blueprintWorkbench(BuildContext context) {
    final blueprints = controller.items('blueprints');
    final roots = controller.tasks
        .where((task) => task['parentTaskID'] == null)
        .toList();
    final color = Theme.of(context).colorScheme;
    return Obx(() {
      final visible = blueprints
          .where(
            (row) => _showArchivedBlueprints.value || row['archivedAt'] == null,
          )
          .toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '从任务出发，按步骤持续推进。',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              Switch(
                value: _showArchivedBlueprints.value,
                onChanged: (value) => _showArchivedBlueprints.value = value,
              ),
              const Text('显示已归档'),
            ],
          ),
          const SizedBox(height: 18),
          if (visible.isEmpty && roots.isEmpty)
            const SizedBox(
              height: 320,
              child: Center(
                child: Text(
                  '还没有蓝图\n创建一份蓝图，把长期目标拆成可执行的步骤。',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                for (final root in roots)
                  SizedBox(
                    width: constraints.maxWidth < 620
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2,
                    child: Builder(
                      builder: (context) {
                        final children = controller.tasks
                            .where((row) => row['parentTaskID'] == root['id'])
                            .toList();
                        final completed = children
                            .where((row) => row['status'] == 'completed')
                            .length;
                        final progress = children.isEmpty
                            ? 0.0
                            : completed / children.length;
                        return Card(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(color: color.outlineVariant),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () => showTaskBlueprintDetail(context, root),
                            child: Padding(
                              padding: const EdgeInsets.all(18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        Icons.account_tree_outlined,
                                        color: color.primary,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          '${root['title']}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    '任务蓝图',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelMedium,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    '${children.length} 项子任务 · $completed 项已完成',
                                  ),
                                  const SizedBox(height: 8),
                                  LinearProgressIndicator(value: progress),
                                  const SizedBox(height: 12),
                                  Text(
                                    '与列表、四象限共用任务',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                for (final row in visible)
                  SizedBox(
                    width: constraints.maxWidth < 620
                        ? constraints.maxWidth
                        : (constraints.maxWidth - 16) / 2,
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                        side: BorderSide(color: color.outlineVariant),
                      ),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => showBlueprintDetail(context, row),
                        child: Padding(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 10,
                                    height: 34,
                                    decoration: BoxDecoration(
                                      color: color.primary,
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      '${row['name']}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Text(
                                    '${(blueprintProgress('${row['id']}', controller.tasks) * 100).round()}%',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              Text(
                                '${row['goal'] ?? '尚未填写目标说明'}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 14),
                              LinearProgressIndicator(
                                value: blueprintProgress(
                                  '${row['id']}',
                                  controller.tasks,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                '${controller.items('stages').where((stage) => stage['blueprintID'] == row['id']).length} 个阶段${row['archivedAt'] == null ? '' : ' · 已归档'}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      );
    });
  }

  Widget _records(BuildContext context, String key, String empty) {
    final rows = controller.items(key);
    if (rows.isEmpty) return _empty(empty);
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      children: [
        for (final row in rows)
          Card(
            child: ListTile(
              leading: key == 'anniversaries' && row['privacyMode'] != true
                  ? _anniversaryCover(row)
                  : null,
              title: Text(
                key == 'anniversaries' && row['privacyMode'] == true
                    ? '重要日子'
                    : '${row['name'] ?? row['content'] ?? ''}',
              ),
              subtitle: key == 'blueprints'
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('${row['goal'] ?? ''}'),
                        const SizedBox(height: 6),
                        LinearProgressIndicator(
                          value: blueprintProgress(
                            '${row['id']}',
                            controller.tasks,
                          ),
                        ),
                        Text(
                          '${(blueprintProgress('${row['id']}', controller.tasks) * 100).round()}% 已完成',
                        ),
                      ],
                    )
                  : key == 'anniversaries'
                  ? _anniversaryDetails(row)
                  : Text(
                      '${row['goal'] ?? row['date'] ?? row['reportDate'] ?? ''}',
                    ),
              onTap: () => key == 'blueprints'
                  ? showBlueprintDetail(context, row)
                  : showEditor(context, key, existing: row),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (key == 'anniversaries' &&
                      row['preparationEnabled'] == true &&
                      row['generatedTaskID'] == null)
                    IconButton(
                      icon: const Icon(Icons.playlist_add_check),
                      tooltip: '预览准备任务',
                      onPressed: () => showPreparationTaskPreview(context, row),
                    ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '删除',
                    onPressed: () => controller.remove(key, '${row['id']}'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _anniversaryDetails(Map<String, dynamic> row) {
    final source = DateTime.tryParse('${row['date']}');
    if (source == null) return const Text('日期无效');
    final lunar = row['calendar'] == 'lunar';
    return FutureBuilder<DateTime?>(
      future: NativeBridge.anniversaryNextOccurrence(
        source,
        repeatYearly: row['repeatYearly'] == true,
        lunar: lunar,
      ),
      builder: (context, snapshot) {
        final next = snapshot.data;
        final detail = snapshot.hasError
            ? '日期计算失败'
            : snapshot.connectionState != ConnectionState.done
            ? '正在计算下一次日期'
            : next == null
            ? '已结束'
            : '下次 ${next.year}-${next.month.toString().padLeft(2, '0')}-${next.day.toString().padLeft(2, '0')}';
        return Text('${lunar ? '农历' : '公历'} · $detail');
      },
    );
  }

  Widget _anniversaryCover(Map<String, dynamic> row) {
    final bytes = anniversaryCoverBytes(row['coverImage']);
    if (bytes == null) return const Icon(Icons.cake_outlined);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.memory(
        bytes,
        width: 52,
        height: 52,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      ),
    );
  }

  Widget _quadrants(BuildContext context) => GridView.count(
    padding: const EdgeInsets.all(24),
    crossAxisCount: 2,
    childAspectRatio: 1.5,
    children: [
      for (var i = 1; i <= 4; i++)
        Card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '第 $i 象限',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Expanded(
                child: _taskList(
                  context,
                  controller.tasks
                      .where(
                        (t) => t['quadrant'] == i && t['status'] != 'completed',
                      )
                      .toList(),
                  empty: '暂无事项',
                ),
              ),
            ],
          ),
        ),
    ],
  );
  Widget _calendar(BuildContext context) {
    final dates =
        controller.tasks.where((t) => t['scheduledFor'] != null).toList()..sort(
          (a, b) => '${a['scheduledFor']}'.compareTo('${b['scheduledFor']}'),
        );
    return CalendarPage(tasks: dates);
  }

  Widget _categories(BuildContext context) {
    final groups = <String, int>{};
    for (final category in controller.items('categories')) {
      groups['${category['name']}'] = 0;
    }
    for (final task in controller.tasks) {
      final name = '${task['category'] ?? ''}'.trim();
      if (name.isNotEmpty) groups[name] = (groups[name] ?? 0) + 1;
    }
    if (groups.isEmpty) return _empty('还没有分类');
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      children: [
        for (final entry in groups.entries)
          Card(
            child: ListTile(
              title: Text(entry.key),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${entry.value} 项'),
                  PopupMenuButton<String>(
                    onSelected: (action) async {
                      if (action == 'rename') {
                        await showCategoryEditor(context, existing: entry.key);
                        return;
                      }
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (dialog) => AlertDialog(
                          title: const Text('删除分类'),
                          content: Text('将“${entry.key}”从事项中移除？'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(dialog, false),
                              child: const Text('取消'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.pop(dialog, true),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await controller.deleteCategory(entry.key);
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'rename', child: Text('重命名')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              onTap: () => showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: Text(entry.key),
                  content: SizedBox(
                    width: 520,
                    height: 400,
                    child: _taskList(
                      context,
                      controller.tasks
                          .where((t) => t['category'] == entry.key)
                          .toList(),
                      empty: '暂无事项',
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _settings(BuildContext context) => ListView(
    padding: const EdgeInsets.all(28),
    children: [
      const Text('外观'),
      OutlinedButton.icon(
        onPressed: () async {
          try {
            final opened = await NativeBridge.openWidget();
            if (opened != true) throw StateError('桌面小组件未能打开');
            controller.widgetStatus.value = '桌面小组件已打开';
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('桌面小组件已打开')));
            }
          } catch (error) {
            controller.widgetStatus.value = '桌面小组件打开失败：$error';
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('$error')));
            }
          }
        },
        icon: const Icon(Icons.widgets_outlined),
        label: const Text('打开桌面小组件'),
      ),
      if (controller.widgetStatus.value.isNotEmpty)
        Text(controller.widgetStatus.value),
      SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.system, label: Text('跟随系统')),
          ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
          ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
        ],
        selected: {controller.themeMode.value},
        onSelectionChanged: (value) => controller.setThemeMode(value.first),
      ),
      const SizedBox(height: 24),
      const Text('提醒'),
      SwitchListTile(
        title: const Text('每日复盘提醒'),
        value: controller.dailyReviewEnabled.value,
        onChanged: (enabled) async {
          try {
            await controller.setDailyReview(
              enabled,
              controller.dailyReviewHour.value,
            );
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('$error')));
            }
          }
        },
      ),
      if (controller.dailyReviewEnabled.value)
        DropdownButtonFormField<int>(
          initialValue: controller.dailyReviewHour.value,
          decoration: const InputDecoration(labelText: '提醒时间'),
          items: [
            for (var hour = 6; hour <= 23; hour++)
              DropdownMenuItem(
                value: hour,
                child: Text('${hour.toString().padLeft(2, '0')}:00'),
              ),
          ],
          onChanged: (hour) async {
            if (hour != null) await controller.setDailyReview(true, hour);
          },
        ),
      const SizedBox(height: 24),
      const Text('DeepSeek API Key'),
      OutlinedButton(
        onPressed: () async {
          final current = await NativeBridge.readApiKey() ?? '';
          final input = TextEditingController(text: current);
          if (!context.mounted) return;
          await showDialog<void>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('DeepSeek API Key'),
              content: TextField(controller: input, obscureText: true),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    await NativeBridge.writeApiKey(input.text.trim());
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                  },
                  child: const Text('保存'),
                ),
              ],
            ),
          );
          input.dispose();
        },
        child: const Text('设置 API Key'),
      ),
      const SizedBox(height: 24),
      const Text('应用更新'),
      OutlinedButton(
        onPressed: () async {
          try {
            final version = await NativeBridge.appVersion() ?? '0.0.0';
            final update = await UpdateService.check(version);
            if (!context.mounted) return;
            await showDialog<void>(
              context: context,
              builder: (dialog) {
                var downloading = false;
                return StatefulBuilder(
                  builder: (dialog, setDialogState) {
                    return AlertDialog(
                      title: Text(
                        update == null ? '已是最新版本' : '发现版本 ${update.version}',
                      ),
                      content: SizedBox(
                        width: 460,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              update == null ? '当前版本：$version' : update.notes,
                            ),
                            if (downloading) ...[
                              const SizedBox(height: 16),
                              const LinearProgressIndicator(),
                              const SizedBox(height: 8),
                              const Text('正在下载并校验 DMG…'),
                            ],
                          ],
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: downloading
                              ? null
                              : () => Navigator.pop(dialog),
                          child: const Text('关闭'),
                        ),
                        if (update != null)
                          FilledButton(
                            onPressed: downloading
                                ? null
                                : () async {
                                    setDialogState(() => downloading = true);
                                    try {
                                      final dmg =
                                          await UpdateService.downloadAndVerify(
                                            update,
                                          );
                                      final opened =
                                          await NativeBridge.openVerifiedUpdate(
                                            dmg.path,
                                          );
                                      if (opened != true) {
                                        throw StateError('系统未能打开已校验的更新包');
                                      }
                                      if (dialog.mounted) Navigator.pop(dialog);
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  '更新包已通过校验，请在打开的磁盘映像中替换应用',
                                                ),
                                              ),
                                            );
                                      }
                                    } catch (error) {
                                      if (dialog.mounted) {
                                        setDialogState(
                                          () => downloading = false,
                                        );
                                      }
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(content: Text('$error')),
                                            );
                                      }
                                    }
                                  },
                            child: const Text('下载并安装'),
                          ),
                      ],
                    );
                  },
                );
              },
            );
          } catch (error) {
            if (context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text('$error')));
            }
          }
        },
        child: const Text('检查更新'),
      ),
      const SizedBox(height: 24),
      const Text('数据'),
      Wrap(
        spacing: 12,
        children: [
          OutlinedButton(
            onPressed: () async {
              await FilePicker.saveFile(
                dialogTitle: '导出数据',
                fileName: '序-备份.json',
                bytes: Uint8List.fromList(
                  utf8.encode(
                    const JsonEncoder.withIndent('  ')
                        .convert(controller.repository.snapshot()),
                  ),
                ),
              );
            },
            child: const Text('导出 JSON 备份'),
          ),
          OutlinedButton(
            onPressed: () async {
              final result = await FilePicker.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['json'],
              );
              if (result.isNotEmpty && result.single.path != null) {
                await controller.importWorkspace(result.single.path!);
              }
            },
            child: const Text('导入 JSON 备份'),
          ),
          OutlinedButton(
            onPressed: () async {
              try {
                final resolving = controller.syncStatus.value.startsWith(
                  '同步冲突',
                );
                final conflict = resolving
                    ? await controller.syncFolder(
                        controller.syncFolderPath.value,
                      )
                    : await controller.selectAndSyncFolder();
                final folder = controller.syncFolderPath.value;
                if (folder.isEmpty) return;
                if (conflict == null || !context.mounted) return;
                final choice = await showDialog<SyncChoice>(
                  context: context,
                  builder: (dialog) => AlertDialog(
                    title: const Text('同步文件存在差异'),
                    content: const Text('请选择要保留的数据，或按 ID 合并两侧记录。'),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(dialog, SyncChoice.useRemote),
                        child: const Text('使用文件夹数据'),
                      ),
                      TextButton(
                        onPressed: () =>
                            Navigator.pop(dialog, SyncChoice.keepLocal),
                        child: const Text('使用本机数据'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(dialog, SyncChoice.merge),
                        child: const Text('合并'),
                      ),
                    ],
                  ),
                );
                if (choice != null) {
                  await controller.syncFolder(folder, choice: choice);
                  controller.syncStatus.value = '同步冲突已解决';
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
            child: Obx(
              () => Text(
                controller.syncStatus.value.startsWith('同步冲突')
                    ? '解决同步冲突'
                    : '选择同步文件夹',
              ),
            ),
          ),
        ],
      ),
      Obx(
        () => Text(
          controller.syncStatus.value.isEmpty
              ? (controller.syncFolderPath.value.isEmpty
                    ? '未设置自动同步文件夹'
                    : '自动同步已启用：${controller.syncFolderPath.value}')
              : controller.syncStatus.value,
        ),
      ),
      const SizedBox(height: 12),
      const Text('Flutter 数据格式 v1；旧版 SwiftData 数据不会自动导入。'),
    ],
  );
}

class _AddIntent extends Intent {
  const _AddIntent();
}

Future<void> showPreparationTaskPreview(
  BuildContext context,
  Map<String, dynamic> anniversary,
) async {
  final source = DateTime.tryParse('${anniversary['date']}');
  if (source == null) return;
  DateTime? occurrence;
  try {
    occurrence = await NativeBridge.anniversaryNextOccurrence(
      source,
      repeatYearly: anniversary['repeatYearly'] == true,
      lunar: anniversary['calendar'] == 'lunar',
    );
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
    return;
  }
  if (!context.mounted) return;
  if (occurrence == null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('纪念日已结束，无法创建准备任务')));
    return;
  }
  final due = occurrence;
  final title = '${anniversary['preparationTaskTitle'] ?? ''}'.trim();
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('确认准备任务'),
      content: Text(
        '${title.isEmpty ? '准备${anniversary['name']}' : title}\n'
        '截止：${due.year}-${due.month}-${due.day}\n'
        '提前 ${anniversary['preparationLeadDays'] ?? 7} 天开始。确认后才会创建事项。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: const Text('暂不创建'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              await Get.find<WorkspaceViewModel>().createAnniversaryPreparation(
                '${anniversary['id']}',
                due,
              );
              if (dialogContext.mounted) Navigator.pop(dialogContext);
            } catch (error) {
              if (dialogContext.mounted) {
                ScaffoldMessenger.of(dialogContext)
                    .showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          },
          child: const Text('确认创建'),
        ),
      ],
    ),
  );
}

Future<void> showEditor(
  BuildContext context,
  String section, {
  Map<String, dynamic>? existing,
  Map<String, dynamic>? defaults,
}) async {
  final vm = Get.find<WorkspaceViewModel>();
  final title = TextEditingController(
    text: '${existing?['title'] ?? existing?['name'] ?? ''}',
  );
  final notes = TextEditingController(
    text:
        '${existing?['notes'] ?? existing?['goal'] ?? existing?['content'] ?? ''}',
  );
  final category = TextEditingController(
    text: '${existing?['category'] ?? ''}',
  );
  final project = TextEditingController(text: '${existing?['project'] ?? ''}');
  final contact = TextEditingController(text: '${existing?['contact'] ?? ''}');
  final preparationTitle = TextEditingController(
    text: '${existing?['preparationTaskTitle'] ?? ''}',
  );
  String reportCategory = '${existing?['reportCategory'] ?? 'projectProgress'}';
  int quadrant = (existing?['quadrant'] as int?) ?? 1;
  bool repeatYearly = existing?['repeatYearly'] != false;
  bool notificationEnabled = existing?['notificationEnabled'] == true;
  String anniversaryCalendar = '${existing?['calendar'] ?? 'solar'}';
  String anniversaryType = '${existing?['type'] ?? 'custom'}';
  int reminderDays = (existing?['reminderDays'] as num?)?.toInt() ?? 7;
  bool showOnHome = existing?['showOnHome'] != false;
  bool showInMenuBar = existing?['showInMenuBar'] != false;
  bool privacyMode = existing?['privacyMode'] == true;
  bool preparationEnabled = existing?['preparationEnabled'] == true;
  String? coverImage = existing?['coverImage'] as String?;
  int preparationLeadDays =
      (existing?['preparationLeadDays'] as num?)?.toInt() ?? 7;
  String blueprintId =
      '${existing?['blueprintID'] ?? defaults?['blueprintID'] ?? ''}';
  final dependencyIds = List<String>.from(
    (existing?['dependencyIDs'] as List?)?.map((e) => '$e') ?? [],
  );
  DateTime date =
      DateTime.tryParse(
        '${existing?['scheduledFor'] ?? existing?['date'] ?? ''}',
      ) ??
      DateTime.now();
  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(
          existing == null
              ? '添加${section == 'tasks'
                    ? '事项'
                    : section == 'blueprints'
                    ? '蓝图'
                    : section == 'reports'
                    ? '日报'
                    : section == 'stages'
                    ? '阶段'
                    : section == 'milestones'
                    ? '里程碑'
                    : '纪念日'}'
              : '编辑',
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (section != 'reports')
                  TextField(
                    controller: title,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: section == 'tasks' ? '标题' : '名称',
                    ),
                  ),
                TextField(
                  controller: notes,
                  maxLines: section == 'reports' ? 8 : 3,
                  decoration: InputDecoration(
                    labelText: section == 'tasks'
                        ? '备注'
                        : section == 'blueprints'
                        ? '目标'
                        : '内容',
                  ),
                ),
                if (section == 'tasks') ...[
                  TextField(
                    controller: project,
                    decoration: const InputDecoration(labelText: '项目'),
                  ),
                  TextField(
                    controller: category,
                    decoration: const InputDecoration(labelText: '分类'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: reportCategory,
                    decoration: const InputDecoration(labelText: '日报分类'),
                    items: const [
                      DropdownMenuItem(
                        value: 'projectProgress',
                        child: Text('项目/测试/开发进度'),
                      ),
                      DropdownMenuItem(
                        value: 'collaboration',
                        child: Text('会议/方案/讨论'),
                      ),
                    ],
                    onChanged: (value) =>
                        reportCategory = value ?? reportCategory,
                  ),
                  DropdownButtonFormField<int>(
                    initialValue: quadrant,
                    decoration: const InputDecoration(labelText: '象限'),
                    items: [
                      for (var i = 1; i <= 4; i++)
                        DropdownMenuItem(value: i, child: Text('第 $i 象限')),
                    ],
                    onChanged: (value) => quadrant = value ?? 1,
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: blueprintId,
                    decoration: const InputDecoration(labelText: '蓝图'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('无蓝图')),
                      for (final blueprint in vm.items('blueprints'))
                        DropdownMenuItem(
                          value: '${blueprint['id']}',
                          child: Text('${blueprint['name']}'),
                        ),
                    ],
                    onChanged: (value) => setState(() {
                      blueprintId = value ?? '';
                      dependencyIds.clear();
                    }),
                  ),
                  if (blueprintId.isNotEmpty) ...[
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('前置任务'),
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        for (final task in vm.tasks.where(
                          (task) =>
                              task['blueprintID'] == blueprintId &&
                              task['id'] != existing?['id'],
                        ))
                          FilterChip(
                            label: Text('${task['title']}'),
                            selected: dependencyIds.contains('${task['id']}'),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                dependencyIds.add('${task['id']}');
                              } else {
                                dependencyIds.remove('${task['id']}');
                              }
                            }),
                          ),
                      ],
                    ),
                  ],
                ],
                if (section == 'anniversaries') ...[
                  Row(
                    children: [
                      if (anniversaryCoverBytes(coverImage) case final bytes?)
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: Image.memory(
                            bytes,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_outlined),
                          ),
                        ),
                      TextButton.icon(
                        onPressed: () async {
                          final picked = await FilePicker.pickFiles(
                            type: FileType.image,
                          );
                          if (picked.isEmpty) return;
                          try {
                            final file = picked.single;
                            if ((file.lengthSync() ?? 0) >
                                anniversaryCoverMaxBytes) {
                              throw const FormatException('封面图片须小于 5 MB');
                            }
                            final bytes = await file.readAsBytes();
                            final encoded = encodeAnniversaryCover(bytes);
                            setState(() => coverImage = encoded);
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                        icon: const Icon(Icons.image_outlined),
                        label: Text(coverImage == null ? '选择封面' : '更换封面'),
                      ),
                      if (coverImage != null)
                        IconButton(
                          tooltip: '移除封面',
                          onPressed: () => setState(() => coverImage = null),
                          icon: const Icon(Icons.close),
                        ),
                    ],
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: anniversaryType,
                    decoration: const InputDecoration(labelText: '类型'),
                    items: const [
                      DropdownMenuItem(value: 'birthday', child: Text('生日')),
                      DropdownMenuItem(
                        value: 'relationship',
                        child: Text('纪念日'),
                      ),
                      DropdownMenuItem(value: 'festival', child: Text('节日')),
                      DropdownMenuItem(value: 'project', child: Text('项目节点')),
                      DropdownMenuItem(value: 'custom', child: Text('其他')),
                    ],
                    onChanged: (value) => anniversaryType = value ?? 'custom',
                  ),
                  TextField(
                    controller: contact,
                    decoration: const InputDecoration(labelText: '联系人（可选）'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: anniversaryCalendar,
                    decoration: const InputDecoration(labelText: '历法'),
                    items: const [
                      DropdownMenuItem(value: 'solar', child: Text('公历')),
                      DropdownMenuItem(value: 'lunar', child: Text('农历')),
                    ],
                    onChanged: (value) =>
                        setState(() => anniversaryCalendar = value ?? 'solar'),
                  ),
                  if (anniversaryCalendar == 'lunar')
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text('选择原始公历日期，应用将按对应农历月日计算；闰月单独计算。'),
                    ),
                  SwitchListTile(
                    title: const Text('每年重复'),
                    value: repeatYearly,
                    onChanged: (value) => setState(() => repeatYearly = value),
                  ),
                  SwitchListTile(
                    title: const Text('通过系统通知提醒'),
                    value: notificationEnabled,
                    onChanged: (value) =>
                        setState(() => notificationEnabled = value),
                  ),
                  if (notificationEnabled)
                    ListTile(
                      title: Text('提前 $reminderDays 天提醒（09:00）'),
                      subtitle: Slider(
                        value: reminderDays.toDouble(),
                        min: 0,
                        max: 365,
                        divisions: 365,
                        label: '$reminderDays 天',
                        onChanged: (value) =>
                            setState(() => reminderDays = value.round()),
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('显示在首页'),
                    value: showOnHome,
                    onChanged: (value) => setState(() => showOnHome = value),
                  ),
                  SwitchListTile(
                    title: const Text('显示在菜单栏'),
                    value: showInMenuBar,
                    onChanged: (value) => setState(() => showInMenuBar = value),
                  ),
                  SwitchListTile(
                    title: const Text('隐私模式（隐藏名称）'),
                    value: privacyMode,
                    onChanged: (value) => setState(() => privacyMode = value),
                  ),
                  SwitchListTile(
                    title: const Text('到期前建议准备任务'),
                    value: preparationEnabled,
                    onChanged: (value) =>
                        setState(() => preparationEnabled = value),
                  ),
                  if (preparationEnabled) ...[
                    DropdownButtonFormField<String>(
                      initialValue: blueprintId,
                      decoration: const InputDecoration(labelText: '准备任务关联蓝图'),
                      items: [
                        const DropdownMenuItem(value: '', child: Text('不关联')),
                        for (final blueprint in vm.items('blueprints'))
                          DropdownMenuItem(
                            value: '${blueprint['id']}',
                            child: Text('${blueprint['name']}'),
                          ),
                      ],
                      onChanged: (value) => blueprintId = value ?? '',
                    ),
                    ListTile(
                      title: Text('提前 $preparationLeadDays 天开始准备'),
                      subtitle: Slider(
                        value: preparationLeadDays.toDouble(),
                        min: 1,
                        max: 365,
                        divisions: 364,
                        label: '$preparationLeadDays 天',
                        onChanged: (value) =>
                            setState(() => preparationLeadDays = value.round()),
                      ),
                    ),
                    TextField(
                      controller: preparationTitle,
                      decoration: const InputDecoration(
                        labelText: '准备任务名称（可选）',
                      ),
                    ),
                    const Text('应用只展示预览，确认后才会创建事项。'),
                  ],
                ],
                Row(
                  children: [
                    Text('日期：${date.toString().split(' ').first}'),
                    IconButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          initialDate: date,
                        );
                        if (picked != null) setState(() => date = picked);
                      },
                      icon: const Icon(Icons.date_range),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              if (section != 'reports' && title.text.trim().isEmpty) return;
              final row = <String, dynamic>{
                ...?defaults,
                ...?existing,
                'id': existing?['id'] ?? newId(),
              };
              if (section == 'tasks') {
                row.addAll({
                  'title': title.text.trim(),
                  'notes': notes.text,
                  'project': project.text,
                  'category': category.text,
                  'reportCategory': reportCategory,
                  'quadrant': quadrant,
                  'blueprintID': blueprintId.isEmpty ? null : blueprintId,
                  'dependencyIDs': dependencyIds,
                  'scheduledFor': date.toIso8601String(),
                  'status': row['status'] ?? 'pending',
                });
                if (existing == null && row['status'] == 'completed') {
                  final now = DateTime.now().toIso8601String();
                  row['completedAt'] = now;
                  row['statusChangedAt'] = now;
                }
              } else if (section == 'blueprints') {
                row.addAll({
                  'name': title.text.trim(),
                  'goal': notes.text,
                  'date': date.toIso8601String(),
                });
              } else if (section == 'reports') {
                row.addAll({
                  'content': notes.text,
                  'reportDate': date.toIso8601String(),
                });
              } else {
                row.addAll({
                  'name': title.text.trim(),
                  'date': date.toIso8601String(),
                });
                if (section == 'anniversaries') {
                  row['notes'] = notes.text;
                  row['coverImage'] = coverImage;
                  row['type'] = anniversaryType;
                  row['contact'] = contact.text.trim();
                  row['calendar'] = anniversaryCalendar;
                  row['repeatYearly'] = repeatYearly;
                  row['notificationEnabled'] = notificationEnabled;
                  row['reminderDays'] = reminderDays;
                  row['showOnHome'] = showOnHome;
                  row['showInMenuBar'] = showInMenuBar;
                  row['privacyMode'] = privacyMode;
                  row['preparationEnabled'] = preparationEnabled;
                  row['preparationLeadDays'] = preparationLeadDays;
                  row['preparationTaskTitle'] = preparationTitle.text.trim();
                  row['blueprintID'] = blueprintId.isEmpty ? null : blueprintId;
                }
              }
              try {
                await vm.put(section, row);
                if (context.mounted) Navigator.pop(context);
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
  title.dispose();
  notes.dispose();
  category.dispose();
  project.dispose();
  contact.dispose();
  preparationTitle.dispose();
}

Future<void> showTaskBlueprintDetail(
  BuildContext context,
  Map<String, dynamic> root,
) async {
  final vm = Get.find<WorkspaceViewModel>();
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('${root['title']} · 任务蓝图'),
      content: SizedBox(
        width: 860,
        height: 580,
        child: Obx(() {
          vm.revision.value;
          final descendants = <Map<String, dynamic>>[root];
          final seen = <String>{'${root['id']}'};
          for (var index = 0; index < descendants.length; index++) {
            final parentId = '${descendants[index]['id']}';
            for (final child in vm.tasks.where(
              (task) => task['parentTaskID'] == parentId,
            )) {
              if (seen.add('${child['id']}')) descendants.add(child);
            }
          }
          return WorkflowCanvas(
            tasks: descendants,
            onEdit: (task) => showEditor(dialog, 'tasks', existing: task),
            onMove: (task, position) => vm.put('tasks', {
              ...task,
              'workflowX': position.dx,
              'workflowY': position.dy,
            }),
          );
        }),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => showEditor(dialog, 'tasks', existing: root),
          icon: const Icon(Icons.edit_outlined),
          label: const Text('编辑主任务'),
        ),
        TextButton.icon(
          onPressed: () async {
            final input = TextEditingController();
            final title = await showDialog<String>(
              context: dialog,
              builder: (inner) => AlertDialog(
                title: const Text('添加子任务'),
                content: TextField(
                  controller: input,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(inner),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(inner, input.text.trim()),
                    child: const Text('添加'),
                  ),
                ],
              ),
            );
            input.dispose();
            if (title != null && title.isNotEmpty) {
              await vm.addChild(root, title);
            }
          },
          icon: const Icon(Icons.add),
          label: const Text('添加子任务'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Future<void> showBlueprintDetail(
  BuildContext context,
  Map<String, dynamic> blueprint,
) async {
  final vm = Get.find<WorkspaceViewModel>();
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text('${blueprint['name']}'),
      content: SizedBox(
        width: 620,
        height: 540,
        child: Obx(() {
          vm.revision.value;
          final id = blueprint['id'];
          final stages = vm
              .items('stages')
              .where((e) => e['blueprintID'] == id)
              .toList();
          final milestones = vm
              .items('milestones')
              .where((e) => e['blueprintID'] == id)
              .toList();
          final tasks = vm.tasks.where((e) => e['blueprintID'] == id).toList();
          return ListView(
            children: [
              Text('${blueprint['goal'] ?? ''}'),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('阶段'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => showEditor(
                      dialog,
                      'stages',
                      defaults: {'blueprintID': id},
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('添加阶段'),
                  ),
                ],
              ),
              for (final row in stages)
                ListTile(
                  title: Text('${row['name']}'),
                  subtitle: Text('${row['date'] ?? ''}'),
                  onTap: () => showEditor(dialog, 'stages', existing: row),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => vm.remove('stages', '${row['id']}'),
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  const Text('里程碑'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => showEditor(
                      dialog,
                      'milestones',
                      defaults: {'blueprintID': id},
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('添加里程碑'),
                  ),
                ],
              ),
              for (final row in milestones)
                ListTile(
                  title: Text('${row['name']}'),
                  subtitle: Text('${row['date'] ?? ''}'),
                  onTap: () => showEditor(dialog, 'milestones', existing: row),
                  trailing: IconButton(
                    tooltip: '删除',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => vm.remove('milestones', '${row['id']}'),
                  ),
                ),
              const Divider(),
              Row(
                children: [
                  Text('关联事项（${tasks.length}）'),
                  const Spacer(),
                  TextButton.icon(
                    onPressed: () => showDialog<void>(
                      context: dialog,
                      builder: (canvasContext) => AlertDialog(
                        title: Text('${blueprint['name']} · 工作流'),
                        content: SizedBox(
                          width: 860,
                          height: 580,
                          child: Obx(() {
                            vm.revision.value;
                            return WorkflowCanvas(
                              tasks: vm.tasks
                                  .where((task) => task['blueprintID'] == id)
                                  .toList(),
                              onEdit: (task) => showEditor(
                                canvasContext,
                                'tasks',
                                existing: task,
                              ),
                              onMove: (task, position) => vm.put('tasks', {
                                ...task,
                                'workflowX': position.dx,
                                'workflowY': position.dy,
                              }),
                            );
                          }),
                        ),
                        actions: [
                          Obx(
                            () => TextButton.icon(
                              onPressed: vm.undoCount.value > 0
                                  ? vm.undo
                                  : null,
                              icon: const Icon(Icons.undo),
                              label: const Text('撤销'),
                            ),
                          ),
                          Obx(
                            () => TextButton.icon(
                              onPressed: vm.redoCount.value > 0
                                  ? vm.redo
                                  : null,
                              icon: const Icon(Icons.redo),
                              label: const Text('重做'),
                            ),
                          ),
                          FilledButton(
                            onPressed: () => Navigator.pop(canvasContext),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                    icon: const Icon(Icons.account_tree_outlined),
                    label: const Text('工作流'),
                  ),
                  TextButton.icon(
                    onPressed: () => showEditor(
                      dialog,
                      'tasks',
                      defaults: {'blueprintID': id},
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('添加事项'),
                  ),
                ],
              ),
              for (final row in tasks)
                ListTile(
                  title: Text('${row['title']}'),
                  subtitle: Text('${row['status'] ?? 'pending'}'),
                  onTap: () => showEditor(dialog, 'tasks', existing: row),
                ),
            ],
          );
        }),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => showPlanHistory(dialog, '${blueprint['id']}'),
          icon: const Icon(Icons.history),
          label: const Text('规划历史'),
        ),
        TextButton.icon(
          onPressed: () => showReplanDialog(dialog, blueprint),
          icon: const Icon(Icons.auto_awesome),
          label: const Text('AI 重新规划'),
        ),
        TextButton.icon(
          onPressed: () async {
            try {
              final data = vm.exportBlueprint('${blueprint['id']}');
              await FilePicker.saveFile(
                fileName: '蓝图-${blueprint['name']}.json',
                bytes: Uint8List.fromList(
                  utf8.encode(const JsonEncoder.withIndent('  ').convert(data)),
                ),
              );
            } catch (error) {
              if (dialog.mounted) {
                ScaffoldMessenger.of(dialog)
                    .showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          },
          icon: const Icon(Icons.save_alt),
          label: const Text('导出蓝图'),
        ),
        TextButton(
          onPressed: () =>
              showEditor(dialog, 'blueprints', existing: blueprint),
          child: const Text('编辑蓝图'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Future<void> showAiTaskDraft(BuildContext context) async {
  final description = TextEditingController();
  PlatformFile? imageFile;
  final request = await showDialog<(String, PlatformFile?)>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: const Text('AI 事项草稿'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: description,
                maxLines: 5,
                autofocus: true,
                decoration: const InputDecoration(labelText: '描述要完成的事'),
              ),
              TextButton.icon(
                onPressed: () async {
                  final files = await FilePicker.pickFiles(
                    type: FileType.custom,
                    allowedExtensions: ['png', 'jpg', 'jpeg'],
                  );
                  if (files.isNotEmpty) setState(() => imageFile = files.first);
                },
                icon: const Icon(Icons.image_outlined),
                label: Text(imageFile?.name ?? '选择图片'),
              ),
              if (imageFile != null) const Text('生成时会将图片和描述发送至 AI 接口。'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialog, (description.text.trim(), imageFile)),
            child: const Text('生成'),
          ),
        ],
      ),
    ),
  );
  description.dispose();
  if (request == null ||
      (request.$1.isEmpty && request.$2 == null) ||
      !context.mounted) {
    return;
  }
  try {
    final prompt =
        '请将以下事项整理为一个主任务和可执行子任务。只输出 JSON 对象，字段为 title 字符串、notes 字符串、subtasks 字符串数组：${request.$1}';
    final image = request.$2;
    final raw = image == null
        ? await AiService.complete(prompt)
        : await AiService.completeWithImage(
            prompt,
            await File(image.path ?? (throw const FormatException('图片路径不可用')))
                .readAsBytes(),
            image.extension?.toLowerCase() == 'png'
                ? 'image/png'
                : 'image/jpeg',
          );
    final draft = TaskDraft.parse(raw);
    if (!context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('确认任务草稿'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(draft.title, style: Theme.of(dialog).textTheme.titleLarge),
              if (draft.notes.isNotEmpty) Text(draft.notes),
              const SizedBox(height: 12),
              for (final child in draft.subtasks) Text('• $child'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const Text('保存任务'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await Get.find<WorkspaceViewModel>().addTaskTree(
        draft.title,
        draft.notes,
        draft.subtasks,
      );
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class CalendarPage extends StatefulWidget {
  final List<Map<String, dynamic>> tasks;
  const CalendarPage({super.key, required this.tasks});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  List<Map<String, dynamic>>? events;
  String? error;
  bool loading = false;
  Future<void> readEvents() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final now = DateTime.now();
      final loaded = await NativeBridge.calendarEvents(
        DateTime(now.year, now.month, 1),
        DateTime(now.year, now.month + 2, 1),
      );
      if (mounted) setState(() => events = loaded);
    } catch (failure) {
      if (mounted) setState(() => error = '$failure');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(horizontal: 28),
    children: [
      Row(
        children: [
          Text('计划事项', style: Theme.of(context).textTheme.titleLarge),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: loading ? null : readEvents,
            icon: const Icon(Icons.sync),
            label: const Text('读取系统日历'),
          ),
        ],
      ),
      if (widget.tasks.isEmpty)
        const Padding(padding: EdgeInsets.all(20), child: Text('暂无计划事项')),
      for (final task in widget.tasks)
        Card(
          child: ListTile(
            title: Text('${task['title']}'),
            subtitle: Text('${task['scheduledFor']}'.split('T').first),
            trailing: IconButton(
              tooltip: task['calendarAutoSync'] == true
                  ? '停止自动同步并删除日历事件'
                  : '自动同步到系统日历',
              icon: Icon(
                task['calendarAutoSync'] == true
                    ? Icons.event_available
                    : Icons.event_available_outlined,
              ),
              onPressed: () async {
                try {
                  final vm = Get.find<WorkspaceViewModel>();
                  await vm.put('tasks', {
                    ...task,
                    'calendarAutoSync': task['calendarAutoSync'] != true,
                  });
                  if (vm.calendarStatus.value.startsWith('系统日历同步失败')) {
                    throw StateError(vm.calendarStatus.value);
                  }
                } catch (failure) {
                  if (mounted) setState(() => error = '$failure');
                }
              },
            ),
            onTap: () => showEditor(context, 'tasks', existing: task),
          ),
        ),
      const SizedBox(height: 16),
      Text('系统日历', style: Theme.of(context).textTheme.titleLarge),
      if (loading) const LinearProgressIndicator(),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      Obx(() {
        final status = Get.find<WorkspaceViewModel>().calendarStatus.value;
        return status.startsWith('系统日历同步失败')
            ? Text(
                status,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              )
            : const SizedBox.shrink();
      }),
      if (events != null && events!.isEmpty)
        const Padding(padding: EdgeInsets.all(20), child: Text('所选时间范围内没有日程')),
      for (final event in events ?? [])
        Card(
          child: ListTile(
            leading: const Icon(Icons.event_outlined),
            title: Text('${event['title']}'),
            subtitle: Text(
              '${event['start']}'.replaceFirst('T', ' ').substring(0, 16),
            ),
          ),
        ),
    ],
  );
}

Future<void> showCategoryEditor(
  BuildContext context, {
  String? existing,
}) async {
  final name = TextEditingController(text: existing ?? '');
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: Text(existing == null ? '添加分类' : '重命名分类'),
      content: TextField(
        controller: name,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialog),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            try {
              final vm = Get.find<WorkspaceViewModel>();
              if (existing == null) {
                await vm.addCategory(name.text);
              } else {
                await vm.renameCategory(existing, name.text);
              }
              if (dialog.mounted) Navigator.pop(dialog);
            } catch (error) {
              if (dialog.mounted) {
                ScaffoldMessenger.of(dialog)
                    .showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          },
          child: const Text('保存'),
        ),
      ],
    ),
  );
  name.dispose();
}

Future<void> showTemplateDialog(BuildContext context) async {
  final vm = Get.find<WorkspaceViewModel>();
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('选择蓝图模板'),
      content: SizedBox(
        width: 500,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final template in blueprintTemplates)
              ListTile(
                title: Text(template.name),
                subtitle: Text(template.goal),
                onTap: () async {
                  try {
                    await vm.createBlueprintFromTemplate(template);
                    if (dialog.mounted) Navigator.pop(dialog);
                  } catch (error) {
                    if (dialog.mounted) {
                      ScaffoldMessenger.of(dialog)
                          .showSnackBar(SnackBar(content: Text('$error')));
                    }
                  }
                },
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
}

Future<void> showReplanDialog(
  BuildContext context,
  Map<String, dynamic> blueprint,
) async {
  final vm = Get.find<WorkspaceViewModel>();
  final id = '${blueprint['id']}';
  final editable = vm.tasks
      .where(
        (t) =>
            t['blueprintID'] == id &&
            !['completed', 'cancelled', 'unscheduled'].contains(t['status']) &&
            t['isPlanLocked'] != true,
      )
      .toList();
  if (editable.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('没有可重新规划的任务')));
    return;
  }
  final minutes = TextEditingController(text: '240');
  var includeNotes = false, includeProject = true;
  final settings = await showDialog<(int, bool, bool)>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: const Text('AI 重新规划'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('将 ${editable.length} 项未完成任务发送给 DeepSeek 生成日期建议。'),
              TextField(
                controller: minutes,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: '每日可用分钟'),
              ),
              SwitchListTile(
                title: const Text('包含项目名称'),
                value: includeProject,
                onChanged: (value) => setState(() => includeProject = value),
              ),
              SwitchListTile(
                title: const Text('包含任务备注'),
                value: includeNotes,
                onChanged: (value) => setState(() => includeNotes = value),
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
            onPressed: () {
              final value = int.tryParse(minutes.text);
              if (value != null && value > 0 && value <= 1440) {
                Navigator.pop(dialog, (value, includeNotes, includeProject));
              }
            },
            child: const Text('生成建议'),
          ),
        ],
      ),
    ),
  );
  minutes.dispose();
  if (settings == null || !context.mounted) return;
  try {
    final rows = editable
        .map(
          (t) => {
            'id': t['id'],
            'title': t['title'],
            'project': settings.$3 ? t['project'] : null,
            'scheduledFor': t['scheduledFor'],
            'dueDate': t['dueDate'],
            'estimatedMinutes': t['estimatedMinutes'] ?? 30,
            'status': t['status'],
            'blockReason': t['blockReason'],
            'notes': settings.$2 ? t['notes'] : null,
            'dependencyIDs': t['dependencyIDs'] ?? [],
          },
        )
        .toList();
    final raw = await AiService.complete(
      '只返回 JSON：{"summary":"", "changes":[{"taskID":"原任务 ID", "newScheduledFor":"ISO8601 日期时间", "newDueDate":"ISO8601 日期时间或 null", "reason":""}]}。根据延期、阻塞原因和每日 ${settings.$1} 分钟容量重新安排任务，保持依赖顺序，不修改标题。蓝图目标：${blueprint['goal'] ?? ''}。任务：${jsonEncode(rows)}',
    );
    final proposal = ReplanProposal.parse(
      raw,
      editable.map((e) => '${e['id']}').toSet(),
    );
    if (!context.mounted) return;
    final included = proposal.changes.map((e) => e.taskId).toSet();
    String? capacityWarning() {
      if (included.isEmpty) return null;
      final chosen = proposal.changes
          .where((change) => included.contains(change.taskId))
          .toList();
      final planned = applyReplanToTasks(vm.tasks, id, chosen);
      final overloads = replanCapacityOverloads(planned, included, settings.$1);
      return overloads.isEmpty ? null : capacityOverloadMessage(overloads);
    }

    final selected = await showDialog<List<ReplanChange>>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, setState) {
          final warning = capacityWarning();
          return AlertDialog(
            title: const Text('确认重新规划'),
            content: SizedBox(
              width: 620,
              height: 440,
              child: ListView(
                children: [
                  Text(proposal.summary),
                  if (warning != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(
                        warning,
                        style: TextStyle(
                          color: Theme.of(dialog).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  for (final change in proposal.changes)
                    CheckboxListTile(
                      value: included.contains(change.taskId),
                      onChanged: (value) => setState(() {
                        if (value == true) {
                          included.add(change.taskId);
                        } else {
                          included.remove(change.taskId);
                        }
                      }),
                      title: Text(
                        '${editable.firstWhere((task) => task['id'] == change.taskId)['title']}',
                      ),
                      subtitle: Text(
                        '${change.scheduledFor.toLocal().toString().split(' ').first} · ${change.reason}',
                      ),
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
                onPressed: included.isEmpty || warning != null
                    ? null
                    : () => Navigator.pop(
                        dialog,
                        proposal.changes
                            .where((e) => included.contains(e.taskId))
                            .toList(),
                      ),
                child: const Text('应用选中变更'),
              ),
            ],
          );
        },
      ),
    );
    if (selected != null && selected.isNotEmpty) {
      await vm.commitReplan(id, selected, dailyMinutes: settings.$1);
    }
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}
