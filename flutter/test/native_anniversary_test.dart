import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('lunar anniversary forwards calendar and recurrence to macOS', () async {
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
          calls.add(call);
          if (call.method == 'anniversaryNextOccurrence') {
            return '2027-02-06T00:00:00Z';
          }
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null),
    );

    final date = DateTime(2026, 2, 17);
    final next = await NativeBridge.anniversaryNextOccurrence(
      date,
      repeatYearly: true,
      lunar: true,
    );
    await NativeBridge.anniversaryNotification(
      id: 'birthday',
      title: '生日',
      date: date,
      enabled: true,
      repeatYearly: true,
      lunar: true,
    );

    expect(next, DateTime.parse('2027-02-06T00:00:00Z').toLocal());
    expect(calls.map((call) => call.method), [
      'anniversaryNextOccurrence',
      'anniversaryNotification',
    ]);
    for (final call in calls) {
      final arguments = call.arguments as Map;
      expect(arguments['lunar'], true);
      expect(arguments['repeatYearly'], true);
      expect(arguments['year'], 2026);
      expect(arguments['month'], 2);
      expect(arguments['day'], 17);
      if (call.method == 'anniversaryNotification') {
        expect(arguments['reminderDays'], 0);
        expect(arguments['privacyMode'], false);
      }
    }
  });
}
