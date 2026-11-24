import 'package:flutter/material.dart';

import 'design_system/components/xu_shell.dart';

typedef CategoryIcon = (String label, IconData icon);

const _groups = <String, Map<String, CategoryIcon>>{
  '常用': {
    'label': ('标签', Icons.label_outline),
    'star': ('星标', Icons.star_border_rounded),
    'flag': ('旗帜', Icons.flag_outlined),
    'bookmark': ('书签', Icons.bookmark_border_rounded),
    'calendar': ('日程', Icons.calendar_today_outlined),
    'alarm': ('提醒', Icons.alarm_rounded),
    'checklist': ('清单', Icons.checklist_rounded),
    'pin': ('置顶', Icons.push_pin_outlined),
    'archive': ('归档', Icons.inventory_2_outlined),
    'key': ('钥匙', Icons.key_outlined),
    'target': ('目标', Icons.track_changes_rounded),
    'lightbulb': ('灵感', Icons.lightbulb_outline_rounded),
  },
  '工作与项目': {
    'work': ('工作', Icons.work_outline),
    'folder': ('项目', Icons.folder_outlined),
    'meeting': ('会议', Icons.groups_outlined),
    'mail': ('邮件', Icons.mail_outline_rounded),
    'document': ('文档', Icons.description_outlined),
    'presentation': ('演示', Icons.slideshow_rounded),
    'chart': ('统计', Icons.bar_chart_rounded),
    'computer': ('电脑', Icons.computer_rounded),
    'code': ('开发', Icons.code_rounded),
    'design': ('设计', Icons.design_services_outlined),
    'workflow': ('流程', Icons.account_tree_outlined),
    'tools': ('工具', Icons.handyman_outlined),
  },
  '学习与研究': {
    'school': ('学习', Icons.school_outlined),
    'book': ('阅读', Icons.menu_book_outlined),
    'writing': ('写作', Icons.edit_note_rounded),
    'notebook': ('笔记', Icons.edit_document),
    'language': ('语言', Icons.translate_rounded),
    'science': ('科学', Icons.science_outlined),
    'math': ('数学', Icons.functions_rounded),
    'history': ('历史', Icons.history_edu_outlined),
    'question': ('问答', Icons.quiz_outlined),
    'library': ('资料', Icons.local_library_outlined),
    'research': ('研究', Icons.biotech_rounded),
    'award': ('成果', Icons.workspace_premium_outlined),
  },
  '生活与家庭': {
    'home': ('生活', Icons.home_outlined),
    'family': ('家人', Icons.family_restroom_rounded),
    'cooking': ('做饭', Icons.restaurant_menu_rounded),
    'coffee': ('咖啡', Icons.coffee_outlined),
    'shopping': ('采购', Icons.shopping_cart_outlined),
    'groceries': ('食材', Icons.shopping_basket_outlined),
    'cleaning': ('清洁', Icons.cleaning_services_outlined),
    'laundry': ('洗衣', Icons.local_laundry_service_outlined),
    'pets': ('宠物', Icons.pets_rounded),
    'garden': ('园艺', Icons.yard_outlined),
    'gift': ('礼物', Icons.card_giftcard_rounded),
    'birthday': ('生日', Icons.cake_outlined),
  },
  '健康与运动': {
    'favorite': ('健康', Icons.favorite_border),
    'fitness': ('健身', Icons.fitness_center_rounded),
    'running': ('跑步', Icons.directions_run_rounded),
    'walking': ('步行', Icons.directions_walk_rounded),
    'cycling': ('骑行', Icons.directions_bike_rounded),
    'swimming': ('游泳', Icons.pool_rounded),
    'basketball': ('篮球', Icons.sports_basketball_outlined),
    'yoga': ('冥想', Icons.self_improvement_rounded),
    'sleep': ('睡眠', Icons.bedtime_outlined),
    'medicine': ('用药', Icons.medication_outlined),
    'hospital': ('就医', Icons.local_hospital_outlined),
    'water': ('饮水', Icons.water_drop_outlined),
  },
  '旅行与出行': {
    'travel': ('旅行', Icons.luggage_outlined),
    'map': ('地图', Icons.map_outlined),
    'location': ('地点', Icons.location_on_outlined),
    'plane': ('航班', Icons.flight_rounded),
    'train': ('火车', Icons.train_outlined),
    'bus': ('公交', Icons.directions_bus_outlined),
    'car': ('驾车', Icons.directions_car_outlined),
    'boat': ('船只', Icons.directions_boat_outlined),
    'hotel': ('住宿', Icons.hotel_outlined),
    'camping': ('露营', Icons.cabin_outlined),
    'hiking': ('徒步', Icons.hiking_rounded),
    'cafe': ('探店', Icons.storefront_rounded),
  },
  '兴趣与创作': {
    'music': ('音乐', Icons.music_note_outlined),
    'headphones': ('播客', Icons.headphones_rounded),
    'movie': ('电影', Icons.movie_outlined),
    'photo': ('摄影', Icons.photo_camera_outlined),
    'drawing': ('绘画', Icons.brush_outlined),
    'palette': ('配色', Icons.palette_outlined),
    'gaming': ('游戏', Icons.sports_esports_outlined),
    'puzzle': ('拼图', Icons.extension_outlined),
    'theater': ('戏剧', Icons.theater_comedy_outlined),
    'craft': ('手工', Icons.content_cut_rounded),
    'microphone': ('录音', Icons.mic_none_rounded),
    'video': ('视频', Icons.videocam_outlined),
  },
  '财务与账务': {
    'wallet': ('钱包', Icons.account_balance_wallet_outlined),
    'budget': ('预算', Icons.calculate_outlined),
    'bill': ('账单', Icons.receipt_long_outlined),
    'payment': ('支付', Icons.credit_card_rounded),
    'savings': ('储蓄', Icons.savings_outlined),
    'bank': ('银行', Icons.account_balance_outlined),
    'income': ('收入', Icons.south_west_rounded),
    'expense': ('支出', Icons.north_east_rounded),
    'investment': ('投资', Icons.trending_up_rounded),
    'tax': ('税务', Icons.request_quote_outlined),
    'insurance': ('保险', Icons.shield_outlined),
    'subscription': ('订阅', Icons.autorenew_rounded),
  },
};

