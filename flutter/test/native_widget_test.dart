import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:xu/src/native.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('widget command uses the macOS bridge', () async {
    String? method;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
          method = call.method;
          return true;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null),
    );
    expect(await NativeBridge.openWidget(), true);
    expect(method, 'openWidget');
  });
  test('menu actions reach the matching Flutter callbacks', () async {
    final actions = <String>[];
    NativeBridge.listen(
      onAddTask: () => actions.add('add'),
      onToggleTask: (id) => actions.add('toggle:$id'),
      onShowAnniversaries: () => actions.add('anniversaries'),
      onStartTask: (id) => actions.add('start:$id'),
      onCompleteTask: (id) => actions.add('complete:$id'),
      onCancelTask: (id) => actions.add('cancel:$id'),
      onAddCompletedTask: () => actions.add('completed'),
      onAddAiTask: () => actions.add('ai'),
      onShowCommandPalette: () => actions.add('palette'),
      onShowSettings: () => actions.add('settings'),
    );
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    for (final method in [
      'addTask',
      'addCompletedTask',
      'addAiTask',
      'showCommandPalette',
      'showSettings',
      'showAnniversaries',
    ]) {
      await messenger.handlePlatformMessage(
        NativeBridge.channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method)),
        (_) {},
      );
    }
    for (final method in [
      'startTask',
      'completeTask',
      'cancelTask',
      'toggleTask',
    ]) {
      await messenger.handlePlatformMessage(
        NativeBridge.channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(method, 'one')),
        (_) {},
      );
    }
    expect(actions, [
      'add',
      'completed',
      'ai',
      'palette',
      'settings',
      'anniversaries',
      'start:one',
      'complete:one',
      'cancel:one',
      'toggle:one',
    ]);
    addTearDown(() => NativeBridge.channel.setMethodCallHandler(null));
  });
}
