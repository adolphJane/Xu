import 'package:flutter/material.dart';

const nodeWidth = 220.0;
const nodeHeight = 96.0;

Map<String, Offset> automaticPositions(List<Map<String, dynamic>> tasks) {
  final byId = {for (final task in tasks) '${task['id']}': task};
  final levels = <String, int>{};
  int level(String id, Set<String> visiting) {
    if (levels.containsKey(id)) return levels[id]!;
    final task = byId[id];
    if (task == null || visiting.contains(id)) return 0;
    final parents = <String>{
      for (final dep in task['dependencyIDs'] as List? ?? [])
        if (byId.containsKey('$dep')) '$dep',
      if (task['parentTaskID'] != null &&
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
  for (final task in tasks) {
    final x = task['workflowX'], y = task['workflowY'];
    if (x is num && y is num) {
      positions['${task['id']}'] = Offset(x.toDouble(), y.toDouble());
    }
  }
  return positions;
}

class WorkflowCanvas extends StatefulWidget {
  final List<Map<String, dynamic>> tasks;
  final void Function(Map<String, dynamic>) onEdit;
  final Future<void> Function(Map<String, dynamic>, Offset) onMove;
  const WorkflowCanvas({
    super.key,
    required this.tasks,
    required this.onEdit,
    required this.onMove,
  });
  @override
  State<WorkflowCanvas> createState() => _WorkflowCanvasState();
}

class _WorkflowCanvasState extends State<WorkflowCanvas> {
  late Map<String, Offset> positions = automaticPositions(widget.tasks);
  @override
  void didUpdateWidget(covariant WorkflowCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tasks != widget.tasks) {
      positions = automaticPositions(widget.tasks);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tasks.isEmpty) return const Center(child: Text('蓝图中尚无事项'));
    final maxX =
        positions.values.map((p) => p.dx).reduce((a, b) => a > b ? a : b) +
        nodeWidth +
        48;
    final maxY =
        positions.values.map((p) => p.dy).reduce((a, b) => a > b ? a : b) +
        nodeHeight +
        48;
    final scheme = Theme.of(context).colorScheme;
    return InteractiveViewer(
      constrained: false,
      minScale: 0.5,
      maxScale: 2.0,
      child: SizedBox(
        width: maxX,
        height: maxY,
        child: Stack(
          children: [
            CustomPaint(
              size: Size(maxX, maxY),
              painter: _Connections(widget.tasks, positions, scheme.outline),
            ),
            for (final task in widget.tasks)
              Positioned(
                left: positions['${task['id']}']!.dx,
                top: positions['${task['id']}']!.dy,
                width: nodeWidth,
                height: nodeHeight,
                child: GestureDetector(
                  onPanUpdate: (details) {
                    final id = '${task['id']}';
                    setState(
                      () => positions[id] =
                          (positions[id] ?? Offset.zero) + details.delta,
                    );
                  },
                  onPanEnd: (_) async {
                    final id = '${task['id']}';
                    try {
                      await widget.onMove(task, positions[id]!);
                    } catch (_) {
                      if (mounted) {
                        setState(
                          () => positions = automaticPositions(widget.tasks),
                        );
                      }
                    }
                  },
                  child: Card(
                    color: task['status'] == 'completed'
                        ? scheme.primaryContainer
                        : scheme.surfaceContainer,
                    child: InkWell(
                      onTap: () => widget.onEdit(task),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${task['title']}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const Spacer(),
                            Text(
                              '${task['status'] ?? 'pending'}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Connections extends CustomPainter {
  final List<Map<String, dynamic>> tasks;
  final Map<String, Offset> positions;
  final Color color;
  _Connections(this.tasks, this.positions, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (final task in tasks) {
      final end = positions['${task['id']}'];
      if (end == null) continue;
      for (final dependency in task['dependencyIDs'] as List? ?? []) {
        final start = positions['$dependency'];
        if (start == null) continue;
        final from = start + const Offset(nodeWidth, nodeHeight / 2);
        final to = end + const Offset(0, nodeHeight / 2);
        final path = Path()
          ..moveTo(from.dx, from.dy)
          ..cubicTo(from.dx + 60, from.dy, to.dx - 60, to.dy, to.dx, to.dy);
        canvas.drawPath(path, paint);
        final arrow = Path()
          ..moveTo(to.dx - 7, to.dy - 5)
          ..lineTo(to.dx, to.dy)
          ..lineTo(to.dx - 7, to.dy + 5);
        canvas.drawPath(arrow, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Connections old) =>
      old.tasks != tasks || old.positions != positions || old.color != color;
}
