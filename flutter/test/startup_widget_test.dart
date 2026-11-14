import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/app.dart';
import 'package:xu/src/workspace.dart';

void main() {
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
    await tester.tap(find.text('事项').first);
    await tester.pumpAndSettle();
    expect(find.text('任务系列'), findsOneWidget);
    expect(find.text('第一步'), findsNothing);
    await tester.tap(find.byTooltip('展开子任务'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('收起子任务'), findsOneWidget);
    expect(find.text('第一步'), findsOneWidget);
    await tester.tap(find.text('蓝图').first);
    await tester.pumpAndSettle();
    expect(find.text('年度蓝图'), findsOneWidget);
    await tester.tap(find.text('长期项目'));
    await tester.pumpAndSettle();
    expect(find.text('长期项目 · 任务蓝图'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
