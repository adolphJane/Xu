import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renaming and deleting a category update task membership', () async {
    final dir = await Directory.systemTemp.createTemp('xu-category-actions-');
    addTearDown(() async {
      Get.reset();
      await dir.delete(recursive: true);
    });
    final repo = WorkspaceRepository()
      ..file = File('${dir.path}/workspace.json');
    repo.load({
      'formatVersion': 1,
      'categories': [
        {'id': 'category', 'name': '工作', 'symbol': 'work'},
      ],
      'tasks': [
        {'id': 'task', 'title': '完成计划', 'status': 'pending', 'category': '工作'},
      ],
    });
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());

    await vm.renameCategory('工作', '项目');
    expect(vm.items('categories').single['name'], '项目');
    expect(vm.items('categories').single['symbol'], 'work');
    expect(vm.tasks.single['category'], '项目');
    await vm.deleteCategory('项目');
    expect(vm.items('categories'), isEmpty);
    expect(vm.tasks.single['category'], isNull);
  });
}
