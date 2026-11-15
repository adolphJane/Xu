import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'calendar_plan_logic.dart';
import 'design_system/xu_theme.dart';
import 'native.dart';
import 'workspace.dart';

enum CalendarMode { day, week, month }

class CalendarPage extends StatefulWidget {
  const CalendarPage({
    super.key,
    required this.tasks,
    required this.onEditTask,
    required this.onAddTask,
  });
  final List<Map<String, dynamic>> tasks;
  final void Function(Map<String, dynamic> task) onEditTask;
  final void Function(DateTime day) onAddTask;

  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  CalendarMode mode = CalendarMode.week;
  DateTime selectedDate = CalendarPlanLogic.day(DateTime.now());
  bool showsSeries = true;
  bool waitingOnly = false;
  String? selectedRootId;
  final expandedRoots = <String>{};
  final knownRoots = <String>{};
  List<Map<String, dynamic>> events = [];
  String calendarState = '未连接系统日历，空闲估计仅含序内安排';
  bool connected = false;
  bool loadingEvents = false;
  int eventRequest = 0;
  late CalendarWorkHours hours;
  List<Map<String, dynamic>>? lastBefore;
  List<Map<String, dynamic>>? lastAfter;

  WorkspaceViewModel get vm => Get.find<WorkspaceViewModel>();

  @override
  void initState() {
    super.initState();
    hours = CalendarWorkHours.fromSettings(
      vm
          .items('settings')
          .where((row) => row['id'] == 'preferences')
          .firstOrNull,
    );
    _expandCurrentRoots();
  }

  @override
  void didUpdateWidget(covariant CalendarPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _expandCurrentRoots();
  }

  void _expandCurrentRoots() {
    for (final root in _roots) {
      final id = '${root['id']}';
      if (knownRoots.add(id) && _childrenOf(root).isNotEmpty) {
        expandedRoots.add(id);
      }
    }
  }

  List<Map<String, dynamic>> get _roots {
    final byId = widget.tasks.map((row) => '${row['id']}').toSet();
    return widget.tasks
        .where(
          (row) =>
              row['status'] != 'cancelled' &&
              !byId.contains('${row['parentTaskID']}'),
        )
        .toList();
  }

  List<Map<String, dynamic>> _childrenOf(Map<String, dynamic> root) {
    final result = <Map<String, dynamic>>[];
    final seen = <String>{};
    void collect(String id) {
      if (!seen.add(id)) return;
      for (final child in widget.tasks.where(
        (row) => '${row['parentTaskID']}' == id,
      )) {
        result.add(child);
        collect('${child['id']}');
      }
    }

    collect('${root['id']}');
    return result;
  }

  DateTime get _weekStart =>
      CalendarPlanLogic.addDays(selectedDate, -(selectedDate.weekday % 7));
  DateTime get _monthStart => DateTime(selectedDate.year, selectedDate.month);
  DateTime get _monthGridStart =>
      CalendarPlanLogic.addDays(_monthStart, -(_monthStart.weekday % 7));
  List<DateTime> get _days {
    final start = switch (mode) {
      CalendarMode.day => selectedDate,
      CalendarMode.week => _weekStart,
      CalendarMode.month => _monthGridStart,
    };
    final count = switch (mode) {
      CalendarMode.day => 1,
      CalendarMode.week => 7,
      CalendarMode.month =>
        ((CalendarPlanLogic.daysBetween(
                      DateTime(selectedDate.year, selectedDate.month + 1),
                      _monthGridStart,
                    ) +
                    6) ~/
                7) *
            7,
    };
    return [
      for (var i = 0; i < count; i++) CalendarPlanLogic.addDays(start, i),
    ];
  }

  String get _periodTitle => switch (mode) {
    CalendarMode.day =>
      '${selectedDate.year}年${selectedDate.month}月${selectedDate.day}日 星期${_weekday(selectedDate)}',
    CalendarMode.week =>
      '${_weekStart.month}月${_weekStart.day}日—${CalendarPlanLogic.addDays(_weekStart, 6).month}月${CalendarPlanLogic.addDays(_weekStart, 6).day}日',
    CalendarMode.month => '${selectedDate.year}年${selectedDate.month}月',
  };

  static String _weekday(DateTime day) => '日一二三四五六'[day.weekday % 7];
  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
  static String _clock(DateTime value) =>
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  static String _shortDate(DateTime value) => '${value.month}月${value.day}日';

  void _shift(int direction) {
    setState(() {
      selectedDate = switch (mode) {
        CalendarMode.day => CalendarPlanLogic.addDays(selectedDate, direction),
        CalendarMode.week => CalendarPlanLogic.addDays(
          selectedDate,
          7 * direction,
        ),
        CalendarMode.month => DateTime(
          selectedDate.year,
          selectedDate.month + direction,
          math.min(
            selectedDate.day,
            DateTime(
              selectedDate.year,
              selectedDate.month + direction + 1,
              0,
            ).day,
          ),
        ),
      };
    });
    if (connected) unawaited(_readEvents());
  }

  Future<void> _readEvents() async {
    final request = ++eventRequest;
    setState(() => loadingEvents = true);
    try {
      final days = _days;
      final loaded = await NativeBridge.calendarEvents(
        days.first,
        CalendarPlanLogic.addDays(days.last, 1),
      );
      if (!mounted || request != eventRequest) return;
      setState(() {
        events = loaded;
        connected = true;
        calendarState = loaded.isEmpty
            ? '系统日历：本周期无日程'
            : '系统日历：${loaded.length} 项日程';
      });
    } catch (error) {
      if (mounted && request == eventRequest) {
        setState(() => calendarState = '系统日历读取失败：$error');
      }
    } finally {
      if (mounted && request == eventRequest) {
        setState(() => loadingEvents = false);
      }
    }
  }

  List<Map<String, dynamic>> _scheduledOn(DateTime day) =>
      CalendarPlanLogic.executable(widget.tasks).where((task) {
        final date =
            CalendarPlanLogic.taskBlock(task)?.start ??
            CalendarPlanLogic.plannedDate(task);
        return date != null &&
            _sameDay(day, date) &&
            (selectedRootId == null ||
                CalendarPlanLogic.rootId(task, widget.tasks) == selectedRootId);
      }).toList();

