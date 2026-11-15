import 'dart:convert';
import 'dart:io';
import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'task_rules.dart';
import 'native.dart';
import 'blueprint_transfer.dart';
import 'blueprint_templates.dart';
import 'replan.dart';
import 'report_rules.dart';
import 'weekly_review_rules.dart';
import 'ai_blueprint.dart';
import 'calendar_links.dart';

String newId() => '${DateTime.now().microsecondsSinceEpoch}-${_counter++}';
int _counter = 0;

class WorkspaceRepository extends BaseRepository {
  late final File file;
  String? loadError;
  bool readOnly = false;
  final data = <String, List<Map<String, dynamic>>>{};
  final sections = const [
    'tasks',
    'blueprints',
    'stages',
    'milestones',
    'anniversaries',
    'reports',
    'weeklyReviews',
    'planChanges',
    'settings',
    'categories',
  ];
  Future<void> init() async {
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/flutter-v1',
    );
    await dir.create(recursive: true);
    file = File('${dir.path}/workspace.json');
    await loadFromDisk();
  }

  Future<void> loadFromDisk() async {
    if (await file.exists()) {
      try {
        load(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      } catch (error) {
        final backup = File('${file.path}.bak');
        try {
          load(jsonDecode(await backup.readAsString()) as Map<String, dynamic>);
          await backup.copy(file.path);
          loadError = '主数据文件损坏，已从最近一次备份恢复。';
        } catch (_) {
          readOnly = true;
          loadError = '数据文件及备份无法读取；已进入只读模式，原文件不会被覆盖。';
          debugPrint('Workspace read failed: $error');
        }
      }
    }
    for (final section in sections) {
      data.putIfAbsent(section, () => []);
    }
  }

  void load(Map<String, dynamic> snapshot) {
    if (snapshot['formatVersion'] != 1) {
      throw const FormatException('Unsupported workspace format');
    }
    final parsed = <String, List<Map<String, dynamic>>>{};
    for (final section in sections) {
      final raw = snapshot[section];
      if (raw != null && raw is! List) throw FormatException('$section 不是列表');
      parsed[section] = raw is List
          ? raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
          : [];
    }
    data
      ..clear()
      ..addAll(parsed);
  }

  Map<String, dynamic> snapshot() => {'formatVersion': 1, ...data};
  Future<void> commit(Map<String, List<Map<String, dynamic>>> next) async {
    if (readOnly) throw StateError(loadError ?? '数据处于只读模式');
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(
      jsonEncode({'formatVersion': 1, ...next}),
      flush: true,
    );
    if (await file.exists()) await file.copy('${file.path}.bak');
    await tmp.rename(file.path);
    data
      ..clear()
      ..addAll(next);
  }

  Future<void> save() async {
    await commit({for (final entry in data.entries) entry.key: entry.value});
  }

  Future<void> exportTo(String path) async {
    await File(path)
        .writeAsString(const JsonEncoder.withIndent('  ').convert(snapshot()));
  }

  Future<void> importFrom(String path) async {
    final parsed =
        jsonDecode(await File(path).readAsString()) as Map<String, dynamic>;
    final previous = snapshot();
    load(parsed);
    try {
      await save();
    } catch (_) {
      load(previous);
      rethrow;
    }
  }

  Future<SyncConflict?> syncFolder(String path, {SyncChoice? choice}) async {
    final folder = Directory(path);
    if (!await folder.exists()) throw const FileSystemException('同步文件夹不存在');
    final remote = File('${folder.path}/xu-workspace-v1.json');
    final stateFile = File('${file.path}.sync');
    final state = await stateFile.exists()
        ? Map<String, dynamic>.from(
            jsonDecode(await stateFile.readAsString()) as Map,
          )
        : <String, dynamic>{};
    Future<void> record(String checksum, Map<String, dynamic> common) async {
      state[folder.absolute.path] = {'checksum': checksum, 'snapshot': common};
      await stateFile.writeAsString(jsonEncode(state), flush: true);
    }

    final local = snapshot();
    final localHash = sha256.convert(utf8.encode(jsonEncode(local))).toString();
    if (!await remote.exists()) {
      await remote.writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'revision': 1,
          'snapshot': local,
          'checksum': localHash,
        }),
        flush: true,
      );
      await record(localHash, local);
      return null;
    }
    final envelope =
        jsonDecode(await remote.readAsString()) as Map<String, dynamic>;
    final remoteSnapshot = Map<String, dynamic>.from(
      envelope['snapshot'] as Map,
    );
    final remoteHash = sha256
        .convert(utf8.encode(jsonEncode(remoteSnapshot)))
        .toString();
    if (envelope['formatVersion'] != 1 || envelope['checksum'] != remoteHash) {
      throw const FormatException('同步文件校验失败');
    }
    if (remoteHash == localHash) {
      await record(localHash, local);
      return null;
    }
    final savedBase = state[folder.absolute.path];
    final baseHash = savedBase is Map ? savedBase['checksum'] : savedBase;
    final baseSnapshot = savedBase is Map && savedBase['snapshot'] is Map
        ? Map<String, dynamic>.from(savedBase['snapshot'] as Map)
        : null;
    if (choice == null && baseHash == localHash) choice = SyncChoice.useRemote;
    if (choice == null && baseHash == remoteHash) choice = SyncChoice.keepLocal;
    if (choice == null) return SyncConflict(remoteSnapshot);
    if (choice == SyncChoice.useRemote) {
      await importSnapshot(remoteSnapshot);
      await record(remoteHash, remoteSnapshot);
    } else {
      if (choice == SyncChoice.merge && baseSnapshot == null) {
        throw StateError('缺少共同同步基线，请先选择使用本机或文件夹数据');
      }
      final next = choice == SyncChoice.merge
          ? mergeSnapshotsWithBase(
              baseSnapshot!,
              local,
              remoteSnapshot,
              sections,
            )
          : local;
      if (choice == SyncChoice.merge) await importSnapshot(next);
      final hash = sha256.convert(utf8.encode(jsonEncode(next))).toString();
      final temp = File('${remote.path}.tmp');
      await temp.writeAsString(
        jsonEncode({
          'formatVersion': 1,
          'revision': (envelope['revision'] as int? ?? 0) + 1,
          'snapshot': next,
          'checksum': hash,
        }),
        flush: true,
      );
      await temp.rename(remote.path);
      await record(hash, next);
    }
    return null;
  }

  Future<void> importSnapshot(Map<String, dynamic> snapshot) async {
    final previous = this.snapshot();
    load(snapshot);
    try {
      await save();
    } catch (_) {
      load(previous);
      rethrow;
    }
  }
}

