import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/blueprint_images.dart';
import 'package:xu/src/workspace.dart';
import 'package:xu/src/native.dart';

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(const Color(0xff28776a), BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(16, 12);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  picture.dispose();
  return data!.buffer.asUint8List();
}

class _MemoryRepository extends WorkspaceRepository {
  @override
  Future<void> commit(Map<String, List<Map<String, dynamic>>> next) async {
    data
      ..clear()
      ..addAll(next);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('a blueprint can export task reference images and remap acceptance evidence', () async {
    final dir = await Directory.systemTemp.createTemp('xu-blueprint-images-');
    addTearDown(() async {
      Get.reset();
      await dir.delete(recursive: true);
    });
    final repository = WorkspaceRepository()
      ..file = File('${dir.path}/workspace.json')
      ..load({
        'formatVersion': 1,
        'blueprints': [
          {'id': 'b', 'name': '参考图蓝图'},
        ],
        'tasks': [
          {
            'id': 't',
            'title': '有图任务',
            'blueprintID': 'b',
            'milestoneID': 'm',
            'status': 'completed',
          },
        ],
        'milestones': [
          {'id': 'm', 'name': '成果验收', 'blueprintID': 'b'},
        ],
      });
    Get.put(repository);
    final vm = Get.put(WorkspaceViewModel());
    final bytes = await _png();
    final image = await decodeBlueprintImage(bytes, '成果.png');
    expect(image['width'], 16);
    await expectLater(
      decodeBlueprintImage(Uint8List.fromList([1, 2, 3]), '坏图'),
      throwsFormatException,
    );
    await vm.updateBlueprintFields('tasks', vm.tasks.single, {
      'images': [image],
    });
    await vm.saveMilestoneAcceptance(
      vm.items('milestones').single,
      [
        {'id': 'check', 'title': '核对截图', 'done': true},
      ],
      [
        {'taskID': 't', 'imageID': image['id'], 'label': '成果.png'},
      ],
      accept: true,
    );
    final package = vm.exportBlueprint('b');
    await vm.importBlueprint(package);
    final clonedTask = vm.tasks.last;
    final clonedMilestone = vm.items('milestones').last;
    final evidence =
        (clonedMilestone['acceptanceEvidence'] as List).single as Map;
    expect(evidence['taskID'], clonedTask['id']);
    expect(
      blueprintImageBytes(blueprintImages(clonedTask['images']).single),
      bytes,
    );
  });

  testWidgets('preview shows the image and can switch and close with keys', (
    tester,
  ) async {
    final images = (await tester.runAsync(() async {
      final bytes = await _png();
      return [
        await decodeBlueprintImage(bytes, '第一张'),
        await decodeBlueprintImage(bytes, '第二张'),
      ];
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () =>
                  showBlueprintImagePreview(context, images, 0, '任务参考图'),
              child: const Text('打开参考图'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开参考图'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2'), findsOneWidget);
    await tester.tap(find.byTooltip('下一张'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 2'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.text('任务参考图'), findsNothing);
  });
  testWidgets('a pasted reference image is saved by the blueprint editor', (
    tester,
  ) async {
    final bytes = (await tester.runAsync(_png))!;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(NativeBridge.channel, (call) async {
      return call.method == 'readClipboardImage' ? bytes : null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(NativeBridge.channel, null);
      Get.reset();
    });
    final repo = _MemoryRepository()
      ..load({
        'formatVersion': 1,
        'blueprints': [
          {'id': 'b', 'name': '编辑图片'},
        ],
      });
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put(WorkspaceViewModel());
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => editBlueprintImages(
                context,
                vm,
                'blueprints',
                vm.items('blueprints').single,
              ),
              child: const Text('编辑参考图'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('编辑参考图'));
    await tester.pumpAndSettle();
    await tester.runAsync(() async {
      await tester.tap(find.text('粘贴图片'));
      await Future<void>.delayed(const Duration(milliseconds: 120));
    });
    await tester.pumpAndSettle();
    expect(find.byTooltip('预览第 1 张图片'), findsOneWidget);
    await tester.tap(find.text('保存参考图'));
    await tester.pumpAndSettle();
    final stored = blueprintImages(vm.items('blueprints').single['images'])
        .single;
    expect(blueprintImageBytes(stored), bytes);
  });
}
