import 'package:flutter/material.dart';

import '../xu_theme.dart';
import 'xu_shell.dart';

class XuCompactNavigation extends StatelessWidget {
  const XuCompactNavigation({
    super.key,
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  final List<XuNavigationItem> items;
  final String selected;
  final ValueChanged<String> onSelect;

  static const _mainKeys = ['today', 'tasks', 'calendar', 'inbox'];

  @override
  Widget build(BuildContext context) {
    final colors = XuColors.of(context);
    final byKey = {for (final item in items) item.key: item};
    final mainItems = _mainKeys.map((key) => byKey[key]!).toList();
    final moreItems = items.where((item) => !_mainKeys.contains(item.key));
    final index = _mainKeys.indexOf(selected);

    return NavigationBar(
      height:
          64 + (MediaQuery.textScalerOf(context).scale(12) - 12).clamp(0, 16),
      backgroundColor: colors.topbar,
      indicatorColor: colors.selection,
      animationDuration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 180),
      selectedIndex: index == -1 ? mainItems.length : index,
      destinations: [
        for (final item in mainItems)
          NavigationDestination(
            label: item.key == 'calendar' ? '日历' : item.label,
            icon: Icon(item.icon),
            selectedIcon: Icon(item.selectedIcon),
          ),
        const NavigationDestination(
          label: '更多',
          icon: Icon(Icons.more_horiz_rounded),
        ),
      ],
      onDestinationSelected: (index) async {
        if (index < mainItems.length) {
          onSelect(mainItems[index].key);
          return;
        }

        final page = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          useSafeArea: true,
          builder: (sheet) => SafeArea(
            top: false,
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              children: [
                for (final item in moreItems)
                  ListTile(
                    title: Text(item.label),
                    leading: Icon(
                      selected == item.key ? item.selectedIcon : item.icon,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    selected: selected == item.key,
                    selectedTileColor: colors.selection,
                    onTap: () => Navigator.pop(sheet, item.key),
                  ),
              ],
            ),
          ),
        );
        if (context.mounted && page != null) onSelect(page);
      },
    );
  }
}
