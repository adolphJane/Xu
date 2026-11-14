import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/updates.dart';

void main() {
  test('verified update bytes accept only the expected SHA-256', () {
    final bytes = utf8.encode('verified dmg payload');
    final checksum =
        '0e70e8a506524ddd9188b8cfb24e039ebff0033121d10de48278c6fde3c5bbb2';
    // Keep the test independent from the network while exercising the real verifier.
    expect(() => UpdateService.verifyBytes(bytes, checksum), returnsNormally);
    expect(
      () => UpdateService.verifyBytes(bytes, 'not-a-sha'),
      throwsFormatException,
    );
  });
}
