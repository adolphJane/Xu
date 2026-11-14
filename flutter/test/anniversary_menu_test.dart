import 'package:flutter_test/flutter_test.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';
import 'package:xu/src/native.dart';
import 'package:xu/src/workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('menu shows opted-in anniversary and redacts private name', () async {
    Map? menu;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(NativeBridge.channel, (call) async {
          if (call.method == 'anniversaryNextOccurrence') {
            return '2027-02-06T00:00:00Z';
          }
          if (call.method == 'updateMenu') menu = call.arguments as Map;
          return true;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeBridge.channel, null);
      Get.reset();
    });
    final repo = WorkspaceRepository();
    repo.load({
      'formatVersion': 1,
      'anniversaries': [
        {
          'id': 'private',
          'name': '真实姓名',
          'date': '2026-02-17T00:00:00',
          'repeatYearly': true,
          'calendar': 'lunar',
          'privacyMode': true,
        },
        {
          'id': 'hidden',
          'name': '不要出现',
          'date': '2026-02-17T00:00:00',
          'showInMenuBar': false,
        },
      ],
    });
    Get.put<WorkspaceRepository>(repo);
    final vm = Get.put<WorkspaceViewModel>(WorkspaceViewModel());
    await vm.updateMenu();
    final anniversaries = menu?['anniversaries'] as List;
    expect(anniversaries, hasLength(1));
    expect((anniversaries.single as Map)['title'], '重要日子');
    expect(menu.toString(), isNot(contains('真实姓名')));
    expect(menu.toString(), isNot(contains('不要出现')));
  });
}
