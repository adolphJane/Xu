import 'dart:convert';
import 'dart:typed_data';

const blueprintImageMaxBytes = 4 * 1024 * 1024;
const blueprintImageMaxPixels = 24000000;
const blueprintImagesMaxBytes = 24 * 1024 * 1024;

List<Map<String, dynamic>> blueprintImages(Object? value) => value is List
    ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
    : [];

Uint8List? blueprintImageBytes(Map<String, dynamic> row) {
  final data = row['data'];
  if (data is! String ||
      data.length > (blueprintImageMaxBytes * 4 / 3).ceil() + 4) {
    return null;
  }
  try {
    return base64Decode(data);
  } on FormatException {
    return null;
  }
}
