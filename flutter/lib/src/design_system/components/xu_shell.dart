import 'package:flutter/material.dart';

import '../xu_theme.dart';

class XuNavigationItem {
  const XuNavigationItem(this.key, this.label, this.icon, this.selectedIcon);
  final String key, label;
  final IconData icon, selectedIcon;
}

class XuSidebar extends StatelessWidget {
  const XuSidebar({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
    this.desktop = true,
  });
  final List<XuNavigationItem> items;
  final String selected;
  final ValueChanged<String> onSelect;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = XuColors.of(context);
    final rule = colors.border.withValues(alpha: 0.75);
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 180);
    final byKey = {for (final item in items) item.key: item};

    Widget navigationButton(XuNavigationItem item, {bool footer = false}) {
      final active = selected == item.key;
      final foreground = active ? scheme.primary : scheme.onSurface;
      return MergeSemantics(
        child: Semantics(
          selected: active,
          child: TextButton(
            onPressed: () => onSelect(item.key),
            style:
                TextButton.styleFrom(
                  foregroundColor: foreground,
                  backgroundColor: active
                      ? colors.selection
                      : footer
                      ? colors.topbar
                      : null,
                  overlayColor: scheme.primary,
                  textStyle: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                  minimumSize: const Size(double.infinity, 40),
                  padding: const EdgeInsetsDirectional.fromSTEB(0, 8, 11, 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  animationDuration: duration,
                ).copyWith(
                  side: WidgetStateProperty.resolveWith(
                    (states) => states.contains(WidgetState.focused)
                        ? BorderSide(color: scheme.primary, width: 2)
                        : BorderSide(
                            color: footer && !active
                                ? rule
                                : Colors.transparent,
                          ),
                  ),
                ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: duration,
                  margin: const EdgeInsetsDirectional.only(start: 5, end: 8),
                  width: 3,
                  height: 16,
                  decoration: BoxDecoration(
                    color: active ? scheme.primary : Colors.transparent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Icon(
                  active ? item.selectedIcon : item.icon,
                  size: 19,
                  color: active ? foreground : colors.secondaryText,
                ),
                const SizedBox(width: 11),
                Expanded(child: Text(item.label)),
                if (footer && desktop)
                  ExcludeSemantics(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: Text('⌘,', style: theme.textTheme.labelSmall),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    Widget section(String title, List<String> keys) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 10, 6),
          child: Row(
            children: [
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Divider(height: 1, color: rule)),
            ],
          ),
        ),
        for (final key in keys)
          Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: navigationButton(byKey[key]!),
          ),
      ],
    );

    return Container(
      width: 216,
      decoration: BoxDecoration(
        color: colors.sidebar,
        border: BorderDirectional(end: BorderSide(color: rule)),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(17, desktop ? 41 : 12, 16, 12),
            child: Row(
              children: [
                Image.asset(
                  'macos/Runner/Assets.xcassets/XuIcon.appiconset/app_icon_128.png',
                  width: 46,
                  height: 46,
                  excludeFromSemantics: true,
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Text(
                    '序',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 7, 12, 12),
              children: [
                section('工作区', ['today', 'tasks', 'categories', 'calendar']),
                const SizedBox(height: 19),
                section('记录', [
                  'inbox',
                  'anniversaries',
                  'processed',
                  'reports',
                ]),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 14),
            child: navigationButton(byKey['settings']!, footer: true),
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
    this.compact = false,
    this.onUndo,
    this.onRedo,
  });
  final String section, title;
  final VoidCallback onSearch, onPalette;
  final VoidCallback? onUndo, onRedo;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final colors = XuColors.of(context);
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 52 : 64),
      padding: compact
          ? const EdgeInsetsDirectional.only(start: 16, end: 4)
          : const EdgeInsets.fromLTRB(20, 8, 20, 4),
      decoration: BoxDecoration(
        color: colors.topbar,
        border: Border(
          bottom: BorderSide(color: colors.border.withValues(alpha: 0.7)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                if (!compact && section.isNotEmpty) ...[
                  Text(section, style: Theme.of(context).textTheme.bodySmall),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: colors.secondaryText,
                  ),
                ],
                Text(title, style: Theme.of(context).textTheme.titleSmall),
              ],
            ),
          ),
          if (compact && (onUndo != null || onRedo != null))
            PopupMenuButton<VoidCallback>(
              tooltip: '操作历史',
              icon: const Icon(Icons.history_rounded, size: 21),
              onSelected: (action) => action(),
              itemBuilder: (context) => [
                if (onUndo != null)
                  PopupMenuItem(value: onUndo, child: const Text('撤销工作区操作')),
                if (onRedo != null)
                  PopupMenuItem(value: onRedo, child: const Text('重做工作区操作')),
              ],
            ),
          if (!compact && onUndo != null)
            IconButton(
              tooltip: '撤销工作区操作',
              onPressed: onUndo,
              icon: const Icon(Icons.undo, size: 20),
            ),
          if (!compact && onRedo != null)
            IconButton(
              tooltip: '重做工作区操作',
              onPressed: onRedo,
              icon: const Icon(Icons.redo, size: 20),
            ),
          Semantics(
            label: '搜索事项',
            child: IconButton(
              tooltip: '搜索事项',
              onPressed: onSearch,
              icon: const Icon(Icons.search_rounded, size: 20),
            ),
          ),
          if (compact)
            IconButton(
              tooltip: '快速操作',
              onPressed: onPalette,
              icon: const Icon(Icons.bolt_outlined, size: 22),
            )
          else
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              onPressed: onPalette,
              icon: const Icon(Icons.bolt_outlined, size: 19),
              label: const Text('快速操作'),
            ),
        ],
      ),
    );
  }
}

class XuPageHeader extends StatelessWidget {
  const XuPageHeader({
    super.key,
    required this.title,
    this.eyebrow,
    this.description,
    this.actions = const [],
  });

  final String title;
  final String? eyebrow, description;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 520 ||
            MediaQuery.textScalerOf(context).scale(14) > 18;
        final heading = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (eyebrow != null) ...[
              Text(
                eyebrow!,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Semantics(
              header: true,
              child: Text(title, style: theme.textTheme.headlineMedium),
            ),
            if (description != null) ...[
              const SizedBox(height: 5),
              Text(description!, style: theme.textTheme.bodySmall),
            ],
          ],
        );
        if (actions.isEmpty) return heading;
        final controls = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: actions,
        );
        return stacked
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [heading, const SizedBox(height: 10), controls],
              )
            : Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: constraints.maxWidth * 0.65,
                    ),
                    child: controls,
                  ),
                ],
              );
      },
    );
  }
}

class XuIconTile extends StatelessWidget {
  const XuIconTile(this.icon, {super.key, this.size = 40});

  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: BorderRadius.circular(size >= 64 ? 20 : 12),
    ),
    child: Icon(
      icon,
      size: size * 0.54,
      color: Theme.of(context).colorScheme.primary,
    ),
  );
}

class XuSectionCard extends StatelessWidget {
  const XuSectionCard({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.action,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              XuIconTile(icon, size: 36),
              Semantics(
                header: true,
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
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
          XuIconTile(icon, size: 70),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          if (description != null) ...[
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                description!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall,
              ),
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
