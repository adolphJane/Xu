import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/ai_blueprint.dart';
import 'package:xu/src/workspace.dart';

const sample =
    '''{"name":"发布新版","goal":"完成桌面版","startDate":"2026-11-07","dueDate":"2026-11-30","stages":[{"name":"设计","startDate":"2026-11-07","dueDate":"2026-11-10","milestone":"设计完成","tasks":[{"title":"画界面","scheduledFor":"2026-11-08T09:00:00","estimatedMinutes":60,"quadrant":"doNow"}]},{"name":"实现","startDate":"2026-11-11","dueDate":"2026-11-30","milestone":"发布","tasks":[{"title":"开发","scheduledFor":"2026-11-12T09:00:00","estimatedMinutes":90,"quadrant":"schedule"}]}]}''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('AI blueprint draft validates capacity', () {
    expect(AiBlueprintDraft.parse(sample, 120).tasks.length, 2);
    expect(() => AiBlueprintDraft.parse(sample, 30), throwsFormatException);
    expect(
      () =>
          AiBlueprintDraft.parse(sample, 120, deadline: DateTime(2026, 11, 20)),
      throwsFormatException,
    );
  });
  test('AI relationships use task IDs and can be selectively edited', () {
    final input = sample
        .replaceFirst('"title":"画界面"', '"id":"design","title":"画界面"')
        .replaceFirst(
          '"title":"开发"',
          '"id":"code","dependsOn":["design"],"title":"开发"',
        );
    final draft = AiBlueprintDraft.parse(input, 120);
    expect(draft.dependenciesFor(), {
      '0:0': <String>{},
      '1:0': {'0:0'},
    });
    expect(draft.dependenciesFor(excluded: {'0:0'}), {'1:0': <String>{}});
    expect(draft.dependenciesFor(overrides: {'1:0': {}})['1:0'], isEmpty);
    expect(
      () => draft.dependenciesFor(
        overrides: {
          '0:0': {'1:0'},
        },
      ),
      throwsFormatException,
    );
    expect(
      AiBlueprintDraft.parse(sample, 120).dependenciesFor()['1:0'],
      isEmpty,
    );
  });
  test('AI blueprint commits atomically and can be safely undone', () async {
    final dir = await Directory.systemTemp.createTemp('xu-ai-blueprint-');
    addTearDown(() async {
      Get.reset();
      await dir.delete(recursive: true);
    });
    final repo = WorkspaceRepository()
      ..file = File('${dir.path}/workspace.json');
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await vm.createAiBlueprint(
      AiBlueprintDraft.parse(sample, 120),
      chainStages: true,
    );
    expect(vm.items('blueprints'), hasLength(1));
    expect(vm.items('stages'), hasLength(2));
    expect(vm.items('milestones'), hasLength(2));
    expect(vm.tasks, hasLength(2));
    expect(vm.tasks.last['dependencyIDs'], [vm.tasks.first['id']]);
    final record = vm.items('planChanges').single;
    expect(record['kind'], 'aiBlueprint');
    expect((record['beforeSnapshot'] as Map)['tasks'], isEmpty);
    expect((record['afterSnapshot'] as Map)['tasks'], hasLength(2));
    expect(
      (record['afterSnapshot'] as Map).containsKey('planChanges'),
      isFalse,
    );
    await vm.undoPlanChange('${record['id']}');
    expect(vm.items('blueprints'), isEmpty);
    expect(vm.tasks, isEmpty);
    expect(vm.items('planChanges').single['isUndone'], true);
  });
  test('AI blueprint undo refuses later task edits', () async {
    final dir = await Directory.systemTemp.createTemp('xu-ai-blueprint-edit-');
    addTearDown(() async {
      Get.reset();
      await dir.delete(recursive: true);
    });
    final repo = WorkspaceRepository()
      ..file = File('${dir.path}/workspace.json');
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await vm.createAiBlueprint(AiBlueprintDraft.parse(sample, 120));
    final id = '${vm.items('planChanges').single['id']}';
    await vm.put('tasks', {...vm.tasks.first, 'title': '后来修改'});
    await expectLater(vm.undoPlanChange(id), throwsStateError);
    expect(vm.items('blueprints'), hasLength(1));
  });
}
