import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'design_system/components/xu_shell.dart';

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
  XuCommand('blueprints', '按蓝图浏览事项', Icons.account_tree_outlined),
  XuCommand('quadrants', '按四象限浏览事项', Icons.grid_view_outlined),
  XuCommand('anniversaries', '打开纪念日', Icons.favorite_border),
  XuCommand('widget', '打开桌面小组件', Icons.widgets_outlined),
  XuCommand('settings', '打开设置', Icons.settings_outlined),
];

Future<String?> showXuCommandPalette(
  BuildContext context, {
  bool includeDesktopWidget = true,
}) => showDialog<String>(
  context: context,
  builder: (context) =>
      _CommandPaletteDialog(includeDesktopWidget: includeDesktopWidget),
);

class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({required this.includeDesktopWidget});

  final bool includeDesktopWidget;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  String query = '';
  int selected = 0;

  void move(List<XuCommand> commands, int direction) {
    if (commands.isEmpty) return;
    setState(
      () => selected = (selected + direction).clamp(0, commands.length - 1),
    );
    final key = GlobalObjectKey(commands[selected]);
    final row = key.currentContext;
    if (row != null) {
      Scrollable.ensureVisible(
        row,
        alignmentPolicy: direction > 0
            ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
            : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 180),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = query.trim().toLowerCase();
    final commands = xuCommands
        .where(
          (command) =>
              (widget.includeDesktopWidget || command.key != 'widget') &&
              command.label.toLowerCase().contains(term),
        )
        .toList();
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 460),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                      move(commands, 1),
                  const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                      move(commands, -1),
                },
                child: TextField(
                  autofocus: true,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.bolt_outlined),
                    labelText: '搜索命令',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() {
                    query = value;
                    selected = 0;
                  }),
                  onSubmitted: (_) {
                    if (commands.isNotEmpty) {
                      Navigator.pop(context, commands[selected].key);
                    }
                  },
                ),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: commands.isEmpty
                    ? const XuEmptyState(
                        icon: Icons.search_off_rounded,
                        title: '没有匹配的命令',
                      )
                    : SingleChildScrollView(
                        child: Column(
                          children: [
                            for (final (index, command) in commands.indexed)
                              ListTile(
                                key: GlobalObjectKey(command),
                                selected: index == selected,
                                selectedTileColor: Theme.of(context)
                                    .colorScheme
                                    .surfaceContainer,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                leading: Icon(command.icon),
                                title: Text(command.label),
                                trailing: index == selected
                                    ? const Icon(Icons.keyboard_return_rounded)
                                    : null,
                                onTap: () =>
                                    Navigator.pop(context, command.key),
                              ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
