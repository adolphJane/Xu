# 项目协作约束

当前 macOS 14+ 主应用在 `flutter/`，使用 Flutter 3.47.9 与 FVM，基础框架为 Git 固定提交的 `ifa_flutter_scaffold`。旧 SwiftUI macOS 工程独立存放在 `legacy-macos/`，用于迁移对照和单独构建；`iOS/` 旧工程暂不修改或验证。

- 在 `flutter/` 目录使用 `fvm flutter` 运行 Flutter 命令；依赖锁文件应提交。不得写入 API Key、签名证书、私钥或 Secrets。
- Flutter 应用从空数据开始；不读取 SwiftData 数据。新 JSON 备份和文件夹同步无需兼容旧格式。
- 修改 Flutter 应用代码后在 `flutter/` 运行 `fvm flutter analyze` 和相关测试，再从仓库根目录运行 `zsh scripts/build-app.sh` 并打开 `dist/序.app`。修改旧版 macOS 代码后在 `legacy-macos/` 运行 `swift test` 和 `zsh scripts/build-app.sh`。
- Flutter 构建产物放在根目录不提交的 `dist/`；旧版产物放在 `legacy-macos/dist/`。根目录 `scripts/build-app.sh` 是 Flutter 本地与 CI 统一入口；两套工程各有独立打包脚本。
- macOS UI 保持浅色、深色、大字体、长中文、键盘与辅助功能可用。新增或迁移页面以 `docs/design-system/flutter/README.md` 为设计规范；`docs/design-system/` 其余旧文档与 `legacy-macos/Sources/` 仅作对照。
- 仅用户明确要求时才修改或验证 iOS 工程。
