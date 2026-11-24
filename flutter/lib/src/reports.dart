import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'ai.dart';
import 'design_system/components/xu_shell.dart';
import 'report_rules.dart';
import 'workspace.dart';
import 'weekly_review.dart';

class ReportsPage extends StatelessWidget {
  const ReportsPage({super.key});

  @override
  Widget build(BuildContext context) => Obx(() {
    final vm = Get.find<WorkspaceViewModel>();
    vm.revision.value;
    final reports = [...vm.items('reports')]
      ..sort(
        (a, b) =>
            '${b['reportDate'] ?? ''}'.compareTo('${a['reportDate'] ?? ''}'),
      );
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
      children: [
        const WeeklyReviewsSection(),
        const SizedBox(height: 20),
        if (reports.isEmpty)
          const XuSectionCard(
            title: '历史日报',
            icon: Icons.history_rounded,
            children: [Text('还没有保存的日报。创建并保存日报后，可以在这里回顾。')],
          )
        else
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Semantics(
              header: true,
              child: Text(
                '历史日报',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
          ),
        for (final report in reports)
          Card(
            child: ListTile(
              leading: const XuIconTile(Icons.description_outlined),
              title: Text(() {
                final date = DateTime.tryParse('${report['reportDate']}');
                return date == null
                    ? '日报'
                    : '${date.year}年${date.month}月${date.day}日';
              }()),
              subtitle: Text(
                '${report['content'] ?? ''}'.replaceAll('\n', ' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Text(
                '${ReportRules.length('${report['content'] ?? ''}')} 字',
              ),
              onTap: () => showReportDetail(context, report),
            ),
          ),
      ],
    );
  });
}

Future<void> showReportDetail(
  BuildContext context,
  Map<String, dynamic> report,
) {
  final content = '${report['content'] ?? ''}';
  final date = DateTime.tryParse('${report['reportDate']}');
  return showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(
        date == null ? '历史日报' : '${date.year}年${date.month}月${date.day}日 日报',
      ),
      content: SizedBox(
        width: 700,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '字数范围 ${report['minimumLength'] ?? '—'}～${report['maximumLength'] ?? '—'} · 实际 ${ReportRules.length(content)} 字',
            ),
            const SizedBox(height: 12),
            Expanded(
              child: SingleChildScrollView(child: SelectableText(content)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: content)),
          icon: const Icon(Icons.copy_outlined),
          label: const Text('复制 Markdown'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}

Future<void> showReportEditor(BuildContext context) async {
  final vm = Get.find<WorkspaceViewModel>();
  final content = TextEditingController();
  final supplement = TextEditingController();
  final minimumInput = TextEditingController(text: '125');
  final maximumInput = TextEditingController(text: '180');
  var preset = ReportLengthPreset.short;
  var loading = false;
  var saving = false;
  String? error;
  try {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<void>(
      context: context,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      builder: (context) => StatefulBuilder(
        builder: (context, setState) {
          final minimum = preset == ReportLengthPreset.custom
              ? int.tryParse(minimumInput.text) ?? 0
              : preset.minimum;
          final maximum = preset == ReportLengthPreset.custom
              ? int.tryParse(maximumInput.text) ?? 0
              : preset.maximum;
          final rangeValid = ReportRules.validRange(minimum, maximum);
          final warning = content.text.trim().isEmpty
              ? null
              : ReportRules.warning(content.text, minimum, maximum);
          final compact = MediaQuery.sizeOf(context).shortestSide < 600;
          final draftField = TextField(
            controller: content,
            expands: !compact,
            maxLines: compact ? 10 : null,
            minLines: compact ? 5 : null,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              labelText: '日报草稿',
              alignLabelWithHint: true,
              border: OutlineInputBorder(),
            ),
          );
          final fields = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('按项目归类输出固定三段，生成后可编辑草稿。'),
              const SizedBox(height: 12),
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: 190,
                    child: DropdownButtonFormField<ReportLengthPreset>(
                      initialValue: preset,
                      decoration: const InputDecoration(labelText: '字数'),
                      items: [
                        for (final value in ReportLengthPreset.values)
                          DropdownMenuItem(
                            value: value,
                            child: Text(value.label),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => preset = value ?? preset),
                    ),
                  ),
                  if (preset == ReportLengthPreset.custom) ...[
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: minimumInput,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '最少'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(
                      width: 100,
                      child: TextField(
                        controller: maximumInput,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: '最多'),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ] else
                    Text('$minimum～$maximum 字'),
                ],
              ),
              if (!rangeValid)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '最少字数须在 50～3000 之间；最多不得小于最少字数且不超过 5000。',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              const SizedBox(height: 10),
              TextField(
                controller: supplement,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '日报补充',
                  hintText: '会议信息、结论、风险或想强调的内容',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (compact) draftField else Expanded(child: draftField),
              if (loading) const LinearProgressIndicator(),
              if (error != null)
                Text(
                  error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              if (warning != null)
                Text(
                  warning,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              Text('${ReportRules.length(content.text)} 字'),
            ],
          );
          final actions = [
            if (content.text.isNotEmpty)
              TextButton.icon(
                onPressed: () =>
                    Clipboard.setData(ClipboardData(text: content.text)),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('复制 Markdown'),
              ),
            if (content.text.isNotEmpty)
              FilledButton.tonal(
                onPressed: loading || saving || warning != null
                    ? null
                    : () async {
                        setState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          final now = DateTime.now();
                          await vm.put('reports', {
                            'id': newId(),
                            'reportDate': now.toIso8601String(),
                            'createdAt': now.toIso8601String(),
                            'minimumLength': minimum,
                            'maximumLength': maximum,
                            'supplement': supplement.text,
                            'content': content.text.trim(),
                          });
                          if (context.mounted) Navigator.pop(context);
                        } catch (e) {
                          if (context.mounted) setState(() => error = '$e');
                        } finally {
                          if (context.mounted) setState(() => saving = false);
                        }
                      },
                child: const Text('保存日报'),
              ),
            OutlinedButton(
              onPressed: loading || saving || !rangeValid
                  ? null
                  : () {
                      setState(() {
                        error = null;
                        content.text = ReportRules.fallback(
                          vm.tasks,
                          day: DateTime.now(),
                          supplement: supplement.text,
                          blueprints: vm.items('blueprints'),
                        );
                      });
                    },
              child: const Text('生成本地草稿'),
            ),
            FilledButton.icon(
              onPressed: loading || saving || !rangeValid
                  ? null
                  : () async {
                      setState(() {
                        loading = true;
                        error = null;
                      });
                      try {
                        final prompt = ReportRules.prompt(
                          vm.tasks,
                          day: DateTime.now(),
                          supplement: supplement.text,
                          minimum: minimum,
                          maximum: maximum,
                          blueprints: vm.items('blueprints'),
                        );
                        var draft = await AiService.complete(prompt);
                        if (ReportRules.warning(draft, minimum, maximum) !=
                            null) {
                          draft = await AiService.complete(
                            ReportRules.revisionPrompt(draft, minimum, maximum),
                          );
                        }
                        if (ReportRules.length(draft) < minimum) {
                          draft = ReportRules.enforceMinimumLength(
                            draft,
                            ReportRules.fallback(
                              vm.tasks,
                              day: DateTime.now(),
                              supplement: supplement.text,
                              blueprints: vm.items('blueprints'),
                            ),
                            minimum,
                          );
                        }
                        if (context.mounted) {
                          setState(() => content.text = draft);
                        }
                      } catch (e) {
                        if (context.mounted) setState(() => error = '$e');
                      } finally {
                        if (context.mounted) setState(() => loading = false);
                      }
                    },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('生成日报'),
            ),
          ];
          if (compact) {
            return Dialog.fullscreen(
              child: Scaffold(
                appBar: AppBar(
                  automaticallyImplyLeading: false,
                  title: const Text('今日日报'),
                  actions: [
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                body: SafeArea(
                  top: false,
                  child: ListView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      fields,
                      const SizedBox(height: 12),
                      Wrap(spacing: 8, runSpacing: 8, children: actions),
                    ],
                  ),
                ),
              ),
            );
          }
          return AlertDialog(
            title: const Text('今日日报'),
            content: SizedBox(width: 750, height: 560, child: fields),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('关闭'),
              ),
              ...actions,
            ],
          );
        },
      ),
    );
    await navigator.push(route);
    await route.completed;
  } finally {
    content.dispose();
    supplement.dispose();
    minimumInput.dispose();
    maximumInput.dispose();
  }
}
