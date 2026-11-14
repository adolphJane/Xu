# 序 · 旧版 SwiftUI macOS 工程

本目录保留独立的 SwiftPM macOS 14+ 工程，供迁移对照和旧功能验证。`Package.swift`、`Sources/`、`Tests/`、`Assets/` 与 `Packaging/` 都在此目录；不引用仓库根目录的 Flutter 源码。

```sh
cd legacy-macos
swift test --disable-sandbox
zsh scripts/build-app.sh
open dist/序.app
```

`scripts/package-unsigned.sh` 可生成临时签名 DMG；`scripts/package-macos.sh` 在提供原有签名及公证环境变量时生成正式包。产物留在 `legacy-macos/dist/`。本工程与 Flutter 主应用保留相同 Bundle ID，安装到同一路径时会互相覆盖；请分别保管构建产物。
