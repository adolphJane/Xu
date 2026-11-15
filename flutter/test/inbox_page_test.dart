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

  Future<_MemoryRepository> openInbox(
    WidgetTester tester, {
    List<Map<String, dynamic>> tasks = const [],
  }) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = _MemoryRepository();
    repo.load({'formatVersion': 1, 'tasks': tasks});
    Get.put<WorkspaceRepository>(repo);
    Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await tester.pumpWidget(const XuApp());
    await tester.tap(find.text('收集箱').first);
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('empty inbox offers capture with an unscheduled plan', (
    tester,
  ) async {
    final repo = await openInbox(tester);
    expect(find.text('CAPTURE'), findsOneWidget);
    expect(find.text('收集箱已清空'), findsOneWidget);
    expect(find.textContaining('暂不安排日期'), findsOneWidget);
    await tester.tap(find.text('收集事项'));
    await tester.pumpAndSettle();
    final planSwitch = find.widgetWithText(SwitchListTile, '计划日期');
    expect(tester.widget<SwitchListTile>(planSwitch).value, isFalse);
    await tester.enterText(
      find.byWidgetPredicate(
        (widget) => widget is TextField && widget.decoration?.labelText == '标题',
      ),
      '稍后整理资料',
    );
    await tester.tap(find.text('保存'));
    await waitForData(tester, () => repo.data['tasks']!.isNotEmpty);
    expect(repo.data['tasks']!.single['status'], 'unscheduled');
    expect(repo.data['tasks']!.single['scheduledFor'], isNull);
    expect(find.widgetWithText(ListTile, '稍后整理资料'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('inbox filters by status and planning today removes the task', (
    tester,
  ) async {
    final repo = await openInbox(
      tester,
      tasks: [
        {
          'id': 'planned',
          'title': '今天已安排',
          'status': 'pending',
          'scheduledFor': DateTime.now().toIso8601String(),
        },
        {
          'id': 'capture',
          'title': '待规划事项',
          'status': 'unscheduled',
          'createdAt': '2026-11-15T08:00:00',
        },
        {'id': 'done', 'title': '已完成事项', 'status': 'completed'},
      ],
    );
    expect(find.text('待规划事项'), findsOneWidget);
    expect(find.text('今天已安排'), findsNothing);
    expect(find.text('已完成事项'), findsNothing);
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('安排今天'));
    await waitForData(
      tester,
      () => repo.data['tasks']!.any(
        (task) => task['id'] == 'capture' && task['status'] == 'pending',
      ),
    );
    expect(find.text('收集箱已清空'), findsOneWidget);
    expect(find.text('待规划事项'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
