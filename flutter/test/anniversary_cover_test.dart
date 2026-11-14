import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/anniversary_cover.dart';

void main() {
  test('cover image remains portable in JSON and rejects invalid files', () {
    final png = Uint8List.fromList([
      0x89,
      0x50,
      0x4e,
      0x47,
      0x0d,
      0x0a,
      0x1a,
      0x0a,
    ]);
    final encoded = encodeAnniversaryCover(png);
    expect(anniversaryCoverBytes(encoded), png);
    expect(anniversaryCoverBytes('not-base64!'), isNull);
    expect(
      () => encodeAnniversaryCover(Uint8List.fromList([1, 2, 3])),
      throwsFormatException,
    );
    expect(
      () => encodeAnniversaryCover(Uint8List(anniversaryCoverMaxBytes + 1)),
      throwsFormatException,
    );
  });
}
