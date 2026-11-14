import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/replan.dart';
import 'package:xu/src/workspace.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

void main() {
  test('proposal rejects unknown task IDs and malformed dates', () {
    expect(
      () => ReplanProposal.parse(
        '{"summary":"","changes":[{"taskID":"other","newScheduledFor":"2026-11-08"}]}',
        {'known'},
      ),
      throwsFormatException,
    );
    expect(
      () => ReplanProposal.parse(
        '{"summary":"","changes":[{"taskID":"known","newScheduledFor":"bad"}]}',
        {'known'},
      ),
      throwsFormatException,
    );
  });
  test(
    'replan preserves original dates, locked tasks and dependency order',
    () {
      final original = [
        <String, dynamic>{
          'id': 'a',
          'blueprintID': 'b',
          'title': '先做',
          'status': 'pending',
          'scheduledFor': '2026-11-07T09:00:00.000',
          'dueDate': '2026-11-10T10:00:00.000',
        },
        <String, dynamic>{
          'id': 'c',
          'blueprintID': 'b',
          'title': '后做',
          'status': 'pending',
          'scheduledFor': '2026-11-08T09:00:00.000',
          'dueDate': '2026-11-09T10:00:00.000',
          'dependencyIDs': ['a'],
          'estimatedMinutes': 60,
        },
        <String, dynamic>{
          'id': 'locked',
          'blueprintID': 'b',
          'title': '锁定',
          'status': 'pending',
          'isPlanLocked': true,
          'scheduledFor': '2026-11-07T09:00:00.000',
        },
      ];
      final result = applyReplanToTasks(original, 'b', [
        ReplanChange('c', DateTime(2026, 11, 8), DateTime(2026, 11, 8), ''),
        ReplanChange('locked', DateTime(2026, 11, 20), null, ''),
      ]);
      expect(result[1]['originalScheduledFor'], original[1]['scheduledFor']);
      expect(
        DateTime.parse(
          result[1]['scheduledFor'] as String,
        ).isBefore(DateTime.parse(original[0]['dueDate'] as String)),
        false,
      );
      expect(result[2]['scheduledFor'], original[2]['scheduledFor']);
      expect(original[1]['originalScheduledFor'], isNull);
    },
  );
  test('history captures applied dates and reasons', () {
    final before = [
      {
        'id': 'a',
        'title': '准备发布',
        'scheduledFor': '2026-11-07T09:00:00',
        'dueDate': null,
      },
    ];
    final after = [
      {
        'id': 'a',
        'title': '准备发布',
        'scheduledFor': '2026-11-08T09:00:00',
        'dueDate': '2026-11-08T11:00:00',
      },
    ];
    final entries = replanHistoryEntries(before, after, [
      ReplanChange(
        'a',
        DateTime(2026, 11, 8, 9),
        DateTime(2026, 11, 8, 11),
        '等待评审',
      ),
    ]);
    expect(entries, hasLength(1));
    expect(entries.single['beforeScheduledFor'], '2026-11-07T09:00:00');
    expect(entries.single['afterDueDate'], '2026-11-08T11:00:00');
    expect(entries.single['reason'], '等待评审');
  });
  test('committed replan stores history with final dates', () async {
    final repo = _MemoryRepository();
    repo.load({
      'formatVersion': 1,
      'blueprints': [
        {'id': 'b', 'name': '项目'},
      ],
      'tasks': [
        {
          'id': 'a',
          'title': '准备发布',
          'blueprintID': 'b',
          'status': 'pending',
          'scheduledFor': '2026-11-07T09:00:00',
          'dependencyIDs': <String>[],
        },
      ],
    });
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    addTearDown(Get.reset);
    await vm.commitReplan('b', [
      ReplanChange('a', DateTime(2026, 11, 8, 9), null, '等待评审'),
    ], dailyMinutes: 240);
    final record = vm.items('planChanges').single;
    expect(record['blueprintID'], 'b');
    expect((record['beforeSnapshot'] as Map)['tasks'], hasLength(1));
    expect((record['afterSnapshot'] as Map)['tasks'], hasLength(1));
    expect((record['entries'] as List).single['reason'], '等待评审');
    expect(
      (record['entries'] as List).single['afterScheduledFor'],
      vm.tasks.single['scheduledFor'],
    );
    await vm.undoPlanChange('${record['id']}');
    expect(vm.tasks.single['scheduledFor'], '2026-11-07T09:00:00');
    expect(vm.items('planChanges').single['isUndone'], true);
    await expectLater(vm.undoPlanChange('${record['id']}'), throwsStateError);
  });
  test('capacity counts existing tasks on adjusted dependency day', () {
    final before = [
      <String, dynamic>{
        'id': 'pre',
        'blueprintID': 'b',
        'status': 'pending',
        'scheduledFor': '2026-11-07T09:00:00',
        'dueDate': '2026-11-09T09:00:00',
        'estimatedMinutes': 30,
      },
      <String, dynamic>{
        'id': 'move',
        'blueprintID': 'b',
        'status': 'pending',
        'scheduledFor': '2026-11-07T09:00:00',
        'dependencyIDs': ['pre'],
        'estimatedMinutes': 90,
      },
      <String, dynamic>{
        'id': 'existing',
        'blueprintID': 'other',
        'status': 'pending',
        'scheduledFor': '2026-11-09T11:00:00',
        'estimatedMinutes': 60,
      },
      <String, dynamic>{
        'id': 'done',
        'status': 'completed',
        'scheduledFor': '2026-11-09T12:00:00',
        'estimatedMinutes': 500,
      },
    ];
    final planned = applyReplanToTasks(before, 'b', [
      ReplanChange('move', DateTime(2026, 11, 8), null, ''),
    ]);
    final overloads = replanCapacityOverloads(planned, {'move'}, 120);
    expect(planned[1]['scheduledFor'], startsWith('2026-11-09'));
    expect(overloads.single.plannedMinutes, 150);
    expect(capacityOverloadMessage(overloads), contains('2026-11-09'));
    expect(replanCapacityOverloads(planned, {'move'}, 150), isEmpty);
  });
  test('undo refuses to overwrite an edited task', () async {
    final repo = _MemoryRepository();
    repo.load({
      'formatVersion': 1,
      'blueprints': [
        {'id': 'b', 'name': '项目'},
      ],
      'tasks': [
        {
          'id': 'a',
          'title': '原题',
          'blueprintID': 'b',
          'status': 'pending',
          'scheduledFor': '2026-11-07T09:00:00',
          'dependencyIDs': <String>[],
        },
      ],
    });
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    addTearDown(Get.reset);
    await vm.commitReplan('b', [
      ReplanChange('a', DateTime(2026, 11, 8, 9), null, ''),
    ], dailyMinutes: 240);
    final id = '${vm.items('planChanges').single['id']}';
    await vm.put('tasks', {...vm.tasks.single, 'title': '后来编辑'});
    await expectLater(vm.undoPlanChange(id), throwsStateError);
    expect(vm.tasks.single['title'], '后来编辑');
    expect(vm.items('planChanges').single['isUndone'], isNot(true));
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
