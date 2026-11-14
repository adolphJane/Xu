# 序

macOS 14+ 应用有两个独立工程：

| 目录 | 内容 | 构建入口 |
| --- | --- | --- |
| [`flutter/`](flutter/) | 当前主应用，Flutter 3.47.9、FVM、`ifa_flutter_scaffold` 固定提交 | 根目录 `zsh scripts/build-app.sh`，产物 `dist/序.app` |
| [`legacy-macos/`](legacy-macos/) | 原 SwiftUI macOS 工程，SwiftPM、原有资源和打包文件 | `zsh legacy-macos/scripts/build-app.sh`，产物 `legacy-macos/dist/序.app` |

`iOS/` 旧工程保持原位，本次未修改或验证。两套 macOS 工程沿用同一应用名称和 Bundle ID；分别构建没有冲突，但不要同时把两份应用安装到同一个 `/Applications/序.app` 路径。

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

正式发布要求 GitHub Actions Secrets：`APPLE_CERTIFICATE_P12_BASE64`、`APPLE_CERTIFICATE_PASSWORD`、`APPLE_NOTARY_KEY_P8`、`APPLE_NOTARY_KEY_ID`、`APPLE_NOTARY_ISSUER_ID`。发布工作流会验证 Developer ID、双架构、Hardened Runtime 与 Apple 公证；缺少凭据时不会发布正式包。
