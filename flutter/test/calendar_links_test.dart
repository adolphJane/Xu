import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/calendar_links.dart';
import 'package:xu/src/native.dart';
import 'package:xu/src/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('automatic calendar link creates, updates, and deletes once', () async {
    final dir = await Directory.systemTemp.createTemp('xu-calendar-link-');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
          if (call.method == 'calendarCreate' ||
              call.method == 'calendarDelete') {
            calls.add(call);
          }
          if (call.method == 'calendarCreate') return 'event-1';
          return true;
        });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null);
      await dir.delete(recursive: true);
    });
    final links = CalendarLinks(File('${dir.path}/links.json'));
    final task = <String, dynamic>{
      'id': 'task-1',
      'title': '计划会议',
      'scheduledFor': '2026-11-09T00:00:00',
      'estimatedMinutes': 45,
      'calendarAutoSync': true,
    };
    await links.sync([task]);
    await links.sync([task]);
    expect(
      calls.where((call) => call.method == 'calendarCreate'),
      hasLength(1),
    );
    await links.sync([
      {...task, 'title': '改期会议'},
    ]);
    expect(
      calls.where((call) => call.method == 'calendarCreate'),
      hasLength(2),
    );
    expect((calls[1].arguments as Map)['eventID'], 'event-1');
    await links.sync([]);
    expect(calls.last.method, 'calendarDelete');
    expect(calls.last.arguments, 'event-1');
    final saved =
        jsonDecode(await File('${dir.path}/links.json').readAsString()) as Map;
    expect(saved['links'], isEmpty);
  });

  test('failed deletion keeps the local link for retry', () async {
    final dir = await Directory.systemTemp.createTemp('xu-calendar-retry-');
    var failDelete = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
          if (call.method == 'calendarCreate') return 'event-2';
          if (call.method == 'calendarDelete' && failDelete) {
            throw PlatformException(code: 'calendar', message: '暂时不可用');
          }
          return true;
        });
    addTearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null);
      await dir.delete(recursive: true);
    });
    final links = CalendarLinks(File('${dir.path}/links.json'));
    await links.sync([
      {
        'id': 'task-2',
        'title': '事项',
        'scheduledFor': '2026-11-09',
        'calendarAutoSync': true,
      },
    ]);
    await expectLater(links.sync([]), throwsStateError);
    failDelete = false;
    await links.sync([]);
    final saved =
        jsonDecode(await File('${dir.path}/links.json').readAsString()) as Map;
    expect(saved['links'], isEmpty);
  });

  test(
    'task edits and removal trigger calendar link synchronization',
    () async {
      final dir = await Directory.systemTemp.createTemp('xu-calendar-vm-');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, (call) async {
            calls.add(call.method);
            if (call.method == 'calendarCreate') return 'event-3';
            return true;
          });
      addTearDown(() async {
        Get.reset();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, null);
        await dir.delete(recursive: true);
      });
      final repo = WorkspaceRepository()
        ..file = File('${dir.path}/workspace.json');
      repo.load({'formatVersion': 1});
      Get.put<WorkspaceRepository>(repo);
      final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
      await vm.put('tasks', {
        'id': 'task-3',
        'title': '准备发布',
        'status': 'pending',
        'scheduledFor': '2026-11-09',
        'calendarAutoSync': true,
      });
      expect(calls, contains('calendarCreate'));
      await vm.remove('tasks', 'task-3');
      expect(calls, contains('calendarDelete'));
    },
  );
}
