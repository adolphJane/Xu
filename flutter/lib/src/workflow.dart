import 'dart:math' as math;

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';

import 'blueprint_images.dart';

const nodeWidth = 220.0;
const nodeHeight = 96.0;

Map<String, Offset> automaticPositions(
  List<Map<String, dynamic>> tasks, {
  bool includeHierarchy = true,
  bool useSavedPositions = true,
}) {
  final byId = {for (final task in tasks) '${task['id']}': task};
  final levels = <String, int>{};
  int level(String id, Set<String> visiting) {
    if (levels.containsKey(id)) return levels[id]!;
    final task = byId[id];
    if (task == null || visiting.contains(id)) return 0;
    final parents = <String>{
      for (final dep in task['dependencyIDs'] as List? ?? [])
        if (byId.containsKey('$dep')) '$dep',
      if (includeHierarchy &&
          task['parentTaskID'] != null &&
          byId.containsKey('${task['parentTaskID']}'))
        '${task['parentTaskID']}',
    };
    final result = parents.isEmpty
        ? 0
        : 1 +
              parents
                  .map((p) => level(p, {...visiting, id}))
                  .reduce((a, b) => a > b ? a : b);
    levels[id] = result;
    return result;
  }

  for (final id in byId.keys) {
    level(id, <String>{});
  }
  final byLevel = <int, List<String>>{};
  for (final id in byId.keys) {
    byLevel.putIfAbsent(levels[id] ?? 0, () => []).add(id);
  }
  final positions = <String, Offset>{};
  for (final entry in byLevel.entries) {
    entry.value.sort(
      (a, b) => '${byId[a]?['createdAt'] ?? a}'.compareTo(
        '${byId[b]?['createdAt'] ?? b}',
      ),
    );
    for (var row = 0; row < entry.value.length; row++) {
      positions[entry.value[row]] = Offset(
        48 + entry.key * 300,
        48 + row * 150,
      );
    }
  }
  if (!useSavedPositions) return positions;
  for (final task in tasks) {
    final x = task['workflowX'], y = task['workflowY'];
    if (x is num && y is num) {
      positions['${task['id']}'] = Offset(x.toDouble(), y.toDouble());
    }
  }
  return positions;
}

typedef WorkflowNodeAction = ({String label, IconData icon, VoidCallback run});
typedef WorkflowTask = Map<String, dynamic>;

class WorkflowCanvas extends StatefulWidget {
  final List<WorkflowTask> tasks;
  final void Function(WorkflowTask) onEdit;
  final Future<void> Function(WorkflowTask, Offset) onMove;
  final String? selectedId;
  final Set<String> highlightedIds;
  final String Function(WorkflowTask)? statusLabel;
  final bool dependencyLayout;
  final void Function(WorkflowTask)? onPreview;
  final List<WorkflowNodeAction> Function(WorkflowTask)? nodeActions;
  final VoidCallback? onArrange;
  final String? linkSource;
  final String? focusId;
  final int focusRevision;

  const WorkflowCanvas({
    super.key,
    required this.tasks,
    required this.onEdit,
    required this.onMove,
    this.selectedId,
    this.highlightedIds = const {},
    this.statusLabel,
    this.dependencyLayout = false,
    this.onPreview,
    this.nodeActions,
    this.onArrange,
    this.linkSource,
    this.focusId,
    this.focusRevision = 0,
  });

  @override
  State<WorkflowCanvas> createState() => _WorkflowCanvasState();
}

class _WorkflowCanvasState extends State<WorkflowCanvas> {
  final _transform = TransformationController();
  Size _viewport = Size.zero;
  bool _showHierarchy = false;
  static const _minimumScale = 0.15;
  static const _maximumScale = 2.5;
  late Map<String, Offset> positions = _layout();

  Map<String, Offset> _layout() => automaticPositions(
    widget.tasks,
    includeHierarchy: !widget.dependencyLayout,
  );

