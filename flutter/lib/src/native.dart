import 'package:flutter/services.dart';

class NativeBridge {
  static const channel = MethodChannel('com.xu.sequence/native');
  static Future<String?> appVersion() =>
      channel.invokeMethod<String>('appVersion');
  static Future<bool?> openReleasePage(String url) =>
      channel.invokeMethod<bool>('openReleasePage', url);
  static Future<bool?> openVerifiedUpdate(String path) =>
      channel.invokeMethod<bool>('openVerifiedUpdate', path);
  static Future<bool?> openWidget() => channel.invokeMethod<bool>('openWidget');
  static Future<Map<String, dynamic>?> selectSyncFolder() async {
    final raw = await channel.invokeMapMethod<String, dynamic>(
      'selectSyncFolder',
    );
    return raw == null ? null : Map<String, dynamic>.from(raw);
  }

  static Future<String?> restoreSyncFolder(String bookmark) =>
      channel.invokeMethod<String>('restoreSyncFolder', bookmark);
  static Future<String?> readApiKey() =>
      channel.invokeMethod<String>('keychainRead');
  static Future<bool?> writeApiKey(String key) =>
      channel.invokeMethod<bool>('keychainWrite', key);
  static Future<void> updateMenu(
    List<Map<String, String>> tasks, {
    List<Map<String, String>> anniversaries = const [],
  }) async {
    try {
      await channel.invokeMethod('updateMenu', {
        'tasks': tasks,
        'anniversaries': anniversaries,
      });
    } catch (_) {
      /* Flutter tests and unsupported hosts */
    }
  }

  static Future<bool?> dailyReviewNotification(bool enabled, int hour) =>
      channel.invokeMethod<bool>('dailyReviewNotification', {
        'enabled': enabled,
        'hour': hour,
      });
  static Future<bool?> anniversaryNotification({
    required String id,
    required String title,
    required DateTime date,
    required bool enabled,
    required bool repeatYearly,
    bool lunar = false,
    int reminderDays = 0,
    bool privacyMode = false,
  }) => channel.invokeMethod<bool>('anniversaryNotification', {
    'id': id,
    'title': title,
    'year': date.year,
    'month': date.month,
    'day': date.day,
    'enabled': enabled,
    'repeatYearly': repeatYearly,
    'lunar': lunar,
    'reminderDays': reminderDays,
    'privacyMode': privacyMode,
  });
  static Future<DateTime?> anniversaryNextOccurrence(
    DateTime date, {
    required bool repeatYearly,
    required bool lunar,
  }) async {
    final raw = await channel.invokeMethod<String>(
      'anniversaryNextOccurrence',
      {
        'year': date.year,
        'month': date.month,
        'day': date.day,
        'repeatYearly': repeatYearly,
        'lunar': lunar,
      },
    );
    return raw == null ? null : DateTime.tryParse(raw)?.toLocal();
  }

  static Future<List<Map<String, dynamic>>> calendarEvents(
    DateTime start,
    DateTime end,
  ) async {
    final raw = await channel.invokeListMethod<dynamic>('calendarEvents', {
      'start': start.toUtc().toIso8601String(),
      'end': end.toUtc().toIso8601String(),
    });
    return (raw ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }

  static Future<String?> calendarCreate(
    String title,
    DateTime start,
    int minutes, {
    String? eventId,
  }) => channel.invokeMethod<String>('calendarCreate', {
    'title': title,
    'start': start.toUtc().toIso8601String(),
    'minutes': minutes,
    'eventID': eventId,
  });

  static Future<bool?> calendarDelete(String eventId) =>
      channel.invokeMethod<bool>('calendarDelete', eventId);

  static void listen({
    required void Function() onAddTask,
    required void Function(String) onToggleTask,
    required void Function() onShowAnniversaries,
    required void Function(String) onStartTask,
    required void Function(String) onCompleteTask,
    required void Function(String) onCancelTask,
    required void Function() onAddCompletedTask,
    required void Function() onAddAiTask,
    required void Function() onShowCommandPalette,
    required void Function() onShowSettings,
  }) {
    channel.setMethodCallHandler((call) async {
      if (call.method == 'addTask') onAddTask();
      if (call.method == 'showAnniversaries') onShowAnniversaries();
      if (call.method == 'addCompletedTask') onAddCompletedTask();
      if (call.method == 'addAiTask') onAddAiTask();
      if (call.method == 'showCommandPalette') onShowCommandPalette();
      if (call.method == 'showSettings') onShowSettings();
      if (call.method == 'startTask' && call.arguments is String) {
        onStartTask(call.arguments as String);
      }
      if (call.method == 'completeTask' && call.arguments is String) {
        onCompleteTask(call.arguments as String);
      }
      if (call.method == 'cancelTask' && call.arguments is String) {
        onCancelTask(call.arguments as String);
      }
      if (call.method == 'toggleTask' && call.arguments is String) {
        onToggleTask(call.arguments as String);
      }
    });
  }
}