enum SyncChoice { merge, keepLocal, useRemote }

class SyncConflict {
  final Map<String, dynamic> remote;
  SyncConflict(this.remote);
}

Map<String, dynamic> mergeSnapshots(
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
  List<String> sections,
) {
  final result = <String, dynamic>{'formatVersion': 1};
  for (final section in sections) {
    final merged = <String, Map<String, dynamic>>{};
    for (final value in [
      ...(remote[section] as List? ?? []),
      ...(local[section] as List? ?? []),
    ]) {
      final row = Map<String, dynamic>.from(value as Map);
      merged['${row['id']}'] = row;
    }
    result[section] = merged.values.toList();
  }
  return result;
}

Map<String, dynamic> mergeSnapshotsWithBase(
  Map<String, dynamic> base,
  Map<String, dynamic> local,
  Map<String, dynamic> remote,
  List<String> sections,
) {
  Map<String, Map<String, dynamic>> byId(
    Map<String, dynamic> snapshot,
    String section,
  ) => {
    for (final raw in snapshot[section] as List? ?? [])
      '${(raw as Map)['id']}': Map<String, dynamic>.from(raw),
  };
  bool same(Map<String, dynamic>? first, Map<String, dynamic>? second) =>
      jsonEncode(first) == jsonEncode(second);
  final result = <String, dynamic>{'formatVersion': 1};
  for (final section in sections) {
    final original = byId(base, section);
    final left = byId(local, section);
    final right = byId(remote, section);
    final merged = <Map<String, dynamic>>[];
    for (final id in {...original.keys, ...right.keys, ...left.keys}) {
      final before = original[id], mine = left[id], theirs = right[id];
      final chosen = same(mine, before) ? theirs : mine;
      if (chosen != null) merged.add(chosen);
    }
    result[section] = merged;
  }
  return result;
}

class WorkspaceViewModel extends BasePageViewModel<WorkspaceRepository> {
  final selectedTaskIds = <String>{}.obs;
  Timer? _syncTimer;
  Timer? _anniversaryTimer;
  Future<void> _calendarQueue = Future.value();
  final calendarStatus = ''.obs;
  final widgetStatus = ''.obs;
  bool _syncInProgress = false;
  final syncFolderPath = ''.obs;
  final syncStatus = ''.obs;
  final revision = 0.obs;
  final undoCount = 0.obs;
  final redoCount = 0.obs;
  final _undo = <Map<String, dynamic>>[];
  final _redo = <Map<String, dynamic>>[];
  Map<String, dynamic> _copySnapshot() => Map<String, dynamic>.from(
    jsonDecode(jsonEncode(repository.snapshot())) as Map,
  );
  Map<String, dynamic> _historySnapshot(Map<String, dynamic> source) =>
      Map<String, dynamic>.from(
        jsonDecode(
          jsonEncode({
            'formatVersion': 1,
            for (final section in repository.sections)
              if (section != 'planChanges') section: source[section] ?? [],
          }),
        ) as Map,
      );
  void _record(Map<String, dynamic> previous) {
    _undo.add(previous);
    if (_undo.length > 50) _undo.removeAt(0);
    _redo.clear();
    undoCount.value = _undo.length;
    redoCount.value = 0;
  }

  void _clearHistory() {
    _undo.clear();
    _redo.clear();
    undoCount.value = 0;
    redoCount.value = 0;
  }

  Future<void> undo() async {
    if (_undo.isEmpty) return;
    final current = _copySnapshot();
    await repository.importSnapshot(_undo.last);
    _undo.removeLast();
    _redo.add(current);
    undoCount.value = _undo.length;
    redoCount.value = _redo.length;
    revision.value++;
    await updateMenu();
    await syncCalendar();
  }

  Future<void> redo() async {
    if (_redo.isEmpty) return;
    final current = _copySnapshot();
    await repository.importSnapshot(_redo.last);
    _redo.removeLast();
    _undo.add(current);
    undoCount.value = _undo.length;
    redoCount.value = _redo.length;
    revision.value++;
    await updateMenu();
    await syncCalendar();
  }

