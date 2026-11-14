enum ReportLengthPreset {
  short('简短', 125, 180),
  standard('标准', 180, 300),
  detailed('详细', 300, 500),
  custom('自定义', 125, 180);

  const ReportLengthPreset(this.label, this.minimum, this.maximum);
  final String label;
  final int minimum;
  final int maximum;
}

class ReportRules {
  static bool validRange(int minimum, int maximum) =>
      minimum >= 50 && minimum <= 3000 && maximum >= minimum && maximum <= 5000;

  static int length(String content) => content.trim().runes.length;

  static String? warning(String content, int minimum, int maximum) {
    if (!validRange(minimum, maximum)) {
      return '最少字数须在 50～3000 之间；最多字数不得小于最少字数且不超过 5000。';
    }
    final count = length(content);
    if (count < minimum) return '当前 $count 字，少于设定下限 $minimum 字。';
    if (count > maximum) return '当前 $count 字，超过设定上限 $maximum 字。';
    return null;
  }

  static List<Map<String, dynamic>> relevantTasks(
    List<Map<String, dynamic>> tasks,
    DateTime day,
  ) {
    bool sameDay(Object? value) {
      final date = DateTime.tryParse('$value')?.toLocal();
      return date != null &&
          date.year == day.year &&
          date.month == day.month &&
          date.day == day.day;
    }

    return tasks.where((task) {
      return sameDay(task['scheduledFor']) ||
          sameDay(task['completedAt']) ||
          sameDay(task['statusChangedAt']);
    }).toList();
  }

  static String prompt(
    List<Map<String, dynamic>> tasks, {
    required DateTime day,
    required String supplement,
    required int minimum,
    required int maximum,
    List<Map<String, dynamic>> blueprints = const [],
  }) {
    final relevant = _withBlueprintProjects(
      relevantTasks(tasks, day),
      blueprints,
    );
    final progress = _group(
      relevant.where((task) => task['reportCategory'] != 'collaboration'),
    );
    final collaboration = _group(
      relevant.where((task) => task['reportCategory'] == 'collaboration'),
    );
    final pending = _group(
      relevant.where(
        (task) =>
            task['status'] != 'completed' && task['status'] != 'cancelled',
      ),
    );
    final date =
        '${day.year}年${day.month.toString().padLeft(2, '0')}月${day.day.toString().padLeft(2, '0')}日';
    return '''请基于以下任务数据生成 $date 的中文 Markdown 日报。不要编造事实。
全文控制在 $minimum～$maximum 字。只能按顺序使用以下三个一级编号：
1. 项目/测试/开发进度
2. 会议/方案/讨论
3. 明日重点事项规划
每段按项目归类，项目标题使用「- 【项目名称】」，下方用缩进列表记录事项。同一项目只出现一次。第三段按重要性列出待办及推进方向；没有待办时基于已完成事项规划。将补充信息融入对应章节。不要添加其他一级标题、寒暄或总结。

项目/测试/开发进度：
${progress.isEmpty ? '无' : progress}

会议/方案/讨论：
${collaboration.isEmpty ? '无' : collaboration}

明日重点待办：
${pending.isEmpty ? '无' : pending}

日报补充：
${supplement.trim().isEmpty ? '无' : supplement.trim()}''';
  }

  static String revisionPrompt(String draft, int minimum, int maximum) =>
      '请将下面日报调整到 $minimum～$maximum 字，严格保留三个一级编号与项目归类，不得编造事实，只返回修改后的日报。\n\n$draft';

  static String fallback(
    List<Map<String, dynamic>> tasks, {
    required DateTime day,
    required String supplement,
    List<Map<String, dynamic>> blueprints = const [],
  }) {
    final relevant = _withBlueprintProjects(
      relevantTasks(tasks, day),
      blueprints,
    );
    final progress = _group(
      relevant.where((task) => task['reportCategory'] != 'collaboration'),
    );
    final collaboration = _group(
      relevant.where((task) => task['reportCategory'] == 'collaboration'),
    );
    final pending = _group(
      relevant.where(
        (task) =>
            task['status'] != 'completed' && task['status'] != 'cancelled',
      ),
    );
    final context = supplement.trim();
    return '''1. 项目/测试/开发进度
${progress.isEmpty ? '- 【未归类项目】\n  - 当天没有记录项目、测试或开发事项。' : progress}

2. 会议/方案/讨论
${collaboration.isEmpty ? '- 【未归类项目】\n  - 当天没有记录会议、方案或讨论事项。' : collaboration}

3. 明日重点事项规划
${pending.isEmpty ? '- 【重点规划】\n  - 当前没有未完成事项，请在下一次计划时核对实际进度。' : pending}
${context.isEmpty ? '' : '\n- 【补充说明】\n  - $context'}''';
  }

  static String enforceMinimumLength(
    String report,
    String fallback,
    int minimum,
  ) {
    var result = length(report) >= minimum ? report.trim() : fallback.trim();
    const note = '\n  - 本日报依据已登记事项和补充信息整理；实际进度与后续安排以任务记录为准。';
    while (length(result) < minimum) {
      result += note;
    }
    return result;
  }

  static List<Map<String, dynamic>> _withBlueprintProjects(
    List<Map<String, dynamic>> tasks,
    List<Map<String, dynamic>> blueprints,
  ) {
    final names = {
      for (final blueprint in blueprints)
        '${blueprint['id']}': '${blueprint['name'] ?? ''}',
    };
    return tasks.map((task) {
      if ('${task['project'] ?? ''}'.trim().isNotEmpty) return task;
      final name = names['${task['blueprintID']}'];
      return name == null || name.trim().isEmpty
          ? task
          : {...task, 'project': name};
    }).toList();
  }

  static String _group(Iterable<Map<String, dynamic>> tasks) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final task in tasks) {
      final project = '${task['project'] ?? ''}'.trim();
      groups
          .putIfAbsent(project.isEmpty ? '未归类项目' : project, () => [])
          .add(task);
    }
    return (groups.keys.toList()..sort())
        .map((project) {
          final lines = groups[project]!
              .map((task) {
                final status = switch ('${task['status'] ?? 'pending'}') {
                  'completed' => '已完成',
                  'inProgress' => '进行中',
                  'blocked' => '已阻塞',
                  'postponed' => '已延期',
                  'cancelled' => '已取消',
                  _ => '待处理',
                };
                final note = '${task['notes'] ?? ''}'.trim();
                final blocker = '${task['blockReason'] ?? ''}'.trim();
                final title = '${task['title'] ?? ''}'.trim();
                final minutes = task['estimatedMinutes'];
                final quadrant = switch ('${task['quadrant'] ?? ''}') {
                  '1' || 'doNow' => '立即执行',
                  '2' || 'schedule' => '安排计划',
                  '3' || 'delegate' => '委派协作',
                  '4' || 'eliminate' => '暂缓处理',
                  _ => '',
                };
                final plan = [
                  if (quadrant.isNotEmpty) quadrant,
                  if (minutes is num && minutes > 0) '预计${minutes.toInt()}分钟',
                ].join('，');
                return '  - $status：$title${plan.isEmpty ? '' : '（$plan）'}${note.isEmpty ? '' : '；$note'}${blocker.isEmpty ? '' : '；阻塞原因：$blocker'}';
              })
              .join('\n');
          return '- 【$project】\n$lines';
        })
        .join('\n');
  }
}