  List<Map<String, dynamic>> _eventsOn(DateTime day, {bool? allDay}) {
    final start = CalendarPlanLogic.day(day);
    final end = CalendarPlanLogic.addDays(start, 1);
    return events.where((event) {
      final block = CalendarPlanLogic.eventBlock(event);
      return block != null &&
          block.start.isBefore(end) &&
          block.end.isAfter(start) &&
          (allDay == null || (event['isAllDay'] == true) == allDay);
    }).toList();
  }

  String _availability(DateTime day, {bool detailed = false}) {
    if (!hours.worksOn(day)) return '非工作日';
    final slots = CalendarPlanLogic.availability(
      day,
      hours,
      widget.tasks,
      events,
    );
    final minutes = slots.fold<int>(0, (sum, slot) => sum + slot.minutes);
    if (minutes <= 0) return '无可用空档';
    String duration(int value) =>
        value % 60 == 0 ? '${value ~/ 60}小时' : '${value ~/ 60}时${value % 60}分';
    final total = '可用 ${duration(minutes)}';
    if (!detailed) return total;
    final longest = slots.map((slot) => slot.minutes).reduce(math.max);
    return '$total · 最长 ${duration(longest)}';
  }

  Future<bool> _applyChanges(
    List<Map<String, dynamic>> before,
    List<Map<String, dynamic>> after,
  ) async {
    try {
      await vm.applyCalendarChanges(before, after);
      if (!mounted) return true;
      setState(() {
        lastBefore = before;
        lastAfter = after;
      });
      if (connected) unawaited(_readEvents());
      return true;
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
      return false;
    }
  }

