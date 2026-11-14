import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

class AvailableUpdate {
  final String version;
  final String url;
  final String notes;
  final String checksum;
  AvailableUpdate(this.version, this.url, this.notes, this.checksum);
}

class UpdateService {
  static final releasesUri = Uri.parse(
    'https://api.github.com/repos/adolphJane/Xu/releases?per_page=100',
  );
  static List<int>? versionParts(String value) {
    if (!RegExp(r'^\d+\.\d+\.\d+$').hasMatch(value)) return null;
    return value.split('.').map(int.parse).toList();
  }

  static bool newer(String candidate, String installed) {
    final a = versionParts(candidate), b = versionParts(installed);
    if (a == null || b == null) return false;
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static AvailableUpdate? select(List<dynamic> releases, String installed) {
    final found = <AvailableUpdate>[];
    for (final raw in releases) {
      if (raw is! Map || raw['draft'] == true) continue;
      final tag = '${raw['tag_name'] ?? ''}';
      if (!tag.startsWith('v') || !newer(tag.substring(1), installed)) continue;
      final name = 'Xu-$tag.dmg';
      final expectedPage = 'https://github.com/adolphJane/Xu/releases/tag/$tag';
      final expectedAsset =
          'https://github.com/adolphJane/Xu/releases/download/$tag/$name';
      if (raw['html_url'] != expectedPage) continue;
      for (final asset in raw['assets'] as List? ?? []) {
        if (asset is! Map ||
            asset['name'] != name ||
            asset['browser_download_url'] != expectedAsset) {
          continue;
        }
        final digest = '${asset['digest'] ?? ''}';
        if (!RegExp(r'^sha256:[0-9a-fA-F]{64}$').hasMatch(digest)) continue;
        found.add(
          AvailableUpdate(
            tag.substring(1),
            expectedPage,
            '${raw['body'] ?? ''}',
            digest.substring(7).toLowerCase(),
          ),
        );
      }
    }
    found.sort((a, b) {
      final x = versionParts(a.version)!, y = versionParts(b.version)!;
      for (var i = 0; i < 3; i++) {
        if (x[i] != y[i]) return y[i].compareTo(x[i]);
      }
      return 0;
    });
    return found.isEmpty ? null : found.first;
  }

  static Future<AvailableUpdate?> check(String installed) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(releasesUri);
      request.headers.set(
        HttpHeaders.acceptHeader,
        'application/vnd.github+json',
      );
      request.headers.set(HttpHeaders.userAgentHeader, 'Xu/$installed');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != 200) {
        throw HttpException('检查更新失败 (${response.statusCode})');
      }
      final body = await utf8
          .decodeStream(response)
          .timeout(const Duration(seconds: 30));
      return select(jsonDecode(body) as List<dynamic>, installed);
    } finally {
      client.close();
    }
  }

  static Future<File> downloadAndVerify(
    AvailableUpdate update, {
    Directory? directory,
  }) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15)
      ..maxConnectionsPerHost = 2;
    final targetDirectory =
        directory ?? await Directory.systemTemp.createTemp('xu-update-');
    await targetDirectory.create(recursive: true);
    final file = File('${targetDirectory.path}/Xu-v${update.version}.dmg');
    try {
      final request = await client.getUrl(
        Uri.parse(
          'https://github.com/adolphJane/Xu/releases/download/v${update.version}/Xu-v${update.version}.dmg',
        ),
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');
      request.headers.set(HttpHeaders.userAgentHeader, 'Xu/${update.version}');
      final response = await request.close().timeout(
        const Duration(seconds: 90),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('下载更新失败 (${response.statusCode})');
      }
      final bytes = await consolidateHttpClientResponseBytes(response);
      if (bytes.isEmpty || bytes.length > 1024 * 1024 * 1024) {
        throw const FormatException('更新包大小无效');
      }
      verifyBytes(bytes, update.checksum);
      await file.writeAsBytes(bytes, flush: true);
      return file;
    } catch (_) {
      if (await file.exists()) await file.delete();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  static void verifyBytes(List<int> bytes, String expectedChecksum) {
    final digest = sha256.convert(bytes).toString().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expectedChecksum.toLowerCase()) ||
        digest != expectedChecksum.toLowerCase()) {
      throw const FormatException('更新包 SHA-256 校验失败，已保留当前应用');
    }
  }

  static Future<List<int>> consolidateHttpClientResponseBytes(
    HttpClientResponse response,
  ) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
      if (builder.length > 1024 * 1024 * 1024) {
        throw const FormatException('更新包超过 1 GB');
      }
    }
    return builder.takeBytes();
  }
}
