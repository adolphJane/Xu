import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('task edit can be undone and redone', () async {
    final dir = await Directory.systemTemp.createTemp('xu-undo-');
    addTearDown(() async {
      Get.reset();
      await dir.delete(recursive: true);
    });
    final repo = WorkspaceRepository()
      ..file = File('${dir.path}/workspace.json');
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await vm.put('tasks', {'id': 'task', 'title': '原题', 'status': 'pending'});
    await vm.put('tasks', {'id': 'task', 'title': '新题', 'status': 'pending'});
    await vm.undo();
    expect(vm.tasks.single['title'], '原题');
    await vm.redo();
    expect(vm.tasks.single['title'], '新题');
  });
}
