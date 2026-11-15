import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'native.dart';

/// Device-local EventKit identifiers must not be copied to another Mac.
class CalendarLinks {
  CalendarLinks(this.file);

  final File file;

  Future<void> sync(List<Map<String, dynamic>> tasks) async {
    final links = await _read();
    final enabled = <String, Map<String, dynamic>>{
      for (final task in tasks)
        if (task['calendarAutoSync'] == true &&
            task['status'] != 'unscheduled' &&
            DateTime.tryParse('${task['scheduledFor']}') != null)
          '${task['id']}': task,
    };
    final failures = <String>[];

    for (final id in links.keys.toList()) {
      if (enabled.containsKey(id)) continue;
      try {
        await NativeBridge.calendarDelete('${links[id]!['eventID']}');
        links.remove(id);
        await _write(links);
      } catch (error) {
        failures.add('删除日历事件失败：$error');
      }
    }

    for (final entry in enabled.entries) {
      final task = entry.value;
      final scheduled = DateTime.parse('${task['scheduledFor']}');
      final block = task['timeBlock'];
      final blockStart = block is Map
          ? DateTime.tryParse('${block['start']}')
          : null;
      final blockEnd = block is Map
          ? DateTime.tryParse('${block['end']}')
          : null;
      final start =
          blockStart ??
          DateTime(scheduled.year, scheduled.month, scheduled.day, 9);
      final minutes =
          blockStart != null && blockEnd != null && blockEnd.isAfter(blockStart)
          ? blockEnd.difference(blockStart).inMinutes.clamp(1, 1440)
          : ((task['estimatedMinutes'] as num?)?.toInt() ?? 30).clamp(1, 1440);
      final title = '${task['title'] ?? ''}'.trim();
      if (title.isEmpty) {
        failures.add('存在无标题的日历任务');
        continue;
      }
      final fingerprint = jsonEncode([title, start.toIso8601String(), minutes]);
      final prior = links[entry.key];
      if (prior?['fingerprint'] == fingerprint) continue;
      try {
        String? eventId;
        try {
          eventId = await NativeBridge.calendarCreate(
            title,
            start,
            minutes,
            eventId: prior?['eventID'] ?? task['calendarEventID'] as String?,
          );
        } on PlatformException catch (error) {
          if (error.code != 'calendarMissing') rethrow;
          eventId = await NativeBridge.calendarCreate(title, start, minutes);
        }
        if (eventId == null || eventId.isEmpty) {
          throw StateError('系统日历没有返回事件 ID');
        }
        links[entry.key] = {'eventID': eventId, 'fingerprint': fingerprint};
        await _write(links);
      } catch (error) {
        failures.add('“$title”同步失败：$error');
      }
    }
    if (failures.isNotEmpty) throw StateError(failures.join('；'));
  }

  Future<Map<String, Map<String, String>>> _read() async {
    if (!await file.exists()) return {};
    final raw = jsonDecode(await file.readAsString());
    if (raw is! Map || raw['formatVersion'] != 1 || raw['links'] is! Map) {
      throw const FormatException('日历关联文件无效');
    }
    return {
      for (final entry in (raw['links'] as Map).entries)
        '${entry.key}': Map<String, String>.from(entry.value as Map),
    };
  }

  Future<void> _write(Map<String, Map<String, String>> links) async {
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(
      jsonEncode({'formatVersion': 1, 'links': links}),
      flush: true,
    );
    await temp.rename(file.path);
  }
}
