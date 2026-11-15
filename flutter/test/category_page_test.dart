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
    await tester.enterText(find.byType(TextField).first, '学习');
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.ancestor(
              of: find.byTooltip('添加类别'),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNotNull,
    );
    await tester.tap(find.byTooltip('添加类别'));
    await waitForData(tester, () => repo.data['categories']!.isNotEmpty);
    expect(repo.data['categories']!.single['name'], '学习');

    await tester.tap(find.byTooltip('管理类别'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重命名类别'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '成长');
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('阅读').last);
    await tester.pumpAndSettle();
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
    expect(find.text('任务分类'), findsOneWidget);
    expect(find.text('类别概览'), findsOneWidget);
    expect(find.text('先从一个类别开始'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
