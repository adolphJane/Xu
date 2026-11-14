import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/task_rules.dart';
import 'package:xu/src/workspace.dart';

void main() {
  final blueprint = <String, dynamic>{'id': 'b', 'status': 'active'};
  test('dependency cycles and cross-blueprint links are rejected', () {
    final first = <String, dynamic>{
      'id': 'a',
      'title': 'A',
      'blueprintID': 'b',
      'dependencyIDs': ['c'],
      'status': 'pending',
    };
    final second = <String, dynamic>{
      'id': 'c',
      'title': 'C',
      'blueprintID': 'b',
      'dependencyIDs': <String>[],
      'status': 'pending',
    };
    expect(
      TaskRules.validate(
        {
          ...second,
          'dependencyIDs': ['a'],
        },
        [first, second],
        [blueprint],
      ),
      contains('循环'),
    );
    expect(
      TaskRules.validate(
        {
          ...second,
          'blueprintID': 'other',
          'dependencyIDs': ['a'],
        },
        [first, second],
        [blueprint],
      ),
      contains('同一蓝图'),
    );
  });
  test('unfinished predecessors block execution', () {
    final predecessor = <String, dynamic>{
      'id': 'a',
      'title': 'A',
      'blueprintID': 'b',
      'status': 'pending',
    };
    final task = <String, dynamic>{
      'id': 'c',
      'title': 'C',
      'blueprintID': 'b',
      'dependencyIDs': ['a'],
      'status': 'pending',
    };
    expect(
      TaskRules.blockingReason(task, [predecessor, task], [blueprint]),
      contains('等待'),
    );
  });
  test('completed parent requires completed children', () {
    final parent = <String, dynamic>{
      'id': 'parent',
      'title': '父',
      'status': 'completed',
    };
    final child = <String, dynamic>{
      'id': 'child',
      'title': '子',
      'parentTaskID': 'parent',
      'status': 'pending',
    };
    expect(TaskRules.validate(parent, [parent, child], []), contains('子任务'));
  });
  test('merge prefers local record with the same ID', () {
    final result = mergeSnapshots(
      {
        'formatVersion': 1,
        'tasks': [
          {'id': 'a', 'title': '本机'},
        ],
      },
      {
        'formatVersion': 1,
        'tasks': [
          {'id': 'a', 'title': '文件夹'},
          {'id': 'b', 'title': '新增'},
        ],
      },
      ['tasks'],
    );
    expect((result['tasks'] as List).length, 2);
    expect(
      (result['tasks'] as List).firstWhere((e) => e['id'] == 'a')['title'],
      '本机',
    );
  });
}
