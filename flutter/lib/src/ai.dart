import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'native.dart';

class AiService {
  static Future<String> complete(
    String prompt, {
    String model = 'deepseek-chat',
  }) async {
    return _request(prompt, model);
  }

  static Future<String> completeWithImage(
    String prompt,
    Uint8List bytes,
    String mimeType, {
    String model = 'deepseek-flash',
  }) async {
    if (bytes.isEmpty ||
        bytes.length > 10 * 1024 * 1024 ||
        !['image/jpeg', 'image/png'].contains(mimeType)) {
      throw const FormatException('请选择小于 10 MB 的 JPEG 或 PNG 图片');
    }
    return _request([
      {'type': 'text', 'text': prompt},
      {
        'type': 'image_url',
        'image_url': {'url': 'data:$mimeType;base64,${base64Encode(bytes)}'},
      },
    ], model);
  }

  static Future<String> _request(Object content, String model) async {
    final key = await NativeBridge.readApiKey();
    if (key == null || key.isEmpty) {
      throw StateError('请先在设置中填写 DeepSeek API Key');
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(
        Uri.parse('https://api.deepseek.com/chat/completions'),
      );
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $key');
      request.write(
        jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': content},
          ],
        }),
      );
      final response = await request.close().timeout(
        const Duration(seconds: 60),
      );
      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('AI 请求失败 (${response.statusCode})');
      }
      final parsed = jsonDecode(body) as Map<String, dynamic>;
      final choices = parsed['choices'] as List?;
      return '${(choices?.first as Map?)?['message']?['content'] ?? ''}'.trim();
    } finally {
      client.close();
    }
  }
}

class TaskDraft {
  final String title;
  final String notes;
  final List<String> subtasks;
  TaskDraft(this.title, this.notes, this.subtasks);

  static TaskDraft parse(String response) {
    final start = response.indexOf('{');
    final end = response.lastIndexOf('}');
    if (start < 0 || end <= start) throw const FormatException('AI 未返回有效任务草稿');
    final json =
        jsonDecode(response.substring(start, end + 1)) as Map<String, dynamic>;
    final title = '${json['title'] ?? ''}'.trim();
    if (title.isEmpty) throw const FormatException('任务标题为空');
    final subtasks = (json['subtasks'] as List? ?? [])
        .map((e) => '$e'.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return TaskDraft(title, '${json['notes'] ?? ''}'.trim(), subtasks);
  }
}
