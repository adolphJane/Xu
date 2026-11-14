import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/workflow.dart';

void main() {
  test('saved node position overrides automatic layout', () {
    final positions = automaticPositions([
      {'id': 'a', 'workflowX': 420, 'workflowY': 180},
    ]);
    expect(positions['a']!.dx, 420);
    expect(positions['a']!.dy, 180);
  });
  test('dependency and hierarchy advance nodes to later columns', () {
    final positions = automaticPositions([
      {'id': 'a', 'title': '开始'},
      {'id': 'b', 'title': '并行'},
      {
        'id': 'c',
        'title': '汇合',
        'dependencyIDs': ['a', 'b'],
      },
      {'id': 'd', 'title': '子任务', 'parentTaskID': 'c'},
    ]);
    expect(positions['a']!.dx, positions['b']!.dx);
    expect(positions['c']!.dx, greaterThan(positions['a']!.dx));
    expect(positions['d']!.dx, greaterThan(positions['c']!.dx));
  });
}
