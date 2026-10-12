# Design System 实施计划与阶段记录

本计划以 `ui-audit.md` 为依据。2026-10-12 已确认新增 iOS 应用目标，最低版本定为 iOS 17。第二至第六阶段的设计基础、共享 token、必要组件、Gallery 和协作规则已建立；第七阶段选择“今日”为双平台试点。其余页面继续渐进迁移。

试点后的分批迁移以 [rollout.md](rollout.md) 为准。已确认的规范写入仓库级 `AGENTS.md`；后续页面沿用现有 token 和组件，先核对业务状态与现有主题，再做呈现层替换。

## 前置决定：平台范围

当前交付同时包含 **macOS 14+** 与 **iOS/iPadOS 17+**。iOS 工程位于 `iOS/SequenceIOS.xcodeproj`，先提供“今日”试点，复用同一套任务模型、SwiftData、旧 JSON 迁移及业务规则。平台 UI 分别实现：macOS 继续使用侧边栏、菜单栏和设置窗口，iOS 用原生 `NavigationStack`。iOS 试点只有一个一级页面，暂不引入 Tab Bar。两平台沙盒独立，跨设备同步不属于这一轮的 UI 试点。

## 第二阶段：设计语言与文档

1. 建立 `docs/design-system/README.md`（使用入口）、`foundations.md`（设计原则与 Color/Typography/4pt Spacing/Shape/Motion/Layout 规范）、`components.md`（组件使用与原生控件优先级）。为浅色、深色、高对比度分别定义语义角色；保留现有主题预设和用户自定义值的映射规则。
2. 字体采用系统语义样式和弹性布局；明确 macOS 字体缩放与未来 iOS Dynamic Type 的差异。间距以 4pt 阶梯为默认，少数尺寸例外需说明。动效读取系统 Reduce Motion，避免纯视觉状态成为唯一反馈。
3. 明确 macOS 窗口/侧边栏/设置/菜单栏，以及未来 iOS Safe Area/Navigation/Tab Bar/Sheet 的平台规则。表单、搜索、进度和空态优先用 SwiftUI 原生控件。

**验收**：规范中每种角色能指向现有业务示例；主题与平台例外有明确规则，不要求每个页面一次性迁移。

## 第三阶段：Design Tokens

1. 在可复用的 `DesignSystem` 目录或 SwiftPM target 建立 `AppColors.swift`、`AppTypography.swift`、`AppSpacing.swift`、`AppRadius.swift`、`AppShadows.swift`、`AppTheme.swift`。选择 target 方式时先确认资源打包及现有可执行 target 的访问方式。
2. 添加 Asset Catalog 的浅/深色 Color Set，并在 SwiftPM manifest 中配置资源；系统表面优先使用动态系统色。`AppTheme` 将现有 `AppPreferences` 的预设、自定义 HEX、密度、字号、圆角等映射到语义 token，保持旧用户偏好有效，不改 UserDefaults key 或数据结构。
3. 设计值只在新/迁移 UI 中通过 token 使用；主题设置仍可改变外观。若用户 HEX 无法保证对比度，应采用明确的前景色策略并在主题页反馈。

**验收**：macOS 14+ 可编译；浅/深/高对比度及全部现有预设有可读的关键组合；现有外观偏好升级后保留。

## 第四阶段：组件库

按试点真实重复需求逐项建立，先复用 `PageHeader`、`TaskCard`、`AddTaskControl`、`WorkbenchPressStyle` 与原生 SwiftUI 控件。`AppButton` 可优先体现统一操作层级与状态；`AppCard` 可作为表面样式或轻量容器；`AppSectionHeader`、`AppListRow`、`AppBadge` 仅在发现跨页面重复结构时抽取。`AppTextField`、`AppSearchField`、`AppEmptyState`、`AppErrorState`、`AppLoadingView` 先评估 `TextField`、`.searchable`、`ContentUnavailableView`、`ProgressView` 是否已满足需求，避免无意义包装。

每个最终新增组件提供独立 SwiftUI Preview，覆盖启用/禁用、选中、加载、长文案、浅/深色和较大字体；图标按钮提供可读标签与合理目标尺寸。

**验收**：组件不接管业务状态；原生焦点、键盘、VoiceOver 和平台默认行为仍正常。

## 第五阶段：Gallery

创建 `DesignSystemGallery.swift`，在 Xcode Preview 中展示 Colors、Typography、Buttons、Cards、Forms、Lists、States 与已实现组件；配置浅色/深色和不同文字尺寸 Preview。Gallery 不挂入正式业务导航。由于当前是 SwiftPM 可执行包，先验证所用 Xcode/SwiftPM 配置是否能渲染 Preview；若工具链受限，保留可编译的 Gallery 视图并记录验证限制。

## 第六阶段：协作规则

保留现有 `AGENTS.md` 的数据、构建、发布要求，在其后增加 UI 规则：先读 `docs/design-system/README.md`，复用组件并使用 token，遵守 Apple HIG，支持 Dark Mode/字体放大/VoiceOver，不随意引入 UI 依赖或修改全局规范，新增组件同步更新文档和 Preview。只增加规则，不重写原有条款。

## 第七阶段：今日页试点

1. 在实施前记录 `TodayWorkbenchView` 的浅色、深色、放大文字、空态和有任务状态；以本审计中的固定字号、卡片、间距和交互问题为基线。
2. 把页标题、重点卡片、任务分组、辅助栏和状态操作映射到语义 token 与必要组件；保持数据筛选、任务开始/完成/编辑、日报、蓝图入口等调用不变。
3. 验证 Preview/Gallery、键盘焦点、VoiceOver、长中文标题、缩窄窗口、Reduce Motion 与现有主题预设。
4. 按仓库规则运行 `zsh scripts/build-app.sh`，确认 `dist/序.app` 实际生成，并执行 `open dist/序.app`；运行相关测试，人工查看试点页实际效果。代码每次修改后都遵守该构建与打开要求。
5. 汇总试点前后差异及已知限制，得到效果确认后再按页面优先级扩展；不在这一轮改造整个 App。

**完成标准**：试点主要视觉参数已从页面硬编码转为语义规则，浅/深色和文字放大下内容可读，操作路径与数据行为无回归，开发版应用已成功构建并打开。

## 推荐顺序与边界

先做文档与 token，再做试点所需组件和 Gallery，最后迁移今日页及更新协作规则。全程不变更 API/数据库/备份格式，不引入第三方 UI 框架。当前工作区已有未提交的分类页面修改及未跟踪的 `AGENTS.md`，实施时需保留它们。
