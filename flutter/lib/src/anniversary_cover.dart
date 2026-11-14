import 'dart:convert';
import 'dart:typed_data';

const anniversaryCoverMaxBytes = 5 * 1024 * 1024;

String encodeAnniversaryCover(Uint8List bytes) {
  if (bytes.isEmpty || bytes.length > anniversaryCoverMaxBytes) {
    throw const FormatException('封面图片须小于 5 MB');
  }
  final png =
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4e &&
      bytes[3] == 0x47;
  final jpeg =
      bytes.length >= 3 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[2] == 0xff;
  final gif =
      bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46;
  final webp =
      bytes.length >= 12 &&
      ascii.decode(bytes.sublist(0, 4)) == 'RIFF' &&
      ascii.decode(bytes.sublist(8, 12)) == 'WEBP';
  if (!png && !jpeg && !gif && !webp) {
    throw const FormatException('请选择 PNG、JPEG、GIF 或 WebP 图片');
  }
  return base64Encode(bytes);
}

Uint8List? anniversaryCoverBytes(Object? value) {
  if (value is! String || value.isEmpty) return null;
  try {
    final bytes = base64Decode(value);
    return bytes.length <= anniversaryCoverMaxBytes ? bytes : null;
  } on FormatException {
    return null;
  }
}
