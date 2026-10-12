# “今日”试点记录

## 原有问题与改造范围

`TodayWorkbenchView` 的标题、间距、卡片圆角和边框原先分别写在页面内部。macOS 试点把主要页面节奏接入 `AppTypography`、`AppSpacing`、`AppRadius` 和 `AppColors.border`，保留 `AppPreferences` 提供的卡片与品牌主题、现有任务分组和操作调用。

iOS 新目标使用 `NavigationStack`、`Form`、系统 sheet 和原生按钮实现“今日”页；直接复用 `TaskStore`、`TodayBlueprintOrganizer`、`TaskItem`、SwiftData 与旧 JSON 迁移。设计映射：页面底色 `canvas`，卡片 `AppCard`，状态 `AppBadge`，文案层级 `AppTypography`，页面操作 `AppButton`，空态 `AppEmptyState` 复用系统 `ContentUnavailableView`。焦点任务从下方列表排除，避免重复呈现。

## 已验证

- iOS 17 最低版本的 Xcode 工程在 iPhone 16 Pro / iOS 18.5 Simulator 上构建成功，模拟器内实际启动。
- 浅色和深色截图核对了“今日”空态；深色实心按钮的动作色已调深。通过模拟器界面添加一项测试任务，确认重点卡片出现且任务可切换为“正在执行”。
- macOS `zsh scripts/build-app.sh` 成功生成 `dist/序.app`，已执行 `open dist/序.app`；`swift test` 的 32 项现有测试全部通过。

## 后续迁移边界

当前 iOS 仅覆盖“今日”试点，不代表桌面全部功能已经移植。设备签名、发布、完整 iPad 布局检查、VoiceOver 人工走查、系统增大对比度与最大字体尺寸实测仍需单独验收。Gallery 已提供浅/深色和大字 Preview 配置；模拟器运行与编译成功不等同于所有 Preview 已在 Xcode 中逐一人工打开。

后续分批迁移记录见 [rollout.md](rollout.md)。
