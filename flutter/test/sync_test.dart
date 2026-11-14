import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/workspace.dart';

void main() {
  test(
    'folder sync pulls remote-only changes and reports divergent edits',
    () async {
      final root = await Directory.systemTemp.createTemp('xu-sync-test-');
      addTearDown(() => root.delete(recursive: true));
      final folder = Directory('${root.path}/shared')..createSync();
      WorkspaceRepository makeRepo(String name, String title) {
        final repo = WorkspaceRepository()
          ..file = File('${root.path}/$name.json');
        repo.load({
          'formatVersion': 1,
          'tasks': [
            {'id': 'a', 'title': title},
          ],
        });
        return repo;
      }

      final first = makeRepo('first', '原始');
      final second = makeRepo('second', '原始');
      await first.syncFolder(folder.path);
      await second.syncFolder(folder.path);
      first.data['tasks']!.first['title'] = '第一台修改';
      await first.save();
      expect(await first.syncFolder(folder.path), isNull);
      expect(await second.syncFolder(folder.path), isNull);
      expect(second.data['tasks']!.first['title'], '第一台修改');
      first.data['tasks']!.first['title'] = '第一台再次修改';
      await first.save();
      second.data['tasks']!.first['title'] = '第二台修改';
      await second.save();
      await first.syncFolder(folder.path);
      expect(await second.syncFolder(folder.path), isA<SyncConflict>());
      final envelope = jsonDecode(
        File('${folder.path}/xu-workspace-v1.json').readAsStringSync(),
      ) as Map;
      expect(envelope['revision'], 3);
    },
  );
  test('three-way merge preserves deletions and independent additions', () {
    final base = <String, dynamic>{
      'formatVersion': 1,
      'tasks': [
        {'id': 'gone', 'title': '待删除'},
        {'id': 'keep', 'title': '原题'},
      ],
    };
    final local = <String, dynamic>{
      'formatVersion': 1,
      'tasks': [
        {'id': 'keep', 'title': '原题'},
        {'id': 'new', 'title': '新增'},
      ],
    };
    final remote = <String, dynamic>{
      'formatVersion': 1,
      'tasks': [
        {'id': 'gone', 'title': '待删除'},
        {'id': 'keep', 'title': '远端修改'},
      ],
    };
    final merged = mergeSnapshotsWithBase(base, local, remote, ['tasks']);
    final tasks = merged['tasks'] as List;
    expect(tasks.map((row) => row['id']), containsAll(['keep', 'new']));
    expect(tasks.map((row) => row['id']), isNot(contains('gone')));
    expect(tasks.firstWhere((row) => row['id'] == 'keep')['title'], '远端修改');
  });

  test('local record wins an edit versus deletion conflict', () {
    final base = <String, dynamic>{
      'formatVersion': 1,
      'tasks': [
        {'id': 'a', 'title': '原题'},
      ],
    };
    final local = <String, dynamic>{
      'formatVersion': 1,
      'tasks': [
        {'id': 'a', 'title': '本机修改'},
      ],
    };
    final remote = <String, dynamic>{'formatVersion': 1, 'tasks': []};
    final merged = mergeSnapshotsWithBase(base, local, remote, ['tasks']);
    expect((merged['tasks'] as List).single['title'], '本机修改');
  });
  test('folder sync merges a deletion without resurrecting it', () async {
    final root = await Directory.systemTemp.createTemp('xu-sync-delete-');
    addTearDown(() => root.delete(recursive: true));
    final folder = Directory('${root.path}/shared')..createSync();
    WorkspaceRepository repo(String name) {
      final value = WorkspaceRepository()
        ..file = File('${root.path}/$name.json');
      value.load({
        'formatVersion': 1,
        'tasks': [
          {'id': 'a', 'title': '删掉'},
          {'id': 'b', 'title': '保留'},
        ],
      });
      return value;
    }

    final first = repo('first'), second = repo('second');
    await first.syncFolder(folder.path);
    await second.syncFolder(folder.path);
    first.data['tasks']!.removeWhere((row) => row['id'] == 'a');
    await first.save();
    second.data['tasks']!.firstWhere((row) => row['id'] == 'b')['title'] = '修改';
    await second.save();
    await first.syncFolder(folder.path);
    expect(await second.syncFolder(folder.path), isA<SyncConflict>());
    await second.syncFolder(folder.path, choice: SyncChoice.merge);
    expect(second.data['tasks']!.map((row) => row['id']), ['b']);
    expect(second.data['tasks']!.single['title'], '修改');
  });
  test('unchanged periodic sync preserves task undo history', () async {
    final root = await Directory.systemTemp.createTemp('xu-sync-undo-');
    addTearDown(() async {
      Get.reset();
      await root.delete(recursive: true);
    });
    final folder = Directory('${root.path}/shared')..createSync();
    final repo = WorkspaceRepository()
      ..file = File('${root.path}/workspace.json');
    repo.load({'formatVersion': 1});
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await vm.put('tasks', {'id': 'a', 'title': '先做', 'status': 'pending'});
    await vm.syncFolder(folder.path);
    expect(vm.undoCount.value, 1);
    await vm.syncFolder(folder.path);
    expect(vm.undoCount.value, 1);
  });
}
