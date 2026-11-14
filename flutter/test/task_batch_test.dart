import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('batch completion is atomic and undoable', () async {
    final dir = await Directory.systemTemp.createTemp('xu-batch-');
    addTearDown(() async {
      Get.reset();
      await dir.delete(recursive: true);
    });
    final repo = WorkspaceRepository()
      ..file = File('${dir.path}/workspace.json');
    repo.load({
      'formatVersion': 1,
      'tasks': [
        {'id': 'a', 'title': '第一项', 'status': 'pending'},
        {'id': 'b', 'title': '第二项', 'status': 'pending'},
      ],
    });
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    vm.selectedTaskIds.addAll(['a', 'b']);
    await vm.applyTaskBatch('complete');
    expect(vm.tasks.every((task) => task['status'] == 'completed'), isTrue);
    await vm.undo();
    expect(vm.tasks.every((task) => task['status'] == 'pending'), isTrue);
  });

  test(
    'batch delete rejects remaining dependent task without deleting anything',
    () async {
      final dir = await Directory.systemTemp.createTemp('xu-batch-dependency-');
      addTearDown(() async {
        Get.reset();
        await dir.delete(recursive: true);
      });
      final repo = WorkspaceRepository()
        ..file = File('${dir.path}/workspace.json');
      repo.load({
        'formatVersion': 1,
        'tasks': [
          {'id': 'a', 'title': '前置', 'status': 'pending'},
          {
            'id': 'b',
            'title': '后续',
            'status': 'pending',
            'dependencyIDs': ['a'],
          },
        ],
      });
      Get.put<WorkspaceRepository>(repo);
      final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
      vm.selectedTaskIds.add('a');
      await expectLater(vm.applyTaskBatch('delete'), throwsStateError);
      expect(vm.tasks, hasLength(2));
    },
  );
}
