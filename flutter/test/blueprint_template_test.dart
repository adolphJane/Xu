import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/blueprint_templates.dart';
import 'package:xu/src/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'template creates a blueprint, stages and linked milestones atomically',
    () async {
      final dir = await Directory.systemTemp.createTemp('xu-template-');
      addTearDown(() async {
        Get.reset();
        await dir.delete(recursive: true);
      });
      final repo = WorkspaceRepository()
        ..file = File('${dir.path}/workspace.json');
      repo.load({'formatVersion': 1});
      Get.put<WorkspaceRepository>(repo);
      final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
      await vm.createBlueprintFromTemplate(
        blueprintTemplates.first,
        start: DateTime(2026, 11, 7),
      );
      expect(vm.items('blueprints'), hasLength(1));
      expect(vm.items('stages'), hasLength(3));
      expect(vm.items('milestones'), hasLength(3));
      expect(
        vm.items('milestones').first['stageID'],
        vm.items('stages').first['id'],
      );
      expect(
        blueprintProgress(
          vm.items('blueprints').single['id'] as String,
          vm.tasks,
        ),
        0,
      );
    },
  );
  test('progress excludes cancelled tasks', () {
    expect(
      blueprintProgress('b', [
        {'blueprintID': 'b', 'status': 'completed'},
        {'blueprintID': 'b', 'status': 'pending'},
        {'blueprintID': 'b', 'status': 'cancelled'},
      ]),
      0.5,
    );
  });
}
