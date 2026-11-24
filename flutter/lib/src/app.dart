import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'workspace.dart';
import 'native.dart';
import 'ai.dart';
import 'updates.dart';
import 'workflow.dart';
import 'blueprint_templates.dart';
import 'blueprint_images.dart';
import 'blueprint_workbench.dart';
import 'replan.dart';
import 'reports.dart';
import 'plan_history.dart';
import 'ai_blueprint_dialog.dart';
import 'anniversary_cover.dart';
import 'design_system/xu_theme.dart';
import 'design_system/components/xu_compact_navigation.dart';
import 'design_system/components/xu_shell.dart';
import 'command_palette.dart';
import 'calendar_page.dart';
import 'calendar_plan_logic.dart';
import 'category_icons.dart';

const pages = <String, (String, IconData, IconData)>{
  'today': ('今日', Icons.wb_sunny_outlined, Icons.wb_sunny_rounded),
  'inbox': ('收集箱', Icons.inbox_outlined, Icons.inbox_rounded),
  'tasks': ('事项', Icons.checklist_rounded, Icons.fact_check_rounded),
  'calendar': (
    '日历计划',
    Icons.calendar_month_outlined,
    Icons.calendar_month_rounded,
  ),
  'categories': ('分类', Icons.sell_outlined, Icons.sell_rounded),
  'anniversaries': (
    '纪念日',
    Icons.favorite_border_rounded,
    Icons.favorite_rounded,
  ),
  'processed': ('已处理', Icons.task_alt_rounded, Icons.check_circle_rounded),
  'reports': ('日报', Icons.description_outlined, Icons.description_rounded),
  'settings': ('设置', Icons.settings_outlined, Icons.settings_rounded),
};

final _navigationItems = [
  for (final entry in pages.entries)
    XuNavigationItem(entry.key, entry.value.$1, entry.value.$2, entry.value.$3),
];

bool get _mobilePlatform => Platform.isAndroid || Platform.isIOS;

Future<Map<String, dynamic>?> _pickJsonFile() async {
  final file = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (file == null) return null;
  final json = jsonDecode(utf8.decode(await file.readAsBytes()));
  if (json is! Map<String, dynamic>) {
    throw const FormatException('请选择有效的 JSON 文件');
  }
  return json;
}

const _taskStatusLabels = {
  'pending': '待办',
  'inProgress': '进行中',
  'blocked': '阻塞',
  'completed': '已完成',
  'cancelled': '已取消',
  'unscheduled': '未安排',
  'postponed': '已顺延',
};

