import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/blueprint_transfer.dart';

void main() {
  test('import remaps blueprint, stage, task and dependency IDs', () {
    final source = {
      'formatVersion': 1,
      'blueprints': [
        {'id': 'b', 'name': '蓝图'},
      ],
      'stages': [
        {'id': 's', 'blueprintID': 'b'},
      ],
      'milestones': <Map<String, dynamic>>[],
      'tasks': [
        {
          'id': 'a',
          'title': '起点',
          'status': 'pending',
          'blueprintID': 'b',
          'stageID': 's',
        },
        {
          'id': 'c',
          'title': '终点',
          'status': 'pending',
          'blueprintID': 'b',
          'stageID': 's',
          'dependencyIDs': ['a'],
        },
      ],
    };
    final package = BlueprintTransfer.export(source, 'b');
    var counter = 0;
    final result = BlueprintTransfer.import(
      source,
      package,
      () => 'new-${counter++}',
    );
    final imported = (result['tasks'] as List)
        .where((e) => '${e['id']}'.startsWith('new-'))
        .toList();
    expect(imported.length, 2);
    expect(imported.last['dependencyIDs'], [imported.first['id']]);
    expect(imported.first['stageID'], (result['stages'] as List).last['id']);
    expect(
      imported.first['blueprintID'],
      (result['blueprints'] as List).last['id'],
    );
  });
  test('invalid dependency aborts import', () {
    final package = {
      'formatVersion': 1,
      'blueprint': {'id': 'b'},
      'stages': <Map<String, dynamic>>[],
      'milestones': <Map<String, dynamic>>[],
      'tasks': [
        {
          'id': 'a',
          'blueprintID': 'b',
          'dependencyIDs': ['missing'],
        },
      ],
    };
    expect(
      () => BlueprintTransfer.import(
        {
          'formatVersion': 1,
          'blueprints': [],
          'stages': [],
          'milestones': [],
          'tasks': [],
        },
        package,
        () => 'new',
      ),
      throwsFormatException,
    );
  });
}
