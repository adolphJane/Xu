import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'blueprint_image_data.dart';
import 'native.dart';
import 'workspace.dart';

export 'blueprint_image_data.dart';

Future<Map<String, dynamic>> decodeBlueprintImage(
  Uint8List bytes,
  String label,
) async {
  if (bytes.isEmpty || bytes.length > blueprintImageMaxBytes) {
    throw const FormatException('请选择不超过 4 MB 的图片');
  }
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 255 &&
      bytes[1] == 216 &&
      bytes[2] == 255;
  final png =
      bytes.length >= 8 &&
      bytes[0] == 137 &&
      bytes[1] == 80 &&
      bytes[2] == 78 &&
      bytes[3] == 71 &&
      bytes[4] == 13 &&
      bytes[5] == 10 &&
      bytes[6] == 26 &&
      bytes[7] == 10;
  if (!jpeg && !png) throw const FormatException('请选择 PNG 或 JPEG 图片');
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width * descriptor.height > blueprintImageMaxPixels) {
        throw const FormatException('图片分辨率过大');
      }
      final ratio = math.min(1.0, 320 / descriptor.width);
      final codec = await descriptor.instantiateCodec(
        targetWidth: math.max(1, (descriptor.width * ratio).round()),
      );
      try {
        final frame = await codec.getNextFrame();
        frame.image.dispose();
      } finally {
        codec.dispose();
      }
      return {
        'id': newId(),
        'label': label,
        'description': '',
        'mime': jpeg ? 'image/jpeg' : 'image/png',
        'width': descriptor.width,
        'height': descriptor.height,
        'data': base64Encode(bytes),
      };
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

class BlueprintImageView extends StatelessWidget {
  const BlueprintImageView({
    super.key,
    required this.image,
    this.thumbnail = false,
  });

  final Map<String, dynamic> image;
  final bool thumbnail;

  @override
  Widget build(BuildContext context) {
    final bytes = blueprintImageBytes(image);
    const missing = Center(child: Text('图片不可用'));
    if (bytes == null) return missing;
    return Image.memory(
      bytes,
      cacheWidth: thumbnail ? 256 : null,
      fit: BoxFit.contain,
      semanticLabel:
          '${image['description']?.toString().trim().isNotEmpty == true ? image['description'] : (image['label'] ?? '参考图')}',
      errorBuilder: (context, error, stack) => missing,
    );
  }
}

