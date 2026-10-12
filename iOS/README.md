# 序 iOS 试点

用 Xcode 打开 `SequenceIOS.xcodeproj`，选择 `SequenceIOS` scheme 和 iOS 17+ 的 iPhone/iPad 模拟器运行。命令行验证示例：

```sh
xcodebuild -project iOS/SequenceIOS.xcodeproj -scheme SequenceIOS \
  -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_ALLOWED=NO build
```

当前接入“今日”和“分类”页面，通过系统 Tab Bar 切换。分类页支持选择、新增、重命名、删除类别，按任务状态筛选、任务改类，以及在当前类别下新建任务；其他桌面页面尚未移植。任务模型、SwiftData 持久化、旧 JSON 迁移与状态规则来自 `Sources/Quadrant/` 的共享源文件；iOS 与 macOS 应用各自使用自己的沙盒数据。设计规范见 `../docs/design-system/README.md`。

模拟器 `.app` 是开发产物，不包含发布签名；本地放在 `dist/SequenceIOS-simulator.app`，不提交到 Git。正式设备安装、签名和发布流程尚未配置。
