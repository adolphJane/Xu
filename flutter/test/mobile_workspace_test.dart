import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/ai_blueprint_dialog.dart';
import 'package:xu/src/app.dart';
import 'package:xu/src/blueprint_workbench.dart';
import 'package:xu/src/design_system/components/xu_shell.dart';
import 'package:xu/src/design_system/xu_theme.dart';
import 'package:xu/src/native.dart';
import 'package:xu/src/reports.dart';
import 'package:xu/src/workspace.dart';

class _MemoryRepository extends WorkspaceRepository {
  @override
  Future<void> commit(Map<String, List<Map<String, dynamic>>> next) async {
    data
      ..clear()
      ..addAll(next);
  }
}

void main() {
  testWidgets('short landscape viewport keeps all workspace pages usable', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(667, 375);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    Get.put<WorkspaceRepository>(
      _MemoryRepository()..load({'formatVersion': 1}),
    );
    final vm = Get.put(WorkspaceViewModel());
    await tester.pumpWidget(const XuApp());
    expect(find.byType(NavigationBar), findsOneWidget);

    for (final page in pages.keys) {
      vm.section.value = page;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: page);
    }
  });

  testWidgets('report and AI editors fit the phone keyboard', (tester) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    Get.put<WorkspaceRepository>(
      _MemoryRepository()..load({'formatVersion': 1}),
    );
    final vm = Get.put(WorkspaceViewModel());
    await tester.pumpWidget(
      MaterialApp(
        theme: XuTheme.build(Brightness.light),
        home: Scaffold(
          body: Builder(
            builder: (context) => Column(
              children: [
                TextButton(
                  onPressed: () => showReportEditor(context),
                  child: const Text('打开日报'),
                ),
                TextButton(
                  onPressed: () => showAiBlueprintDialog(context),
                  child: const Text('打开 AI 蓝图'),
                ),
                TextButton(
                  onPressed: () => showAiTaskDraft(context),
                  child: const Text('打开 AI 事项'),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final draft = List.filled(40, '完成计划').join();
    for (final (label, field, value, action) in [
      ('打开日报', '日报草稿', draft, '保存日报'),
      ('打开 AI 蓝图', '目标描述', '在手机上完成编辑', '取消'),
      ('打开 AI 事项', '描述要完成的事', '在手机上创建事项', '取消'),
    ]) {
      await tester.tap(find.text(label));
      await tester.pumpAndSettle();
      final input = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == field,
      );
      await tester.ensureVisible(input);
      await tester.enterText(input, value);
      tester.view.viewInsets = const FakeViewPadding(bottom: 320);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: field);
      final dismiss = find.text(action);
      if (field == '日报草稿') {
        final scroll = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;
        scroll.jumpTo(scroll.maxScrollExtent);
        await tester.pumpAndSettle();
      } else {
        await tester.ensureVisible(dismiss);
      }
      await tester.tap(dismiss);
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
    }
    expect(vm.items('reports').single['content'], draft);
  });

  testWidgets('phone navigation reaches every workspace page at large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeBridge.channel, (_) async => true);
    addTearDown(() {
      Get.reset();
      messenger.setMockMethodCallHandler(NativeBridge.channel, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetViewInsets();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    Get.put<WorkspaceRepository>(
      _MemoryRepository()..load({
        'formatVersion': 1,
        'tasks': [
          {'id': 'root', 'title': '适配手机日历并验证各项日程安排操作', 'status': 'pending'},
          {'id': 'inbox', 'title': '准备移动端验收', 'status': 'unscheduled'},
        ],
        'categories': [
          {'id': 'category', 'name': '较长的项目分类名称'},
        ],
      }),
    );
    final vm = Get.put(WorkspaceViewModel());
    vm.themeMode.value = ThemeMode.dark;
    await tester.pumpWidget(const XuApp());
    await tester.pumpAndSettle();

    final navigation = find.byType(NavigationBar);
    Finder destination(String label) =>
        find.descendant(of: navigation, matching: find.text(label));

    expect(find.byType(XuSidebar), findsNothing);
    expect(find.text('今天还没有安排事项'), findsOneWidget);
    for (final (label, page) in [
      ('事项', 'tasks'),
      ('日历', 'calendar'),
      ('收集箱', 'inbox'),
    ]) {
      await tester.tap(destination(label));
      await tester.pumpAndSettle();
      expect(vm.section.value, page);
      expect(tester.takeException(), isNull, reason: page);
      if (page == 'tasks') {
        final search = find.byType(TextField).first;
        await tester.ensureVisible(search);
        await tester.enterText(search, '日历');
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        expect(navigation, findsNothing);
        expect(tester.takeException(), isNull, reason: '手机事项搜索键盘');
        await tester.enterText(search, '');
        tester.view.resetViewInsets();
        await tester.pumpAndSettle();
      }
      if (page == 'calendar') {
        await tester.tap(find.widgetWithText(FilterChip, '任务系列'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(TextButton, '安排').first);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, '保存安排'));
        await tester.pumpAndSettle();
        final task = vm.tasks.firstWhere((row) => row['id'] == 'root');
        expect(task['scheduledFor'], isNotNull);
        await tester.tap(find.widgetWithText(FilterChip, '返回日历'));
        await tester.pumpAndSettle();
        expect(find.byTooltip('下一日'), findsOneWidget);
      }
    }
    for (final (label, page) in [
      ('分类', 'categories'),
      ('纪念日', 'anniversaries'),
      ('已处理', 'processed'),
      ('日报', 'reports'),
      ('设置', 'settings'),
    ]) {
      await tester.tap(destination('更多'));
      await tester.pumpAndSettle();
      final row = find.widgetWithText(ListTile, label).last;
      await tester.ensureVisible(row);
      await tester.tap(row);
      await tester.pumpAndSettle();
      expect(vm.section.value, page);
      expect(tester.takeException(), isNull, reason: page);
      if (page == 'categories') {
        await tester.tap(find.text('新建分类'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).last, '旅行计划');
        await tester.tap(find.text('选择图标'));
        await tester.pumpAndSettle();
        final group = find.widgetWithText(ChoiceChip, '旅行与出行');
        await tester.ensureVisible(group);
        await tester.tap(group);
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(OutlinedButton, '航班'));
        await tester.pumpAndSettle();
        expect(find.text('航班'), findsOneWidget);
        await tester.tap(find.widgetWithText(FilledButton, '保存'));
        await tester.pumpAndSettle();
        expect(
          vm.items('categories').map((row) => row['name']),
          contains('旅行计划'),
        );
      }
    }
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(vm.section.value, 'today');
  });

  testWidgets('phone blueprint starts two ready branches together', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 700);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeBridge.channel, (_) async => null);
    addTearDown(() {
      Get.reset();
      messenger.setMockMethodCallHandler(NativeBridge.channel, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
    });
    Get.put<WorkspaceRepository>(
      _MemoryRepository()..load({
        'formatVersion': 1,
        'blueprints': [
          {'id': 'b', 'name': '长标题下的移动端蓝图编排与并行执行检查'},
        ],
        'tasks': [
          {
            'id': 'plan',
            'title': '确定方案',
            'blueprintID': 'b',
            'status': 'completed',
          },
          for (final (id, title) in [('art', '整理视觉素材'), ('code', '实现页面交互')])
            {
              'id': id,
              'title': title,
              'blueprintID': 'b',
              'status': 'pending',
              'dependencyIDs': ['plan'],
            },
        ],
      }),
    );
    final vm = Get.put(WorkspaceViewModel());
    await tester.pumpWidget(
      MaterialApp(
        theme: XuTheme.build(Brightness.light),
        home: BlueprintWorkbench(
          id: 'b',
          vm: vm,
          edit: (_, _, {existing, defaults}) async {},
          replan: (_, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('关闭蓝图'), findsOneWidget);
    expect(find.byTooltip('添加事项'), findsOneWidget);

    tester.view.physicalSize = const Size(667, 375);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull, reason: '横屏蓝图工作台');
    await tester.tap(find.text('全选可开始 · 2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('开始选中 · 2'));
    await tester.pumpAndSettle();
    expect(
      vm.tasks
          .where((row) => row['status'] == 'inProgress')
          .map((row) => row['id']),
      unorderedEquals(['art', 'code']),
    );
    expect(tester.takeException(), isNull);
  });
}
