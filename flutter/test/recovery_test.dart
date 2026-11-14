import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/workspace.dart';

void main() {
  test('recovers from backup when main JSON is corrupt', () async {
    final dir = await Directory.systemTemp.createTemp('xu-recovery-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/workspace.json');
    await file.writeAsString('{corrupt');
    await File('${file.path}.bak')
        .writeAsString('{"formatVersion":1,"tasks":[{"id":"a","title":"保留"}]}');
    final repo = WorkspaceRepository()..file = file;
    await repo.loadFromDisk();
    expect(repo.readOnly, false);
    expect(repo.data['tasks']!.single['title'], '保留');
    expect(await file.readAsString(), contains('保留'));
  });
  test('protects both corrupt files from overwrite', () async {
    final dir = await Directory.systemTemp.createTemp('xu-recovery-');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/workspace.json');
    await file.writeAsString('{corrupt');
    final repo = WorkspaceRepository()..file = file;
    await repo.loadFromDisk();
    expect(repo.readOnly, true);
    await expectLater(repo.save(), throwsStateError);
    expect(await file.readAsString(), '{corrupt');
  });
}
