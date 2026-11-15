import 'package:flutter/material.dart';

class XuCommand {
  const XuCommand(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

const xuCommands = <XuCommand>[
  XuCommand('add', '新增待办事项', Icons.add_circle_outline),
  XuCommand('completed', '记录已完成事项', Icons.check_circle_outline),
  XuCommand('ai', 'AI 生成任务', Icons.auto_awesome),
  XuCommand('blueprint', '创建蓝图', Icons.account_tree_outlined),
  XuCommand('aiBlueprint', 'AI 生成完整蓝图', Icons.auto_awesome),
  XuCommand('report', '生成今日日报', Icons.description_outlined),
  XuCommand('today', '打开今日', Icons.wb_sunny_outlined),
  XuCommand('blueprints', '打开蓝图', Icons.account_tree_outlined),
  XuCommand('anniversaries', '打开纪念日', Icons.favorite_border),
  XuCommand('widget', '打开桌面小组件', Icons.widgets_outlined),
  XuCommand('settings', '打开设置', Icons.settings_outlined),
];

Future<String?> showXuCommandPalette(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (context) => const _CommandPaletteDialog(),
    );

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog();

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  String query = '';

  @override
  Widget build(BuildContext context) {
    final term = query.trim().toLowerCase();
    final commands = term.isEmpty
        ? xuCommands
        : xuCommands
              .where((command) => command.label.toLowerCase().contains(term))
              .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '搜索命令',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) => setState(() => query = value),
                onSubmitted: (_) {
                  if (commands.isNotEmpty) {
                    Navigator.pop(context, commands.first.key);
                  }
                },
              ),
              const SizedBox(height: 12),
              Flexible(
                child: commands.isEmpty
                    ? const Center(child: Text('没有匹配的命令'))
                    : ListView.builder(
                        shrinkWrap: true,
                        itemCount: commands.length,
                        itemBuilder: (context, index) {
                          final command = commands[index];
                          return ListTile(
                            leading: Icon(command.icon),
                            title: Text(command.label),
                            trailing: const Icon(Icons.keyboard_return),
                            onTap: () => Navigator.pop(context, command.key),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
