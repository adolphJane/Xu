import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xu/src/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'calendar write forwards existing event identifier for update',
    () async {
      MethodCall? captured;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, (call) async {
            captured = call;
            return 'event-1';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(NativeBridge.channel, null),
      );
      final id = await NativeBridge.calendarCreate(
        '任务',
        DateTime(2026, 11, 7, 9),
        45,
        eventId: 'event-1',
      );
      expect(id, 'event-1');
      expect(captured?.method, 'calendarCreate');
      expect((captured?.arguments as Map)['eventID'], 'event-1');
    },
  );
}
