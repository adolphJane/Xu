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
import 'calendar_plan_logic.dart';

import 'blueprint_graph.dart';
import 'blueprint_image_data.dart';
import 'blueprint_planning.dart';

part 'blueprint_workspace.dart';

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
    'blueprintTemplates',
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

  Future<SyncConflict?> syncFolder(String path, {SyncChoice? choice}) async {
    final documentFolder =
        path.startsWith('content://') || path.startsWith('file://');
    final folder = documentFolder ? null : Directory(path);
    if (folder != null && !await folder.exists()) {
      throw const FileSystemException('同步文件夹不存在');
    }
    final folderKey = folder?.absolute.path ?? path;
    final remote = folder == null
        ? null
        : File('${folder.path}/xu-workspace-v1.json');
    final recovery = folder == null
        ? null
        : File('${folder.path}/xu-workspace-v1.recovery.json');
    final previous = remote == null
        ? await NativeBridge.readSyncDocument(path)
        : await remote.exists()
        ? await remote.readAsString()
        : recovery != null && await recovery.exists()
        ? await recovery.readAsString()
        : null;
    Future<void> write(Map<String, dynamic> envelope) async {
      final content = jsonEncode(envelope);
      if (remote == null) {
        await NativeBridge.writeSyncDocument(path, content, previous: previous);
        return;
      }
      final temp = File('${remote.path}.tmp');
      await temp.writeAsString(content, flush: true);
      await temp.rename(remote.path);
    }

    final stateFile = File('${file.path}.sync');
    final state = await stateFile.exists()
        ? Map<String, dynamic>.from(
            jsonDecode(await stateFile.readAsString()) as Map,
          )
        : <String, dynamic>{};
    Future<void> record(String checksum, Map<String, dynamic> common) async {
      state[folderKey] = {'checksum': checksum, 'snapshot': common};
      await stateFile.writeAsString(jsonEncode(state), flush: true);
    }

    final local = snapshot();
    final localHash = sha256.convert(utf8.encode(jsonEncode(local))).toString();
    if (previous == null) {
      await write({
        'formatVersion': 1,
        'revision': 1,
        'snapshot': local,
        'checksum': localHash,
      });
      await record(localHash, local);
      return null;
    }
    final envelope = jsonDecode(previous) as Map<String, dynamic>;
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
    final savedBase = state[folderKey];
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
      await write({
        'formatVersion': 1,
        'revision': (envelope['revision'] as int? ?? 0) + 1,
        'snapshot': next,
        'checksum': hash,
      });
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

bool _sameValue(Object? a, Object? b) => jsonEncode(a) == jsonEncode(b);

class _WorkspaceChange {
  const _WorkspaceChange(this.before, this.after);

  final Map<String, dynamic> before;
  final Map<String, dynamic> after;
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
  Future<void> _writeQueue = Future.value();
  final _undo = <_WorkspaceChange>[];
  final _redo = <_WorkspaceChange>[];

  Future<T> _write<T>(Future<T> Function() action) {
    final result = _writeQueue.then((_) => action());
    _writeQueue = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return result;
  }

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
    _undo.add(_WorkspaceChange(previous, _copySnapshot()));
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

  Future<void> undo() => _write(() => _applyHistory(_undo, _redo, undo: true));

  Future<void> redo() => _write(() => _applyHistory(_redo, _undo, undo: false));

  Future<void> _applyHistory(
    List<_WorkspaceChange> source,
    List<_WorkspaceChange> destination, {
    required bool undo,
  }) async {
    if (source.isEmpty) return;
    final change = source.last;
    final expected = undo ? change.after : change.before;
    final replacement = undo ? change.before : change.after;
    final next = _editableWorkspace();
    for (final section in next.keys) {
      final oldRows = (expected[section] as List).cast<Map<String, dynamic>>();
      final newRows = (replacement[section] as List)
          .cast<Map<String, dynamic>>();
      final oldById = {for (final row in oldRows) row['id']: row};
      final newById = {for (final row in newRows) row['id']: row};
      final changedIds = {
        ...oldById.keys,
        ...newById.keys,
      }.where((id) => !_sameValue(oldById[id], newById[id])).toSet();
      final rows = next[section]!;
      final current = {for (final row in rows) row['id']: row};
      for (final id in changedIds) {
        if (!_sameValue(current[id], oldById[id])) {
          throw StateError('相关记录已修改，无法安全${undo ? '撤销' : '重做'}');
        }
      }
      rows.removeWhere(
        (row) =>
            changedIds.contains(row['id']) && !newById.containsKey(row['id']),
      );
      for (var i = 0; i < newRows.length; i++) {
        final row = newRows[i];
        if (!changedIds.contains(row['id'])) continue;
        final index = rows.indexWhere((current) => current['id'] == row['id']);
        if (index < 0) {
          rows.insert(i.clamp(0, rows.length), row);
        } else {
          rows[index] = row;
        }
      }
    }
    await repository.commit(next);
    source.removeLast();
    destination.add(change);
    undoCount.value = _undo.length;
    redoCount.value = _redo.length;
    revision.value++;
    await updateMenu();
    await syncCalendar();
  }

  Map<String, List<Map<String, dynamic>>> _editableWorkspace() => {
    for (final entry in repository.data.entries)
      entry.key: entry.value
          .map((row) => Map<String, dynamic>.from(row))
          .toList(),
  };

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
    try {
      if (!await bookmarkFile.exists()) return;
      final bookmark = await bookmarkFile.readAsString();
      syncFolderPath.value =
          await NativeBridge.restoreSyncFolder(bookmark) ?? '';
      if (syncFolderPath.value.isEmpty) throw StateError('同步文件夹不可用');
      _startAutoSync();
      unawaited(autoSync());
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

  Future<void> setThemeMode(ThemeMode mode) => _write(() async {
    await _put('settings', {
      ...?items('settings').where((e) => e['id'] == 'preferences').firstOrNull,
      'id': 'preferences',
      'themeMode': mode.name,
    });
    themeMode.value = mode;
  });

  Future<void> setDailyReview(bool enabled, int hour) => _write(() async {
    final result = await NativeBridge.dailyReviewNotification(enabled, hour);
    if (enabled && result != true) throw StateError('通知权限未获批准');
    await _put('settings', {
      ...?items('settings').where((e) => e['id'] == 'preferences').firstOrNull,
      'id': 'preferences',
      'dailyReviewEnabled': enabled,
      'dailyReviewHour': hour,
    });
    dailyReviewEnabled.value = enabled;
    dailyReviewHour.value = hour;
  });

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
  ) => _write(() async {
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
    final next = _editableWorkspace();
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
  });

  void _validatePlanLinks(
    String section,
    Map<String, dynamic> row,
    Map<String, List<Map<String, dynamic>>> workspace,
  ) {
    if (!['tasks', 'stages', 'milestones'].contains(section)) return;
    final blueprint = row['blueprintID'];
    if (blueprint != null &&
        !workspace['blueprints']!.any((item) => item['id'] == blueprint)) {
      throw StateError('所属蓝图已不存在');
    }
    final stage = row['stageID'];
    if (stage != null &&
        !workspace['stages']!.any(
          (item) => item['id'] == stage && item['blueprintID'] == blueprint,
        )) {
      throw StateError('阶段必须属于同一蓝图');
    }
    final milestone = row['milestoneID'];
    if (milestone != null &&
        !workspace['milestones']!.any(
          (item) =>
              item['id'] == milestone &&
              item['blueprintID'] == blueprint &&
              item['stageID'] == stage,
        )) {
      throw StateError('里程碑必须属于所选阶段');
    }
  }

  List<Map<String, dynamic>> milestoneTasks(Object? id) =>
      _milestoneTasks(tasks, id);

  List<Map<String, dynamic>> _milestoneTasks(
    List<Map<String, dynamic>> rows,
    Object? id,
  ) => rows
      .where((row) => row['milestoneID'] == id && row['status'] != 'cancelled')
      .toList();

  void _refreshMilestones(Map<String, List<Map<String, dynamic>>> workspace) {
    final tasks = workspace['tasks']!;
    for (final milestone in workspace['milestones']!) {
      final linked = _milestoneTasks(tasks, milestone['id']);
      final checks = milestone['acceptanceChecks'] as List? ?? [];
      if (checks.isNotEmpty) {
        final tasksDone = linked.every((row) => row['status'] == 'completed');
        final checksDone = checks.every(
          (row) => row is Map && row['done'] == true,
        );
        if (!tasksDone || !checksDone) milestone['acceptedAt'] = null;
        milestone['isCompleted'] =
            tasksDone && checksDone && milestone['acceptedAt'] != null;
        milestone['acceptanceStatus'] = tasksDone ? 'ready' : 'waiting';
        milestone['completionFromTasks'] = true;
      } else if (linked.isNotEmpty) {
        milestone.remove('acceptanceStatus');
        milestone['isCompleted'] = linked.every(
          (row) => row['status'] == 'completed',
        );
        milestone['completionFromTasks'] = true;
      } else if (milestone.remove('completionFromTasks') == true) {
        milestone.remove('acceptanceStatus');
        milestone['isCompleted'] = false;
      }
    }
  }

  Future<void> setMilestoneCompleted(Object? id, bool completed) =>
      _write(() async {
        final milestone = items('milestones').firstWhere(
          (row) => row['id'] == id,
          orElse: () => throw StateError('里程碑已不存在'),
        );
        if ((milestone['acceptanceChecks'] as List? ?? []).isNotEmpty) {
          throw StateError('请通过检查项验收此里程碑');
        }
        if (milestoneTasks(id).isNotEmpty) throw StateError('此里程碑的完成状态由关联事项决定');
        await _put('milestones', {...milestone, 'isCompleted': completed});
      });

  Future<void> put(String key, Map<String, dynamic> item) =>
      _write(() => _put(key, item));

  Future<void> _put(String key, Map<String, dynamic> item) async {
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
    final next = _editableWorkspace();
    final list = next[key]!;
    final index = list.indexWhere((e) => e['id'] == item['id']);
    final existing = index < 0 ? null : list[index];
    _validatePlanLinks(key, item, next);
    if (index < 0) {
      list.add(item);
    } else {
      list[index] = item;
    }
    if (key == 'milestones' && item['stageID'] != existing?['stageID']) {
      for (final task in next['tasks']!.where(
        (row) => row['milestoneID'] == item['id'],
      )) {
        task['stageID'] = item['stageID'];
      }
    }
    if (key == 'tasks') {
      final blueprintId = item['blueprintID'];
      if (blueprintId != null &&
          (existing == null ||
              !_sameValue(item['dependencyIDs'], existing['dependencyIDs']) ||
              item['parentTaskID'] != existing['parentTaskID'] ||
              blueprintId != existing['blueprintID'])) {
        final graph = BlueprintGraph(
          _requireTask(blueprintId, next['blueprints']!),
          list.where((row) => row['blueprintID'] == blueprintId),
        );
        if (graph.issues[item['id']] case final reason?) {
          throw StateError(reason);
        }
      }
      if (item['status'] != existing?['status'] ||
          item['parentTaskID'] != existing?['parentTaskID']) {
        _reconcileTaskStatuses(list, next['blueprints']!, {
          item['id'],
        }, DateTime.now());
      } else {
        final error = TaskRules.validate(item, list, next['blueprints']!);
        if (error != null) throw StateError(error);
      }
    }
    if (key == 'tasks' || key == 'milestones') _refreshMilestones(next);
    await repository.commit(next);
    if (['tasks', 'blueprints', 'stages', 'milestones'].contains(key)) {
      _record(previous);
    }
    revision.value++;
    if (key == 'tasks' || key == 'anniversaries') await updateMenu();
    if (key == 'tasks' &&
        (item['calendarAutoSync'] == true || previouslySynced)) {
      await syncCalendar();
    }
  }

  Future<void> remove(String key, String id) => _write(() async {
    final previous = _copySnapshot();
    final hadCalendarTasks = items('tasks')
        .any((task) => task['calendarAutoSync'] == true);
    final next = _editableWorkspace();
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
      for (final task in next['tasks']!.where((row) => row['stageID'] == id)) {
        task['stageID'] = null;
      }
      for (final milestone in next['milestones']!.where(
        (row) => row['stageID'] == id,
      )) {
        milestone['stageID'] = null;
      }
      next[key]!.removeWhere((e) => e['id'] == id);
    } else if (key == 'milestones') {
      for (final task in next['tasks']!.where(
        (row) => row['milestoneID'] == id,
      )) {
        task['milestoneID'] = null;
      }
      next[key]!.removeWhere((e) => e['id'] == id);
    } else {
      next[key]!.removeWhere((e) => e['id'] == id);
    }
    if (key == 'tasks') _refreshMilestones(next);
    await repository.commit(next);
    if (['tasks', 'blueprints', 'stages', 'milestones'].contains(key)) {
      _record(previous);
    }
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
  });

  Future<void> setTaskStatus(
    Map<String, dynamic> task,
    String status, {
    String? reason,
  }) => _write(() async {
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    final rows = next['tasks']!;
    final current = _requireTask(task['id'], rows);
    if (status == 'inProgress' || status == 'completed') {
      final error = status == 'inProgress'
          ? _startReason(current, rows, next['blueprints']!)
          : TaskRules.blockingReason(current, rows, next['blueprints']!);
      if (error != null) throw StateError(error);
    }
    final now = DateTime.now();
    _setStatus(current, status, now, reason: reason);
    _reconcileTaskStatuses(rows, next['blueprints']!, {current['id']}, now);
    await _saveTaskChange(previous, next);
  });

  Map<String, dynamic> _requireTask(
    Object? id,
    List<Map<String, dynamic>> rows,
  ) => rows.firstWhere(
    (row) => row['id'] == id,
    orElse: () => throw StateError('事项已不存在'),
  );

  void _setStatus(
    Map<String, dynamic> task,
    String status,
    DateTime date, {
    String? reason,
    bool automatic = false,
  }) {
    final now = date.toIso8601String();
    task.addAll({
      'status': status,
      'statusChangedAt': now,
      'completedAt': status == 'completed' ? now : null,
      'autoCompletedAt': automatic ? now : null,
      'startedAt': status == 'inProgress'
          ? task['startedAt'] ?? now
          : task['startedAt'],
      'blockReason': status == 'blocked' ? reason : null,
    });
  }

  void _reconcileTaskStatuses(
    List<Map<String, dynamic>> rows,
    List<Map<String, dynamic>> blueprints,
    Set<Object?> changed,
    DateTime now,
  ) {
    final byId = {for (final row in rows) row['id']: row};
    final explicitlyCompleted = changed
        .where((id) => byId[id]?['status'] == 'completed')
        .toSet();
    final affectedParents = <Object?>{};
    for (final id in changed) {
      var parentId = byId[id]?['parentTaskID'];
      final seen = <Object?>{};
      while (byId.containsKey(parentId) && seen.add(parentId)) {
        affectedParents.add(parentId);
        parentId = byId[parentId]?['parentTaskID'];
      }
    }
    // Each pass handles changes propagated from a lower level.
    for (var pass = 0; pass < affectedParents.length; pass++) {
      var updated = false;
      for (final id in affectedParents) {
        final parent = byId[id]!;
        final children = rows.where((row) => row['parentTaskID'] == id);
        final allCompleted = children.every(
          (row) => row['status'] == 'completed',
        );
        if (allCompleted &&
            parent['status'] != 'completed' &&
            TaskRules.blockingReason(parent, rows, blueprints) == null) {
          _setStatus(parent, 'completed', now, automatic: true);
        } else if (!allCompleted &&
            parent['status'] == 'completed' &&
            !explicitlyCompleted.contains(id)) {
          _setStatus(parent, 'pending', now);
        } else {
          continue;
        }
        changed.add(id);
        updated = true;
      }
      if (!updated) break;
    }
    for (final row in rows) {
      final id = row['id'];
      final dependencies = row['dependencyIDs'] as List? ?? [];
      if (!changed.contains(id) &&
          (!['completed', 'inProgress'].contains(row['status']) ||
              !dependencies.any(changed.contains))) {
        continue;
      }
      final error = TaskRules.validate(row, rows, blueprints);
      if (error != null) throw StateError('「${row['title'] ?? id}」：$error');
    }
  }

  Future<void> _saveTaskChange(
    Map<String, dynamic> previous,
    Map<String, List<Map<String, dynamic>>> next,
  ) async {
    _refreshMilestones(next);
    await repository.commit(next);
    _record(previous);
    revision.value++;
    await updateMenu();
    if ([
      ...(previous['tasks'] as List).cast<Map>(),
      ...next['tasks']!,
    ].any((row) => row['calendarAutoSync'] == true)) {
      await syncCalendar();
    }
  }

  Future<void> arrangeToday(Map<String, dynamic> task) =>
      _write(() => _moveTask(task, postpone: false));

  Future<void> postponeTask(Map<String, dynamic> task) =>
      _write(() => _moveTask(task, postpone: true));

  Future<void> _moveTask(
    Map<String, dynamic> task, {
    required bool postpone,
  }) async {
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    final current = _requireTask(task['id'], next['tasks']!);
    final now = DateTime.now();
    if (CalendarPlanLogic.isProcessed(current)) throw StateError('请先恢复事项');
    if (CalendarPlanLogic.isLocked(current)) throw StateError('请先解除事项的固定安排');
    if (postpone) {
      final oldDate = CalendarPlanLogic.plannedDate(current);
      if (oldDate == null) throw StateError('请先安排计划日期');
      final tomorrow = CalendarPlanLogic.addDays(CalendarPlanLogic.day(now), 1);
      if (!CalendarPlanLogic.day(oldDate).isBefore(tomorrow)) {
        throw StateError('此事项已安排在明天或更晚');
      }
      current['originalScheduledFor'] ??= current['scheduledFor'];
      final destination = DateTime(
        tomorrow.year,
        tomorrow.month,
        tomorrow.day,
        oldDate.hour,
        oldDate.minute,
      );
      CalendarPlanLogic.reschedule(current, destination);
      current['postponements'] = [
        ...current['postponements'] as List? ?? [],
        {
          'from': oldDate.toIso8601String(),
          'to': current['scheduledFor'],
          'changedAt': now.toIso8601String(),
        },
      ];
      _setStatus(current, 'postponed', now);
    } else {
      CalendarPlanLogic.reschedule(current, CalendarPlanLogic.day(now));
    }
    await _saveTaskChange(previous, next);
  }

  Future<void> toggleTask(Map<String, dynamic> task) => setTaskStatus(
    task,
    task['status'] == 'completed' ? 'pending' : 'completed',
  );

  Future<void> addChild(Map<String, dynamic> task, String title) =>
      _write(() async {
        final parent = _requireTask(task['id'], tasks);
        await _put('tasks', {
          'id': newId(),
          'title': title.trim(),
          'notes': '',
          'project': parent['project'],
          'category': parent['category'],
          'quadrant': parent['quadrant'],
          'scheduledFor': parent['scheduledFor'],
          'status': parent['scheduledFor'] == null ? 'unscheduled' : 'pending',
          'blueprintID': parent['blueprintID'],
          'stageID': parent['stageID'],
          'milestoneID': parent['milestoneID'],
          'parentTaskID': parent['id'],
          'dependencyIDs': <String>[],
        });
      });
  Future<void> addTaskTree(String title, String notes, List<String> subtasks) =>
      _write(() async {
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
        final next = _editableWorkspace();
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
      });

  Future<void> linkDependency(
    Map<String, dynamic> task,
    String predecessorId,
  ) => _write(() {
    final current = _requireTask(task['id'], tasks);
    return _put('tasks', {
      ...current,
      'dependencyIDs': [
        ...(current['dependencyIDs'] as List? ?? []),
        predecessorId,
      ],
    });
  });
  Future<void> addCategory(String name, {String symbol = 'label'}) => _write(
    () async {
      final trimmed = name.trim();
      if (trimmed.isEmpty) throw const FormatException('分类名称不能为空');
      if (items('categories')
          .any((e) => '${e['name']}'.toLowerCase() == trimmed.toLowerCase())) {
        throw StateError('分类已存在');
      }
      await _put('categories', {
        'id': newId(),
        'name': trimmed,
        'symbol': symbol,
      });
    },
  );

  Future<void> renameCategory(
    String oldName,
    String newName, {
    String? symbol,
  }) => _write(() async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) throw const FormatException('分类名称不能为空');
    if (items('categories').any(
      (e) =>
          '${e['name']}'.toLowerCase() == trimmed.toLowerCase() &&
          e['name'] != oldName,
    )) {
      throw StateError('分类已存在');
    }
    final previous = _copySnapshot();
    final next = _editableWorkspace();
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
    _record(previous);
    revision.value++;
  });

  Future<void> deleteCategory(String name) => _write(() async {
    final previous = _copySnapshot();
    final next = _editableWorkspace();
    next['categories']!.removeWhere((e) => e['name'] == name);
    for (final task in next['tasks']!) {
      if (task['category'] == name) task['category'] = null;
    }
    await repository.commit(next);
    _record(previous);
    revision.value++;
  });

  List<Map<String, dynamic>> get tasks => items('tasks');
  Future<void> applyCalendarChanges(
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after,
  ) => _write(() async {
    if (before.isEmpty || before.length != after.length) {
      throw StateError('没有可保存的日历安排');
    }
    final previous = _copySnapshot();
    final next = _editableWorkspace();
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
  });

  Future<void> applyTaskBatch(String action) => _write(() async {
    if (action == 'start') {
      await _startTasks(selectedTaskIds.toSet());
      selectedTaskIds.clear();
      return;
    }
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
    final next = _editableWorkspace();
    final rows = next['tasks']!;
    final now = DateTime.now();
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
          if (CalendarPlanLogic.isProcessed(row) ||
              CalendarPlanLogic.isLocked(row)) {
            throw StateError('选中事项已处理或固定安排');
          }
          CalendarPlanLogic.reschedule(row, CalendarPlanLogic.day(now));
        } else {
          if (action == 'complete' &&
              ['blocked', 'cancelled'].contains(row['status'])) {
            throw StateError('请先恢复「${row['title']}」');
          }
          _setStatus(
            row,
            action == 'complete' ? 'completed' : 'cancelled',
            now,
          );
        }
      }
      if (action != 'today') {
        _reconcileTaskStatuses(rows, next['blueprints']!, {...ids}, now);
      }
    }
    await _saveTaskChange(previous, next);
    selectedTaskIds.clear();
  });

  List<Map<String, dynamic>> get todayTasks {
    final today = CalendarPlanLogic.day(DateTime.now());
    return tasks.where((task) {
      final date = CalendarPlanLogic.plannedDate(task);
      return task['status'] == 'inProgress' ||
          (date != null && CalendarPlanLogic.day(date) == today);
    }).toList();
  }

  Future<void> importWorkspace(Map<String, dynamic> snapshot) =>
      _write(() async {
        await repository.importSnapshot(snapshot);
        _clearHistory();
        revision.value++;
        await updateMenu();
        await syncCalendar();
      });

  Map<String, dynamic> exportBlueprint(String id) =>
      BlueprintTransfer.export(repository.snapshot(), id);
  Future<void> importBlueprint(Map<String, dynamic> package) =>
      _write(() async {
        final previous = _copySnapshot();
        final next = BlueprintTransfer.import(previous, package, newId);
        await repository.importSnapshot(next);
        _record(previous);
        revision.value++;
        await updateMenu();
        await syncCalendar();
      });

  Future<void> createBlueprintFromTemplate(
    BlueprintTemplate template, {
    DateTime? start,
  }) => _write(() async {
    final previous = _copySnapshot();
    final now = start ?? DateTime.now();
    final id = newId();
    final next = _editableWorkspace();
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
  });

  Future<void> createAiBlueprint(
    AiBlueprintDraft draft, {
    Set<String>? excludedTaskKeys,
    Map<String, Set<String>> dependencyOverrides = const {},
    Map<String, String> taskTitles = const {},
    bool chainStages = false,
  }) => _write(() async {
    final previous = _copySnapshot();
    final next = _editableWorkspace();
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
    final connections = draft.dependenciesFor(
      excluded: excludedTaskKeys ?? const {},
      overrides: dependencyOverrides,
      chainStages: chainStages,
    );
    final taskIds = {for (final key in connections.keys) key: newId()};
    for (var index = 0; index < draft.stages.length; index++) {
      final stage = draft.stages[index];
      final stageId = newId();
      final milestoneId = newId();
      created['stages']!.add({
        'id': stageId,
        'blueprintID': id,
        'name': stage.name,
        'order': index,
        'startDate': stage.startDate.toIso8601String(),
        'dueDate': stage.dueDate.toIso8601String(),
      });
      created['milestones']!.add({
        'id': milestoneId,
        'blueprintID': id,
        'stageID': stageId,
        'name': stage.milestone,
        'dueDate': stage.dueDate.toIso8601String(),
        'isCompleted': false,
      });
      for (var taskIndex = 0; taskIndex < stage.tasks.length; taskIndex++) {
        if (excludedTaskKeys?.contains('$index:$taskIndex') == true) continue;
        final task = stage.tasks[taskIndex];
        final taskKey = '$index:$taskIndex';
        final taskId = taskIds[taskKey]!;
        created['tasks']!.add({
          'id': taskId,
          'title': taskTitles[taskKey] ?? task.title,
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
          'milestoneID': milestoneId,
          'dependencyIDs': connections[taskKey]!
              .map((key) => taskIds[key]!)
              .toList(),
        });
      }
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
    _refreshMilestones(next);
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
  });

  Future<void> commitReplan(
    String blueprintId,
    List<ReplanChange> selected, {
    required int dailyMinutes,
  }) => _write(() async {
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
    final next = _editableWorkspace();
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
  });

  Future<void> undoPlanChange(String changeId) => _write(() async {
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
      final next = _editableWorkspace();
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
    final next = _editableWorkspace();
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
  });

  Future<SyncConflict?> syncFolder(String path, {SyncChoice? choice}) =>
      _write(() async {
        final before = jsonEncode(repository.snapshot());
        final conflict = await repository.syncFolder(path, choice: choice);
        if (conflict == null && jsonEncode(repository.snapshot()) != before) {
          _clearHistory();
        }
        revision.value++;
        await updateMenu();
        if (conflict == null) await syncCalendar();
        return conflict;
      });

  Future<void> updateMenu() async {
    if (Platform.isAndroid || Platform.isIOS) return;
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
              'canStart':
                  '${_startReason(t, tasks, items('blueprints')) == null}',
              'canComplete':
                  '${TaskRules.validate({...t, 'status': 'completed'}, tasks, items('blueprints')) == null && TaskRules.blockingReason(t, tasks, items('blueprints')) == null}',
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