final _icons = {for (final group in _groups.values) ...group};

CategoryIcon categoryIconFor(String symbol) =>
    _icons[symbol] ?? _icons['label']!;

Future<String?> showCategoryIconPicker(BuildContext context, String selected) =>
    showDialog<String>(
      context: context,
      builder: (_) => _CategoryIconPicker(selected: selected),
    );

class _CategoryIconPicker extends StatefulWidget {
  const _CategoryIconPicker({required this.selected});

  final String selected;

  @override
  State<_CategoryIconPicker> createState() => _CategoryIconPickerState();
}

class _CategoryIconPickerState extends State<_CategoryIconPicker> {
  final _search = TextEditingController();
  late String _group = _groups.entries
      .firstWhere(
        (entry) => entry.value.containsKey(widget.selected),
        orElse: () => _groups.entries.first,
      )
      .key;
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _selectGroup(String group) {
    _search.clear();
    setState(() {
      _group = group;
      _query = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final results = {
      for (final group in _groups.entries)
        if (_query.isNotEmpty || group.key == _group)
          group.key: [
            for (final icon in group.value.entries)
              if (group.key.contains(_query) ||
                  icon.value.$1.contains(_query) ||
                  icon.key.toLowerCase().contains(_query))
                icon,
          ],
    }..removeWhere((_, icons) => icons.isEmpty);

    final scheme = theme.colorScheme;
    final searching = _query.isNotEmpty;
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: scheme.outline),
    );
    final size = MediaQuery.sizeOf(context);
    final compact = size.width < 540 || size.height < 450;
    final grid = results.isEmpty
        ? const XuEmptyState(icon: Icons.search_off_rounded, title: '没有找到匹配的图标')
        : LayoutBuilder(
            builder: (context, limits) {
              const gap = 8.0;
              final inset = compact ? 12.0 : 16.0;
              final available = limits.maxWidth - inset * 2;
              final minTile =
                  MediaQuery.textScalerOf(context).scale(14) *
                      (compact ? 3 : 4) +
                  (compact ? 18 : 40);
              final columns = ((available + gap) / (minTile + gap))
                  .floor()
                  .clamp(1, 4);
              final tileWidth = (available - (columns - 1) * gap) / columns;
              return ListView(
                key: ValueKey((searching, searching ? _query : _group)),
                padding: EdgeInsets.all(inset),
                children: [
                  if (searching)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Semantics(
                        header: true,
                        liveRegion: true,
                        child: Text(
                          '搜索结果 · ${results.values.fold(0, (total, icons) => total + icons.length)} 个图标',
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                  for (final group in results.entries) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Semantics(
                        header: true,
                        child: Text(
                          group.key,
                          style: searching
                              ? theme.textTheme.bodySmall
                              : theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                    Wrap(
                      spacing: gap,
                      runSpacing: gap,
                      children: [
                        for (final entry in group.value)
                          SizedBox(
                            width: tileWidth,
                            child: _iconButton(context, entry),
                          ),
                      ],
                    ),
                    if (searching) const SizedBox(height: 16),
                  ],
                ],
              );
            },
          );
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 12 : 20,
            vertical: 12,
          ),
          child: LayoutBuilder(
            builder: (context, limits) {
              final title = Semantics(
                header: true,
                namesRoute: true,
                child: Text('分类图标库', style: theme.textTheme.titleLarge),
              );
              final search = TextField(
                controller: _search,
                autofocus: !compact,
                decoration: InputDecoration(
                  hintText: '搜索图标',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  isDense: true,
                  filled: true,
                  fillColor: scheme.surfaceContainerLow,
                  border: fieldBorder,
                  enabledBorder: fieldBorder,
                  focusedBorder: fieldBorder.copyWith(
                    borderSide: BorderSide(color: scheme.primary, width: 2),
                  ),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: () => _selectGroup(_group),
                          icon: const Icon(Icons.close_rounded, size: 18),
                        ),
                ),
                onChanged: (value) =>
                    setState(() => _query = value.trim().toLowerCase()),
              );
              if (limits.maxWidth < 460) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [title, const SizedBox(height: 8), search],
                );
              }
              return Row(
                children: [
                  Expanded(child: title),
                  const SizedBox(width: 12),
                  SizedBox(width: 276, child: search),
                ],
              );
            },
          ),
        ),
        const Divider(height: 1),
        if (compact) ...[
          ColoredBox(
            color: scheme.surfaceContainerLow,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  for (final group in _groups.keys)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        label: Text(group),
                        selected: !searching && _group == group,
                        onSelected: (_) => _selectGroup(group),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(child: grid),
        ] else
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: MediaQuery.textScalerOf(context)
                      .scale(112)
                      .clamp(148, 176)
                      .toDouble(),
                  color: scheme.surfaceContainerLow,
                  child: ListView(
                    padding: const EdgeInsets.all(8),
                    children: [
                      for (final group in _groups.keys)
                        _groupButton(
                          context,
                          group,
                          selected: !searching && _group == group,
                        ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: grid),
              ],
            ),
          ),
        const Divider(height: 1),
        ColoredBox(
          color: scheme.surfaceContainerLow,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消'),
              ),
            ),
          ),
        ),
      ],
    );
    if (compact) return Dialog.fullscreen(child: content);
    return Dialog(
      constraints: const BoxConstraints(maxWidth: 692),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(height: 448, child: content),
    );
  }

  Widget _groupButton(
    BuildContext context,
    String group, {
    required bool selected,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      child: TextButton(
        style:
            TextButton.styleFrom(
              foregroundColor: selected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurface,
              backgroundColor: selected ? scheme.secondaryContainer : null,
              minimumSize: const Size(0, 39),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? BorderSide(color: scheme.primary, width: 2)
                    : BorderSide.none,
              ),
            ),
        onPressed: () => _selectGroup(group),
        child: Row(
          children: [
            Expanded(child: Text(group, textAlign: TextAlign.start)),
            if (selected)
              const ExcludeSemantics(
                child: Icon(Icons.check_rounded, size: 16),
              ),
          ],
        ),
      ),
    );
  }

  Widget _iconButton(
    BuildContext context,
    MapEntry<String, CategoryIcon> entry,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final selected = entry.key == widget.selected;
    return Semantics(
      selected: selected,
      child: OutlinedButton(
        style:
            OutlinedButton.styleFrom(
              backgroundColor: selected
                  ? scheme.secondaryContainer
                  : scheme.surfaceContainerLow,
              foregroundColor: selected
                  ? scheme.onSecondaryContainer
                  : scheme.onSurface,
              minimumSize: const Size(0, 74),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ).copyWith(
              side: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.focused)
                    ? BorderSide(color: scheme.primary, width: 2)
                    : selected
                    ? BorderSide(color: scheme.primary)
                    : BorderSide.none,
              ),
            ),
        onPressed: () => Navigator.pop(context, entry.key),
        child: Stack(
          alignment: Alignment.topRight,
          children: [
            SizedBox(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(entry.value.$2, size: 24, color: scheme.primary),
                  const SizedBox(height: 6),
                  Text(entry.value.$1, textAlign: TextAlign.center),
                ],
              ),
            ),
            if (selected)
              const ExcludeSemantics(
                child: Icon(Icons.check_rounded, size: 14),
              ),
          ],
        ),
      ),
    );
  }
}