class XuApp extends StatelessWidget {
  const XuApp({super.key});
  @override
  Widget build(BuildContext context) {
    final vm = Get.find<WorkspaceViewModel>();
    return Obx(
      () => GetMaterialApp(
        title: '序',
        locale: const Locale('zh', 'CN'),
        supportedLocales: const [Locale('zh', 'CN')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
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
  final RxString _processedScope = 'all'.obs;
  final RxString _taskCategory = ''.obs;
  final RxString _taskDisplay = 'list'.obs;
  final RxString _categorySelection = '\u0000all'.obs;
  final RxString _categoryScope = 'active'.obs;
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

  void _openTaskView(String view) {
    if (controller.section.value != 'tasks') controller.search.value = '';
    _taskDisplay.value = view;
    controller.section.value = 'tasks';
  }

  Future<void> _showCommandPalette(BuildContext context) async {
    final action = await showXuCommandPalette(
      context,
      includeDesktopWidget: !_mobilePlatform,
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
        _openTaskView('blueprints');
        await showEditor(context, 'blueprints');
      case 'aiBlueprint':
        _openTaskView('blueprints');
        await showAiBlueprintDialog(context);
      case 'report':
        controller.section.value = 'reports';
        await showReportEditor(context);
      case 'today':
        controller.section.value = 'today';
      case 'blueprints':
        _openTaskView('blueprints');
      case 'quadrants':
        _openTaskView('quadrants');
      case 'anniversaries':
        controller.section.value = 'anniversaries';
      case 'widget':
        await NativeBridge.openWidget();
      case 'settings':
        controller.section.value = 'settings';
    }
  }

  Future<void> _showSearch(BuildContext context) async {
    var query = controller.search.value;
    final result = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('搜索事项'),
        content: TextFormField(
          autofocus: true,
          initialValue: query,
          decoration: const InputDecoration(
            prefixIcon: Icon(Icons.search_rounded),
            labelText: '名称、备注或分类',
          ),
          onChanged: (value) => query = value,
          onFieldSubmitted: (value) => Navigator.pop(dialog, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, ''),
            child: const Text('清除'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, query.trim()),
            child: const Text('搜索'),
          ),
        ],
      ),
    );
    if (result == null || !context.mounted) return;
    final section = controller.section.value;
    if (result.isNotEmpty &&
        !const {'today', 'inbox', 'tasks', 'processed'}.contains(section)) {
      _taskScope.value = 'all';
      _taskCategory.value = '';
      _openTaskView('list');
    }
    controller.search.value = result;
  }

  @override
  Widget pageScaffold(BuildContext context) {
    return Shortcuts(
      shortcuts: {
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyN):
            const _AddIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
            const _PaletteIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.comma):
            const _SettingsIntent(),
      },
      child: Actions(
        actions: {
          _AddIntent: CallbackAction<_AddIntent>(
            onInvoke: (_) {
              showEditor(
                context,
                'tasks',
                defaults: controller.section.value == 'inbox'
                    ? {'status': 'unscheduled'}
                    : null,
              );
              return null;
            },
          ),
          _PaletteIntent: CallbackAction<_PaletteIntent>(
            onInvoke: (_) {
              _showCommandPalette(context);
              return null;
            },
          ),
          _SettingsIntent: CallbackAction<_SettingsIntent>(
            onInvoke: (_) {
              controller.section.value = 'settings';
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: LayoutBuilder(
            builder: (context, constraints) => _workspace(
              context,
              compact:
                  constraints.maxWidth < 720 ||
                  (_mobilePlatform && constraints.maxHeight < 500),
            ),
          ),
        ),
      ),
    );
  }

  void _selectPage(String page) {
    if (page != controller.section.value) controller.search.value = '';
    controller.section.value = page;
  }

  Widget _workspace(BuildContext context, {required bool compact}) {
    final body = Obx(() {
      controller.revision.value;
      return _content(context, controller.section.value, compact: compact);
    });
    final workspace = compact
        ? body
        : Row(
            children: [
              Obx(
                () => XuSidebar(
                  items: _navigationItems,
                  selected: controller.section.value,
                  onSelect: _selectPage,
                  desktop: !_mobilePlatform,
                ),
              ),
              Expanded(child: body),
            ],
          );
    if (!compact && !_mobilePlatform) {
      return Scaffold(body: workspace);
    }
    final dark = Theme.of(context).brightness == Brightness.dark;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
      child: Obx(
        () => PopScope(
          canPop: controller.section.value == 'today',
          onPopInvokedWithResult: (popped, _) {
            if (!popped) _selectPage('today');
          },
          child: Scaffold(
            body: SafeArea(bottom: !compact, child: workspace),
            bottomNavigationBar:
                compact && MediaQuery.viewInsetsOf(context).bottom == 0
                ? XuCompactNavigation(
                    items: _navigationItems,
                    selected: controller.section.value,
                    onSelect: _selectPage,
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, String page, {required bool compact}) {
    final vm = controller;
    final title = pages[page]!.$1;
    final now = DateTime.now();
    final actions = <Widget>[
      if (page == 'today') ...[
        MenuAnchor(
          menuChildren: [
            MenuItemButton(
              leadingIcon: const Icon(Icons.account_tree_outlined),
              onPressed: () => _openTaskView('blueprints'),
              child: const Text('按蓝图浏览'),
            ),
            MenuItemButton(
              leadingIcon: const Icon(Icons.grid_view_rounded),
              onPressed: () => _openTaskView('quadrants'),
              child: const Text('按四象限浏览'),
            ),
          ],
          builder: (context, menu, child) => OutlinedButton.icon(
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            icon: const Icon(Icons.view_quilt_outlined),
            label: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('事项视图'),
                SizedBox(width: 4),
                Icon(Icons.expand_more_rounded, size: 18),
              ],
            ),
          ),
        ),
        if (vm.todayTasks.isNotEmpty)
          FilledButton.icon(
            onPressed: () => showEditor(context, 'tasks'),
            icon: const Icon(Icons.add),
            label: const Text('添加事项'),
          ),
      ],
      if (page == 'processed' && _processedTasks().isNotEmpty)
        OutlinedButton.icon(
          onPressed: () => _showSearch(context),
          icon: const Icon(Icons.search_rounded),
          label: const Text('搜索记录'),
        ),
      if (page == 'anniversaries' && vm.items('anniversaries').isNotEmpty)
        FilledButton.icon(
          onPressed: () => showEditor(context, 'anniversaries'),
          icon: const Icon(Icons.add),
          label: const Text('添加纪念日'),
        ),
      if (page == 'reports')
        FilledButton.icon(
          onPressed: () => showReportEditor(context),
          icon: const Icon(Icons.edit_note_rounded),
          label: const Text('创建日报'),
        ),
    ];
    return Column(
      children: [
        XuTopBar(
          compact: compact,
          section: page == 'settings'
              ? ''
              : const {
                  'inbox',
                  'anniversaries',
                  'processed',
                  'reports',
                }.contains(page)
              ? '记录'
              : '工作区',
          title: compact && page != 'calendar' ? '序' : title,
          onSearch: () => _showSearch(context),
          onPalette: () => _showCommandPalette(context),
          onUndo: vm.undoCount.value == 0
              ? null
              : () => _changeWorkspaceHistory(context, vm.undo),
          onRedo: vm.redoCount.value == 0
              ? null
              : () => _changeWorkspaceHistory(context, vm.redo),
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
        if (!const {'tasks', 'categories', 'calendar', 'inbox'}.contains(page))
          Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
                : const EdgeInsets.fromLTRB(28, 20, 28, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                XuPageHeader(
                  title: title,
                  eyebrow: page == 'today'
                      ? '${now.month}月${now.day}日 星期${'一二三四五六日'[now.weekday - 1]}'
                      : null,
                  description: switch (page) {
                    'processed' => '查阅完成、取消和顺延记录。',
                    'reports' => '记录执行进展，回顾每周行动。',
                    _ => null,
                  },
                  actions: actions,
                ),
                if (page == 'today') ...[
                  const SizedBox(height: 16),
                  const Divider(height: 1),
                ],
              ],
            ),
          ),
        Expanded(
          child: SizedBox.expand(
            child: TweenAnimationBuilder<double>(
              key: ValueKey(page),
              tween: Tween(begin: 0.76, end: 1),
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              builder: (context, opacity, child) =>
                  Opacity(opacity: opacity, child: child),
              child: switch (page) {
                'today' => _todayPage(context, compact: compact),
                'inbox' => _inboxPage(context),
                'tasks' => _tasksWorkbench(context),
                'processed' => _processedPage(context),
                'calendar' => _calendar(context, compact: compact),
                'categories' => _categories(context),
                'anniversaries' => _anniversaries(context),
                'reports' => const ReportsPage(),
                _ => _settings(context),
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(String text) =>
      XuEmptyState(icon: Icons.inbox_outlined, title: text);

  Widget _inboxPage(BuildContext context) {
    final vm = controller;
    final entries =
        vm.tasks
            .asMap()
            .entries
            .where((entry) => entry.value['status'] == 'unscheduled')
            .toList()
          ..sort((a, b) {
            final aDate = DateTime.tryParse('${a.value['createdAt'] ?? ''}');
            final bDate = DateTime.tryParse('${b.value['createdAt'] ?? ''}');
            if (aDate != null && bDate != null) {
              final order = bDate.compareTo(aDate);
              if (order != 0) return order;
            }
            return b.key.compareTo(a.key);
          });
    final tasks = entries.map((entry) => entry.value).toList();
    final query = vm.search.value.trim();
    final visible = query.isEmpty || tasks.isEmpty
        ? tasks
        : tasks.where((task) {
            final text = [
              task['title'],
              task['notes'],
              task['project'],
              task['category'],
            ].join(' ').toLowerCase();
            return text.contains(query.toLowerCase());
          }).toList();
    void capture() =>
        showEditor(context, 'tasks', defaults: {'status': 'unscheduled'});

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          XuPageHeader(
            title: '收集箱',
            description: tasks.isEmpty
                ? '先记下事项，稍后安排日期。'
                : '${tasks.length} 项待安排',
            actions: [
              if (tasks.isNotEmpty)
                FilledButton.icon(
                  onPressed: capture,
                  icon: const Icon(Icons.add),
                  label: const Text('收集事项'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: tasks.isEmpty
                ? XuEmptyState(
                    icon: Icons.inbox_outlined,
                    title: '收集箱已清空',
                    description: '想到新事项时，可以先收集起来。',
                    actionLabel: '收集事项',
                    onAction: capture,
                  )
                : visible.isEmpty
                ? XuEmptyState(
                    icon: Icons.search_off_outlined,
                    title: '没有找到匹配的事项',
                    description: '试试其他关键词。',
                    actionLabel: '清除搜索',
                    actionIcon: Icons.close,
                    onAction: () => vm.search.value = '',
                  )
                : _taskList(
                    context,
                    visible,
                    empty: '收集箱已清空',
                    applySearch: false,
                    padding: EdgeInsets.zero,
                  ),
          ),
        ],
      ),
    );
  }

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

    bool inScope(Map<String, dynamic> task, String scope) {
      final root = rootOf(task);
      final status = '${root['status'] ?? 'pending'}';
      return switch (scope) {
        'active' => status != 'completed' && status != 'cancelled',
        'inbox' =>
          status != 'completed' &&
              status != 'cancelled' &&
              root['scheduledFor'] == null,
        'processed' =>
          status == 'completed' ||
              status == 'cancelled' ||
              status == 'postponed' ||
              _postponements(root).isNotEmpty,
        _ => true,
      };
    }

    final query = controller.search.value.trim().toLowerCase();
    final category = _taskCategory.value;
    final visible = all.where((task) {
      if (!inScope(task, _taskScope.value)) return false;
      if (category.isNotEmpty && '${task['category'] ?? ''}' != category) {
        return false;
      }
      return query.isEmpty ||
          ['title', 'notes', 'project', 'category'].any(
            (field) => '${task[field] ?? ''}'.toLowerCase().contains(query),
          );
    }).toList();
    final categories = <String>{
      for (final row in controller.items('categories')) '${row['name'] ?? ''}',
      for (final task in all) '${task['category'] ?? ''}',
    }..remove('');
    final categoryNames = categories.toList()..sort();
    final colors = XuColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final scopeOptions = [
      ('待处理', 'active'),
      ('收集箱', 'inbox'),
      ('已处理', 'processed'),
      ('全部', 'all'),
    ];
    Widget scopeTabs() => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (label, scope) in scopeOptions)
          ChoiceChip(
            label: Text(
              '$label  ${all.where((task) => inScope(task, scope)).length}',
            ),
            selected: _taskScope.value == scope,
            onSelected: (_) {
              _taskScope.value = scope;
              _expandedSeries.clear();
              _seriesRevision.value++;
            },
          ),
      ],
    );
    final displayToggle = SegmentedButton<String>(
      segments: const [
        ButtonSegment(
          value: 'list',
          icon: Icon(Icons.view_list_outlined),
          label: Text('列表'),
        ),
        ButtonSegment(
          value: 'quadrants',
          icon: Icon(Icons.grid_view_outlined),
          label: Text('四象限'),
        ),
        ButtonSegment(
          value: 'blueprints',
          icon: Icon(Icons.account_tree_outlined),
          label: Text('蓝图'),
        ),
      ],
      selected: {_taskDisplay.value},
      onSelectionChanged: (value) => _taskDisplay.value = value.first,
      showSelectedIcon: false,
    );
    final searchField = _TaskSearchField(
      value: controller.search.value,
      onChanged: (value) => controller.search.value = value,
    );
    final categoryField = DropdownButton<String>(
      value: category,
      isExpanded: true,
      underline: const SizedBox.shrink(),
      items: [
        const DropdownMenuItem(value: '', child: Text('全部分类')),
        for (final name in categoryNames)
          DropdownMenuItem(value: name, child: Text(name)),
      ],
      onChanged: (value) => _taskCategory.value = value ?? '',
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final narrow = constraints.maxWidth < 900;
        final compact =
            constraints.maxWidth < 620 || constraints.maxHeight < 400;
        final controls = [
          XuPageHeader(
            title: '事项',
            actions: [
              if (controller.selectedTaskIds.isNotEmpty) ...[
                PopupMenuButton<String>(
                  tooltip: '批量操作',
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
                    PopupMenuItem(value: 'start', child: Text('批量开始')),
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
              ],
              FilledButton.icon(
                onPressed: () => showEditor(context, 'tasks'),
                icon: const Icon(Icons.add),
                label: const Text('添加事项'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (narrow) ...[
            scopeTabs(),
            const SizedBox(height: 12),
            displayToggle,
          ] else
            Row(
              children: [
                Expanded(child: scopeTabs()),
                displayToggle,
              ],
            ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colors.border),
            ),
            child: constraints.maxWidth < 620
                ? Column(
                    children: [
                      searchField,
                      const Divider(height: 1),
                      categoryField,
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: searchField),
                      const SizedBox(width: 20),
                      SizedBox(width: 180, child: categoryField),
                    ],
                  ),
          ),
          SizedBox(height: compact ? 12 : 24),
        ];
        return Padding(
          padding: compact
              ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
              : const EdgeInsets.fromLTRB(28, 24, 28, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (compact)
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight * 0.68,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: controls,
                    ),
                  ),
                )
              else
                ...controls,
              Expanded(
                child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: visible.isEmpty && _taskDisplay.value == 'list'
                          ? 360
                          : double.infinity,
                    ),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: scheme.surface,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: _taskDisplay.value == 'quadrants'
                          ? _quadrants(context, source: visible)
                          : _taskDisplay.value == 'blueprints'
                          ? _blueprintWorkbench(
                              context,
                              visible,
                              query: query,
                              category: category,
                              matchingRootIds: visible
                                  .map((task) => '${rootOf(task)['id']}')
                                  .toSet(),
                            )
                          : visible.isEmpty
                          ? XuEmptyState(
                              icon: query.isEmpty
                                  ? Icons.checklist_outlined
                                  : Icons.search_off_outlined,
                              title: query.isEmpty
                                  ? (_taskScope.value == 'active'
                                        ? '没有待处理事项'
                                        : '这个范围还没有事项')
                                  : '没有匹配的事项',
                              description: query.isEmpty
                                  ? '添加一项新的事项，开始下一步。'
                                  : '试试其他关键词或分类。',
                            )
                          : _taskList(context, visible, empty: '没有匹配的事项'),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  });

  Widget _todayPage(BuildContext context, {required bool compact}) {
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
                    leading: const XuIconTile(Icons.event_available_outlined),
                    title: Text(
                      row['privacyMode'] == true ? '重要日子' : '${row['name']}',
                    ),
                    subtitle: Text(days == 0 ? '就是今天' : '还有 $days 天'),
                    trailing: const Icon(Icons.chevron_right_rounded),
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
                  shortcutHint: compact || _mobilePlatform
                      ? null
                      : '⌘  N   快速添加',
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
    bool applySearch = true,
    EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 28),
  }) {
    final query = controller.search.value.trim().toLowerCase();
    if (applySearch && query.isNotEmpty) {
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
        padding: padding,
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
                          icon: AnimatedRotation(
                            duration: MediaQuery.disableAnimationsOf(context)
                                ? Duration.zero
                                : const Duration(milliseconds: 180),
                            curve: Curves.easeInOut,
                            turns: expanded ? 0.25 : 0,
                            child: const Icon(Icons.chevron_right_rounded),
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
                      _taskStatusLabels[task['status']] ?? '待办',
                      task['project'],
                      task['category'],
                      task['scheduledFor']?.toString().split('T').first,
                      if (_postponements(task).lastOrNull case final event?)
                        '延期 ${_planDateLabel(event['from'])} → ${_planDateLabel(event['to'])}',
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
                        tooltip: '事项操作',
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
                              var input = '';
                              final name = await showDialog<String>(
                                context: context,
                                builder: (dialog) => AlertDialog(
                                  title: const Text('添加子任务'),
                                  content: TextField(
                                    onChanged: (value) => input = value,
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
                                      onPressed: () =>
                                          Navigator.pop(dialog, input.trim()),
                                      child: const Text('添加'),
                                    ),
                                  ],
                                ),
                              );
                              if (name != null && name.isNotEmpty) {
                                await controller.addChild(task, name);
                              }
                            }
                            if (action == 'blueprint' && context.mounted) {
                              await showBlueprintForTask(context, task);
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
                              await controller.arrangeToday(task);
                            }
                            if (action == 'postpone') {
                              await controller.postponeTask(task);
                            }
                            if (action == 'postponements' && context.mounted) {
                              await _showPostponements(context, task);
                            }
                          } catch (error) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(
                                context,
                              ).showSnackBar(SnackBar(content: Text('$error')));
                            }
                          }
                        },
                        itemBuilder: (_) => [
                          PopupMenuItem(value: 'edit', child: Text('编辑')),
                          const PopupMenuItem(
                            value: 'blueprint',
                            child: Text('在蓝图中查看'),
                          ),
                          PopupMenuItem(value: 'child', child: Text('添加子任务')),
                          PopupMenuItem(value: 'start', child: Text('开始')),
                          PopupMenuItem(value: 'block', child: Text('标记阻塞')),
                          PopupMenuItem(value: 'cancel', child: Text('取消任务')),
                          PopupMenuItem(value: 'restore', child: Text('恢复待办')),
                          if (!CalendarPlanLogic.isProcessed(task))
                            const PopupMenuItem(
                              value: 'today',
                              child: Text('安排今天'),
                            ),
                          if (!CalendarPlanLogic.isProcessed(task) &&
                              CalendarPlanLogic.plannedDate(task) != null)
                            const PopupMenuItem(
                              value: 'postpone',
                              child: Text('延期到明天'),
                            ),
                          if (_postponements(task).isNotEmpty)
                            const PopupMenuItem(
                              value: 'postponements',
                              child: Text('延期记录'),
                            ),
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
                      subtitle: Text(
                        _taskStatusLabels[child['status']] ?? '待办',
                      ),
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

  Widget _blueprintWorkbench(
    BuildContext context,
    List<Map<String, dynamic>> tasks, {
    required String query,
    required String category,
    required Set<String> matchingRootIds,
  }) {
    final blueprints = controller.items('blueprints');
    final matchingBlueprintIds = tasks
        .map((task) => task['blueprintID'])
        .toSet();
    final projectIds = blueprints.map((row) => row['id']).toSet();
    final roots = controller.tasks
        .where(
          (task) =>
              matchingRootIds.contains('${task['id']}') &&
              !projectIds.contains(task['blueprintID']),
        )
        .toList();
    final blueprintsWithTasks = controller.tasks
        .map((task) => task['blueprintID'])
        .toSet();
    final color = Theme.of(context).colorScheme;
    return Obx(() {
      final visible = blueprints.where((row) {
        if (!_showArchivedBlueprints.value && row['archivedAt'] != null) {
          return false;
        }
        if (matchingBlueprintIds.contains(row['id'])) return true;
        if (category.isNotEmpty) return false;
        if (query.isNotEmpty) {
          return [
            'name',
            'goal',
          ].any((field) => '${row[field] ?? ''}'.toLowerCase().contains(query));
        }
        return !blueprintsWithTasks.contains(row['id']);
      }).toList();
      return ListView(
        padding: const EdgeInsets.fromLTRB(28, 8, 28, 32),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => showPlanHistory(context, null),
                icon: const Icon(Icons.history),
                label: const Text('变更记录'),
              ),
              TextButton.icon(
                onPressed: () => showAiBlueprintDialog(context),
                icon: const Icon(Icons.auto_awesome),
                label: const Text('AI 创建蓝图'),
              ),
              TextButton.icon(
                onPressed: () => showTemplateDialog(context),
                icon: const Icon(Icons.auto_fix_high),
                label: const Text('从模板创建'),
              ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    final package = await _pickJsonFile();
                    if (package != null) {
                      await controller.importBlueprint(package);
                    }
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
              FilledButton.icon(
                onPressed: () => showEditor(context, 'blueprints'),
                icon: const Icon(Icons.add),
                label: const Text('新建蓝图'),
              ),

              FilterChip(
                selected: _showArchivedBlueprints.value,
                onSelected: (value) => _showArchivedBlueprints.value = value,
                label: const Text('显示已归档'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (visible.isEmpty && roots.isEmpty)
            SizedBox(
              height: 260,
              child: XuEmptyState(
                icon: query.isNotEmpty || category.isNotEmpty
                    ? Icons.search_off_rounded
                    : Icons.account_tree_outlined,
                title: query.isNotEmpty || category.isNotEmpty
                    ? '没有匹配的蓝图'
                    : '还没有蓝图',
                description: query.isNotEmpty || category.isNotEmpty
                    ? '调整关键词或分类后再查看。'
                    : '创建蓝图后，可以把目标拆成串行和并行事项。',
              ),
            ),
          LayoutBuilder(
            builder: (context, constraints) => Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
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
                                  const XuIconTile(Icons.account_tree_outlined),
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
              ],
            ),
          ),
        ],
      );
    });
  }

  List<Map<String, dynamic>> _processedTasks() => controller.tasks
      .where(
        (task) =>
            task['status'] == 'completed' ||
            task['status'] == 'cancelled' ||
            task['status'] == 'postponed' ||
            _postponements(task).isNotEmpty,
      )
      .toList();

  Widget _processedPage(BuildContext context) {
    final rows = _processedTasks();
    if (rows.isEmpty) {
      return XuEmptyState(
        icon: Icons.inventory_2_outlined,
        title: '暂无已处理事项',
        description: '已完成、已取消和有顺延记录的事项会出现在这里。',
        actionLabel: '浏览事项',
        actionIcon: Icons.checklist_rounded,
        onAction: () => _openTaskView('list'),
      );
    }
    return Obx(() {
      final scope = _processedScope.value;
      final query = controller.search.value.trim();
      final matches = rows
          .where(
            (task) => switch (scope) {
              'completed' || 'cancelled' => task['status'] == scope,
              'postponed' =>
                task['status'] == scope || _postponements(task).isNotEmpty,
              _ => true,
            },
          )
          .toList();
      final visible = query.isEmpty
          ? matches
          : matches
                .where(
                  (task) => ['title', 'notes', 'project', 'category'].any(
                    (field) => '${task[field] ?? ''}'.toLowerCase().contains(
                      query.toLowerCase(),
                    ),
                  ),
                )
                .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                for (final (value, label, icon) in const [
                  ('all', '全部记录', Icons.inventory_2_outlined),
                  ('completed', '已完成', Icons.check_circle_outline),
                  ('cancelled', '已取消', Icons.cancel_outlined),
                  ('postponed', '已顺延', Icons.update_rounded),
                ])
                  ChoiceChip(
                    avatar: Icon(icon, size: 16),
                    label: Text(label),
                    selected: scope == value,
                    onSelected: (_) => _processedScope.value = value,
                  ),
                if (query.isNotEmpty)
                  InputChip(
                    label: Text(
                      query,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: () => controller.search.value = '',
                    deleteButtonTooltipMessage: '清除搜索',
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: visible.isEmpty
                ? XuEmptyState(
                    icon: query.isEmpty
                        ? Icons.inventory_2_outlined
                        : Icons.search_off_rounded,
                    title: query.isEmpty ? '此状态下暂无记录' : '没有匹配的记录',
                    actionLabel: query.isEmpty ? '查看全部' : '清除搜索',
                    actionIcon: query.isEmpty
                        ? Icons.filter_list_off_rounded
                        : Icons.close_rounded,
                    onAction: () {
                      if (query.isEmpty) {
                        _processedScope.value = 'all';
                      } else {
                        controller.search.value = '';
                      }
                    },
                  )
                : _taskList(
                    context,
                    visible,
                    empty: '暂无已处理事项',
                    applySearch: false,
                  ),
          ),
        ],
      );
    });
  }

