import 'package:flutter/material.dart';

import '../xu_theme.dart';

class XuNavigationItem {
  const XuNavigationItem(this.key, this.label, this.icon);
  final String key, label;
  final IconData icon;
}

class XuSidebar extends StatelessWidget {
  const XuSidebar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });
  final List<XuNavigationItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = XuColors.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    Widget section(String title, List<XuNavigationItem> entries) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            title.isEmpty ? 4 : 14,
            16,
            title.isEmpty ? 0 : 6,
          ),
          child: Text(title, style: Theme.of(context).textTheme.labelSmall),
        ),
        for (final entry in entries)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
            child: Material(
              color: selected == entry.key
                  ? colors.selection
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => onSelect(entry.key),
                child: Semantics(
                  button: true,
                  selected: selected == entry.key,
                  child: SizedBox(
                    height: 38,
                    child: Row(
                      children: [
                        const SizedBox(width: 12),
                        Icon(
                          entry.icon,
                          size: 20,
                          color: selected == entry.key
                              ? primary
                              : colors.secondaryText,
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Text(
                            entry.label,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: selected == entry.key
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: selected == entry.key
                                  ? primary
                                  : colors.secondaryText,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
    final byKey = {for (final item in items) item.key: item};
    final work = [
      for (final key in [
        'today',
        'tasks',
        'categories',
        'calendar',
        'blueprints',
        'quadrants',
      ])
        byKey[key]!,
    ];
    final records = [
      for (final key in ['inbox', 'anniversaries', 'processed', 'reports'])
        byKey[key]!,
    ];
    final settings = items.firstWhere((e) => e.key == 'settings');
    return Container(
      width: 216,
      color: colors.sidebar,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 54, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: primary,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: const Text(
                    '序',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('序', style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        '把计划变成行动',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              children: [section('工作区', work), section('记录', records)],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 18),
            child: section('', [settings]),
          ),
        ],
      ),
    );
  }
}

class XuTopBar extends StatelessWidget {
  const XuTopBar({
    super.key,
    required this.section,
    required this.title,
    required this.onSearch,
    required this.onPalette,
  });
  final String section, title;
  final VoidCallback onSearch, onPalette;

  @override
  Widget build(BuildContext context) {
    final colors = XuColors.of(context);
    return Container(
      height: 72,
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
      decoration: BoxDecoration(
        color: colors.topbar,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.5)),
        ),
      ),
      child: Row(
        children: [
          Text(
            section,
            style: TextStyle(color: colors.secondaryText, fontSize: 14),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Icon(
              Icons.chevron_right,
              size: 18,
              color: colors.secondaryText,
            ),
          ),
          Text(
            title,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const Spacer(),
          IconButton(
            tooltip: '搜索事项',
            onPressed: onSearch,
            icon: const Icon(Icons.search, size: 20),
          ),
          IconButton(
            tooltip: '快速操作',
            onPressed: onPalette,
            icon: const Icon(Icons.palette_outlined, size: 20),
          ),
          const SizedBox(width: 4),
          Text(
            '石墨',
            style: TextStyle(color: colors.secondaryText, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class XuEmptyState extends StatelessWidget {
  const XuEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.actionIcon = Icons.add,
    this.shortcutHint,
  });
  final IconData icon;
  final String title;
  final String? description, actionLabel;
  final VoidCallback? onAction;
  final IconData actionIcon;
  final String? shortcutHint;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 24),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (description != null) ...[
            const SizedBox(height: 10),
            Text(
              description!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onAction,
              icon: Icon(actionIcon),
              label: Text(actionLabel!),
            ),
          ],
          if (shortcutHint != null) ...[
            const SizedBox(height: 12),
            Text(shortcutHint!, style: Theme.of(context).textTheme.labelSmall),
          ],
        ],
      ),
    ),
  );
}
