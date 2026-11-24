import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/app.dart';
import 'package:xu/src/native.dart';
import 'package:xu/src/report_rules.dart';
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
  testWidgets(
    'empty workspace: capture, plan today, complete, review, and read history',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        Get.reset();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        NativeBridge.channel,
        (_) async => null,
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(NativeBridge.channel, null),
      );
      final repo = _MemoryRepository()..load({'formatVersion': 1});
      Get.put<WorkspaceRepository>(repo);
      final vm = Get.put(WorkspaceViewModel());
      Future<void> click(Finder finder) async {
        await tester.tap(finder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 450));
        await tester.pumpAndSettle();
      }

      await tester.pumpWidget(const XuApp());
      await click(find.text('收集箱').first);
      await click(find.text('收集事项'));
      await tester.enterText(find.widgetWithText(TextField, '标题'), '放弃的草稿');
      await click(find.text('取消'));
      expect(vm.tasks, isEmpty);
      expect(tester.takeException(), isNull);
      await click(find.text('收集事项'));
      const title = '验收闭环事项';
      await tester.enterText(find.widgetWithText(TextField, '标题'), title);
      await click(find.text('保存'));
      expect(vm.tasks.single['status'], 'unscheduled');
      expect(find.byType(AlertDialog), findsNothing);
      await click(find.byType(PopupMenuButton<String>).first);
      await click(find.text('安排今天'));
      expect(find.text('收集箱已清空'), findsOneWidget);
      expect(vm.tasks.single['status'], 'pending');
      await click(find.text('今日').first);
      expect(find.text(title), findsOneWidget);
      await click(find.byType(Checkbox).first);
      expect(vm.tasks.single['status'], 'completed');
      await click(find.text('已处理').first);
      expect(find.text(title), findsOneWidget);
      await click(find.widgetWithText(ChoiceChip, '已取消'));
      expect(find.text(title), findsNothing);
      expect(find.text('此状态下暂无记录'), findsOneWidget);
      await click(find.text('查看全部'));
      expect(find.text(title), findsOneWidget);
      await click(find.text('日报').first);
      await click(find.text('创建日报'));
      await tester.enterText(
        find.widgetWithText(TextField, '日报补充'),
        '核对执行结果与次日计划。',
      );
      await click(find.text('生成本地草稿'));
      final form = tester.widget<TextField>(
        find.widgetWithText(TextField, '日报草稿'),
      );
      final report = form.controller!.text;
      expect(report, contains('已完成：$title'));
      expect(ReportRules.warning(report, 125, 180), isNull);
      await click(find.text('保存日报'));
      expect(vm.items('reports').single['content'], contains(title));
      expect(find.text('历史日报'), findsOneWidget);
      await click(
        find.widgetWithText(ListTile, '${ReportRules.length(report)} 字'),
      );
      expect(find.text('复制 Markdown'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
