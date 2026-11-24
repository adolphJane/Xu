# 序

「序」的主应用覆盖 macOS 14+、iOS 15+ 和 Android 7.0+。

| 目录 | 内容 | 构建入口 |
| --- | --- | --- |
| [`flutter/`](flutter/) | 当前主应用，Flutter 3.47.9、FVM、`ifa_flutter_scaffold` 固定提交 | macOS 使用根目录 `zsh scripts/build-app.sh`，移动端使用 Flutter 构建命令 |
| [`legacy-macos/`](legacy-macos/) | 原 SwiftUI macOS 工程，SwiftPM、原有资源和打包文件 | `zsh legacy-macos/scripts/build-app.sh`，产物 `legacy-macos/dist/序.app` |

移动端工程位于 `flutter/ios/` 和 `flutter/android/`。两套 macOS 工程共用应用名称和 Bundle ID，可分别构建并保存在各自的产物目录。

## Flutter 开发

```sh
cd flutter
fvm install
fvm flutter pub get
fvm flutter analyze
fvm flutter test
cd ..
zsh scripts/build-app.sh
open dist/序.app
```

根目录的 `scripts/build-app.sh`、`scripts/package-unsigned.sh`、`scripts/package-macos.sh` 和 `scripts/verify-developer-id.sh` 是兼容入口，实际脚本位于 `flutter/scripts/`。CI、预览 DMG 和正式发布继续调用根目录入口；Flutter 使用 `flutter/Packaging/` 的版本与安装说明。构建产物不提交。

### 移动端调试

iOS 使用 Xcode 和已安装的模拟器运行时。Android 使用 JDK 17+、SDK 36、NDK 28.2.13676358 和 CMake 3.22.1。从 `flutter/` 目录运行以下命令。

```sh
fvm flutter devices
fvm flutter run -d <设备ID>
fvm flutter build ios --simulator --debug
fvm flutter build apk --debug
```

iOS 模拟器应用位于 `build/ios/iphonesimulator/Runner.app`，Android 调试包位于 `build/app/outputs/flutter-apk/app-debug.apk`。手机使用底部导航，「更多」提供分类、纪念日、已处理、日报和设置。通过日历页连接系统日历，在事项编辑器中开启单项同步。文件夹同步和每日复盘提醒位于设置页。

## 旧版 macOS 开发

```sh
cd legacy-macos
swift test --disable-sandbox
zsh scripts/build-app.sh
open dist/序.app
```

旧版的 `Package.swift`、`Sources/`、`Tests/`、`Assets/`、`Packaging/` 和 `scripts/` 均在 `legacy-macos/`，其构建不依赖 Flutter 目录。旧版的打包入口为 `legacy-macos/scripts/package-macos.sh` 和 `legacy-macos/scripts/package-unsigned.sh`。

## 文档与发布

Flutter 的 [设计规范](docs/design-system/flutter/README.md) 和 [迁移进度](docs/FLUTTER-MIGRATION.md) 位于根目录 `docs/`；旧 SwiftUI 设计文档保留供对照。Flutter 数据从空数据开始，不读取 SwiftData，新 JSON 备份与同步无需兼容旧格式。

推送到 `main` 或手动运行 **Build Flutter previews** 后，可在运行详情的 **Artifacts** 下载 macOS 通用预览 DMG、iOS 模拟器和未签名真机构建，以及 Android 调试 APK。推送版本标签时，发布流程也会生成移动端 Artifacts，GitHub Release 提供签名并公证的 macOS DMG。

三端 CI 都通过仓库的 Actions Secret `IFA_FLUTTER_SCAFFOLD_TOKEN` 访问私有脚手架。凭据只需拥有 `adolphJane/ifa_flutter_scaffold` 的 Contents 读取权限。iOS 真机包需要签名后安装。Android APK 支持 ARM32、ARM64 和 x86_64。

macOS 正式发布需要 `APPLE_CERTIFICATE_P12_BASE64`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_NOTARY_KEY_P8`、`APPLE_NOTARY_KEY_ID` 和 `APPLE_NOTARY_ISSUER_ID`。发布工作流验证 Developer ID、双架构、Hardened Runtime 和 Apple 公证。
