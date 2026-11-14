import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preparation task and anniversary marker commit together', () async {
    final dir = await Directory.systemTemp.createTemp('xu-anniversary-');
    addTearDown(() async {
      Get.reset();
      await dir.delete(recursive: true);
    });
    final repo = WorkspaceRepository()
      ..file = File('${dir.path}/workspace.json');
    repo.load({
      'formatVersion': 1,
      'anniversaries': [
        {
          'id': 'anniversary-1',
          'name': '生日',
          'preparationEnabled': true,
          'preparationLeadDays': 7,
        },
      ],
    });
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    final due = DateTime.now().add(const Duration(days: 30));
    await vm.createAnniversaryPreparation('anniversary-1', due);
    expect(vm.tasks, hasLength(1));
    expect(vm.tasks.single['title'], '准备生日');
    expect(
      vm.items('anniversaries').single['generatedTaskID'],
      vm.tasks.single['id'],
    );
    await expectLater(
      vm.createAnniversaryPreparation('anniversary-1', due),
      throwsStateError,
    );
    await vm.undo();
    expect(vm.tasks, isEmpty);
    expect(vm.items('anniversaries').single['generatedTaskID'], isNull);
  });
}