  final section = 'today'.obs;
  final search = ''.obs;
  final themeMode = ThemeMode.system.obs;
  final dailyReviewEnabled = false.obs;
  final dailyReviewHour = 18.obs;
  @override
  void onInit() {
    super.onInit();
    final preferences = items('settings')
        .where((e) => e['id'] == 'preferences')
        .firstOrNull;
    final mode = '${preferences?['themeMode'] ?? 'system'}';
    themeMode.value = ThemeMode.values.firstWhere(
      (e) => e.name == mode,
      orElse: () => ThemeMode.system,
    );
    dailyReviewEnabled.value = preferences?['dailyReviewEnabled'] == true;
    dailyReviewHour.value = preferences?['dailyReviewHour'] as int? ?? 18;
  }

  void startAnniversaryRefresh() {
    unawaited(refreshAnniversaryNotifications());
    unawaited(syncCalendar());
    _anniversaryTimer?.cancel();
    _anniversaryTimer = Timer.periodic(const Duration(hours: 1), (_) {
      unawaited(refreshAnniversaryNotifications());
      unawaited(syncCalendar());
    });
  }

  void _startAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(autoSync());
    });
  }

  @override
  void onClose() {
    _syncTimer?.cancel();
    _anniversaryTimer?.cancel();
    super.onClose();
  }

  Future<void> restoreSyncFolder() async {
    final bookmarkFile = File('${repository.file.path}.bookmark');
    if (!await bookmarkFile.exists()) return;
    try {
      final bookmark = await bookmarkFile.readAsString();
      syncFolderPath.value =
          await NativeBridge.restoreSyncFolder(bookmark) ?? '';
      if (syncFolderPath.value.isEmpty) throw StateError('同步文件夹不可用');
      _startAutoSync();
      await autoSync();
    } catch (error) {
      syncFolderPath.value = '';
      syncStatus.value = '自动同步暂停：$error';
    }
  }

  Future<SyncConflict?> selectAndSyncFolder() async {
    final selected = await NativeBridge.selectSyncFolder();
    if (selected == null) return null;
    final path = '${selected['path'] ?? ''}';
    final bookmark = '${selected['bookmark'] ?? ''}';
    if (path.isEmpty || bookmark.isEmpty) throw StateError('文件夹授权不完整');
    await File('${repository.file.path}.bookmark')
        .writeAsString(bookmark, flush: true);
    syncFolderPath.value = path;
    _startAutoSync();
    syncStatus.value = '';
    final conflict = await syncFolder(path);
    syncStatus.value = conflict == null ? '自动同步已启用' : '同步冲突：请在设置中选择保留的数据';
    return conflict;
  }

  Future<void> autoSync() async {
    final path = syncFolderPath.value;
    if (path.isEmpty ||
        syncStatus.value.startsWith('同步冲突') ||
        _syncInProgress) {
      return;
    }
    _syncInProgress = true;
    try {
      final conflict = await syncFolder(path);
      syncStatus.value = conflict == null ? '自动同步已完成' : '同步冲突：请在设置中选择保留的数据';
    } catch (error) {
      syncStatus.value = '自动同步暂停：$error';
    } finally {
      _syncInProgress = false;
    }
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode.value = mode;
    await put('settings', {
      ...?items('settings').where((e) => e['id'] == 'preferences').firstOrNull,
      'id': 'preferences',
      'themeMode': mode.name,
    });
  }

  Future<void> setDailyReview(bool enabled, int hour) async {
    final result = await NativeBridge.dailyReviewNotification(enabled, hour);
    if (enabled && result != true) throw StateError('通知权限未获批准');
    dailyReviewEnabled.value = enabled;
    dailyReviewHour.value = hour;
    await put('settings', {
      ...?items('settings').where((e) => e['id'] == 'preferences').firstOrNull,
      'id': 'preferences',
      'dailyReviewEnabled': enabled,
      'dailyReviewHour': hour,
    });
  }

  Future<void> refreshAnniversaryNotifications() async {
    for (final item in items(
      'anniversaries',
    ).where((row) => row['notificationEnabled'] == true)) {
      final date = DateTime.tryParse('${item['date']}');
      if (date == null) continue;
      try {
        await NativeBridge.anniversaryNotification(
          id: '${item['id']}',
          title: '${item['name'] ?? '纪念日'}',
          date: date,
          enabled: true,
          repeatYearly: item['repeatYearly'] == true,
          lunar: item['calendar'] == 'lunar',
          reminderDays: (item['reminderDays'] as num?)?.toInt() ?? 0,
          privacyMode: item['privacyMode'] == true,
        );
      } catch (error) {
        debugPrint('纪念日提醒刷新失败：$error');
      }
    }
    await updateMenu();
  }

  List<Map<String, dynamic>> items(String key) => repository.data[key] ?? [];

  Future<void> syncCalendar() {
    final next = _calendarQueue.then((_) async {
      try {
        await CalendarLinks(File('${repository.file.path}.calendar-links.json'))
            .sync(items('tasks'));
        calendarStatus.value = '系统日历已同步';
      } catch (error) {
        calendarStatus.value = '系统日历同步失败：$error';
      }
    });
    _calendarQueue = next;
    return next;
  }

  Future<void> createAnniversaryPreparation(
    String id,
    DateTime occurrence,
  ) async {
    final anniversary = items('anniversaries')
        .where((row) => '${row['id']}' == id)
        .firstOrNull;
    if (anniversary == null ||
        anniversary['preparationEnabled'] != true ||
        anniversary['generatedTaskID'] != null) {
      throw StateError('准备任务已经创建或纪念日不可用');
    }
    final lead = ((anniversary['preparationLeadDays'] as num?)?.toInt() ?? 7)
        .clamp(1, 365);
    final planned = DateTime(
      occurrence.year,
      occurrence.month,
      occurrence.day - lead,
    );
    final today = DateTime.now();
    final scheduled = planned.isBefore(today) ? today : planned;
    final blueprintId = anniversary['blueprintID'];
    final blueprint = items('blueprints')
        .where((row) => row['id'] == blueprintId)
        .firstOrNull;
    if (blueprintId != null && blueprint == null) throw StateError('关联蓝图已不存在');
    final task = <String, dynamic>{
      'id': newId(),
      'title': '${anniversary['preparationTaskTitle'] ?? ''}'.trim().isEmpty
          ? '准备${anniversary['name']}'
          : '${anniversary['preparationTaskTitle']}'.trim(),
      'project': blueprint?['name'] ?? '纪念日准备',
      'quadrant': 2,
      'scheduledFor': scheduled.toIso8601String(),
      'dueDate': occurrence.toIso8601String(),
      'estimatedMinutes': 30,
      'status': 'pending',
      'blueprintID': blueprintId,
    };
    final previous = _copySnapshot();
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
    };
    next['tasks']!.add(task);
    final warning = TaskRules.validate(
      task,
      next['tasks']!,
      next['blueprints']!,
    );
    if (warning != null) throw StateError(warning);
    final index = next['anniversaries']!.indexWhere(
      (row) => '${row['id']}' == id,
    );
    next['anniversaries']![index]['generatedTaskID'] = task['id'];
    await repository.commit(next);
    _record(previous);
    revision.value++;
    await updateMenu();
  }

  Future<void> put(String key, Map<String, dynamic> item) async {
    final previous = _copySnapshot();
    final previouslySynced =
        key == 'tasks' &&
        items('tasks').any(
          (task) =>
              task['id'] == item['id'] && task['calendarAutoSync'] == true,
        );
    if (key == 'reports') {
      final minimum = item['minimumLength'];
      final maximum = item['maximumLength'];
      final date = DateTime.tryParse('${item['reportDate']}');
      if (minimum is! int || maximum is! int || date == null) {
        throw const FormatException('日报日期或字数范围无效');
      }
      final warning = ReportRules.warning(
        '${item['content'] ?? ''}',
        minimum,
        maximum,
      );
      if (warning != null) throw FormatException(warning);
    }
    if (key == 'weeklyReviews') {
      final warning = WeeklyReviewRules.validate(item);
      if (warning != null) throw FormatException(warning);
    }
    if (key == 'anniversaries') {
      final date = DateTime.tryParse('${item['date']}');
      if (date == null) throw const FormatException('纪念日日期无效');
      final result = await NativeBridge.anniversaryNotification(
        id: '${item['id']}',
        title: '${item['name']}',
        date: date,
        enabled: item['notificationEnabled'] == true,
        repeatYearly: item['repeatYearly'] == true,
        lunar: item['calendar'] == 'lunar',
        reminderDays: (item['reminderDays'] as num?)?.toInt() ?? 0,
        privacyMode: item['privacyMode'] == true,
      );
      if (item['notificationEnabled'] == true && result != true) {
        throw StateError('纪念日通知权限未获批准');
      }
    }
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
    };
    final list = next[key]!;
    final index = list.indexWhere((e) => e['id'] == item['id']);
    if (index < 0) {
      list.add(item);
    } else {
      list[index] = item;
    }
    if (key == 'tasks') {
      final error = TaskRules.validate(item, list, next['blueprints']!);
      if (error != null) throw StateError(error);
    }
    await repository.commit(next);
    if (key == 'tasks') _record(previous);
    revision.value++;
    if (key == 'tasks' || key == 'anniversaries') await updateMenu();
    if (key == 'tasks' &&
        (item['calendarAutoSync'] == true || previouslySynced)) {
      await syncCalendar();
    }
  }

  Future<void> remove(String key, String id) async {
    final previous = _copySnapshot();
    final hadCalendarTasks = items('tasks')
        .any((task) => task['calendarAutoSync'] == true);
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
    };
    if (key == 'tasks') {
      final removed = {id, ...TaskRules.descendants(id, next['tasks']!)};
      final successors = next['tasks']!.where(
        (t) =>
            !removed.contains('${t['id']}') &&
            (t['dependencyIDs'] as List? ?? []).any(
              (d) => removed.contains('$d'),
            ),
      );
      if (successors.isNotEmpty) throw StateError('请先移除后续任务的前置连线');
      next['tasks']!.removeWhere((e) => removed.contains('${e['id']}'));
    } else if (key == 'blueprints') {
      next['tasks']!.removeWhere((e) => e['blueprintID'] == id);
      next['stages']!.removeWhere((e) => e['blueprintID'] == id);
      next['milestones']!.removeWhere((e) => e['blueprintID'] == id);
      next[key]!.removeWhere((e) => e['id'] == id);
    } else if (key == 'stages') {
      next['tasks']!.removeWhere((e) => e['stageID'] == id);
      next['milestones']!.removeWhere((e) => e['stageID'] == id);
      next[key]!.removeWhere((e) => e['id'] == id);
    } else {
      next[key]!.removeWhere((e) => e['id'] == id);
    }
    await repository.commit(next);
    if (key == 'tasks' || key == 'blueprints') _record(previous);
    revision.value++;
    if (key == 'tasks' || key == 'blueprints' || key == 'anniversaries') {
      await updateMenu();
    }
    if (key == 'anniversaries') {
      await NativeBridge.anniversaryNotification(
        id: id,
        title: '',
        date: DateTime.now(),
        enabled: false,
        repeatYearly: false,
        lunar: false,
      );
    }
    if (hadCalendarTasks && ['tasks', 'blueprints', 'stages'].contains(key)) {
      await syncCalendar();
    }
  }

  Future<void> setTaskStatus(
    Map<String, dynamic> task,
    String status, {
    String? reason,
  }) async {
    final now = DateTime.now().toIso8601String();
    final updated = {
      ...task,
      'status': status,
      'statusChangedAt': now,
      'completedAt': status == 'completed' ? now : null,
      'startedAt': status == 'inProgress'
          ? (task['startedAt'] ?? now)
          : task['startedAt'],
      'blockReason': status == 'blocked' ? reason : null,
    };
    await put('tasks', updated);
    if (status == 'completed') {
      var parentId = updated['parentTaskID'];
      while (parentId != null) {
        final parent = tasks.where((t) => t['id'] == parentId).firstOrNull;
        if (parent == null) break;
        final children = tasks
            .where((t) => t['parentTaskID'] == parentId)
            .toList();
        if (children.isEmpty ||
            children.any((t) => t['status'] != 'completed')) {
          break;
        }
        if (TaskRules.blockingReason(parent, tasks, items('blueprints')) !=
            null) {
          break;
        }
        await put('tasks', {
          ...parent,
          'status': 'completed',
          'completedAt': now,
          'autoCompletedAt': now,
        });
        parentId = parent['parentTaskID'];
      }
    }
  }

  Future<void> toggleTask(Map<String, dynamic> task) => setTaskStatus(
    task,
    task['status'] == 'completed' ? 'pending' : 'completed',
  );
  Future<void> addChild(Map<String, dynamic> parent, String title) =>
      put('tasks', {
        'id': newId(),
        'title': title.trim(),
        'notes': '',
        'project': parent['project'],
        'category': parent['category'],
        'quadrant': parent['quadrant'],
        'scheduledFor': parent['scheduledFor'],
        'status': 'pending',
        'blueprintID': parent['blueprintID'],
        'stageID': parent['stageID'],
        'parentTaskID': parent['id'],
        'dependencyIDs': <String>[],
      });
  Future<void> addTaskTree(
    String title,
    String notes,
    List<String> subtasks,
  ) async {
    final previous = _copySnapshot();
    final parentId = newId();
    final now = DateTime.now().toIso8601String();
    final incoming = <Map<String, dynamic>>[
      {
        'id': parentId,
        'title': title.trim(),
        'notes': notes,
        'status': 'pending',
        'quadrant': 1,
        'scheduledFor': now,
      },
      for (final child in subtasks)
        {
          'id': newId(),
          'title': child.trim(),
          'notes': '',
          'status': 'pending',
          'quadrant': 1,
          'scheduledFor': now,
          'parentTaskID': parentId,
        },
    ];
    if (title.trim().isEmpty || subtasks.any((e) => e.trim().isEmpty)) {
      throw const FormatException('任务标题不能为空');
    }
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
    };
    next['tasks']!.insertAll(0, incoming);
    for (final task in incoming) {
      final error = TaskRules.validate(
        task,
        next['tasks']!,
        next['blueprints']!,
      );
      if (error != null) throw StateError(error);
    }
    await repository.commit(next);
    _record(previous);
    revision.value++;
    await updateMenu();
  }

  Future<void> linkDependency(
    Map<String, dynamic> task,
    String predecessorId,
  ) => put('tasks', {
    ...task,
    'dependencyIDs': [...(task['dependencyIDs'] as List? ?? []), predecessorId],
  });
  Future<void> addCategory(String name, {String symbol = 'label'}) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const FormatException('分类名称不能为空');
    if (items('categories')
        .any((e) => '${e['name']}'.toLowerCase() == trimmed.toLowerCase())) {
      throw StateError('分类已存在');
    }
    await put('categories', {'id': newId(), 'name': trimmed, 'symbol': symbol});
  }

  Future<void> renameCategory(
    String oldName,
    String newName, {
    String? symbol,
  }) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw const FormatException('分类名称不能为空');
    if (items('categories').any(
      (e) =>
          '${e['name']}'.toLowerCase() == trimmed.toLowerCase() &&
          e['name'] != oldName,
    )) {
      throw StateError('分类已存在');
    }
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
    };
    var found = false;
    for (final row in next['categories']!) {
      if (row['name'] == oldName) {
        found = true;
        row['name'] = trimmed;
        if (symbol != null) row['symbol'] = symbol;
      }
    }
    if (!found) {
      next['categories']!.add({
        'id': newId(),
        'name': trimmed,
        'symbol': symbol ?? 'label',
      });
    }
    for (final task in next['tasks']!) {
      if (task['category'] == oldName) task['category'] = trimmed;
    }
    await repository.commit(next);
    revision.value++;
  }

  Future<void> deleteCategory(String name) async {
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
    };
    next['categories']!.removeWhere((e) => e['name'] == name);
    for (final task in next['tasks']!) {
      if (task['category'] == name) task['category'] = null;
    }
    await repository.commit(next);
    revision.value++;
  }

  List<Map<String, dynamic>> get tasks => items('tasks');
  Future<void> applyCalendarChanges(
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after,
  ) async {
    if (before.isEmpty || before.length != after.length) {
      throw StateError('没有可保存的日历安排');
    }
    final previous = _copySnapshot();
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
    };
    for (var i = 0; i < before.length; i++) {
      final id = '${before[i]['id']}';
      if (id != '${after[i]['id']}') throw StateError('安排的任务 ID 不一致');
      final index = next['tasks']!.indexWhere((row) => '${row['id']}' == id);
      if (index < 0 ||
          jsonEncode(next['tasks']![index]) != jsonEncode(before[i])) {
        throw StateError('事项已在其他位置修改，请重新检查安排');
      }
      next['tasks']![index] = Map<String, dynamic>.from(after[i]);
    }
    for (final row in after) {
      final error = TaskRules.validate(
        row,
        next['tasks']!,
        next['blueprints']!,
      );
      if (error != null) throw StateError(error);
    }
    await repository.commit(next);
    _record(previous);
    revision.value++;
    await updateMenu();
    if ([...before, ...after].any((row) => row['calendarAutoSync'] == true)) {
      await syncCalendar();
    }
  }

  Future<void> applyTaskBatch(String action) async {
    final ids = selectedTaskIds
        .where((id) => tasks.any((task) => '${task['id']}' == id))
        .toSet();
    if (ids.isEmpty) {
      selectedTaskIds.clear();
      return;
    }
    if (!{'complete', 'cancel', 'today', 'delete'}.contains(action)) {
      throw ArgumentError.value(action, 'action');
    }
    final previous = _copySnapshot();
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
    };
    final rows = next['tasks']!;
    final now = DateTime.now().toIso8601String();
    if (action == 'delete') {
      final removed = <String>{...ids};
      for (final id in ids) {
        removed.addAll(TaskRules.descendants(id, rows));
      }
      final blocked = rows.any(
        (row) =>
            !removed.contains('${row['id']}') &&
            (row['dependencyIDs'] as List? ?? []).any(
              (id) => removed.contains('$id'),
            ),
      );
      if (blocked) throw StateError('请先移除后续任务的前置连线');
      rows.removeWhere((row) => removed.contains('${row['id']}'));
    } else {
      for (final row in rows.where((row) => ids.contains('${row['id']}'))) {
        if (action == 'today') {
          row['scheduledFor'] = now;
        } else {
          final status = action == 'complete' ? 'completed' : 'cancelled';
          row['status'] = status;
          row['statusChangedAt'] = now;
          row['completedAt'] = status == 'completed' ? now : null;
        }
      }
      for (final row in rows.where((row) => ids.contains('${row['id']}'))) {
        final error = TaskRules.validate(row, rows, next['blueprints']!);
        if (error != null) throw StateError(error);
      }
    }
    await repository.commit(next);
    _record(previous);
    selectedTaskIds.clear();
    revision.value++;
    await updateMenu();
    if (action == 'today' || action == 'delete') await syncCalendar();
  }

  List<Map<String, dynamic>> get todayTasks {
    final now = DateTime.now();
    return tasks.where((t) {
      final date = DateTime.tryParse('${t['scheduledFor']}');
      return date != null &&
          date.year == now.year &&
          date.month == now.month &&
          date.day == now.day;
    }).toList();
  }

  Future<void> importWorkspace(String path) async {
    await repository.importFrom(path);
    _clearHistory();
    revision.value++;
    await updateMenu();
    await syncCalendar();
  }

  Map<String, dynamic> exportBlueprint(String id) =>
      BlueprintTransfer.export(repository.snapshot(), id);
  Future<void> importBlueprint(Map<String, dynamic> package) async {
    final previous = _copySnapshot();
    final next = BlueprintTransfer.import(previous, package, newId);
    await repository.importSnapshot(next);
    _record(previous);
    revision.value++;
    await updateMenu();
    await syncCalendar();
  }

  Future<void> createBlueprintFromTemplate(
    BlueprintTemplate template, {
    DateTime? start,
  }) async {
    final previous = _copySnapshot();
    final now = start ?? DateTime.now();
    final id = newId();
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
    };
    next['blueprints']!.add({
      'id': id,
      'name': template.name,
      'goal': template.goal,
      'status': 'active',
      'startDate': now.toIso8601String(),
      'dueDate': now
          .add(Duration(days: template.stages.length * 14))
          .toIso8601String(),
    });
    for (var index = 0; index < template.stages.length; index++) {
      final stageId = newId();
      final due = now.add(Duration(days: (index + 1) * 14));
      next['stages']!.add({
        'id': stageId,
        'blueprintID': id,
        'name': template.stages[index],
        'order': index,
        'startDate': now.add(Duration(days: index * 14)).toIso8601String(),
        'dueDate': due.toIso8601String(),
      });
      next['milestones']!.add({
        'id': newId(),
        'blueprintID': id,
        'stageID': stageId,
        'name': '完成${template.stages[index]}',
        'dueDate': due.toIso8601String(),
        'isCompleted': false,
      });
    }
    await repository.commit(next);
    _record(previous);
    revision.value++;
  }

  Future<void> createAiBlueprint(
    AiBlueprintDraft draft, {
    Set<String>? excludedTaskKeys,
  }) async {
    final previous = _copySnapshot();
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
    };
    final id = newId();
    final created = <String, List<Map<String, dynamic>>>{
      'blueprints': [],
      'stages': [],
      'milestones': [],
      'tasks': [],
    };
    created['blueprints']!.add({
      'id': id,
      'name': draft.name,
      'goal': draft.goal,
      'status': 'active',
      'startDate': draft.startDate.toIso8601String(),
      'dueDate': draft.dueDate.toIso8601String(),
    });
    var predecessors = <String>[];
    for (var index = 0; index < draft.stages.length; index++) {
      final stage = draft.stages[index];
      final stageId = newId();
      created['stages']!.add({
        'id': stageId,
        'blueprintID': id,
        'name': stage.name,
        'order': index,
        'startDate': stage.startDate.toIso8601String(),
        'dueDate': stage.dueDate.toIso8601String(),
      });
      created['milestones']!.add({
        'id': newId(),
        'blueprintID': id,
        'stageID': stageId,
        'name': stage.milestone,
        'dueDate': stage.dueDate.toIso8601String(),
        'isCompleted': false,
      });
      final current = <String>[];
      for (var taskIndex = 0; taskIndex < stage.tasks.length; taskIndex++) {
        if (excludedTaskKeys?.contains('$index:$taskIndex') == true) continue;
        final task = stage.tasks[taskIndex];
        final taskId = newId();
        created['tasks']!.add({
          'id': taskId,
          'title': task.title,
          'notes': task.notes,
          'project': draft.name,
          'reportCategory': 'projectProgress',
          'quadrant': task.quadrant,
          'scheduledFor': task.scheduledFor.toIso8601String(),
          'dueDate': task.dueDate?.toIso8601String(),
          'estimatedMinutes': task.estimatedMinutes,
          'status': 'pending',
          'blueprintID': id,
          'stageID': stageId,
          'dependencyIDs': [...predecessors],
        });
        current.add(taskId);
      }
      if (current.isNotEmpty) predecessors = current;
    }
    if (created['tasks']!.isEmpty) throw const FormatException('至少保留一项任务');
    for (final entry in created.entries) {
      next[entry.key]!.addAll(entry.value);
    }
    for (final task in created['tasks']!) {
      final error = TaskRules.validate(
        task,
        next['tasks']!,
        next['blueprints']!,
      );
      if (error != null) throw StateError(error);
    }
    next['planChanges']!.add({
      'id': newId(),
      'kind': 'aiBlueprint',
      'blueprintID': id,
      'title': 'AI 创建蓝图：${draft.name}',
      'changedAt': DateTime.now().toIso8601String(),
      'createdRecords': created,
      'beforeSnapshot': _historySnapshot(previous),
      'afterSnapshot': _historySnapshot({'formatVersion': 1, ...next}),
    });
    await repository.commit(next);
    _record(previous);
    revision.value++;
    await updateMenu();
  }

  Future<void> commitReplan(
    String blueprintId,
    List<ReplanChange> selected, {
    required int dailyMinutes,
  }) async {
    final previous = _copySnapshot();
    final planned = applyReplanToTasks(tasks, blueprintId, selected);
    final overloads = replanCapacityOverloads(
      planned,
      selected.map((change) => change.taskId).toSet(),
      dailyMinutes,
    );
    if (overloads.isNotEmpty) {
      throw StateError(capacityOverloadMessage(overloads));
    }
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
    };
    next['tasks'] = planned;
    final historyEntries = replanHistoryEntries(tasks, planned, selected);
    for (final task in planned.where(
      (e) => selected.any((c) => c.taskId == e['id']),
    )) {
      final error = TaskRules.validate(task, planned, next['blueprints']!);
      if (error != null) throw StateError(error);
    }
    next['planChanges']!.add({
      'id': newId(),
      'kind': 'aiReplan',
      'blueprintID': blueprintId,
      'changedAt': DateTime.now().toIso8601String(),
      'taskIDs': selected.map((e) => e.taskId).toList(),
      'title': 'AI 重新规划 ${historyEntries.length} 项任务',
      'entries': historyEntries,
      'beforeTasks': [
        for (final task in tasks)
          if (selected.any((change) => change.taskId == task['id']))
            Map<String, dynamic>.from(task),
      ],
      'afterTasks': [
        for (final task in planned)
          if (selected.any((change) => change.taskId == task['id']))
            Map<String, dynamic>.from(task),
      ],
      'beforeSnapshot': _historySnapshot(previous),
      'afterSnapshot': _historySnapshot({'formatVersion': 1, ...next}),
    });
    await repository.commit(next);
    _record(previous);
    revision.value++;
    await updateMenu();
    await syncCalendar();
  }

  Future<void> undoPlanChange(String changeId) async {
    final previous = _copySnapshot();
    final records = items('planChanges');
    final record = records.where((item) => item['id'] == changeId).firstOrNull;
    if (record == null || record['isUndone'] == true) {
      throw StateError('规划记录不存在或已撤销');
    }
    if (record['kind'] == 'aiBlueprint') {
      final raw = record['createdRecords'];
      if (raw is! Map) throw StateError('这条记录没有可恢复的蓝图快照');
      final blueprintId = '${record['blueprintID']}';
      final created = <String, List<Map<String, dynamic>>>{};
      for (final section in ['blueprints', 'stages', 'milestones', 'tasks']) {
        final rows = raw[section];
        if (rows is! List) throw StateError('蓝图快照不完整');
        created[section] = rows
            .map((row) => Map<String, dynamic>.from(row as Map))
            .toList();
      }
      final next = {
        for (final entry in repository.data.entries)
          entry.key: entry.value
              .map((row) => Map<String, dynamic>.from(row))
              .toList(),
      };
      for (final section in created.keys) {
        final current = {for (final row in next[section]!) '${row['id']}': row};
        for (final row in created[section]!) {
          if (jsonEncode(current['${row['id']}']) != jsonEncode(row)) {
            throw StateError('蓝图已有后续修改，无法安全撤销');
          }
        }
      }
      final taskIds = created['tasks']!.map((row) => '${row['id']}').toSet();
      if (next['tasks']!.any(
            (row) =>
                row['blueprintID'] == blueprintId &&
                !taskIds.contains('${row['id']}'),
          ) ||
          next['tasks']!.any(
            (row) =>
                row['blueprintID'] != blueprintId &&
                (row['dependencyIDs'] as List? ?? []).any(
                  (id) => taskIds.contains('$id'),
                ),
          )) {
        throw StateError('蓝图已有新的关联任务，无法安全撤销');
      }
      for (final section in created.keys) {
        final ids = created[section]!.map((row) => '${row['id']}').toSet();
        next[section]!.removeWhere((row) => ids.contains('${row['id']}'));
      }
      next['planChanges']!.firstWhere(
        (row) => row['id'] == changeId,
      )['isUndone'] = true;
      await repository.commit(next);
      _record(previous);
      revision.value++;
      await updateMenu();
      await syncCalendar();
      return;
    }
    final beforeRaw = record['beforeTasks'], afterRaw = record['afterTasks'];
    if (beforeRaw is! List || afterRaw is! List) {
      throw StateError('这条早期记录没有可恢复的任务快照');
    }
    final before = beforeRaw
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    final after = afterRaw
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList();
    if (before.length != after.length || before.isEmpty) {
      throw StateError('任务快照不完整');
    }
    final current = {for (final task in tasks) '${task['id']}': task};
    for (final task in after) {
      if (jsonEncode(current['${task['id']}']) != jsonEncode(task)) {
        throw StateError('相关任务已被修改，无法安全撤销这次规划');
      }
    }
    final replacement = {for (final task in before) '${task['id']}': task};
    final next = {
      for (final entry in repository.data.entries)
        entry.key: entry.value
            .map((row) => Map<String, dynamic>.from(row))
            .toList(),
    };
    next['tasks'] = [
      for (final task in tasks) replacement['${task['id']}'] ?? task,
    ];
    for (final task in next['tasks']!) {
      if (!replacement.containsKey('${task['id']}')) continue;
      final error = TaskRules.validate(
        task,
        next['tasks']!,
        next['blueprints']!,
      );
      if (error != null) throw StateError(error);
    }
    final index = next['planChanges']!.indexWhere(
      (item) => item['id'] == changeId,
    );
    next['planChanges']![index]['isUndone'] = true;
    await repository.commit(next);
    _record(previous);
    revision.value++;
    await updateMenu();
    await syncCalendar();
  }

  Future<SyncConflict?> syncFolder(String path, {SyncChoice? choice}) async {
    final before = jsonEncode(repository.snapshot());
    final conflict = await repository.syncFolder(path, choice: choice);
    if (conflict == null && jsonEncode(repository.snapshot()) != before) {
      _clearHistory();
    }
    revision.value++;
    await updateMenu();
    if (conflict == null) await syncCalendar();
    return conflict;
  }

  Future<void> updateMenu() async {
    final upcoming = await Future.wait(
      items('anniversaries')
          .where((row) => row['showInMenuBar'] != false)
          .map((row) async {
            final source = DateTime.tryParse('${row['date']}');
            if (source == null) return null;
            try {
              final next = await NativeBridge.anniversaryNextOccurrence(
                source,
                repeatYearly: row['repeatYearly'] == true,
                lunar: row['calendar'] == 'lunar',
              );
              if (next == null) return null;
              final now = DateTime.now();
              final days = DateTime.utc(
                next.year,
                next.month,
                next.day,
              ).difference(DateTime.utc(now.year, now.month, now.day)).inDays;
              return <String, String>{
                'id': '${row['id']}',
                'title': row['privacyMode'] == true ? '重要日子' : '${row['name']}',
                'date': '${next.month}月${next.day}日',
                'days': '$days',
                'sortKey': next.toIso8601String(),
              };
            } catch (_) {
              return null;
            }
          }),
    );
    final anniversaries = upcoming.whereType<Map<String, String>>().toList()
      ..sort((a, b) => a['sortKey']!.compareTo(b['sortKey']!));
    await NativeBridge.updateMenu(
      todayTasks
          .where(
            (t) => t['status'] != 'completed' && t['status'] != 'cancelled',
          )
          .map((t) {
            final started = DateTime.tryParse('${t['startedAt']}');
            return {
              'id': '${t['id']}',
              'title': '${t['title'] ?? ''}',
              'status': '${t['status'] ?? 'pending'}',
              'canRun':
                  TaskRules.blockingReason(t, tasks, items('blueprints')) ==
                      null
                  ? 'true'
                  : 'false',
              if (started != null)
                'startedAt': started.toUtc().toIso8601String(),
            };
          })
          .toList(),
      anniversaries: anniversaries.take(5).toList(),
    );
  }
}
