import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/workspace.dart';

void main() {
  test(
    'workspace rejects an unsupported backup without replacing existing data',
    () {
      final repo = WorkspaceRepository();
      repo.load({
        'formatVersion': 1,
        'tasks': [
          {'id': 'a', 'title': '保留'},
        ],
      });
      expect(
        () => repo.load({'formatVersion': 2, 'tasks': []}),
        throwsFormatException,
      );
      expect(repo.data['tasks']!.single['title'], '保留');
    },
  );
}
