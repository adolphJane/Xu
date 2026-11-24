import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/blueprint_graph.dart';
import 'package:xu/src/blueprint_workbench.dart';
import 'package:xu/src/native.dart';
import 'package:xu/src/workspace.dart';

const blueprint = <String, dynamic>{
  'id': 'b',
  'name': '发布新版',
  'status': 'active',
};
const stages = [
  {'id': 'stage', 'name': '发布阶段', 'blueprintID': 'b'},
];
Map<String, dynamic> row(
  String id, {
  String status = 'pending',
  int? minutes,
  List<String> dependencies = const [],
  String? parent,
}) => {
  'id': id,
  'title': id,
  'blueprintID': 'b',
  'status': status,
  'dependencyIDs': dependencies,
  'estimatedMinutes': ?minutes,
  'parentTaskID': ?parent,
};

class MemoryWorkspace extends WorkspaceRepository {
  @override
  Future<void> commit(Map<String, List<Map<String, dynamic>>> next) async {
    data
      ..clear()
      ..addAll(next);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<WorkspaceViewModel> openWorkspace(
    List<Map<String, dynamic>> tasks, {
    bool memory = false,
  }) async {
    final dir = await Directory.systemTemp.createTemp('xu-blueprint-');
    addTearDown(() async {
      Get.reset();
      await dir.delete(recursive: true);
    });
    final repo = (memory ? MemoryWorkspace() : WorkspaceRepository())
      ..file = File('${dir.path}/workspace.json')
      ..load({
        'formatVersion': 1,
        'blueprints': [blueprint],
        'stages': stages,
        'tasks': tasks,
      });
    Get.put<WorkspaceRepository>(repo);
    return Get.put(WorkspaceViewModel());
  }

  test('parallel readiness, critical chain and mixed hierarchy cycle', () {
    final graph = BlueprintGraph(blueprint, [
      row('准备', status: 'completed'),
      row('开发', minutes: 240, dependencies: ['准备']),
      row('数据', minutes: 120, dependencies: ['准备']),
      row('联调', minutes: 60, dependencies: ['开发', '数据']),
    ]);
    expect(graph.readyIds, ['开发', '数据']);
    expect(graph.parallelWith('开发'), ['数据']);
    expect(graph.forecast(['联调']).minutes, 300);
    expect(graph.forecast(['联调']).criticalIds, {'开发', '联调'});
    expect(graph.startReason('联调'), contains('开发'));
    final cyclic = BlueprintGraph(blueprint, [
      row('父'),
      row('子', parent: '父', dependencies: ['父']),
      row('独立'),
    ]);
    expect(cyclic.issues.keys.toSet(), {'父', '子'});
    expect(cyclic.readyIds, ['独立']);
  });

  test('one transaction starts both branches and undo restores both', () async {
    final vm = await openWorkspace([
      row('A', status: 'completed'),
      row('B', dependencies: ['A']),
      row('C', dependencies: ['A']),
      row('D', dependencies: ['B', 'C']),
    ]);
    await expectLater(
      vm.startBlueprintTasks('b', {'B', 'D'}),
      throwsStateError,
    );
    expect(vm.tasks.where((task) => task['status'] == 'inProgress'), isEmpty);
    await vm.startBlueprintTasks('b', {'B', 'C'});
    final started = vm.tasks
        .where((task) => task['status'] == 'inProgress')
        .toList();
    expect(started, hasLength(2));
    expect(started.map((row) => row['startedAt']).toSet(), hasLength(1));
    expect(vm.todayTasks, hasLength(2));
    await vm.setTaskStatus(started.first, 'completed');
    expect(vm.blueprintGraph('b').startReason('D'), contains('C'));
    await vm.undo();
    await vm.undo();
    expect(vm.blueprintGraph('b').readyIds, ['B', 'C']);
  });

  test(
    'preview edits reject cycles and persist inserted stages atomically',
    () async {
      final vm = await openWorkspace([
        row('A'),
        row('Z', dependencies: ['A']),
      ]);
      final before = vm.tasks.last;
      await expectLater(
        vm.applyBlueprintTaskEdits('b', [
          (
            before: vm.tasks.first,
            after: {
              ...vm.tasks.first,
              'dependencyIDs': ['Z'],
            },
          ),
        ]),
        throwsStateError,
      );
      await vm.applyBlueprintTaskEdits('b', [
        (before: null, after: row('B', dependencies: ['A'])),
        (
          before: before,
          after: {
            ...before,
            'dependencyIDs': ['B'],
          },
        ),
      ]);
      expect(vm.blueprintGraph('b').upstream('Z'), {'A', 'B'});
      await vm.undo();
      expect(vm.blueprintGraph('b').upstream('Z'), {'A'});
    },
  );

  test(
    'milestone acceptance, baseline, delay history and template preserve scope',
    () async {
      final date = DateTime(2026, 11, 23);
      final vm = await openWorkspace([
        {...row('A'), 'scheduledFor': date.toIso8601String()},
        {
          ...row('B', dependencies: ['A']),
          'scheduledFor': date.toIso8601String(),
        },
      ]);
      await vm.saveBlueprintBaseline('b');
      final preview = vm.previewBlueprintMove('b', 'A', DateTime(2026, 11, 24));
      expect(preview.affected, {'B'});
      expect(preview.moves, hasLength(2));
      await vm.commitBlueprintMove('b', preview, {'A'}, '调整发布前置');
      expect(vm.tasks.last['scheduledFor'], date.toIso8601String());
      expect(vm.items('planChanges').single['kind'], 'manualReplan');
      await vm.put('milestones', {'id': 'm', 'name': '验收', 'blueprintID': 'b'});
      final milestone = vm.items('milestones').single;
      await vm.saveMilestoneAcceptance(
        milestone,
        [
          {'id': 'check', 'title': '核对', 'done': true},
        ],
        [],
        accept: true,
      );
      expect(vm.items('milestones').single['isCompleted'], true);
      await vm.saveBlueprintTemplate('b', '发布模板');
      await vm.createFromSavedBlueprintTemplate(
        vm.items('blueprintTemplates').single['id'] as String,
        DateTime(2027, 1, 1),
      );
      final copy = vm.items('blueprints').last;
      final copiedTasks = vm.tasks
          .where((task) => task['blueprintID'] == copy['id'])
          .toList();
      expect(copiedTasks.last['dependencyIDs'], [copiedTasks.first['id']]);
      expect(copiedTasks.first['id'], isNot('A'));
      expect(vm.items('milestones').last['isCompleted'], false);
      expect(
        (vm.items('milestones').last['acceptanceChecks'] as List)
            .single['done'],
        false,
      );
    },
  );

  testWidgets(
    'workbench previews parallel edits and starts selected tasks on macOS-sized layout',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, (_) async => null);
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, null),
      );
      final vm = (await tester.runAsync(
        () => openWorkspace([row('初始任务')], memory: true),
      ))!;
      await tester.pumpWidget(
        GetMaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => BlueprintWorkbench(
                    id: 'b',
                    vm: vm,
                    edit: (_, _, {existing, defaults}) async {},
                    replan: (_, _) async {},
                  ),
                ),
                child: const Text('打开蓝图'),
              ),
            ),
          ),
        ),
      );
      Future<void> tap(String text) async {
        final target = find.text(text).last;
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      await tap('打开蓝图');
      await tap('执行列表');
      await tap('初始任务');
      await tap('关系编排');
      await tap('添加并行分支');
      await tester.enterText(
        find.widgetWithText(TextFormField, '一行一项任务'),
        '分支一\n分支二',
      );
      await tester.pumpAndSettle();
      await tap('预览关系');
      expect(find.text('关系变更预览'), findsOneWidget);
      await tap('确认保存');
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 100 && vm.tasks.length < 3; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pump(const Duration(milliseconds: 500));
      await tester.pumpAndSettle();
      expect(
        vm.tasks,
        hasLength(3),
        reason: tester
            .widgetList<Text>(
              find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(Text),
              ),
            )
            .map((text) => text.data)
            .join(' | '),
      );
      await tap('工作流');
      await tap('自动排版');
      expect(
        vm.tasks.every(
          (row) => row['workflowX'] is num && row['workflowY'] is num,
        ),
        isTrue,
      );
      await tap('连接后继');
      await tap('从列表选择后继');
      await tap('分支二');
      expect(find.text('新增 初始任务 → 分支二'), findsOneWidget);
      await tap('确认保存');
      await tester.pumpAndSettle();
      final target = vm.tasks.firstWhere((row) => row['title'] == '分支二');
      expect(target['dependencyIDs'], ['初始任务']);
      await tap('定位事项');
      await tap('初始任务');
      await tap('连接后继');
      await tap('从列表选择后继');
      await tap('分支二');
      expect(find.text('移除 初始任务 → 分支二'), findsOneWidget);
      await tap('确认保存');
      expect(
        vm.tasks.firstWhere((row) => row['title'] == '分支二')['dependencyIDs'],
        isEmpty,
      );
      await tap('全选可开始 · 3');
      await tap('开始选中 · 3');
      expect(
        vm.tasks.where((task) => task['status'] == 'inProgress'),
        hasLength(3),
      );
      tester.view.physicalSize = const Size(900, 620);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ChoiceChip, '详情'));
      await tester.pumpAndSettle();
      expect(find.text('蓝图概览'), findsOneWidget);
      await tap('蓝图概览');
      expect(find.text('蓝图参考图'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
