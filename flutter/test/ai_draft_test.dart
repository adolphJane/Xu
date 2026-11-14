import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/ai.dart';

void main() {
  test('draft parser accepts fenced JSON and skips blank subtasks', () {
    final draft = TaskDraft.parse(
      '```json\n{"title":"项目计划","notes":"先整理","subtasks":["列提纲"," ","确认范围"]}\n```',
    );
    expect(draft.title, '项目计划');
    expect(draft.subtasks, ['列提纲', '确认范围']);
  });
  test(
    'image request rejects an empty image before contacting the API',
    () async {
      await expectLater(
        AiService.completeWithImage('描述', Uint8List(0), 'image/png'),
        throwsFormatException,
      );
    },
  );
  test('draft parser rejects a missing title', () {
    expect(
      () => TaskDraft.parse('{"title":" ","subtasks":[]}'),
      throwsFormatException,
    );
  });
}
