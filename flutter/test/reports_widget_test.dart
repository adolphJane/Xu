import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/reports.dart';
import 'package:xu/src/report_rules.dart';
import 'package:xu/src/workspace.dart';
import 'package:xu/src/weekly_review.dart';

void main() {
  testWidgets('manual report is validated, saved, and visible in history', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() async {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = _MemoryRepository();
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await expectLater(
      vm.put('reports', {
        'id': 'invalid',
        'reportDate': DateTime.now().toIso8601String(),
        'minimumLength': 125,
        'maximumLength': 180,
        'content': '太短',
      }),
      throwsFormatException,
    );
    await tester.pumpWidget(
      GetMaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              TextButton(
                onPressed: () => showReportEditor(Get.context!),
                child: const Text('写日报'),
              ),
              const Expanded(child: ReportsPage()),
            ],
          ),
        ),
      ),
    );
    await tester.tap(find.text('写日报'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('今日日报'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, '日报草稿'), '太短');
    await tester.pump();
    expect(find.textContaining('少于设定下限'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存日报'))
          .onPressed,
      isNull,
    );
    final body = List.filled(40, '完成计划').join();
    await tester.enterText(find.widgetWithText(TextField, '日报草稿'), body);
    await tester.pump();
    await tester.tap(find.text('保存日报'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(vm.items('reports'), hasLength(1));
    expect(vm.items('reports').single['minimumLength'], 125);
    await tester.pumpWidget(
      GetMaterialApp(home: const Scaffold(body: ReportsPage())),
    );
    expect(find.text('${ReportRules.length(body)} 字'), findsOneWidget);
    await tester.tap(find.byType(ListTile));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('复制 Markdown'), findsOneWidget);
  });

  testWidgets('weekly review saves and opens from history', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = _MemoryRepository();
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: WeeklyReviewsSection())),
    );
    await tester.tap(find.text('本周复盘'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '保存周复盘'))
          .onPressed,
      isNull,
    );
    await tester.enterText(
      find.widgetWithText(TextField, '本周总结'),
      '完成 Flutter 周复盘迁移',
    );
    await tester.enterText(find.widgetWithText(TextField, '下周重点'), '检查蓝图容量');
    await tester.pump();
    await tester.tap(find.text('保存周复盘'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(vm.items('weeklyReviews').single['summary'], '完成 Flutter 周复盘迁移');
    await tester.pumpWidget(
      const GetMaterialApp(home: Scaffold(body: WeeklyReviewsSection())),
    );
    await tester.tap(find.byType(ListTile));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('检查蓝图容量'), findsOneWidget);
  });
}

class _MemoryRepository extends WorkspaceRepository {
  @override
  Future<void> commit(Map<String, List<Map<String, dynamic>>> next) async {
    data
      ..clear()
      ..addAll(next);
  }
}
