import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/calendar_plan_logic.dart';
import 'package:xu/src/replan.dart';
import 'package:xu/src/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late WorkspaceRepository repository;
  late WorkspaceViewModel vm;

  setUp(() async {
    final directory = await Directory.systemTemp.createTemp('xu-closure-');
    addTearDown(() async {
      Get.reset();
      await directory.delete(recursive: true);
    });
    repository = WorkspaceRepository()
      ..file = File('${directory.path}/workspace.json')
      ..load({'formatVersion': 1});
    Get.put(repository);
    vm = Get.put(WorkspaceViewModel());
  });

  Map<String, dynamic> task(String id) => {
    'id': id,
    'title': id,
    'status': 'pending',
  };

  test(
    'writes serialize and undo only restores the records it changed',
    () async {
      await Future.wait([
        vm.put('tasks', task('a')),
        vm.put('tasks', task('b')),
      ]);
      final report = {
        'id': 'report',
        'reportDate': '2026-11-21',
        'minimumLength': 50,
        'maximumLength': 100,
        'content': List.filled(50, '完').join(),
      };
      await vm.put('reports', report);
      await vm.undo();
      final disk = WorkspaceRepository()..file = repository.file;
      await disk.loadFromDisk();
      expect(disk.data['tasks']!.map((row) => row['id']), ['a']);
      expect(disk.data['reports'], [report]);
      await vm.redo();
      await disk.loadFromDisk();
      expect(disk.data['tasks']!.map((row) => row['id']), ['a', 'b']);
      expect(disk.data['reports'], [report]);
    },
  );

  test(
    'batch today and AI replan keep the task date and execution block aligned',
    () async {
      final today = CalendarPlanLogic.day(DateTime.now());
      final tomorrow = CalendarPlanLogic.addDays(today, 1);
      final yesterday = CalendarPlanLogic.addDays(today, -1);
      await vm.put('blueprints', {'id': 'bp', 'name': '项目'});
      await vm.put('tasks', {...task('captured'), 'status': 'unscheduled'});
      await vm.put('tasks', {
        ...task('planned'),
        'blueprintID': 'bp',
        'scheduledFor': yesterday.toIso8601String(),
        'timeBlock': {
          'start': yesterday.add(const Duration(hours: 10)).toIso8601String(),
          'end': yesterday.add(const Duration(hours: 11)).toIso8601String(),
        },
      });
      vm.selectedTaskIds.addAll(['captured', 'planned']);
      await vm.applyTaskBatch('today');
      expect(vm.todayTasks, hasLength(2));
      expect(vm.tasks.first['status'], 'pending');
      expect(CalendarPlanLogic.plannedDate(vm.tasks.first), today);
      expect(CalendarPlanLogic.taskBlock(vm.tasks.last)?.start.day, today.day);

      await vm.commitReplan('bp', [
        ReplanChange('planned', tomorrow, null, '复盘调整'),
      ], dailyMinutes: 480);
      final block = CalendarPlanLogic.taskBlock(vm.tasks.last)!;
      expect(CalendarPlanLogic.day(block.start), tomorrow);
      expect(block.start.hour, 10);
      expect(block.minutes, 60);

      await vm.arrangeToday(vm.tasks.last);
      expect(
        CalendarPlanLogic.day(
          CalendarPlanLogic.taskBlock(vm.tasks.last)!.start,
        ),
        today,
      );
    },
  );

  test('stage removal preserves tasks, dependencies and milestones and can be undone', () async {
    await vm.put('blueprints', {'id': 'bp', 'name': '项目'});
    await vm.put('stages', {'id': 'stage', 'blueprintID': 'bp'});
    await vm.put('milestones', {
      'id': 'mile',
      'blueprintID': 'bp',
      'stageID': 'stage',
    });
    await vm.put('tasks', {
      ...task('a'),
      'blueprintID': 'bp',
      'stageID': 'stage',
      'milestoneID': 'mile',
    });
    await vm.put('tasks', {
      ...task('b'),
      'blueprintID': 'bp',
      'dependencyIDs': ['a'],
    });
    await vm.remove('stages', 'stage');
    expect(vm.items('stages'), isEmpty);
    expect(vm.items('milestones').single['stageID'], isNull);
    expect(vm.tasks.first['stageID'], isNull);
    expect(vm.tasks.first['milestoneID'], 'mile');
    expect(vm.tasks.last['dependencyIDs'], ['a']);
    await vm.undo();
    expect(vm.items('stages').single['id'], 'stage');
    expect(vm.tasks.first['stageID'], 'stage');
    await vm.remove('milestones', 'mile');
    expect(vm.tasks.first['milestoneID'], isNull);
    expect(vm.tasks.first['stageID'], 'stage');
  });

  test('child completion and restore change all ancestors and milestone atomically', () async {
    await vm.put('blueprints', {'id': 'bp', 'name': '项目'});
    await vm.put('milestones', {'id': 'mile', 'blueprintID': 'bp'});
    await vm.setMilestoneCompleted('mile', true);
    expect(vm.items('milestones').single['isCompleted'], true);
    for (final (id, parent) in [
      ('root', null),
      ('middle', 'root'),
      ('leaf', 'middle'),
    ]) {
      await vm.put('tasks', {
        ...task(id),
        'blueprintID': 'bp',
        'milestoneID': 'mile',
        'parentTaskID': parent,
      });
    }
    final count = vm.undoCount.value;
    await vm.setTaskStatus(vm.tasks.last, 'completed');
    expect(vm.undoCount.value, count + 1);
    expect(vm.tasks.every((row) => row['status'] == 'completed'), true);
    expect(vm.items('milestones').single['isCompleted'], true);
    await vm.setTaskStatus(vm.tasks.last, 'pending');
    expect(vm.tasks.every((row) => row['status'] == 'pending'), true);
    expect(vm.items('milestones').single['isCompleted'], false);
    await vm.undo();
    expect(vm.tasks.every((row) => row['status'] == 'completed'), true);
    expect(vm.items('milestones').single['isCompleted'], true);
  });

  test('postponement holds the original plan, moves tomorrow and stays in saved history', () async {
    final today = CalendarPlanLogic.day(DateTime.now());
    final tomorrow = CalendarPlanLogic.addDays(today, 1);
    final start = today.add(const Duration(hours: 9));
    await vm.put('tasks', {
      ...task('a'),
      'scheduledFor': start.toIso8601String(),
      'timeBlock': {
        'start': start.toIso8601String(),
        'end': start.add(const Duration(hours: 1)).toIso8601String(),
      },
    });
    await vm.postponeTask(vm.tasks.single);
    final postponed = vm.tasks.single;
    expect(postponed['status'], 'postponed');
    expect(postponed['originalScheduledFor'], start.toIso8601String());
    expect(
      CalendarPlanLogic.day(CalendarPlanLogic.taskBlock(postponed)!.start),
      tomorrow,
    );
    expect(vm.todayTasks, isEmpty);
    await vm.setTaskStatus(postponed, 'completed');
    final disk = WorkspaceRepository()..file = repository.file;
    await disk.loadFromDisk();
    final saved = disk.data['tasks']!.single;
    expect(saved['status'], 'completed');
    final event = (saved['postponements'] as List).single as Map;
    expect(event['from'], start.toIso8601String());
    expect(
      CalendarPlanLogic.day(DateTime.parse(event['to'] as String)),
      tomorrow,
    );
  });
}