  Future<void> _undo() async {
    if (lastBefore == null || lastAfter == null) return;
    final before = lastBefore!;
    final after = lastAfter!;
    try {
      await vm.applyCalendarChanges(after, before);
      if (!mounted) return;
      setState(() {
        lastBefore = null;
        lastAfter = null;
      });
      if (connected) unawaited(_readEvents());
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$error')));
      }
    }
  }

  Future<void> _clearBlock(
    Map<String, dynamic> task, {
    required bool keepDate,
  }) async {
    final after = Map<String, dynamic>.from(task)..['timeBlock'] = null;
    if (!keepDate) {
      after['scheduledFor'] = null;
      after['status'] = 'unscheduled';
    }
    await _applyChanges([Map<String, dynamic>.from(task)], [after]);
  }

  bool _canDrop(String id) {
    final task = widget.tasks.where((row) => '${row['id']}' == id).firstOrNull;
    if (task == null || task['status'] == 'cancelled') return false;
    if (_childrenOf(task).isNotEmpty) return true;
    return !CalendarPlanLogic.isProcessed(task) &&
        task['planLocked'] != true &&
        CalendarPlanLogic.executable(widget.tasks)
            .any((row) => '${row['id']}' == id);
  }

  Future<void> _drop(String id, DateTime day, {int? hour}) async {
    if (!_canDrop(id)) return;
    final task = widget.tasks.firstWhere((row) => '${row['id']}' == id);
    setState(() => selectedDate = CalendarPlanLogic.day(day));
    if (connected) await _readEvents();
    if (!mounted) return;
    if (_childrenOf(task).isNotEmpty) {
      _showMoveSeries(task, day: day);
    } else {
      _showArrange(task, day: day, hour: hour);
    }
  }

  Widget _dragSource(Map<String, dynamic> task, Widget child) {
    if (!_canDrop('${task['id']}')) return child;
    return Draggable<String>(
      data: '${task['id']}',
      feedback: Material(
        elevation: 4,
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 230),
            child: Text('${task['title']}', maxLines: 2),
          ),
        ),
      ),
      childWhenDragging: Opacity(opacity: 0.4, child: child),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = XuColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, limits) {
            final navigation = Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.outlined(
                  tooltip:
                      '上一${mode.name == 'day'
                          ? '日'
                          : mode.name == 'week'
                          ? '周'
                          : '月'}',
                  onPressed: () => _shift(-1),
                  icon: const Icon(Icons.chevron_left),
                ),
                SizedBox(
                  width: limits.maxWidth < 900 ? 150 : 210,
                  child: Text(
                    _periodTitle,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                IconButton.outlined(
                  tooltip:
                      '下一${mode.name == 'day'
                          ? '日'
                          : mode.name == 'week'
                          ? '周'
                          : '月'}',
                  onPressed: () => _shift(1),
                  icon: const Icon(Icons.chevron_right),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () {
                    setState(
                      () =>
                          selectedDate = CalendarPlanLogic.day(DateTime.now()),
                    );
                    if (connected) unawaited(_readEvents());
                  },
                  child: const Text('今天'),
                ),
              ],
            );
            final controls = Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SegmentedButton<CalendarMode>(
                  segments: const [
                    ButtonSegment(value: CalendarMode.day, label: Text('日')),
                    ButtonSegment(value: CalendarMode.week, label: Text('周')),
                    ButtonSegment(value: CalendarMode.month, label: Text('月')),
                  ],
                  selected: {mode},
                  showSelectedIcon: false,
                  onSelectionChanged: (value) {
                    setState(() => mode = value.first);
                    if (connected) unawaited(_readEvents());
                  },
                ),
                OutlinedButton.icon(
                  onPressed: () => setState(() => showsSeries = !showsSeries),
                  icon: const Icon(Icons.view_sidebar_outlined),
                  label: const Text('任务系列'),
                ),
                FilledButton.icon(
                  onPressed: () => widget.onAddTask(selectedDate),
                  icon: const Icon(Icons.add),
                  label: const Text('安排事项'),
                ),
              ],
            );
            return Container(
              color: colors.topbar,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: limits.maxWidth < 980
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              '日历计划',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const Spacer(),
                            navigation,
                          ],
                        ),
                        const SizedBox(height: 8),
                        controls,
                      ],
                    )
                  : Row(
                      children: [
                        Text(
                          '日历计划',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Spacer(),
                        navigation,
                        const SizedBox(width: 12),
                        controls,
                      ],
                    ),
            );
          },
        ),
        Divider(height: 1, color: colors.border),
        Expanded(
          child: Row(
            children: [
              Expanded(
                child: mode == CalendarMode.month
                    ? _monthView(context)
                    : _timeView(context),
              ),
              if (showsSeries) ...[
                VerticalDivider(width: 1, color: colors.border),
                SizedBox(width: 320, child: _seriesPanel(context)),
              ],
            ],
          ),
        ),
        Divider(height: 1, color: colors.border),
        _footer(context, scheme),
      ],
    );
  }

  Widget _footer(BuildContext context, ColorScheme scheme) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    child: Wrap(
      spacing: 14,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('☑ 子任务时间块', style: Theme.of(context).textTheme.labelSmall),
        Text('▦ 系统日程', style: Theme.of(context).textTheme.labelSmall),
        Text('▱ 系列范围不占用时间', style: Theme.of(context).textTheme.labelSmall),
        Text(
          calendarState,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: calendarState.contains('失败') ? scheme.error : null,
          ),
        ),
        OutlinedButton(onPressed: _showWorkHours, child: const Text('工作时段')),
        OutlinedButton(
          onPressed: loadingEvents ? null : _readEvents,
          child: Text(connected ? '刷新日历' : '连接日历'),
        ),
        if (lastBefore != null)
          TextButton(onPressed: _undo, child: const Text('撤销安排')),
      ],
    ),
  );

  Widget _monthView(BuildContext context) {
    final days = _days;
    final colors = XuColors.of(context);
    return LayoutBuilder(
      builder: (context, limits) {
        final rowHeight = math.max(
          120.0,
          (limits.maxHeight - 34) / (days.length ~/ 7),
        );
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(limits.maxWidth, 700),
            child: Column(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < 7; i++)
                      Expanded(
                        child: Container(
                          color: colors.muted,
                          padding: const EdgeInsets.all(8),
                          child: Text(
                            '星期${'日一二三四五六'[i]}',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                      ),
                  ],
                ),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (var row = 0; row < days.length ~/ 7; row++)
                          SizedBox(
                            height: rowHeight,
                            child: Row(
                              children: [
                                for (var col = 0; col < 7; col++)
                                  Expanded(
                                    child: _monthCell(
                                      context,
                                      days[row * 7 + col],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _monthCell(BuildContext context, DateTime day) {
    final colors = XuColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final tasks = _scheduledOn(day);
    final dayEvents = _eventsOn(day);
    final due = widget.tasks.where((task) {
      final date = CalendarPlanLogic.parse(task['dueDate']);
      return date != null &&
          _sameDay(date, day) &&
          task['status'] != 'cancelled';
    }).toList();
    final spans = _seriesSpans()
        .where((span) => !day.isBefore(span.$2) && !day.isAfter(span.$3))
        .toList();
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => _canDrop(details.data),
      onAcceptWithDetails: (details) => unawaited(_drop(details.data, day)),
      builder: (context, candidates, rejected) => InkWell(
        onTap: () => setState(() => selectedDate = day),
        onDoubleTap: () {
          setState(() {
            selectedDate = day;
            mode = CalendarMode.day;
          });
          if (connected) unawaited(_readEvents());
        },
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: candidates.isNotEmpty || _sameDay(day, selectedDate)
                ? colors.selection
                : scheme.surface,
            border: Border.all(color: colors.border, width: 0.5),
          ),
          child: Opacity(
            opacity: day.month == selectedDate.month ? 1 : 0.55,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '${day.day}日',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Spacer(),
                    if (_sameDay(day, DateTime.now()))
                      Text('今天', style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      if (spans.isNotEmpty)
                        Text(
                          '系列 · ${spans.first.$1}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.primary),
                        ),
                      for (final task in tasks)
                        Text(
                          '${CalendarPlanLogic.taskBlock(task) == null ? '待定时' : _clock(CalendarPlanLogic.taskBlock(task)!.start)} · ${task['title']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      for (final event in dayEvents)
                        Text(
                          '▦ ${event['title']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (due.isNotEmpty)
                        Text(
                          '⚑ ${due.first['title']} 截止',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: scheme.error),
                        ),
                    ],
                  ),
                ),
                Text(
                  _availability(day),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<(String, DateTime, DateTime)> _seriesSpans() {
    final spans = <(String, DateTime, DateTime)>[];
    for (final root in _roots) {
      if (_childrenOf(root).isEmpty) continue;
      final dates =
          CalendarPlanLogic.executable(_childrenOf(root))
              .map(
                (task) =>
                    CalendarPlanLogic.taskBlock(task)?.start ??
                    CalendarPlanLogic.plannedDate(task),
              )
              .whereType<DateTime>()
              .map(CalendarPlanLogic.day)
              .toList()
            ..sort();
      if (dates.isNotEmpty) {
        spans.add(('${root['title']}', dates.first, dates.last));
      }
    }
    return spans;
  }

  Widget _timeView(BuildContext context) {
    final days = _days;
    return LayoutBuilder(
      builder: (context, limits) {
        final width = mode == CalendarMode.day
            ? math.max(limits.maxWidth, 420.0)
            : math.max(limits.maxWidth, 80.0 + 7 * 124.0);
        final columnWidth = (width - 80) / days.length;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: width,
            child: SingleChildScrollView(
              child: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(width: 80),
                      for (final day in days)
                        SizedBox(
                          width: columnWidth,
                          child: InkWell(
                            onTap: () => setState(() => selectedDate = day),
                            child: Container(
                              color: _sameDay(day, selectedDate)
                                  ? XuColors.of(context).selection
                                  : null,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              child: Column(
                                children: [
                                  Text(
                                    '周${_weekday(day)}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                  Text(
                                    _shortDate(day),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium,
                                  ),
                                  if (_sameDay(day, DateTime.now()))
                                    const Text('今天'),
                                  Text(
                                    _availability(
                                      day,
                                      detailed: mode == CalendarMode.day,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (mode == CalendarMode.week)
                    _seriesRangeStrip(context, days, columnWidth),
                  _waitingStrip(context, days, columnWidth),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 80,
                        child: Column(
                          children: [
                            for (var hour = 8; hour < 21; hour++)
                              SizedBox(
                                height: 64,
                                child: Align(
                                  alignment: Alignment.topRight,
                                  child: Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Text(
                                      '${hour.toString().padLeft(2, '0')}:00',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      for (final day in days)
                        _timeColumn(context, day, columnWidth),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _seriesRangeStrip(
    BuildContext context,
    List<DateTime> days,
    double columnWidth,
  ) {
    final spans = _seriesSpans()
        .where(
          (span) =>
              !span.$3.isBefore(days.first) && !span.$2.isAfter(days.last),
        )
        .toList();
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      decoration: BoxDecoration(
        border: Border.symmetric(
          horizontal: BorderSide(color: XuColors.of(context).border),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text('系列范围', style: Theme.of(context).textTheme.labelSmall),
          ),
          SizedBox(
            width: columnWidth * 7,
            height: math.max(40, spans.length * 26.0),
            child: Stack(
              children: [
                for (var i = 0; i < spans.length; i++)
                  Positioned(
                    left:
                        math.max(
                          0,
                          CalendarPlanLogic.daysBetween(
                            spans[i].$2,
                            days.first,
                          ),
                        ) *
                        columnWidth,
                    top: i * 26.0,
                    width:
                        (math.min(
                              6,
                              CalendarPlanLogic.daysBetween(
                                spans[i].$3,
                                days.first,
                              ),
                            ) -
                            math.max(
                              0,
                              CalendarPlanLogic.daysBetween(
                                spans[i].$2,
                                days.first,
                              ),
                            ) +
                            1) *
                        columnWidth,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      color: XuColors.of(context).selection,
                      child: Text(
                        spans[i].$1,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _waitingStrip(
    BuildContext context,
    List<DateTime> days,
    double width,
  ) => Container(
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: XuColors.of(context).border)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 80,
          child: Padding(
            padding: const EdgeInsets.all(4),
            child: Text('当天待定时', style: Theme.of(context).textTheme.labelSmall),
          ),
        ),
        for (final day in days)
          DragTarget<String>(
            onWillAcceptWithDetails: (details) => _canDrop(details.data),
            onAcceptWithDetails: (details) =>
                unawaited(_drop(details.data, day)),
            builder: (context, candidates, rejected) => Container(
              width: width,
              height: 56,
              color: candidates.isNotEmpty
                  ? XuColors.of(context).selection
                  : null,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final event in _eventsOn(day, allDay: true).take(1))
                      Text(
                        '▦ ${event['title']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    for (final task
                        in _scheduledOn(day)
                            .where(
                              (task) =>
                                  CalendarPlanLogic.taskBlock(task) == null &&
                                  !CalendarPlanLogic.isProcessed(task),
                            )
                            .take(2))
                      InkWell(
                        onTap: () => _showArrange(task, day: day),
                        child: Text(
                          '${task['title']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );

  Widget _timeColumn(BuildContext context, DateTime day, double width) {
    final tasks = _scheduledOn(day)
        .where((task) => CalendarPlanLogic.taskBlock(task) != null)
        .toList();
    final dayEvents = _eventsOn(day, allDay: false);
    final entries = <String, CalendarInterval>{
      for (final task in tasks)
        '${task['id']}': CalendarPlanLogic.taskBlock(task)!,
      for (final event in dayEvents)
        'event:${event['id']}': CalendarPlanLogic.eventBlock(event)!,
    };
    final lanes = CalendarPlanLogic.lanes(entries);
    final dayStart = DateTime(day.year, day.month, day.day, 8);
    final dayEnd = DateTime(day.year, day.month, day.day, 21);
    Widget? block(
      String key,
      CalendarInterval interval,
      String title,
      String subtitle,
      bool external,
      VoidCallback? onTap,
      Map<String, dynamic>? task,
    ) {
      if (!interval.end.isAfter(dayStart) || !interval.start.isBefore(dayEnd)) {
        return null;
      }
      final clippedStart = interval.start.isBefore(dayStart)
          ? dayStart
          : interval.start;
      final clippedEnd = interval.end.isAfter(dayEnd) ? dayEnd : interval.end;
      final top = clippedStart.difference(dayStart).inMinutes / 60 * 64;
      final height = math.max(
        28.0,
        clippedEnd.difference(clippedStart).inMinutes / 60 * 64,
      );
      final lane = lanes[key] ?? (0, 1);
      final laneWidth = width / lane.$2;
      final content = Material(
        color: external
            ? XuColors.of(context).muted
            : XuColors.of(context).selection,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              border: Border.all(
                color: external
                    ? XuColors.of(context).border
                    : Theme.of(context).colorScheme.primary,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
                if (height > 45)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.labelSmall,
                  ),
              ],
            ),
          ),
        ),
      );
      return Positioned(
        left: lane.$1 * laneWidth + 3,
        top: top,
        width: laneWidth - 6,
        height: height,
        child: task == null ? content : _dragSource(task, content),
      );
    }

    return SizedBox(
      width: width,
      height: 13 * 64,
      child: Stack(
        children: [
          for (var hour = 8; hour < 21; hour++)
            Positioned(
              top: (hour - 8) * 64.0,
              left: 0,
              right: 0,
              height: 64,
              child: DragTarget<String>(
                onWillAcceptWithDetails: (details) => _canDrop(details.data),
                onAcceptWithDetails: (details) =>
                    unawaited(_drop(details.data, day, hour: hour)),
                builder: (context, candidates, rejected) => InkWell(
                  onDoubleTap: () => widget.onAddTask(
                    DateTime(day.year, day.month, day.day, hour),
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: candidates.isNotEmpty
                          ? XuColors.of(context).selection
                          : null,
                      border: Border(
                        top: BorderSide(color: XuColors.of(context).border),
                        left: BorderSide(color: XuColors.of(context).border),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          for (final task in tasks)
            ?block(
              '${task['id']}',
              CalendarPlanLogic.taskBlock(task)!,
              '${task['title']}',
              '${_clock(CalendarPlanLogic.taskBlock(task)!.start)}–${_clock(CalendarPlanLogic.taskBlock(task)!.end)}',
              false,
              () => widget.onEditTask(task),
              task,
            ),
          for (final event in dayEvents)
            ?block(
              'event:${event['id']}',
              CalendarPlanLogic.eventBlock(event)!,
              '${event['title']}',
              '${event['calendarTitle'] ?? '系统日历'} · 只读',
              true,
              null,
              null,
            ),
        ],
      ),
    );
  }

  Widget _seriesPanel(BuildContext context) {
    final colors = XuColors.of(context);
    final roots = _roots.where((root) {
      if (!waitingOnly) return true;
      final members = [root, ..._childrenOf(root)];
      return CalendarPlanLogic.executable(members).any(
        (task) =>
            !CalendarPlanLogic.isProcessed(task) &&
            CalendarPlanLogic.taskBlock(task) == null,
      );
    }).toList();
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    '任务系列',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton.outlined(
                  tooltip: '添加事项',
                  onPressed: () => widget.onAddTask(selectedDate),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('全部')),
                ButtonSegment(value: true, label: Text('待安排')),
              ],
              selected: {waitingOnly},
              showSelectedIcon: false,
              onSelectionChanged: (value) =>
                  setState(() => waitingOnly = value.first),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: roots.isEmpty
                ? Center(
                    child: Text(
                      '暂无任务系列',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.all(12),
                    children: [
                      for (final root in roots)
                        _seriesCard(context, root, colors),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _seriesCard(
    BuildContext context,
    Map<String, dynamic> root,
    XuColors colors,
  ) {
    final children = _childrenOf(root);
    final isSeries = children.isNotEmpty;
    final id = '${root['id']}';
    final expanded = expandedRoots.contains(id);
    final direct = children
        .where((task) => task['parentTaskID'] == root['id'])
        .toList();
    final completed = direct
        .where((task) => task['status'] == 'completed')
        .length;
    final due = CalendarPlanLogic.parse(root['dueDate']);
    return Card(
      color: selectedRootId == id ? colors.selection : null,
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (isSeries)
                  IconButton(
                    tooltip: expanded
                        ? '收起${root['title']}'
                        : '展开${root['title']}',
                    onPressed: () => setState(
                      () => expanded
                          ? expandedRoots.remove(id)
                          : expandedRoots.add(id),
                    ),
                    icon: Icon(
                      expanded ? Icons.expand_more : Icons.chevron_right,
                    ),
                  ),
                Expanded(
                  child: _dragSource(
                    root,
                    InkWell(
                      onTap: () => setState(
                        () => selectedRootId = selectedRootId == id ? null : id,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${root['title']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          Text(
                            isSeries
                                ? '$completed/${direct.length} 已完成${due == null ? '' : ' · 截止 ${_shortDate(due)}'}'
                                : _taskDescription(root),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: '任务操作',
                  onSelected: (action) =>
                      _taskAction(action, root, isSeries: isSeries),
                  itemBuilder: (_) => [
                    const PopupMenuItem(value: 'edit', child: Text('编辑')),
                    if (isSeries)
                      const PopupMenuItem(
                        value: 'moveSeries',
                        child: Text('移动整个系列'),
                      )
                    else ...[
                      const PopupMenuItem(
                        value: 'arrange',
                        child: Text('安排时间'),
                      ),
                      if (CalendarPlanLogic.taskBlock(root) != null)
                        const PopupMenuItem(
                          value: 'clearBlock',
                          child: Text('取消时间块'),
                        ),
                      const PopupMenuItem(
                        value: 'unschedule',
                        child: Text('移回待安排'),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            if (isSeries && expanded)
              for (final task in children) _seriesChild(context, task, root),
            if (!isSeries && !CalendarPlanLogic.isProcessed(root))
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _showArrange(root),
                  child: const Text('安排'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _seriesChild(
    BuildContext context,
    Map<String, dynamic> task,
    Map<String, dynamic> root,
  ) {
    final block = CalendarPlanLogic.taskBlock(task);
    final planned = CalendarPlanLogic.plannedDate(task);
    final selected = planned != null && _sameDay(planned, selectedDate);
    return Container(
      color: selected
          ? XuColors.of(context).selection.withValues(alpha: 0.45)
          : null,
      padding: const EdgeInsets.only(left: 20, top: 6, bottom: 6),
      child: Row(
        children: [
          Icon(
            task['status'] == 'completed'
                ? Icons.check_circle
                : block == null
                ? Icons.circle_outlined
                : Icons.schedule,
            size: 18,
            color: task['status'] == 'completed'
                ? Colors.green
                : Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _dragSource(
              task,
              InkWell(
                onTap: () {
                  if (block != null) {
                    setState(
                      () => selectedDate = CalendarPlanLogic.day(block.start),
                    );
                  }
                  widget.onEditTask(task);
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${task['title']}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _taskDescription(task),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: '子任务操作',
            onSelected: (action) => _taskAction(action, task),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑')),
              const PopupMenuItem(value: 'arrange', child: Text('安排时间')),
              if (block != null)
                const PopupMenuItem(value: 'clearBlock', child: Text('取消时间块')),
              const PopupMenuItem(value: 'unschedule', child: Text('移回待安排')),
            ],
          ),
        ],
      ),
    );
  }

  String _taskDescription(Map<String, dynamic> task) {
    final block = CalendarPlanLogic.taskBlock(task);
    if (block != null) {
      return '${_shortDate(block.start)} ${_clock(block.start)}–${_clock(block.end)}';
    }
    final planned = CalendarPlanLogic.plannedDate(task);
    final minutes = (task['estimatedMinutes'] as num?)?.toInt() ?? 30;
    return planned == null
        ? '待安排日期 · $minutes 分钟'
        : '${_shortDate(planned)} · 待定时 · $minutes 分钟';
  }

  void _taskAction(
    String action,
    Map<String, dynamic> task, {
    bool isSeries = false,
  }) {
    switch (action) {
      case 'edit':
        widget.onEditTask(task);
      case 'arrange':
        _showArrange(task);
      case 'moveSeries':
        _showMoveSeries(task);
      case 'clearBlock':
        _clearBlock(task, keepDate: true);
      case 'unschedule':
        _clearBlock(task, keepDate: false);
    }
  }

  Future<void> _showArrange(
    Map<String, dynamic> task, {
    DateTime? day,
    int? hour,
  }) async {
    if (task['planLocked'] == true || CalendarPlanLogic.isProcessed(task)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已处理或锁定的任务不能重新安排')));
      return;
    }
    final oldBlock = CalendarPlanLogic.taskBlock(task);
    final base =
        day ??
        oldBlock?.start ??
        CalendarPlanLogic.plannedDate(task) ??
        selectedDate;
    var start = DateTime(
      base.year,
      base.month,
      base.day,
      hour ?? oldBlock?.start.hour ?? 9,
      hour == null ? oldBlock?.start.minute ?? 0 : 0,
    );
    final now = DateTime.now();
    if (hour == null &&
        oldBlock == null &&
        _sameDay(base, now) &&
        start.isBefore(now)) {
      start = DateTime.fromMillisecondsSinceEpoch(
        ((now.millisecondsSinceEpoch + 899999) ~/ 900000) * 900000,
      );
    }
    var duration =
        oldBlock?.minutes ?? (task['estimatedMinutes'] as num?)?.toInt() ?? 30;
    duration = duration.clamp(15, 480);
    var hasTime = hour != null || oldBlock != null;
    var allowConflict = false;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) {
          final end = start.add(Duration(minutes: duration));
          final conflicts = hasTime
              ? CalendarPlanLogic.conflicts(
                  CalendarInterval(start, end),
                  '${task['id']}',
                  widget.tasks,
                  events,
                )
              : <String>[];
          final due = CalendarPlanLogic.parse(task['dueDate']);
          final unmet = (task['dependencyIDs'] as List? ?? [])
              .map(
                (id) => widget.tasks
                    .where((row) => '${row['id']}' == '$id')
                    .firstOrNull,
              )
              .where((row) => row != null && row['status'] != 'completed')
              .map((row) => '${row!['title']}')
              .toList();
          final suggestions = <CalendarInterval>[];
          if (hasTime) {
            for (
              var offset = 0;
              offset < 7 && suggestions.length < 3;
              offset++
            ) {
              final date = CalendarPlanLogic.addDays(
                CalendarPlanLogic.day(start),
                offset,
              );
              for (final slot in CalendarPlanLogic.availability(
                date,
                hours,
                widget.tasks.where((row) => row['id'] != task['id']).toList(),
                events,
              )) {
                final candidate = DateTime.fromMillisecondsSinceEpoch(
                  ((slot.start.millisecondsSinceEpoch + 899999) ~/ 900000) *
                      900000,
                );
                if (candidate
                    .add(Duration(minutes: duration))
                    .isAfter(slot.end)) {
                  continue;
                }
                if (due != null &&
                    candidate.add(Duration(minutes: duration)).isAfter(due)) {
                  continue;
                }
                suggestions.add(
                  CalendarInterval(
                    candidate,
                    candidate.add(Duration(minutes: duration)),
                  ),
                );
                if (suggestions.length == 3) break;
              }
            }
          }
          return AlertDialog(
            title: Text('安排时间 · ${task['title']}'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('指定执行时间'),
                      value: hasTime,
                      onChanged: (value) => update(() {
                        hasTime = value;
                        allowConflict = false;
                      }),
                    ),
                    ListTile(
                      title: const Text('计划日期'),
                      subtitle: Text(_shortDate(start)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialog,
                          initialDate: start,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          update(() {
                            start = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              start.hour,
                              start.minute,
                            );
                            allowConflict = false;
                          });
                        }
                      },
                    ),
                    if (hasTime) ...[
                      ListTile(
                        title: const Text('开始时间'),
                        subtitle: Text(_clock(start)),
                        trailing: const Icon(Icons.schedule),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: dialog,
                            initialTime: TimeOfDay.fromDateTime(start),
                          );
                          if (picked != null) {
                            update(() {
                              start = DateTime(
                                start.year,
                                start.month,
                                start.day,
                                picked.hour,
                                picked.minute,
                              );
                              allowConflict = false;
                            });
                          }
                        },
                      ),
                      Row(
                        children: [
                          const Text('预留时长'),
                          const Spacer(),
                          IconButton(
                            tooltip: '减少15分钟',
                            onPressed: duration > 15
                                ? () => update(() => duration -= 15)
                                : null,
                            icon: const Icon(Icons.remove),
                          ),
                          Text('$duration 分钟'),
                          IconButton(
                            tooltip: '增加15分钟',
                            onPressed: duration < 480
                                ? () => update(() => duration += 15)
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                      Text(
                        '结束 ${_shortDate(end)} ${_clock(end)} · 预计工作量 ${(task['estimatedMinutes'] as num?)?.toInt() ?? 30} 分钟',
                      ),
                      if (suggestions.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text('可选空档'),
                        for (final slot in suggestions)
                          TextButton(
                            onPressed: () => update(() {
                              start = slot.start;
                              allowConflict = false;
                            }),
                            child: Text(
                              '${_shortDate(slot.start)} ${_clock(slot.start)}–${_clock(slot.end)}',
                            ),
                          ),
                      ],
                    ],
                    if (conflicts.isNotEmpty) ...[
                      Text(
                        '与 ${conflicts.join('、')} 重叠',
                        style: TextStyle(
                          color: Theme.of(dialog).colorScheme.error,
                        ),
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('仍然保留重叠安排'),
                        value: allowConflict,
                        onChanged: (value) =>
                            update(() => allowConflict = value == true),
                      ),
                    ],
                    if (unmet.isNotEmpty) Text('前置事项未完成：${unmet.join('、')}'),
                    if (due != null && hasTime && end.isAfter(due))
                      Text(
                        '安排晚于截止时间；截止日期不会改变',
                        style: TextStyle(
                          color: Theme.of(dialog).colorScheme.error,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: saving || (conflicts.isNotEmpty && !allowConflict)
                    ? null
                    : () async {
                        update(() => saving = true);
                        final after = Map<String, dynamic>.from(task)
                          ..['scheduledFor'] = CalendarPlanLogic.day(start)
                              .toIso8601String()
                          ..['status'] = task['status'] == 'unscheduled'
                              ? 'pending'
                              : task['status']
                          ..['timeBlock'] = hasTime
                              ? {
                                  'id':
                                      (task['timeBlock'] is Map
                                          ? task['timeBlock']['id']
                                          : null) ??
                                      newId(),
                                  'start': start.toIso8601String(),
                                  'end': end.toIso8601String(),
                                }
                              : null;
                        final saved = await _applyChanges(
                          [Map<String, dynamic>.from(task)],
                          [after],
                        );
                        if (saved && dialog.mounted) {
                          Navigator.pop(dialog);
                        } else if (dialog.mounted) {
                          update(() => saving = false);
                        }
                      },
                child: const Text('保存安排'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showMoveSeries(
    Map<String, dynamic> root, {
    DateTime? day,
  }) async {
    var target = day ?? selectedDate;
    var accepted = false;
    var saving = false;
    var checkingDestination = connected;
    var destinationRequested = false;
    var destinationRequest = 0;
    String? destinationError;
    List<Map<String, dynamic>> destinationEvents = [];
    Future<void> refreshDestination(
      BuildContext dialog,
      StateSetter update,
    ) async {
      if (!connected) return;
      final request = ++destinationRequest;
      final planned =
          _childrenOf(root)
              .where(
                (row) =>
                    !CalendarPlanLogic.isProcessed(row) &&
                    row['planLocked'] != true &&
                    row['startedAt'] == null,
              )
              .map((row) => CalendarPlanLogic.plannedDate(row))
              .whereType<DateTime>()
              .toList()
            ..sort();
      final spanDays = planned.isEmpty
          ? 1
          : CalendarPlanLogic.daysBetween(planned.last, planned.first) + 2;
      try {
        final loaded = await NativeBridge.calendarEvents(
          CalendarPlanLogic.day(target),
          DateTime(target.year, target.month, target.day + spanDays),
        );
        if (dialog.mounted && request == destinationRequest) {
          update(() {
            destinationEvents = loaded;
            checkingDestination = false;
            destinationError = null;
            accepted = false;
          });
        }
      } catch (error) {
        if (dialog.mounted && request == destinationRequest) {
          update(() {
            destinationEvents = [];
            checkingDestination = false;
            destinationError = '目标日期的系统日程读取失败：$error';
            accepted = false;
          });
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) {
          if (connected && !destinationRequested) {
            destinationRequested = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (dialog.mounted) {
                unawaited(refreshDestination(dialog, update));
              }
            });
          }
          final members = _childrenOf(root);
          final parentIds = members
              .map((row) => '${row['parentTaskID']}')
              .toSet();
          final movable = members
              .where(
                (row) =>
                    !parentIds.contains('${row['id']}') &&
                    !CalendarPlanLogic.isProcessed(row) &&
                    row['planLocked'] != true &&
                    row['startedAt'] == null &&
                    CalendarPlanLogic.plannedDate(row) != null,
              )
              .toList();
          final skipped = members
              .where((row) => !movable.any((item) => item['id'] == row['id']))
              .map((row) {
                final reason = parentIds.contains('${row['id']}')
                    ? '系列汇总，不占用时间'
                    : CalendarPlanLogic.isProcessed(row)
                    ? '已处理'
                    : row['planLocked'] == true
                    ? '计划已锁定'
                    : row['startedAt'] != null
                    ? '已开始执行'
                    : '尚未安排日期';
                return '${row['title']}：$reason';
              })
              .toList();
          final dates =
              movable
                  .map(
                    (row) => CalendarPlanLogic.day(
                      CalendarPlanLogic.taskBlock(row)?.start ??
                          CalendarPlanLogic.plannedDate(row)!,
                    ),
                  )
                  .toList()
                ..sort();
          final offset = dates.isEmpty
              ? 0
              : CalendarPlanLogic.daysBetween(target, dates.first);
          final before = <Map<String, dynamic>>[];
          final after = <Map<String, dynamic>>[];
          final warnings = <String>[?destinationError];
          final conflictEvents = <String, Map<String, dynamic>>{
            for (final event in [...events, ...destinationEvents])
              '${event['id']}': event,
          }.values.toList();
          for (final task in movable) {
            final next = Map<String, dynamic>.from(task);
            final date = CalendarPlanLogic.plannedDate(task)!;
            next['scheduledFor'] = CalendarPlanLogic.addDays(
              date,
              offset,
            ).toIso8601String();
            final block = CalendarPlanLogic.taskBlock(task);
            if (block != null) {
              final moved = Map<String, dynamic>.from(task['timeBlock'] as Map)
                ..['start'] = CalendarPlanLogic.addDays(
                  block.start,
                  offset,
                ).toIso8601String()
                ..['end'] = CalendarPlanLogic.addDays(
                  block.end,
                  offset,
                ).toIso8601String();
              next['timeBlock'] = moved;
              final conflicts = CalendarPlanLogic.conflicts(
                CalendarInterval(
                  CalendarPlanLogic.parse(moved['start'])!,
                  CalendarPlanLogic.parse(moved['end'])!,
                ),
                '${task['id']}',
                widget.tasks
                    .where(
                      (row) => !movable.any((item) => item['id'] == row['id']),
                    )
                    .toList(),
                conflictEvents,
              );
              if (conflicts.isNotEmpty) {
                warnings.add('${task['title']}：与 ${conflicts.join('、')} 重叠');
              }
            }
            final due = CalendarPlanLogic.parse(task['dueDate']);
            if (block != null &&
                due != null &&
                CalendarPlanLogic.parse((next['timeBlock'] as Map)['end'])!
                    .isAfter(due)) {
              warnings.add('${task['title']}：执行时间晚于截止时间');
            } else if (block == null &&
                due != null &&
                CalendarPlanLogic.day(
                  CalendarPlanLogic.parse(next['scheduledFor'])!,
                ).isAfter(CalendarPlanLogic.day(due))) {
              warnings.add('${task['title']}：计划晚于截止日期');
            }
            final unmet = (task['dependencyIDs'] as List? ?? [])
                .map(
                  (id) => widget.tasks
                      .where(
                        (row) =>
                            '${row['id']}' == '$id' &&
                            row['status'] != 'completed',
                      )
                      .firstOrNull,
                )
                .whereType<Map<String, dynamic>>()
                .map((row) => '${row['title']}')
                .toList();
            if (unmet.isNotEmpty) {
              warnings.add('${task['title']}：前置事项未完成（${unmet.join('、')}）');
            }
            if (next['scheduledFor'] != task['scheduledFor']) {
              before.add(Map<String, dynamic>.from(task));
              after.add(next);
            }
          }
          for (final moved in after) {
            final block = CalendarPlanLogic.taskBlock(moved);
            if (block == null) continue;
            final peers = after
                .where((row) => row['id'] != moved['id'])
                .toList();
            final conflicts = CalendarPlanLogic.conflicts(
              block,
              '${moved['id']}',
              peers,
              [],
            );
            if (conflicts.isNotEmpty) {
              warnings.add('${moved['title']}：与 ${conflicts.join('、')} 重叠');
            }
          }
          return AlertDialog(
            title: Text('移动系列 · ${root['title']}'),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('以最早安排的子任务为起点；保留相对日期与具体时刻，截止日期不变。'),
                    ListTile(
                      title: const Text('系列新起点'),
                      subtitle: Text(_shortDate(target)),
                      trailing: const Icon(Icons.calendar_today_outlined),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: dialog,
                          initialDate: target,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null && dialog.mounted) {
                          update(() {
                            target = picked;
                            accepted = false;
                            checkingDestination = connected;
                            destinationEvents = [];
                            destinationError = null;
                          });
                          if (connected) {
                            unawaited(refreshDestination(dialog, update));
                          }
                        }
                      },
                    ),
                    for (var i = 0; i < before.length; i++)
                      ListTile(
                        title: Text('${before[i]['title']}'),
                        subtitle: Text(
                          '${_taskDescription(before[i])} → ${_taskDescription(after[i])}',
                        ),
                      ),
                    for (final item in skipped)
                      Text(
                        '跳过 $item',
                        style: Theme.of(dialog).textTheme.bodySmall,
                      ),
                    if (before.isEmpty) const Text('没有可移动的子任务'),
                    if (checkingDestination)
                      const LinearProgressIndicator(
                        semanticsLabel: '正在核对目标日期的系统日程',
                      ),
                    if (warnings.isNotEmpty) ...[
                      for (final warning in warnings)
                        Text(
                          warning,
                          style: TextStyle(
                            color: Theme.of(dialog).colorScheme.error,
                          ),
                        ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('我已检查以上影响，仍然移动'),
                        value: accepted,
                        onChanged: (value) =>
                            update(() => accepted = value == true),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialog),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed:
                    saving ||
                        checkingDestination ||
                        before.isEmpty ||
                        (warnings.isNotEmpty && !accepted)
                    ? null
                    : () async {
                        update(() => saving = true);
                        final saved = await _applyChanges(before, after);
                        if (saved && dialog.mounted) {
                          Navigator.pop(dialog);
                        } else if (dialog.mounted) {
                          update(() => saving = false);
                        }
                      },
                child: const Text('保存系列安排'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showWorkHours() async {
    var startHour = hours.startHour;
    var endHour = hours.endHour;
    var daysMask = hours.daysMask;
    var lunch = hours.lunchBreak;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialog) => StatefulBuilder(
        builder: (dialog, update) => AlertDialog(
          title: const Text('可安排工作时段'),
          content: SizedBox(
            width: 500,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('日历的可用时间和最长连续空档按这里计算。'),
                  Row(
                    children: [
                      const Text('开始'),
                      const Spacer(),
                      IconButton(
                        tooltip: '开始提前一小时',
                        onPressed: startHour > 8
                            ? () => update(() => startHour--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text('${startHour.toString().padLeft(2, '0')}:00'),
                      IconButton(
                        tooltip: '开始推后一小时',
                        onPressed: startHour < 20
                            ? () => update(() => startHour++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Text('结束'),
                      const Spacer(),
                      IconButton(
                        tooltip: '结束提前一小时',
                        onPressed: endHour > 9
                            ? () => update(() => endHour--)
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text('${endHour.toString().padLeft(2, '0')}:00'),
                      IconButton(
                        tooltip: '结束推后一小时',
                        onPressed: endHour < 21
                            ? () => update(() => endHour++)
                            : null,
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('12:00–13:00 午休'),
                    value: lunch,
                    onChanged: (value) => update(() => lunch = value),
                  ),
                  const Text('每周可安排日期'),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (var i = 0; i < 7; i++)
                        FilterChip(
                          label: Text('周${'日一二三四五六'[i]}'),
                          selected: daysMask & (1 << i) != 0,
                          onSelected: (selected) => update(
                            () => selected
                                ? daysMask |= 1 << i
                                : daysMask &= ~(1 << i),
                          ),
                        ),
                    ],
                  ),
                  if (startHour >= endHour) const Text('结束时间需晚于开始时间'),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(dialog),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving || startHour >= endHour || daysMask == 0
                  ? null
                  : () async {
                      update(() => saving = true);
                      final next = CalendarWorkHours(
                        startHour: startHour,
                        endHour: endHour,
                        daysMask: daysMask,
                        lunchBreak: lunch,
                      );
                      try {
                        await vm.put('settings', {
                          ...?vm
                              .items('settings')
                              .where((row) => row['id'] == 'preferences')
                              .firstOrNull,
                          'id': 'preferences',
                          ...next.toJson(),
                        });
                        if (mounted) setState(() => hours = next);
                        if (dialog.mounted) Navigator.pop(dialog);
                      } catch (error) {
                        if (dialog.mounted) {
                          ScaffoldMessenger.of(dialog)
                              .showSnackBar(SnackBar(content: Text('$error')));
                          update(() => saving = false);
                        }
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
