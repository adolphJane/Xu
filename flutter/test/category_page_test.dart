import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/app.dart';
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
  Finder pickerText(String text) => find.descendant(
    of: find.widgetWithText(Dialog, '分类图标库'),
    matching: find.text(text),
  );

  Future<void> waitForData(WidgetTester tester, bool Function() ready) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 100 && !ready(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(ready(), isTrue);
    });
    await tester.pumpAndSettle();
  }

  testWidgets(
    'category page filters tasks and preselects category for a task',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        Get.reset();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repo = _MemoryRepository();
      repo.load({
        'formatVersion': 1,
        'categories': [
          {'id': 'work', 'name': '工作'},
          {'id': 'empty', 'name': '学习'},
        ],
        'tasks': [
          {'id': 'a', 'title': '工作待办', 'category': '工作', 'status': 'pending'},
          {'id': 'b', 'title': '工作完成', 'category': '工作', 'status': 'completed'},
          {'id': 'c', 'title': '未分类待办', 'status': 'pending'},
        ],
      });
      Get.put<WorkspaceRepository>(repo);
      Get.put<WorkspaceViewModel>(WorkspaceViewModel());

      await tester.pumpWidget(const XuApp());
      await tester.tap(find.text('分类').first);
      await tester.pumpAndSettle();
      expect(find.text('任务分类'), findsOneWidget);
      expect(find.text('3 项任务 · 2 项待处理'), findsOneWidget);
      await tester.tap(find.text('工作').first);
      await tester.pumpAndSettle();
      expect(find.text('工作待办'), findsOneWidget);
      expect(find.text('工作完成'), findsNothing);
      expect(find.text('未分类待办'), findsNothing);

      await tester.tap(find.text('已处理  1'));
      await tester.pumpAndSettle();
      expect(find.text('工作完成'), findsOneWidget);
      expect(find.text('工作待办'), findsNothing);

      await tester.tap(find.text('新建任务').first);
      await tester.pumpAndSettle();
      final categoryField = find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '分类',
      );
      expect(tester.widget<TextField>(categoryField).controller?.text, '工作');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('category page creates, renames and deletes a category', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = _MemoryRepository();
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    Get.put<WorkspaceViewModel>(WorkspaceViewModel());

    await tester.pumpWidget(const XuApp());
    await tester.tap(find.text('分类').first);
    await tester.pumpAndSettle();
    expect(find.text('新建分类'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    await tester.tap(find.text('新建分类'));
    await tester.pumpAndSettle();
    final save = find.widgetWithText(FilledButton, '保存');
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    await tester.enterText(find.byType(TextField).first, '学习');
    await tester.tap(find.text('选择图标'));
    await tester.pumpAndSettle();
    expect(find.text('分类图标库'), findsOneWidget);
    expect(pickerText('标签'), findsOneWidget);
    final travelGroup = find.widgetWithText(TextButton, '旅行与出行');
    await tester.tap(travelGroup);
    await tester.pumpAndSettle();
    expect(pickerText('标签'), findsNothing);
    final flight = tester.getCenter(pickerText('航班'));
    expect(flight.dx, greaterThan(tester.getCenter(travelGroup).dx));
    expect(flight.dy, tester.getCenter(pickerText('旅行')).dy);
    await tester.tap(pickerText('航班'));
    await tester.pumpAndSettle();
    expect(find.text('航班'), findsOneWidget);
    expect(repo.data['categories'], isEmpty);
    await tester.tap(find.text('保存'));
    await waitForData(tester, () => repo.data['categories']!.isNotEmpty);
    expect(repo.data['categories']!.single['name'], '学习');
    expect(repo.data['categories']!.single['symbol'], 'plane');
    expect(find.byIcon(Icons.flight_rounded), findsWidgets);

    await tester.tap(find.text('新建分类'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '学习');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('分类已存在'), findsOneWidget);
    expect(repo.data['categories'], hasLength(1));
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('管理类别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('编辑分类'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '成长');
    await tester.tap(find.text('选择图标'));
    await tester.pumpAndSettle();
    expect(
      find.ancestor(
        of: travelGroup,
        matching: find.byWidgetPredicate(
          (widget) => widget is Semantics && widget.properties.selected == true,
        ),
      ),
      findsWidgets,
    );
    await tester.enterText(find.byType(TextField).last, 'book');
    await tester.pumpAndSettle();
    await tester.tap(pickerText('阅读'));
    await tester.pumpAndSettle();
    expect(repo.data['categories']!.single['symbol'], 'plane');
    await tester.tap(find.text('保存'));
    await waitForData(
      tester,
      () => repo.data['categories']!.single['name'] == '成长',
    );
    expect(repo.data['categories']!.single['name'], '成长');
    expect(repo.data['categories']!.single['symbol'], 'book');

    await tester.tap(find.byTooltip('管理类别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除类别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除').last);
    await waitForData(tester, () => repo.data['categories']!.isEmpty);
    expect(repo.data['categories'], isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('category page fits a compact desktop window', (tester) async {
    tester.view.physicalSize = const Size(900, 620);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.5;
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.platformDispatcher.clearTextScaleFactorTestValue();
      tester.platformDispatcher.clearPlatformBrightnessTestValue();
    });
    final repo = _MemoryRepository();
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    Get.put<WorkspaceViewModel>(WorkspaceViewModel());

    await tester.pumpWidget(const XuApp());
    await tester.tap(find.text('分类').first);
    await tester.pumpAndSettle();
    expect(find.text('任务分类'), findsOneWidget);
    expect(find.text('类别概览'), findsOneWidget);
    expect(find.text('先从一个类别开始'), findsOneWidget);
    await tester.tap(find.text('新建分类'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('选择图标'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '不存在的图标');
    await tester.pumpAndSettle();
    expect(find.text('没有找到匹配的图标'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    expect(pickerText('标签'), findsOneWidget);
    await tester.tap(pickerText('取消'));
    await tester.pumpAndSettle();
    expect(find.text('分类图标库'), findsNothing);
    expect(find.text('标签'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
