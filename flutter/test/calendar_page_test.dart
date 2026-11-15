import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/app.dart';
import 'package:xu/src/native.dart';
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
  test('series changes commit together and reject stale snapshots', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NativeBridge.channel,
          (MethodCall _) async => true,
        );
    addTearDown(() {
      Get.reset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null);
    });
    final repo = _MemoryRepository()
      ..load({
        'formatVersion': 1,
        'tasks': [
          {
            'id': 'a',
            'title': '第一步',
            'status': 'pending',
            'scheduledFor': '2026-11-16',
          },
          {
            'id': 'b',
            'title': '第二步',
            'status': 'pending',
            'scheduledFor': '2026-11-17',
          },
        ],
      });
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    final before = repo.data['tasks']!
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
    final after = [
      {...before[0], 'scheduledFor': '2026-11-19'},
      {...before[1], 'scheduledFor': '2026-11-20'},
    ];
    await vm.applyCalendarChanges(before, after);
    expect(repo.data['tasks']!.map((row) => row['scheduledFor']), [
      '2026-11-19',
      '2026-11-20',
    ]);
    await expectLater(vm.applyCalendarChanges(before, after), throwsStateError);
    expect(repo.data['tasks']!.map((row) => row['scheduledFor']), [
      '2026-11-19',
      '2026-11-20',
    ]);
  });

  testWidgets('arranging a task saves an explicit block and can be undone', (
    tester,
  ) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          NativeBridge.channel,
          (MethodCall _) async => true,
        );
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      Get.reset();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null);
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = _MemoryRepository()
      ..load({
        'formatVersion': 1,
        'tasks': [
          {'id': 'task', 'title': '写迁移计划', 'status': 'unscheduled'},
        ],
      });
    Get.put<WorkspaceRepository>(repo);
    Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await tester.pumpWidget(const XuApp());
    await tester.tap(find.text('日历计划').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('安排').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('指定执行时间'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存安排'));
    await tester.pumpAndSettle();
    expect(repo.data['tasks']!.single['timeBlock'], isA<Map>());
    expect(repo.data['tasks']!.single['status'], 'pending');
    await tester.tap(find.text('撤销安排'));
    await tester.pumpAndSettle();
    expect(repo.data['tasks']!.single['timeBlock'], isNull);
    expect(repo.data['tasks']!.single['status'], 'unscheduled');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'dragging a waiting task onto a month day opens a dated preview',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        Get.reset();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repo = _MemoryRepository()
        ..load({
          'formatVersion': 1,
          'tasks': [
            {'id': 'drag', 'title': '拖动事项', 'status': 'unscheduled'},
          ],
        });
      Get.put<WorkspaceRepository>(repo);
      Get.put<WorkspaceViewModel>(WorkspaceViewModel());
      await tester.pumpWidget(const XuApp());
      await tester.tap(find.text('日历计划').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('月').first);
      await tester.pumpAndSettle();
      final day = DateTime.now().day;
      final source = tester.getCenter(find.text('拖动事项').first);
      final target = tester.getCenter(find.text('$day日').first);
      await tester.dragFrom(source, target - source);
      await tester.pumpAndSettle();
      expect(find.text('安排时间 · 拖动事项'), findsOneWidget);
      await tester.tap(find.text('取消').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('周').first);
      await tester.pumpAndSettle();
      final hourLabel = tester.getTopLeft(find.text('09:00'));
      final hourTarget = Offset(hourLabel.dx + 130, hourLabel.dy + 20);
      final nextSource = tester.getCenter(find.text('拖动事项').first);
      await tester.dragFrom(nextSource, hourTarget - nextSource);
      await tester.pumpAndSettle();
      expect(find.text('安排时间 · 拖动事项'), findsOneWidget);
      expect(
        tester
            .widget<SwitchListTile>(
              find.widgetWithText(SwitchListTile, '指定执行时间'),
            )
            .value,
        isTrue,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('dragging a series opens an atomic move preview', (tester) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      Get.reset();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    final repo = _MemoryRepository()
      ..load({
        'formatVersion': 1,
        'tasks': [
          {'id': 'root', 'title': '搬迁系列', 'status': 'pending'},
          {
            'id': 'leaf',
            'parentTaskID': 'root',
            'title': '第一步',
            'status': 'pending',
            'scheduledFor': DateTime.now()
                .subtract(const Duration(days: 2))
                .toIso8601String(),
          },
        ],
      });
    Get.put<WorkspaceRepository>(repo);
    Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await tester.pumpWidget(const XuApp());
    await tester.tap(find.text('日历计划').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('月').first);
    await tester.pumpAndSettle();
    final source = tester.getCenter(find.text('搬迁系列').last);
    final target = tester.getCenter(find.text('${DateTime.now().day}日').first);
    await tester.dragFrom(source, target - source);
    await tester.pumpAndSettle();
    expect(find.text('移动系列 · 搬迁系列'), findsOneWidget);
    expect(find.text('保存系列安排'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(1200, 800), const Size(900, 620)]) {
    testWidgets('calendar modes and series fit ${size.width} wide window', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        Get.reset();
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final repo = _MemoryRepository()
        ..load({
          'formatVersion': 1,
          'tasks': [
            {'id': 'series', 'title': '项目系列', 'status': 'pending'},
            {
              'id': 'child',
              'title': '执行子任务',
              'parentTaskID': 'series',
              'status': 'pending',
              'scheduledFor': DateTime.now().toIso8601String(),
            },
          ],
        });
      Get.put<WorkspaceRepository>(repo);
      Get.put<WorkspaceViewModel>(WorkspaceViewModel());
      await tester.pumpWidget(const XuApp());
      await tester.tap(find.text('日历计划').first);
      await tester.pumpAndSettle();
      expect(find.text('任务系列'), findsWidgets);
      expect(find.text('项目系列'), findsWidgets);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('月').first);
      await tester.pumpAndSettle();
      expect(find.text('星期日'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('日').first);
      await tester.pumpAndSettle();
      expect(find.text('当天待定时'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}