  @override
  void didUpdateWidget(covariant WorkflowCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    final layout = _layout();
    if (!mapEquals(_lastLayout, layout)) {
      positions = layout;
      _lastLayout = {...layout};
    }
    if (widget.focusId != oldWidget.focusId ||
        widget.focusRevision != oldWidget.focusRevision) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus();
      });
    }
  }

  late Map<String, Offset> _lastLayout = _layout();

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  double get _nodeHeight {
    final scaler = MediaQuery.textScalerOf(context);
    return nodeHeight + math.max(0.0, scaler.scale(16) - 16) * 4;
  }

  Size get _scene => Size(
    positions.values.fold<double>(
          0,
          (value, point) => math.max(value, point.dx),
        ) +
        nodeWidth +
        48,
    positions.values.fold<double>(
          0,
          (value, point) => math.max(value, point.dy),
        ) +
        _nodeHeight +
        48,
  );

  void _center(Offset scenePoint, double scale) {
    if (_viewport.isEmpty) return;
    final center = _viewport.center(Offset.zero) - scenePoint * scale;
    _transform.value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(center.dx, center.dy, 0);
  }

  void _zoom(double ratio) {
    final scale = (_transform.value.getMaxScaleOnAxis() * ratio).clamp(
      _minimumScale,
      _maximumScale,
    );
    _center(_transform.toScene(_viewport.center(Offset.zero)), scale);
  }

  void _fit() {
    final size = _scene;
    final scale = math.min(
      (_viewport.width - 24) / size.width,
      (_viewport.height - 24) / size.height,
    );
    _center(size.center(Offset.zero), scale.clamp(_minimumScale, 1.0));
  }

  void _focus() {
    final position = positions[widget.focusId];
    if (position != null) {
      _center(position + Offset(nodeWidth / 2, _nodeHeight / 2), 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tasks.isEmpty) return const Center(child: Text('蓝图中尚无事项'));
    final scheme = Theme.of(context).colorScheme;
    final size = _scene;
    return Column(
      children: [
        if (widget.nodeActions != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 4,
              children: [
                IconButton(
                  tooltip: '缩小画布',
                  onPressed: () => _zoom(0.8),
                  icon: const Icon(Icons.remove),
                ),
                ValueListenableBuilder<Matrix4>(
                  valueListenable: _transform,
                  builder: (_, matrix, _) =>
                      Text('${(matrix.getMaxScaleOnAxis() * 100).round()}%'),
                ),
                IconButton(
                  tooltip: '放大画布',
                  onPressed: () => _zoom(1.25),
                  icon: const Icon(Icons.add),
                ),
                TextButton.icon(
                  onPressed: _fit,
                  icon: const Icon(Icons.fit_screen),
                  label: const Text('适应画布'),
                ),
                TextButton.icon(
                  onPressed: widget.onArrange,
                  icon: const Icon(Icons.account_tree_outlined),
                  label: const Text('自动排版'),
                ),
                FilterChip(
                  label: const Text('显示子任务关系'),
                  selected: _showHierarchy,
                  onSelected: (value) => setState(() => _showHierarchy = value),
                ),
              ],
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              _viewport = constraints.biggest;
              return InteractiveViewer(
                constrained: false,
                boundaryMargin: const EdgeInsets.all(double.infinity),
                transformationController: _transform,
                minScale: _minimumScale,
                maxScale: _maximumScale,
                child: SizedBox.fromSize(
                  size: size,
                  child: Stack(
                    children: [
                      CustomPaint(
                        size: size,
                        painter: _Connections(
                          widget.tasks,
                          {...positions},
                          scheme.onSurfaceVariant.withValues(alpha: 0.72),
                          scheme.primary,
                          widget.selectedId,
                          _showHierarchy,
                          _nodeHeight,
                        ),
                      ),
                      for (final task in widget.tasks)
                        Positioned(
                          key: ValueKey(task['id']),
                          left: positions['${task['id']}']!.dx,
                          top: positions['${task['id']}']!.dy,
                          width: nodeWidth,
                          height: _nodeHeight,
                          child: _node(context, task),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _node(BuildContext context, WorkflowTask task) {
    final scheme = Theme.of(context).colorScheme;
    final id = '${task['id']}';
    final selected = widget.selectedId == id;
    final source = widget.linkSource == id;
    final actions = widget.nodeActions?.call(task) ?? const [];
    final images = blueprintImages(task['images']);
    return GestureDetector(
      onPanUpdate: widget.linkSource != null
          ? null
          : (details) => setState(() {
              final point = positions[id]! + details.delta;
              positions[id] = Offset(
                point.dx.clamp(0, 20000),
                point.dy.clamp(0, 20000),
              );
            }),
      onPanEnd: widget.linkSource != null
          ? null
          : (_) async {
              try {
                await widget.onMove(task, positions[id]!);
              } catch (error) {
                if (mounted) {
                  setState(() => positions = _layout());
                  ScaffoldMessenger.maybeOf(this.context)
                      ?.showSnackBar(SnackBar(content: Text('$error')));
                }
              }
            },
      child: Card(
        clipBehavior: Clip.antiAlias,
        color: selected || source
            ? scheme.primaryContainer
            : scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected || source || widget.highlightedIds.contains(id)
                ? scheme.primary
                : scheme.outlineVariant,
            width: selected || source ? 2 : 1,
          ),
        ),
        child: InkWell(
          onTap: () => widget.onEdit(task),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 6, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        '${task['title']}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (images.isNotEmpty && widget.onPreview != null)
                      Tooltip(
                        message: '预览 ${images.length} 张参考图',
                        child: InkWell(
                          onTap: () => widget.onPreview?.call(task),
                          child: SizedBox(
                            width: 34,
                            height: 28,
                            child: BlueprintImageView(
                              image: images.first,
                              thumbnail: true,
                            ),
                          ),
                        ),
                      ),
                    if (actions.isNotEmpty)
                      PopupMenuButton<int>(
                        tooltip: '事项操作 · ${task['title']}',
                        padding: EdgeInsets.zero,
                        iconSize: 18,
                        style: IconButton.styleFrom(
                          minimumSize: const Size(32, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          padding: EdgeInsets.zero,
                        ),
                        constraints: const BoxConstraints(minWidth: 178),
                        onSelected: (index) => actions[index].run(),
                        itemBuilder: (_) => [
                          for (var i = 0; i < actions.length; i++)
                            PopupMenuItem(
                              value: i,
                              child: Row(
                                children: [
                                  Icon(actions[i].icon, size: 17),
                                  const SizedBox(width: 10),
                                  Text(actions[i].label),
                                ],
                              ),
                            ),
                        ],
                      ),
                  ],
                ),
                const Spacer(),
                Text(
                  source
                      ? '连线起点'
                      : widget.statusLabel?.call(task) ??
                            '${task['status'] ?? 'pending'}',
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
}

class _Connections extends CustomPainter {
  const _Connections(
    this.tasks,
    this.positions,
    this.color,
    this.accent,
    this.selected,
    this.hierarchy,
    this.height,
  );

  final List<WorkflowTask> tasks;
  final Map<String, Offset> positions;
  final Color color;
  final Color accent;
  final String? selected;
  final bool hierarchy;
  final double height;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.stroke;
    for (final task in tasks) {
      final id = '${task['id']}';
      final end = positions[id];
      if (end == null) continue;
      for (final dependency in task['dependencyIDs'] as List? ?? []) {
        final start = positions['$dependency'];
        if (start == null) continue;
        final active = selected == id || selected == dependency;
        paint
          ..color = active ? accent : color
          ..strokeWidth = active ? 2.2 : 1.4;
        final from = start + Offset(nodeWidth - 3, height / 2);
        final to = end + Offset(4, height / 2);
        canvas.drawPath(
          Path()
            ..moveTo(from.dx, from.dy)
            ..cubicTo(from.dx + 60, from.dy, to.dx - 60, to.dy, to.dx, to.dy),
          paint,
        );
        canvas.drawPath(
          Path()
            ..moveTo(to.dx - 8, to.dy - 5)
            ..lineTo(to.dx, to.dy)
            ..lineTo(to.dx - 8, to.dy + 5),
          paint,
        );
      }
      if ((hierarchy ? positions['${task['parentTaskID']}'] : null)
          case final Offset parent) {
        final from = parent + Offset(nodeWidth / 2, height - 4);
        final to = end + const Offset(nodeWidth / 2, 4);
        paint
          ..color = color.withValues(alpha: 0.75)
          ..strokeWidth = 1.5;
        final line = Path()
          ..moveTo(from.dx, from.dy)
          ..lineTo(to.dx, to.dy);
        for (final metric in line.computeMetrics()) {
          for (var distance = 0.0; distance < metric.length; distance += 10) {
            canvas.drawPath(
              metric.extractPath(
                distance,
                math.min(distance + 4, metric.length),
              ),
              paint,
            );
          }
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Connections old) =>
      old.tasks != tasks ||
      !mapEquals(old.positions, positions) ||
      old.color != color ||
      old.accent != accent ||
      old.selected != selected ||
      old.hierarchy != hierarchy ||
      old.height != height;
}
