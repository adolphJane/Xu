import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/app.dart';
import 'package:xu/src/design_system/components/xu_shell.dart';
import 'package:xu/src/design_system/xu_theme.dart';
import 'package:xu/src/workspace.dart';

void main() {
  testWidgets('sidebar stays navigable with dark theme and large text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(900, 620));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final items = [
      for (final MapEntry(key: key, value: (label, icon, selectedIcon))
          in pages.entries)
        XuNavigationItem(key, label, icon, selectedIcon),
    ];
    var selected = 'today';
    await tester.pumpWidget(
      MaterialApp(
        theme: XuTheme.build(Brightness.dark),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Material(
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: StatefulBuilder(
                builder: (context, setState) => XuSidebar(
                  items: items,
                  selected: selected,
                  onSelect: (page) => setState(() => selected = page),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(
      tester.getSemantics(find.text('今日')).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(selected, 'tasks');
    final settings = find.text('设置');
    final settingsPosition = tester.getCenter(settings);
    await tester.drag(find.byType(ListView), const Offset(0, -260));
    await tester.pumpAndSettle();
    expect(tester.getCenter(settings), settingsPosition);
    await tester.tap(settings);
    await tester.pumpAndSettle();
    expect(
      tester.getSemantics(settings).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('home shows sidebar and today on first frame', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    final repo = WorkspaceRepository();
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const XuApp());
    await tester.pump();
    expect(find.text('序'), findsWidgets);
    expect(find.text('今日'), findsWidgets);
    expect(find.text('收集箱'), findsOneWidget);
    expect(find.text('今天还没有安排事项'), findsOneWidget);
  });
  testWidgets('task series expands and blueprint toolbar fits desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    final repo = WorkspaceRepository();
    repo.load({
      'formatVersion': 1,
      'tasks': [
        {'id': 'root', 'title': '长期项目', 'status': 'pending'},
        {
          'id': 'child',
          'parentTaskID': 'root',
          'title': '第一步',
          'status': 'pending',
        },
      ],
      'blueprints': [
        {'id': 'blueprint', 'name': '年度蓝图', 'goal': '持续推进'},
      ],
    });
    Get.put<WorkspaceRepository>(repo);
    Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const XuApp());
    expect(find.text('蓝图'), findsNothing);
    expect(find.text('四象限'), findsNothing);
    await tester.tap(find.text('事项').first);
    await tester.pumpAndSettle();
    expect(find.text('任务系列'), findsOneWidget);
    expect(find.text('第一步'), findsNothing);
    await tester.tap(find.byTooltip('展开子任务'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起子任务'), findsOneWidget);
    expect(find.text('第一步'), findsOneWidget);
    expect(find.text('蓝图'), findsOneWidget);
    expect(find.text('四象限'), findsOneWidget);
    await tester.tap(find.text('蓝图'));
    await tester.pumpAndSettle();
    expect(find.text('年度蓝图'), findsOneWidget);
    await tester.tap(find.text('长期项目'));
    await tester.pumpAndSettle();
    expect(find.text('长期项目 · 任务蓝图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Today opens the task’s blueprint on its selected node', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    final repo = WorkspaceRepository()
      ..load({
        'formatVersion': 1,
        'blueprints': [
          {'id': 'b', 'name': '关联蓝图'},
        ],
        'tasks': [
          {
            'id': 'b-task',
            'title': '今日步骤',
            'blueprintID': 'b',
            'status': 'pending',
            'scheduledFor': DateTime.now().toIso8601String(),
          },
        ],
      });
    Get.put<WorkspaceRepository>(repo);
    Get.put(WorkspaceViewModel());
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const XuApp());
    await tester.tap(find.byType(PopupMenuButton<String>).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('在蓝图中查看'));
    await tester.pumpAndSettle();
    expect(find.text('关联蓝图'), findsOneWidget);
    expect(find.text('连接后继'), findsOneWidget);
    expect(find.text('关系编排'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tasks workbench follows the wide window layout', (tester) async {
    tester.view.physicalSize = const Size(1600, 970);
    tester.view.devicePixelRatio = 1;
    final repo = WorkspaceRepository();
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const XuApp());
    await tester.tap(find.text('事项').first);
    await tester.pumpAndSettle();

    final heading = tester.getTopLeft(find.text('事项').last);
    final filter = tester.getTopLeft(find.byType(ChoiceChip).first);
    final search = tester.getTopLeft(find.byType(TextFormField).first);
    expect((heading.dx - filter.dx).abs(), lessThan(40));
    expect(search.dx, greaterThanOrEqualTo(filter.dx));
    expect(find.text('没有待处理事项'), findsOneWidget);
    expect(find.text('添加事项'), findsOneWidget);
    expect(find.text('列表'), findsOneWidget);
    expect(find.text('四象限'), findsWidgets);
    await tester.tap(find.text('四象限').last);
    await tester.pumpAndSettle();
    expect(find.text('重要且紧急 · 0 项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tasks workbench fits a compact desktop window', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    final repo = WorkspaceRepository();
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const XuApp());
    await tester.tap(find.text('事项').first);
    await tester.pumpAndSettle();
    expect(find.text('添加事项'), findsOneWidget);
    expect(find.text('没有待处理事项'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('page content expands as the desktop window widens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 800);
    tester.view.devicePixelRatio = 1;
    final repo = WorkspaceRepository()..load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put(WorkspaceViewModel());
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(const XuApp());
    await tester.pumpAndSettle();
    final firstLeft = tester.getTopLeft(find.text('今日').last).dx;
    final firstRight = tester.getTopRight(find.text('事项视图')).dx;
    tester.view.physicalSize = const Size(2000, 800);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('今日').last).dx, closeTo(firstLeft, 1));
    expect(
      tester.getTopRight(find.text('事项视图')).dx - firstRight,
      closeTo(600, 1),
    );
    vm.section.value = 'tasks';
    await tester.pumpAndSettle();
    expect(tester.getTopRight(find.text('添加事项')).dx, greaterThan(1900));
    vm.section.value = 'settings';
    await tester.pumpAndSettle();
    final card = find
        .ancestor(of: find.text('外观'), matching: find.byType(Card))
        .first;
    expect(tester.getSize(card).width, greaterThan(1700));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'all pages fit the minimum window with large dark text and reduced motion',
    (tester) async {
      tester.view.physicalSize = const Size(900, 620);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(() {
        Get.reset();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        tester.platformDispatcher.clearTextScaleFactorTestValue();
        tester.platformDispatcher.clearAccessibilityFeaturesTestValue();
      });
      final repo = WorkspaceRepository()
        ..load({
          'formatVersion': 1,
          'blueprints': [
            {'id': 'b', 'name': '蓝图与非常长的中文说明需要在更窄的窗口中换行展示完整内容'},
          ],
          'tasks': [
            {
              'id': 't',
              'title': '为发布事项准备超过三十个字的中文长标题以验证窗口重新换行完整可读',
              'status': 'pending',
              'blueprintID': 'b',
            },
            {'id': 'closed', 'title': '已完成的事项', 'status': 'completed'},
          ],
        });
      Get.put<WorkspaceRepository>(repo);
      final vm = Get.put(WorkspaceViewModel());
      vm.themeMode.value = ThemeMode.dark;
      await tester.pumpWidget(const XuApp());

      for (final (section, heading) in const [
        ('today', '今天还没有安排事项'),
        ('inbox', '收集事项'),
        ('tasks', '添加事项'),
        ('calendar', '安排事项'),
        ('categories', '新建分类'),
        ('anniversaries', '添加纪念日'),
        ('processed', '全部记录'),
        ('reports', '创建日报'),
        ('settings', '打开桌面小组件'),
      ]) {
        vm.section.value = section;
        await tester.pump();
        expect(find.text(heading), findsOneWidget, reason: section);
        expect(tester.takeException(), isNull, reason: section);
      }

      vm.section.value = 'tasks';
      await tester.pumpAndSettle();
      await tester.tap(find.text('蓝图'));
      await tester.pumpAndSettle();
      expect(find.text('新建蓝图'), findsOneWidget);
      final blueprint = find.textContaining('蓝图与非常长的中文说明');
      await tester.scrollUntilVisible(
        blueprint,
        120,
        scrollable: find.descendant(
          of: find.byType(ListView).last,
          matching: find.byType(Scrollable),
        ),
      );
      await Scrollable.ensureVisible(tester.element(blueprint), alignment: 0.5);
      await tester.pumpAndSettle();
      await tester.tap(blueprint);
      await tester.pumpAndSettle();
      expect(find.byTooltip('关闭蓝图'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