  Widget _anniversaries(BuildContext context) {
    final rows = controller.items('anniversaries');
    if (rows.isEmpty) {
      return XuEmptyState(
        icon: Icons.favorite_border_rounded,
        title: '还没有纪念日',
        description: '记下值得纪念的日期，按需提前提醒或安排准备事项。',
        actionLabel: '添加纪念日',
        onAction: () => showEditor(context, 'anniversaries'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 24),
      itemCount: rows.length,
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final row = rows[index];
        final name = row['privacyMode'] == true ? '重要日子' : '${row['name']}';
        return Card(
          margin: EdgeInsets.zero,
          child: ListTile(
            leading: row['privacyMode'] == true
                ? const XuIconTile(Icons.lock_outline_rounded)
                : _anniversaryCover(row),
            title: Text(name),
            subtitle: _anniversaryDetails(row),
            onTap: () => showEditor(context, 'anniversaries', existing: row),
            trailing: PopupMenuButton<String>(
              tooltip: '纪念日操作',
              onSelected: (action) async {
                if (action == 'edit') {
                  await showEditor(context, 'anniversaries', existing: row);
                } else if (action == 'preview') {
                  await showPreparationTaskPreview(context, row);
                } else {
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (dialog) => AlertDialog(
                      title: const Text('删除纪念日'),
                      content: Text('确定删除“$name”？'),
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
                  await _changeWorkspaceHistory(
                    context,
                    () => controller.remove('anniversaries', '${row['id']}'),
                  );
                }
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: 'edit', child: Text('编辑纪念日')),
                if (row['preparationEnabled'] == true &&
                    row['generatedTaskID'] == null)
                  const PopupMenuItem(value: 'preview', child: Text('预览准备任务')),
                const PopupMenuItem(value: 'delete', child: Text('删除纪念日')),
              ],
            ),
          ),
        );
      },
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
        final calendar = lunar ? '农历' : '公历';
        if (next == null) {
          final state = snapshot.hasError
              ? '日期计算失败'
              : snapshot.connectionState == ConnectionState.done
              ? '已结束'
              : '正在计算下一次日期';
          return Text('$calendar · $state');
        }
        final now = DateTime.now();
        final days = DateTime.utc(
          next.year,
          next.month,
          next.day,
        ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
        final date = '${next.year}年${next.month}月${next.day}日';
        final countdown = days == 0 ? '就是今天' : '还有 $days 天';
        return Text('$countdown · $calendar · $date');
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

  Widget _quadrants(
    BuildContext context, {
    required List<Map<String, dynamic>> source,
  }) {
    const quadrants = [
      ('重要且紧急', Icons.bolt_rounded),
      ('重要但不紧急', Icons.event_available_outlined),
      ('紧急但不重要', Icons.schedule_rounded),
      ('不紧急也不重要', Icons.low_priority_rounded),
    ];
    final grouped = <int, List<Map<String, dynamic>>>{};
    for (final task in source) {
      final quadrant = ((task['quadrant'] as num?)?.toInt() ?? 1).clamp(1, 4);
      (grouped[quadrant] ??= []).add(task);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 630 ? 1 : 2;
        return GridView.count(
          padding: const EdgeInsets.all(12),
          crossAxisCount: columns,
          mainAxisExtent: 264,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (var i = 1; i <= 4; i++)
              Card(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 14, 18, 8),
                      child: Row(
                        children: [
                          XuIconTile(quadrants[i - 1].$2, size: 36),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '${quadrants[i - 1].$1} · ${grouped[i]?.length ?? 0} 项',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: grouped[i] == null
                          ? Center(
                              child: Text(
                                '暂无事项',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            )
                          : _taskList(
                              context,
                              grouped[i]!,
                              applySearch: false,
                              empty: '暂无事项',
                            ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _calendar(BuildContext context, {required bool compact}) {
    return CalendarPage(
      tasks: controller.tasks,
      compact: compact,
      onEditTask: (task) => showEditor(context, 'tasks', existing: task),
      onAddTask: (day) => showEditor(
        context,
        'tasks',
        defaults: {
          'scheduledFor': day.toIso8601String(),
          if (day.hour != 0 || day.minute != 0)
            'timeBlock': {
              'id': newId(),
              'start': day.toIso8601String(),
              'end': day.add(const Duration(minutes: 30)).toIso8601String(),
            },
        },
      ),
    );
  }

  Widget _categories(BuildContext context) {
    return Obx(() {
      controller.revision.value;
      final tasks = controller.tasks;
      final names = <String>{
        for (final row in controller.items('categories'))
          '${row['name'] ?? ''}'.trim(),
        for (final task in tasks) '${task['category'] ?? ''}'.trim(),
      }..remove('');
      final categoryNames = names.toList()..sort();
      IconData categoryIcon(String name) {
        final row = controller
            .items('categories')
            .where((item) => item['name'] == name)
            .firstOrNull;
        return categoryIconFor('${row?['symbol'] ?? 'label'}').$2;
      }

      var selection = _categorySelection.value;
      if (selection != '\u0000all' &&
          selection.isNotEmpty &&
          !names.contains(selection)) {
        selection = '\u0000all';
      }
      final selectedTasks = tasks.where((task) {
        final name = '${task['category'] ?? ''}'.trim();
        return selection == '\u0000all' ||
            (selection.isEmpty ? name.isEmpty : name == selection);
      }).toList();
      bool active(Map<String, dynamic> task) =>
          task['status'] != 'completed' && task['status'] != 'cancelled';
      final pendingCount = selectedTasks.where(active).length;
      final processedCount = selectedTasks.length - pendingCount;
      final visible = selectedTasks.where((task) {
        return switch (_categoryScope.value) {
          'active' => active(task),
          'processed' => !active(task),
          _ => true,
        };
      }).toList();
      visible.sort((a, b) {
        if (_categoryScope.value == 'active') {
          final aDate = '${a['scheduledFor'] ?? ''}';
          final bDate = '${b['scheduledFor'] ?? ''}';
          if (aDate.isEmpty != bDate.isEmpty) return aDate.isEmpty ? 1 : -1;
          return aDate.compareTo(bDate);
        }
        return '${b['statusChangedAt'] ?? b['createdAt'] ?? b['id']}'.compareTo(
          '${a['statusChangedAt'] ?? a['createdAt'] ?? a['id']}',
        );
      });
      final title = selection == '\u0000all'
          ? '所有类别'
          : selection.isEmpty
          ? '未分类'
          : selection;
      final icon = selection == '\u0000all'
          ? Icons.inventory_2_outlined
          : selection.isEmpty
          ? Icons.sell_outlined
          : categoryIcon(selection);
      final colors = XuColors.of(context);
      final scheme = Theme.of(context).colorScheme;

      Future<void> createTask() => showEditor(
        context,
        'tasks',
        defaults: {'category': selection == '\u0000all' ? '' : selection},
      );

      Future<void> editCategory(String action) async {
        if (selection == '\u0000all' || selection.isEmpty) return;
        if (action == 'rename') {
          final renamed = await showCategoryEditor(
            context,
            existing: selection,
          );
          if (renamed != null) _categorySelection.value = renamed;
          return;
        }
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const Text('删除分类'),
            content: Text('删除“$selection”后，其中的任务会移到“未分类”。确定删除吗？'),
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
        if (confirmed != true) return;
        try {
          await controller.deleteCategory(selection);
          _categorySelection.value = '';
        } catch (error) {
          if (context.mounted) {
            ScaffoldMessenger.of(context)
                .showSnackBar(SnackBar(content: Text('$error')));
          }
        }
      }

      Widget categoryOption(String value, String label, IconData symbol) {
        final count = tasks.where((task) {
          final category = '${task['category'] ?? ''}'.trim();
          return value == '\u0000all' ||
              (value.isEmpty ? category.isEmpty : category == value);
        }).length;
        final selected = selection == value;
        return Semantics(
          button: true,
          selected: selected,
          label: '$label，全部状态共 $count 项任务',
          child: Material(
            color: selected ? colors.selection : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => _categorySelection.value = value,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Icon(
                      symbol,
                      size: 20,
                      color: selected ? scheme.primary : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    ),
                    Text(
                      '$count',
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }

      final categoryPanel = Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '类别概览',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                Text(
                  '${tasks.length} 项任务',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 12),
            categoryOption('\u0000all', '所有类别', Icons.inventory_2_outlined),
            categoryOption('', '未分类', Icons.sell_outlined),
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '我的类别',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                ),
                Text(
                  '${categoryNames.length}',
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final name in categoryNames)
              categoryOption(name, name, categoryIcon(name)),
          ],
        ),
      );

      final taskPanel = Container(
        height: 500,
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: colors.border),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 22, 24, 16),
              child: Column(
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colors.selection,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(icon, color: scheme.primary),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              '${selectedTasks.length} 项任务 · $pendingCount 项待处理',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      if (selection != '\u0000all' && selection.isNotEmpty)
                        PopupMenuButton<String>(
                          tooltip: '管理类别',
                          onSelected: editCategory,
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'rename', child: Text('编辑分类')),
                            PopupMenuItem(value: 'delete', child: Text('删除类别')),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  LayoutBuilder(
                    builder: (context, limits) {
                      final scopeTabs = Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final (label, value, count) in [
                            ('待处理', 'active', pendingCount),
                            ('已处理', 'processed', processedCount),
                            ('全部', 'all', selectedTasks.length),
                          ])
                            ChoiceChip(
                              label: Text('$label  $count'),
                              selected: _categoryScope.value == value,
                              onSelected: (_) => _categoryScope.value = value,
                            ),
                        ],
                      );
                      final sortLabel = Text(
                        _categoryScope.value == 'active'
                            ? '◷  按计划时间排序'
                            : '按最近处理时间排序',
                        style: Theme.of(context).textTheme.bodySmall,
                      );
                      return limits.maxWidth < 600
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                scopeTabs,
                                const SizedBox(height: 8),
                                sortLabel,
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(child: scopeTabs),
                                sortLabel,
                              ],
                            );
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: visible.isEmpty
                  ? XuEmptyState(
                      icon: icon,
                      title: tasks.isEmpty && categoryNames.isEmpty
                          ? '先从一个类别开始'
                          : selectedTasks.isEmpty
                          ? (selection.isEmpty ? '所有任务都已有归属' : '这个类别还没有任务')
                          : _categoryScope.value == 'active'
                          ? '这个类别还没有待处理任务'
                          : '还没有已处理的任务',
                      description: tasks.isEmpty && categoryNames.isEmpty
                          ? '为工作、生活或兴趣留一个位置。'
                          : _categoryScope.value == 'active'
                          ? '新建一项任务，或切换状态查看已有记录。'
                          : '切换状态查看其他任务。',
                    )
                  : _taskList(
                      context,
                      visible,
                      empty: '暂无任务',
                      applySearch: false,
                      padding: const EdgeInsets.all(16),
                    ),
            ),
          ],
        ),
      );

      return LayoutBuilder(
        builder: (context, limits) {
          final compact = limits.maxWidth < 900;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 28, 28, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                XuPageHeader(
                  title: '任务分类',
                  description: '按类别查看事项与进度。',
                  actions: [
                    OutlinedButton.icon(
                      onPressed: () async {
                        final name = await showCategoryEditor(context);
                        if (name != null) _categorySelection.value = name;
                      },
                      icon: const Icon(Icons.new_label_outlined),
                      label: const Text('新建分类'),
                    ),
                    FilledButton.icon(
                      onPressed: createTask,
                      icon: const Icon(Icons.add),
                      label: const Text('新建任务'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                if (compact) ...[
                  categoryPanel,
                  const SizedBox(height: 20),
                  taskPanel,
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(width: 258, child: categoryPanel),
                      const SizedBox(width: 20),
                      Expanded(child: taskPanel),
                    ],
                  ),
              ],
            ),
          );
        },
      );
    });
  }

  Widget _settings(BuildContext context) => ListView(
    padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
    children: [
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          XuSectionCard(
            title: '外观',
            icon: Icons.contrast_rounded,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('跟随系统'),
                      ),
                      ButtonSegment(value: ThemeMode.light, label: Text('浅色')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('深色')),
                    ],
                    selected: {controller.themeMode.value},
                    onSelectionChanged: (value) =>
                        controller.setThemeMode(value.first),
                  ),
                  if (!_mobilePlatform)
                    OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          final opened = await NativeBridge.openWidget();
                          if (opened != true) throw StateError('桌面小组件未能打开');
                          controller.widgetStatus.value = '桌面小组件已打开';
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('桌面小组件已打开')),
                            );
                          }
                        } catch (error) {
                          controller.widgetStatus.value = '桌面小组件打开失败：$error';
                          if (context.mounted) {
                            ScaffoldMessenger.of(
                              context,
                            ).showSnackBar(SnackBar(content: Text('$error')));
                          }
                        }
                      },
                      icon: const Icon(Icons.widgets_outlined),
                      label: const Text('打开桌面小组件'),
                    ),
                ],
              ),
              if (controller.widgetStatus.value.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(controller.widgetStatus.value),
                ),
            ],
          ),
          const SizedBox(height: 12),
          XuSectionCard(
            title: '提醒',
            icon: Icons.notifications_outlined,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
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
                    if (hour != null) {
                      await controller.setDailyReview(true, hour);
                    }
                  },
                ),
            ],
          ),
          const SizedBox(height: 12),
          XuSectionCard(
            title: 'AI 服务',
            icon: Icons.auto_awesome_outlined,
            children: [
              const Text('配置 DeepSeek 后，可生成事项、蓝图和日报草稿。'),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  final current = await NativeBridge.readApiKey() ?? '';
                  var input = current;
                  if (!context.mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('DeepSeek API Key'),
                      content: TextFormField(
                        initialValue: current,
                        obscureText: true,
                        onChanged: (value) => input = value,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('取消'),
                        ),
                        FilledButton(
                          onPressed: () async {
                            await NativeBridge.writeApiKey(input.trim());
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                          },
                          child: const Text('保存'),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.key_outlined),
                label: const Text('设置 API Key'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_mobilePlatform)
            XuSectionCard(
              title: '关于序',
              icon: Icons.info_outline_rounded,
              children: [
                FutureBuilder<String?>(
                  future: NativeBridge.appVersion(),
                  builder: (context, snapshot) => Text(
                    snapshot.hasData
                        ? '版本 ${snapshot.data}'
                        : snapshot.hasError
                        ? '版本信息暂不可用'
                        : '正在读取版本信息',
                  ),
                ),
              ],
            )
          else
            XuSectionCard(
              title: '应用更新',
              icon: Icons.system_update_alt_rounded,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    try {
                      final version =
                          await NativeBridge.appVersion() ?? '0.0.0';
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
                                  update == null
                                      ? '已是最新版本'
                                      : '发现版本 ${update.version}',
                                ),
                                content: SizedBox(
                                  width: 460,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        update == null
                                            ? '当前版本：$version'
                                            : update.notes,
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
                                              setDialogState(
                                                () => downloading = true,
                                              );
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
                                                  throw StateError(
                                                    '系统未能打开已校验的更新包',
                                                  );
                                                }
                                                if (dialog.mounted) {
                                                  Navigator.pop(dialog);
                                                }
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
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text('$error'),
                                                    ),
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
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('检查更新'),
                ),
              ],
            ),
          const SizedBox(height: 12),
          XuSectionCard(
            title: '数据与同步',
            icon: Icons.storage_rounded,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
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
                      try {
                        final snapshot = await _pickJsonFile();
                        if (snapshot == null) return;
                        await controller.importWorkspace(snapshot);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('备份已导入')),
                          );
                        }
                      } catch (error) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('备份导入失败：$error')),
                          );
                        }
                      }
                    },
                    child: const Text('导入 JSON 备份'),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      try {
                        final resolving = controller.syncStatus.value
                            .startsWith('同步冲突');
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
              const SizedBox(height: 10),
              Obx(
                () => Semantics(
                  liveRegion: true,
                  child: Text(
                    controller.syncStatus.value.isEmpty
                        ? (controller.syncFolderPath.value.isEmpty
                              ? '未设置自动同步文件夹'
                              : '自动同步已启用：${controller.syncFolderPath.value}')
                        : controller.syncStatus.value,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    ],
  );
}

class _TaskSearchField extends StatefulWidget {
  const _TaskSearchField({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  State<_TaskSearchField> createState() => _TaskSearchFieldState();
}

class _TaskSearchFieldState extends State<_TaskSearchField> {
  late final input = TextEditingController(text: widget.value);

  @override
  void didUpdateWidget(covariant _TaskSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != input.text) {
      input.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: input,
    decoration: InputDecoration(
      prefixIcon: const Icon(Icons.search_rounded),
      hintText: '搜索事项',
      border: InputBorder.none,
      suffixIcon: widget.value.isEmpty
          ? null
          : IconButton(
              tooltip: '清除搜索',
              onPressed: () => widget.onChanged(''),
              icon: const Icon(Icons.close_rounded),
            ),
    ),
    onChanged: widget.onChanged,
  );
}

Future<void> _changeWorkspaceHistory(
  BuildContext context,
  Future<void> Function() action,
) async {
  try {
    await action();
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class _AddIntent extends Intent {
  const _AddIntent();
}

class _PaletteIntent extends Intent {
  const _PaletteIntent();
}

class _SettingsIntent extends Intent {
  const _SettingsIntent();
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

List<Map> _postponements(Map<String, dynamic> task) =>
    (task['postponements'] as List? ?? []).whereType<Map>().toList();

String _planDateLabel(Object? value) {
  final date = CalendarPlanLogic.parse(value);
  return date == null ? '未安排' : '${date.year}年${date.month}月${date.day}日';
}

Future<void> _showPostponements(
  BuildContext context,
  Map<String, dynamic> task,
) => showDialog<void>(
  context: context,
  builder: (dialog) => AlertDialog(
    title: Text('${task['title']} · 延期记录'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final entry in _postponements(task).reversed)
            ListTile(
              title: Text(
                '${_planDateLabel(entry['from'])} → ${_planDateLabel(entry['to'])}',
              ),
              subtitle: Text(_planDateLabel(entry['changedAt'])),
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
);

Future<void> showEditor(
  BuildContext context,
  String section, {
  Map<String, dynamic>? existing,
  Map<String, dynamic>? defaults,
}) async {
  final vm = Get.find<WorkspaceViewModel>();
  var title = '${existing?['title'] ?? existing?['name'] ?? ''}';
  var notes =
      '${existing?['notes'] ?? existing?['goal'] ?? existing?['content'] ?? ''}';
  var category = '${existing?['category'] ?? defaults?['category'] ?? ''}';
  var project = '${existing?['project'] ?? ''}';
  var contact = '${existing?['contact'] ?? ''}';
  var preparationTitle = '${existing?['preparationTaskTitle'] ?? ''}';
  var saving = false;
  String reportCategory = '${existing?['reportCategory'] ?? 'projectProgress'}';
  var estimateText = '${existing?['estimatedMinutes'] ?? ''}';
  var remainingText = '${existing?['remainingMinutes'] ?? ''}';
  var deadline = CalendarPlanLogic.parse(existing?['dueDate']);
  var planLocked = existing == null
      ? false
      : CalendarPlanLogic.isLocked(existing);
  var calendarAutoSync =
      (existing?['calendarAutoSync'] ?? defaults?['calendarAutoSync']) == true;
  String? saveError;
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
  var stageId = '${existing?['stageID'] ?? defaults?['stageID'] ?? ''}';
  var milestoneId =
      '${existing?['milestoneID'] ?? defaults?['milestoneID'] ?? ''}';
  if (!vm.items('blueprints').any((row) => row['id'] == blueprintId)) {
    blueprintId = '';
  }
  if (!vm
      .items('stages')
      .any(
        (row) => row['id'] == stageId && row['blueprintID'] == blueprintId,
      )) {
    stageId = '';
  }
  if (!vm
      .items('milestones')
      .any(
        (row) =>
            row['id'] == milestoneId &&
            row['blueprintID'] == blueprintId &&
            '${row['stageID'] ?? ''}' == stageId,
      )) {
    milestoneId = '';
  }
  final dependencyIds = List<String>.from(
    (existing?['dependencyIDs'] as List?)?.map((e) => '$e') ?? [],
  );
  DateTime date =
      DateTime.tryParse(
        '${existing?['scheduledFor'] ?? existing?['dueDate'] ?? existing?['date'] ?? defaults?['scheduledFor'] ?? ''}',
      ) ??
      DateTime.now();
  Map<String, dynamic>? timeBlock = switch (existing?['timeBlock'] ??
      defaults?['timeBlock']) {
    final Map block => Map<String, dynamic>.from(block),
    _ => null,
  };
  bool hasPlanDate =
      section != 'tasks' ||
      (existing == null && defaults?['status'] != 'unscheduled') ||
      (existing != null &&
          existing['scheduledFor'] != null &&
          existing['status'] != 'unscheduled');
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
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (saveError != null)
                  Text(
                    saveError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                if (section != 'reports')
                  TextFormField(
                    initialValue: title,
                    onChanged: (value) => title = value,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: section == 'tasks' ? '标题' : '名称',
                    ),
                  ),
                if (section == 'tasks')
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('计划日期'),
                    value: hasPlanDate,
                    onChanged: (value) => setState(() => hasPlanDate = value),
                  ),
                if (section == 'tasks' && hasPlanDate)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('同步到系统日历'),
                    value: calendarAutoSync,
                    onChanged: (value) =>
                        setState(() => calendarAutoSync = value),
                  ),
                if (hasPlanDate)
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
                          if (picked != null) {
                            setState(() {
                              final plan = <String, dynamic>{
                                'timeBlock': timeBlock,
                              };
                              CalendarPlanLogic.reschedule(plan, picked);
                              timeBlock =
                                  plan['timeBlock'] as Map<String, dynamic>?;
                              date = picked;
                            });
                          }
                        },
                        icon: const Icon(Icons.date_range),
                      ),
                    ],
                  ),
                if (section == 'tasks' && hasPlanDate && timeBlock != null)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('执行时间块'),
                    subtitle: Text(
                      '${DateTime.tryParse('${timeBlock!['start']}')?.toLocal().toString().substring(0, 16) ?? ''}–${DateTime.tryParse('${timeBlock!['end']}')?.toLocal().toString().substring(11, 16) ?? ''}',
                    ),
                    trailing: IconButton(
                      tooltip: '移除执行时间块',
                      onPressed: () => setState(() => timeBlock = null),
                      icon: const Icon(Icons.close),
                    ),
                  ),
                TextFormField(
                  initialValue: notes,
                  onChanged: (value) => notes = value,
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
                  if (existing != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.image_outlined),
                        label: const Text('管理任务参考图'),
                        onPressed: () {
                          final current = vm.tasks
                              .where((task) => task['id'] == existing['id'])
                              .firstOrNull;
                          if (current != null) {
                            editBlueprintImages(context, vm, 'tasks', current);
                          }
                        },
                      ),
                    ),
                  if (existing != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton.icon(
                        icon: const Icon(Icons.account_tree_outlined),
                        onPressed: () =>
                            showBlueprintForTask(context, existing),
                        label: const Text('在蓝图中查看'),
                      ),
                    ),
                  if (blueprintId.isNotEmpty) ...[
                    TextFormField(
                      initialValue: estimateText,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: '预计工时（分钟）'),
                      onChanged: (value) => estimateText = value.trim(),
                    ),
                    if (existing?['status'] == 'inProgress')
                      TextFormField(
                        initialValue: remainingText,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: '剩余工时（分钟）',
                        ),
                        onChanged: (value) => remainingText = value.trim(),
                      ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        deadline == null
                            ? '截止日期'
                            : '截止 · ${_planDateLabel(deadline!.toIso8601String())}',
                      ),
                      subtitle: deadline == null ? const Text('未设置') : null,
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: deadline ?? date,
                          firstDate: DateTime(1900),
                          lastDate: DateTime(2200),
                        );
                        if (picked != null && context.mounted) {
                          setState(
                            () => deadline = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              23,
                              59,
                              59,
                            ),
                          );
                        }
                      },
                      trailing: deadline == null
                          ? const Icon(Icons.event_outlined)
                          : IconButton(
                              tooltip: '移除截止日期',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(() => deadline = null),
                            ),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('固定安排'),
                      value: planLocked,
                      onChanged: (value) => setState(() => planLocked = value),
                    ),
                  ],

                  TextFormField(
                    initialValue: project,
                    onChanged: (value) => project = value,
                    decoration: const InputDecoration(labelText: '项目'),
                  ),
                  TextFormField(
                    initialValue: category,
                    onChanged: (value) => category = value,
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
                      stageId = '';
                      milestoneId = '';
                      dependencyIds.clear();
                    }),
                  ),
                ],
                if ((section == 'tasks' || section == 'milestones') &&
                    blueprintId.isNotEmpty)
                  DropdownButtonFormField<String>(
                    key: ValueKey(('stage', blueprintId)),
                    initialValue: stageId,
                    decoration: const InputDecoration(labelText: '阶段'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('无阶段')),
                      for (final row
                          in vm
                              .items('stages')
                              .where(
                                (row) => row['blueprintID'] == blueprintId,
                              ))
                        DropdownMenuItem(
                          value: '${row['id']}',
                          child: Text(
                            '${row['name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    isExpanded: true,
                    onChanged: (value) => setState(() {
                      stageId = value ?? '';
                      milestoneId = '';
                    }),
                  ),
                if (section == 'tasks' && blueprintId.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    key: ValueKey(('milestone', blueprintId, stageId)),
                    initialValue: milestoneId,
                    decoration: const InputDecoration(labelText: '里程碑'),
                    items: [
                      const DropdownMenuItem(value: '', child: Text('无里程碑')),
                      for (final row
                          in vm
                              .items('milestones')
                              .where(
                                (row) =>
                                    row['blueprintID'] == blueprintId &&
                                    '${row['stageID'] ?? ''}' == stageId,
                              ))
                        DropdownMenuItem(
                          value: '${row['id']}',
                          child: Text(
                            '${row['name']}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    isExpanded: true,
                    onChanged: (value) =>
                        setState(() => milestoneId = value ?? ''),
                  ),

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
                          try {
                            final file = await FilePicker.pickFile(
                              type: FileType.image,
                            );
                            if (file == null || !context.mounted) return;
                            if ((file.lengthSync() ?? 0) >
                                anniversaryCoverMaxBytes) {
                              throw const FormatException('封面图片须小于 5 MB');
                            }
                            final bytes = await file.readAsBytes();
                            final encoded = encodeAnniversaryCover(bytes);
                            if (context.mounted) {
                              setState(() => coverImage = encoded);
                            }
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
                  TextFormField(
                    initialValue: contact,
                    onChanged: (value) => contact = value,
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
                  if (!_mobilePlatform)
                    SwitchListTile(
                      title: const Text('显示在菜单栏'),
                      value: showInMenuBar,
                      onChanged: (value) =>
                          setState(() => showInMenuBar = value),
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
                    TextFormField(
                      initialValue: preparationTitle,
                      onChanged: (value) => preparationTitle = value,
                      decoration: const InputDecoration(
                        labelText: '准备任务名称（可选）',
                      ),
                    ),
                    const Text('应用只展示预览，确认后才会创建事项。'),
                  ],
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: saving ? null : () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: saving
                ? null
                : () async {
                    if (section != 'reports' && title.trim().isEmpty) return;
                    if (section == 'tasks' &&
                        [estimateText, remainingText].any(
                          (value) =>
                              value.isNotEmpty &&
                              (!RegExp(r'^\d+$').hasMatch(value) ||
                                  int.tryParse(value) == null),
                        )) {
                      setState(() => saveError = '工时请填写非负整数');
                      return;
                    }
                    setState(() => saving = true);
                    final row = <String, dynamic>{
                      ...?defaults,
                      ...?existing,
                      'id': existing?['id'] ?? newId(),
                      if (section == 'tasks' && existing == null)
                        'createdAt': DateTime.now().toIso8601String(),
                    };
                    if (section == 'tasks') {
                      row.addAll({
                        'title': title.trim(),
                        'notes': notes,
                        'project': project,
                        'category': category,
                        'reportCategory': reportCategory,
                        'quadrant': quadrant,
                        'blueprintID': blueprintId.isEmpty ? null : blueprintId,
                        'stageID': stageId.isEmpty ? null : stageId,
                        'milestoneID': milestoneId.isEmpty ? null : milestoneId,
                        'dependencyIDs': [...dependencyIds],
                        'estimatedMinutes': int.tryParse(estimateText),
                        'remainingMinutes': int.tryParse(remainingText),
                        'dueDate': deadline?.toIso8601String(),
                        'isPlanLocked': planLocked,
                        'planLocked': planLocked,

                        'scheduledFor': hasPlanDate
                            ? date.toIso8601String()
                            : null,
                        'timeBlock': hasPlanDate ? timeBlock : null,
                        if (calendarAutoSync ||
                            row.containsKey('calendarAutoSync'))
                          'calendarAutoSync': calendarAutoSync,
                        'status': hasPlanDate && row['status'] == 'unscheduled'
                            ? 'pending'
                            : !hasPlanDate &&
                                  row['status'] != 'completed' &&
                                  row['status'] != 'cancelled'
                            ? 'unscheduled'
                            : row['status'] ?? 'pending',
                      });
                      if (existing == null && row['status'] == 'completed') {
                        final now = DateTime.now().toIso8601String();
                        row['completedAt'] = now;
                        row['statusChangedAt'] = now;
                      }
                    } else if (section == 'blueprints') {
                      row.addAll({
                        'name': title.trim(),
                        'goal': notes,
                        'dueDate': date.toIso8601String(),
                      });
                    } else if (section == 'reports') {
                      row.addAll({
                        'content': notes,
                        'reportDate': date.toIso8601String(),
                      });
                    } else {
                      row.addAll({
                        'name': title.trim(),
                        if (section == 'anniversaries')
                          'date': date.toIso8601String()
                        else
                          'dueDate': date.toIso8601String(),
                        if (section == 'milestones')
                          'stageID': stageId.isEmpty ? null : stageId,
                      });
                      if (section == 'anniversaries') {
                        row['notes'] = notes;
                        row['coverImage'] = coverImage;
                        row['type'] = anniversaryType;
                        row['contact'] = contact.trim();
                        row['calendar'] = anniversaryCalendar;
                        row['repeatYearly'] = repeatYearly;
                        row['notificationEnabled'] = notificationEnabled;
                        row['reminderDays'] = reminderDays;
                        row['showOnHome'] = showOnHome;
                        row['showInMenuBar'] = showInMenuBar;
                        row['privacyMode'] = privacyMode;
                        row['preparationEnabled'] = preparationEnabled;
                        row['preparationLeadDays'] = preparationLeadDays;
                        row['preparationTaskTitle'] = preparationTitle.trim();
                        row['blueprintID'] = blueprintId.isEmpty
                            ? null
                            : blueprintId;
                      }
                    }
                    try {
                      if (section == 'tasks' && existing != null) {
                        row.remove('images');
                        final fields = <String, dynamic>{
                          for (final entry in row.entries)
                            if (entry.key != 'id' &&
                                jsonEncode(entry.value) !=
                                    jsonEncode(existing[entry.key]))
                              entry.key: entry.value,
                        };
                        if (fields.isNotEmpty) {
                          await vm.updateBlueprintFields(
                            section,
                            existing,
                            fields,
                          );
                        }
                      } else {
                        await vm.put(section, row);
                      }
                      if (context.mounted) {
                        Navigator.pop(context);
                        final calendarStatus = vm.calendarStatus.value;
                        if (section == 'tasks' &&
                            (calendarAutoSync ||
                                existing?['calendarAutoSync'] == true) &&
                            calendarStatus.startsWith('系统日历同步失败')) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(calendarStatus)),
                          );
                        }
                      }
                    } catch (error) {
                      if (context.mounted) {
                        setState(() => saving = false);
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
          final current = vm.tasks
              .where((task) => task['id'] == root['id'])
              .firstOrNull;
          if (current == null) return const Center(child: Text('事项已不存在'));
          final descendants = <Map<String, dynamic>>[current];
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
            onMove: (task, position) => vm.moveBlueprintNode(
              task['id'] as String,
              position.dx,
              position.dy,
            ),
            onPreview: (task) => showBlueprintImagePreview(
              dialog,
              blueprintImages(task['images']),
              0,
              '${task['title']} · 参考图',
            ),
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
            var input = '';
            final title = await showDialog<String>(
              context: dialog,
              builder: (inner) => AlertDialog(
                title: const Text('添加子任务'),
                content: TextField(
                  onChanged: (value) => input = value,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: '标题'),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(inner),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(inner, input.trim()),
                    child: const Text('添加'),
                  ),
                ],
              ),
            );
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

Future<void> showBlueprintForTask(
  BuildContext context,
  Map<String, dynamic> task,
) {
  final vm = Get.find<WorkspaceViewModel>();
  final blueprint = vm
      .items('blueprints')
      .where((row) => row['id'] == task['blueprintID'])
      .firstOrNull;
  if (blueprint != null) {
    return showBlueprintDetail(
      context,
      blueprint,
      initialTaskId: '${task['id']}',
    );
  }
  final id = CalendarPlanLogic.rootId(task, vm.tasks);
  final root = vm.tasks.where((row) => row['id'] == id).firstOrNull ?? task;
  return showTaskBlueprintDetail(context, root);
}

Future<void> showBlueprintDetail(
  BuildContext context,
  Map<String, dynamic> blueprint, {
  String? initialTaskId,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (dialog) => BlueprintWorkbench(
    id: blueprint['id'] as String,
    vm: Get.find<WorkspaceViewModel>(),
    edit: showEditor,
    replan: showReplanDialog,
    initialTaskId: initialTaskId,
  ),
);

Future<void> showAiTaskDraft(BuildContext context) async {
  var description = '';
  PlatformFile? imageFile;
  final request = await showDialog<(String, PlatformFile?)>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: const Text('AI 事项草稿'),
        scrollable: true,
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => description = value,
                maxLines: 5,
                autofocus: true,
                decoration: const InputDecoration(labelText: '描述要完成的事'),
              ),
              TextButton.icon(
                onPressed: () async {
                  try {
                    final file = await FilePicker.pickFile(
                      type: FileType.custom,
                      allowedExtensions: ['png', 'jpg', 'jpeg'],
                    );
                    if (file != null && dialog.mounted) {
                      setState(() => imageFile = file);
                    }
                  } catch (error) {
                    if (dialog.mounted) {
                      ScaffoldMessenger.of(
                        dialog,
                      ).showSnackBar(SnackBar(content: Text('无法选择图片：$error')));
                    }
                  }
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
                Navigator.pop(dialog, (description.trim(), imageFile)),
            child: const Text('生成'),
          ),
        ],
      ),
    ),
  );
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
            await image.readAsBytes(),
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
        scrollable: true,
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

Future<String?> showCategoryEditor(
  BuildContext context, {
  String? existing,
}) async {
  var name = existing ?? '';
  final vm = Get.find<WorkspaceViewModel>();
  var symbol = existing == null
      ? 'label'
      : '${vm.items('categories').where((row) => row['name'] == existing).firstOrNull?['symbol'] ?? 'label'}';
  var saving = false;
  String? saveError;
  return showDialog<String>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) {
        final theme = Theme.of(dialog);
        final colors = theme.colorScheme;
        final icon = categoryIconFor(symbol);
        final canSave = !saving && name.trim().isNotEmpty;
        final fieldBorder = OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outline),
        );

        Future<void> save() async {
          final trimmed = name.trim();
          if (saving || trimmed.isEmpty) return;
          setState(() {
            saving = true;
            saveError = null;
          });
          try {
            if (existing == null) {
              await vm.addCategory(trimmed, symbol: symbol);
            } else {
              await vm.renameCategory(existing, trimmed, symbol: symbol);
            }
            if (dialog.mounted) Navigator.pop(dialog, trimmed);
          } catch (error) {
            if (!dialog.mounted) return;
            setState(() {
              saveError = switch (error) {
                StateError() => error.message,
                FormatException() => error.message,
                _ => '$error',
              };
              saving = false;
            });
          }
        }

        return Dialog(
          constraints: const BoxConstraints(maxWidth: 428),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                child: Semantics(
                  header: true,
                  namesRoute: true,
                  child: Text(
                    existing == null ? '新建分类' : '编辑分类',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        initialValue: name,
                        autofocus: true,
                        enabled: !saving,
                        textInputAction: TextInputAction.done,
                        decoration: InputDecoration(
                          labelText: '分类名称',
                          hintText: '例如：工作计划',
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          border: fieldBorder,
                          enabledBorder: fieldBorder,
                          focusedBorder: fieldBorder.copyWith(
                            borderSide: BorderSide(
                              color: colors.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        onChanged: (value) => setState(() {
                          name = value;
                          saveError = null;
                        }),
                        onFieldSubmitted: (_) => save(),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          backgroundColor: colors.surfaceContainerLow,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                        onPressed: saving
                            ? null
                            : () async {
                                final picked = await showCategoryIconPicker(
                                  dialog,
                                  symbol,
                                );
                                if (picked != null && dialog.mounted) {
                                  setState(() => symbol = picked);
                                }
                              },
                        child: Row(
                          children: [
                            XuIconTile(icon.$2),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '分类图标',
                                    style: theme.textTheme.titleSmall,
                                  ),
                                  Text(
                                    icon.$1,
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('选择图标'),
                            const Icon(Icons.chevron_right_rounded, size: 18),
                          ],
                        ),
                      ),
                      if (saveError != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              saveError!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colors.error,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  border: Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  child: OverflowBar(
                    alignment: MainAxisAlignment.end,
                    overflowAlignment: OverflowBarAlignment.end,
                    spacing: 8,
                    overflowSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: saving ? null : () => Navigator.pop(dialog),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(88, 40),
                        ),
                        onPressed: canSave ? save : null,
                        child: Text(saving ? '保存中…' : '保存'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

Future<void> showTemplateDialog(BuildContext context) async {
  final vm = Get.find<WorkspaceViewModel>();
  await showDialog<void>(
    context: context,
    builder: (dialog) => AlertDialog(
      title: const Text('选择蓝图模板'),
      content: SizedBox(
        width: 500,
        height: 440,
        child: ListView(
          children: [
            for (final template in vm.items('blueprintTemplates'))
              ListTile(
                leading: const Icon(Icons.bookmark_outline),
                title: Text('${template['name']}'),
                subtitle: const Text('我的模板'),
                onTap: () async {
                  final date = await showDatePicker(
                    context: dialog,
                    initialDate: DateTime.now(),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2200),
                    helpText: '选择蓝图开始日期',
                  );
                  if (date == null || !dialog.mounted) return;
                  try {
                    await vm.createFromSavedBlueprintTemplate(
                      template['id'] as String,
                      date,
                    );
                    if (dialog.mounted) Navigator.pop(dialog);
                  } catch (error) {
                    if (dialog.mounted) {
                      ScaffoldMessenger.of(dialog)
                          .showSnackBar(SnackBar(content: Text('$error')));
                    }
                  }
                },
              ),
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
            !CalendarPlanLogic.isLocked(t),
      )
      .toList();
  if (editable.isEmpty) {
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('没有可重新规划的任务')));
    return;
  }
  var minutes = '240';
  var includeNotes = false, includeProject = true;
  final settings = await showDialog<(int, bool, bool)>(
    context: context,
    builder: (dialog) => StatefulBuilder(
      builder: (dialog, setState) => AlertDialog(
        title: const Text('AI 重新规划'),
        scrollable: true,
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('将 ${editable.length} 项未完成任务发送给 DeepSeek 生成日期建议。'),
              TextFormField(
                initialValue: minutes,
                onChanged: (value) => minutes = value,
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
              final value = int.tryParse(minutes);
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
