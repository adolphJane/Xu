import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ifa_flutter_scaffold/ifa_flutter_scaffold.dart';

import 'src/workspace.dart';
import 'src/app.dart';

Future<void> main() async {
  BuildConfig.instantiate(
    envType: Environment.production,
    envConfig: EnvConfig(
      appName: '序',
      baseUrl: '',
      shouldCollectCrashLog: false,
    ),
  );
  try {
    await executeApp(
      const XuApp(),
      preBuild: () async {
        Get.put<DataStorageService>(DataStorageService(), permanent: true);
        final repo = WorkspaceRepository();
        await repo.init().timeout(const Duration(seconds: 15));
        Get.put<WorkspaceRepository>(repo, permanent: true);
        final vm = Get.put<WorkspaceViewModel>(
          WorkspaceViewModel(),
          permanent: true,
        );
        await vm.restoreSyncFolder().timeout(const Duration(seconds: 15));
        await vm.updateMenu().timeout(const Duration(seconds: 5));
      },
      afterBuild: () {
        if (Get.isRegistered<WorkspaceViewModel>()) {
          Get.find<WorkspaceViewModel>().startAnniversaryRefresh();
        }
      },
    );
  } catch (error, stackTrace) {
    debugPrint('启动失败：$error\n$stackTrace');
    runApp(
      MaterialApp(
        home: Scaffold(body: Center(child: SelectableText('序启动失败\n$error'))),
      ),
    );
  }
}
