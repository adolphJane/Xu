class BlueprintTemplate {
  final String name;
  final String goal;
  final List<String> stages;
  const BlueprintTemplate(this.name, this.goal, this.stages);
}

const blueprintTemplates = <BlueprintTemplate>[
  BlueprintTemplate('软件开发', '从需求定义、开发验证到发布复盘，完成一个可交付的软件版本。', [
    '需求与设计',
    '开发与测试',
    '发布与复盘',
  ]),
  BlueprintTemplate('学习计划', '建立目标明确、可检查成果的学习闭环。', ['制定计划', '系统学习', '练习与验收']),
  BlueprintTemplate('健身计划', '通过循序渐进的训练与复盘达成健康目标。', ['体能评估', '基础训练', '强化与复测']),
  BlueprintTemplate('旅行计划', '完成行程决策、预订准备和出行检查。', ['目的地与预算', '预订与准备', '出行与回顾']),
];

double blueprintProgress(String id, List<Map<String, dynamic>> tasks) {
  final scoped = tasks
      .where(
        (task) => task['blueprintID'] == id && task['status'] != 'cancelled',
      )
      .toList();
  if (scoped.isEmpty) return 0;
  return scoped.where((task) => task['status'] == 'completed').length /
      scoped.length;
}