Future<void> showBlueprintImagePreview(
  BuildContext context,
  List<Map<String, dynamic>> images,
  int initialIndex,
  String title,
) {
  var index = initialIndex;
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        void move(int delta) =>
            setState(() => index = (index + delta).clamp(0, images.length - 1));
        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft): () => move(-1),
            const SingleActivator(LogicalKeyboardKey.arrowRight): () => move(1),
          },
          child: Focus(
            autofocus: true,
            child: AlertDialog(
              title: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis),
              content: SizedBox(
                width: 860,
                height: 480,
                child: Column(
                  children: [
                    Expanded(
                      child: InteractiveViewer(
                        key: ValueKey(images[index]['id']),
                        maxScale: 6,
                        child: SizedBox.expand(
                          child: BlueprintImageView(image: images[index]),
                        ),
                      ),
                    ),
                    if ('${images[index]['description'] ?? ''}'
                        .trim()
                        .isNotEmpty)
                      Text(
                        '${images[index]['description']}',
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  tooltip: '上一张',
                  onPressed: index > 0 ? () => move(-1) : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                Text('${index + 1} / ${images.length}'),
                IconButton(
                  tooltip: '下一张',
                  onPressed: index + 1 < images.length ? () => move(1) : null,
                  icon: const Icon(Icons.chevron_right),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

Future<void> editBlueprintImages(
  BuildContext context,
  WorkspaceViewModel vm,
  String section,
  Map<String, dynamic> owner,
) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (context) =>
      _BlueprintImagesEditor(vm: vm, section: section, owner: owner),
);

class _BlueprintImagesEditor extends StatefulWidget {
  const _BlueprintImagesEditor({
    required this.vm,
    required this.section,
    required this.owner,
  });
  final WorkspaceViewModel vm;
  final String section;
  final Map<String, dynamic> owner;

  @override
  State<_BlueprintImagesEditor> createState() => _BlueprintImagesEditorState();
}

class _BlueprintImagesEditorState extends State<_BlueprintImagesEditor> {
  late final images = blueprintImages(widget.owner['images']);
  bool busy = false;
  bool dirty = false;
  String? message;

  late final String _dropId = newId();
  StreamSubscription<Map>? _drops;

  @override
  void initState() {
    super.initState();
    _drops = NativeBridge.blueprintImageDrops.listen((event) {
      if (!mounted || event['target'] != _dropId) return;
      if (busy) {
        setState(() => message = '正在读取图片，请稍后重试拖入');
        return;
      }
      unawaited(_add(drop: event));
    });
    unawaited(NativeBridge.setBlueprintImageDropTarget(_dropId, true));
  }

  @override
  void dispose() {
    unawaited(_drops?.cancel());
    unawaited(NativeBridge.setBlueprintImageDropTarget(_dropId, false));
    super.dispose();
  }

  Future<void> _add({bool paste = false, Map? drop}) async {
    setState(() {
      busy = true;
      message = null;
    });
    final errors = <String>[];
    Future<void> add(String label, Future<Uint8List> Function() read) async {
      try {
        final image = await decodeBlueprintImage(await read(), label);
        final encoded = [...images, image].fold<int>(
          0,
          (sum, row) => sum + ((row['data'] as String?)?.length ?? 0),
        );
        if (encoded > blueprintImagesMaxBytes * 4 / 3) {
          throw const FormatException('图片总大小超过 24 MB');
        }
        images.add(image);
        dirty = true;
      } catch (error) {
        errors.add('$label：$error');
      }
    }

    try {
      if (drop != null) {
        errors.addAll((drop['errors'] as List? ?? []).whereType<String>());
        for (final file in (drop['files'] as List? ?? []).whereType<Map>()) {
          if (file['bytes'] case final Uint8List bytes) {
            await add('${file['name']}', () async => bytes);
          }
        }
      } else if (paste) {
        final bytes = await NativeBridge.readClipboardImage();
        if (bytes == null) throw const FormatException('剪贴板里没有可用图片');
        await add('剪贴板图片', () async => bytes);
      } else {
        final picked = await FilePicker.pickFiles(
          type: FileType.custom,
          allowedExtensions: ['png', 'jpg', 'jpeg'],
        );
        for (final file in picked) {
          await add(file.name, () async {
            if (await file.xFile.length() > blueprintImageMaxBytes) {
              throw const FormatException('图片超过 4 MB');
            }
            return file.xFile.readAsBytes();
          });
        }
      }
    } catch (error) {
      errors.add('$error');
    } finally {
      if (mounted) {
        setState(() {
          busy = false;
          message = errors.isEmpty ? null : errors.join('\n');
        });
      }
    }
  }

  void _move(int from, int to) => setState(() {
    dirty = true;
    images.insert(to, images.removeAt(from));
  });

  Future<void> _cancel() async {
    if (busy) return;
    if (dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (dialog) => AlertDialog(
          title: const Text('放弃参考图修改？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialog),
              child: const Text('继续编辑'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('放弃修改'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final title = '${widget.owner['name'] ?? widget.owner['title']} · 参考图';
    return PopScope(
      canPop: !dirty && !busy,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !busy) unawaited(_cancel());
      },
      child: AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _add(),
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('添加图片'),
                    ),
                    TextButton(
                      onPressed: busy ? null : () => _add(paste: true),
                      child: const Text('粘贴图片'),
                    ),
                  ],
                ),
                const Text('也可将图片文件拖入此窗口'),
                if (busy) const LinearProgressIndicator(),
                if (message != null)
                  Text(
                    message!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                for (var index = 0; index < images.length; index++)
                  _imageRow(title, index),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: busy ? null : _cancel, child: const Text('取消')),
          FilledButton(
            onPressed: busy ? null : _save,
            child: const Text('保存参考图'),
          ),
        ],
      ),
    );
  }

  Widget _imageRow(String title, int index) {
    final image = images[index];
    return Padding(
      key: ValueKey(image['id']),
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          Tooltip(
            message: '预览第 ${index + 1} 张图片',
            child: InkWell(
              onTap: () =>
                  showBlueprintImagePreview(context, images, index, title),
              child: SizedBox(
                width: 68,
                height: 54,
                child: BlueprintImageView(image: image, thumbnail: true),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextFormField(
              initialValue: '${image['description'] ?? ''}',
              maxLines: 2,
              decoration: const InputDecoration(labelText: '图片说明'),
              onChanged: (value) {
                image['description'] = value;
                if (!dirty) setState(() => dirty = true);
              },
            ),
          ),
          IconButton(
            tooltip: '前移图片',
            onPressed: busy || index == 0
                ? null
                : () => _move(index, index - 1),
            icon: const Icon(Icons.arrow_upward),
          ),
          IconButton(
            tooltip: '后移图片',
            onPressed: busy || index + 1 == images.length
                ? null
                : () => _move(index, index + 1),
            icon: const Icon(Icons.arrow_downward),
          ),
          IconButton(
            tooltip: '移除图片',
            onPressed: busy
                ? null
                : () => setState(() {
                    dirty = true;
                    images.removeAt(index);
                  }),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    setState(() {
      busy = true;
      message = null;
    });
    try {
      await widget.vm.updateBlueprintFields(widget.section, widget.owner, {
        'images': images,
      });
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() {
          busy = false;
          message = '$error';
        });
      }
    }
  }
}
