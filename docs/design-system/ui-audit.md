# UI 审计（第一阶段）

审计日期：2026-10-12。范围：`Package.swift`、`Packaging/Info.plist`、`AGENTS.md` 和 `Sources/Quadrant/` 的 SwiftUI 实现。此次为源码与资源静态审计，未修改业务代码，也未进行逐页运行截图或 VoiceOver 实测；视觉与无障碍结论需在试点阶段用实际应用验证。

## 1. 平台与项目边界

**当前交付物是 macOS 应用，不存在 iOS Deployment Target。** `Package.swift` 仅声明 `.macOS(.v14)`，`Packaging/Info.plist` 的 `LSMinimumSystemVersion` 为 14.0。应用使用 `AppKit`、`NSApplicationDelegateAdaptor`、`NSOpenPanel`、`MenuBarExtra`、`Settings` 场景，以及主窗口最小尺寸 980 × 680；这些实现不能直接作为 iOS 页面构建。仓库未发现 `.xcodeproj`、`.xcassets` 或 `.colorset`，也没有独立的 `DesignSystem` target。当前应先为 macOS 14+ 建立可复用的跨平台语义层；若目标确实是 iPhone/iPad，还需要单独确定 iOS target、最低 iOS 版本、导航结构与 AppKit 替代方案。

现有 `AGENTS.md` 规定每次**代码**修改后构建并打开 `dist/序.app`；本阶段只增加文档。工作区审计开始时已有未提交的 `TaskCategoriesView.swift`、`TaskCategoryField.swift` 修改及未跟踪的 `AGENTS.md`，本次不触碰这些内容。

## 2. 页面、导航与交互结构

| 区域 | 当前实现 | 审计结论 |
| --- | --- | --- |
| 应用场景 | `QuadrantApp.swift` 定义主窗口、小组件窗口、菜单栏窗口和设置窗口 | 设计系统需覆盖窗口、菜单栏和设置；iOS 的 Tab Bar 目前没有对应业务场景。 |
| 主导航 | `Views.swift` 的 `ContentView` 用 `NavigationSplitView`、自绘 `SidebarView` 和 `AppSection` 枚举切换九个工作区页面 | macOS 侧边栏结构合理；自绘行选中态、字号和间距应统一，并核查键盘焦点与 VoiceOver。 |
| 主内容 | 顶部 `WorkbenchTopBar` + 页面详情；今日使用 `TodayWorkbenchView`，另有收集箱、蓝图、四象限、分类、日历、纪念日、已处理和日报 | 主内容页分别定义边距、标题和卡片，视觉节奏不一致。 |
| 深层流程 | 蓝图详情使用 `NavigationStack`；任务、新建、报表、同步冲突等大量使用 `.sheet`，删除用确认对话框，错误用 `.alert` | 大体遵守平台原生模式；需整理 sheet 尺寸、关闭/保存位置、层级标题和反馈用语。 |
| 设置 | `SettingsView` 用 `TabView` + `Form`，主题页提供预设皮肤及多项个性化控制 | `TabView` 是设置窗口的标签页，不是 iOS 主导航；设计系统必须保留现有用户主题偏好。 |
| 工作流画布 | `BlueprintWorkflowView` 提供画布、拖拽、缩放、快捷键与列表模式 | 高交互区域应单独审查键盘和辅助技术路径，不能用普通卡片组件整体替换。 |

代码入口：`Sources/Quadrant/QuadrantApp.swift`、`Sources/Quadrant/Views.swift`、`Sources/Quadrant/TodayWorkbenchView.swift`、`Sources/Quadrant/BlueprintWorkflowView.swift`。

## 3. 视觉样式现状

### 颜色与外观

- `AppPreferences` 与 `ThemePreset`（`QuadrantApp.swift`、`PhaseTwoModels.swift`）已经支持系统、石墨、纸张、深海、森林、墨色预设，自定义强调色/页面色/卡片色、四象限颜色、跟随系统/时间/专注切换、高对比度设置。`QuadrantApp` 将计算后的颜色方案和强调色注入各场景。
- 系统预设使用 `NSColor.windowBackgroundColor`、`NSColor.controlBackgroundColor`；多数文本使用 `.primary`、`.secondary` 等语义前景色。这是可复用的基础。
- 其他区域散布 `.blue`、`.orange`、`.pink`、`.red`、`.green`、`.white`、`Color(appHex:)`、业务数据中的 HEX 与透明度组合。例如今日重点卡片用按主题分支的固定 HEX 背景和白色字；蓝图卡片从数据读取颜色；任务状态色另行决定。缺少“强调/表面/边框/状态/反色文本”等清晰语义映射。
- 当前没有 Asset Catalog 的浅色/深色 Color Set。主题预设有暗色值，但自定义 HEX 仅一组值；`contrastIsReadable` 只检查页面背景与一组推定正文色，不能证明卡片、强调色、状态色、禁用态和反色按钮在所有主题下达标。

### 字体

- `AppSurfaceModifier`（`PhaseTwoViews.swift:5`）给主内容设置 `.system(size: 13 * preferences.fontScale)` 和 `.fontDesign(...)`；设置中的 `fontScale` 只允许 0.85–1.25。页面又直接使用 `.headline`、`.subheadline`、`.caption` 及大量 `.system(size:)`（如 9、10、11、13、18、23、29、30）。
- `PageHeader` 和今日页主标题均为 29pt，但分别写在不同位置；侧边栏、副标题、任务卡片等文字层级缺乏统一角色定义。固定字号、固定高度和 `.lineLimit(1)` 的组合在放大文字或长中文标题时有截断风险。
- 当前没有 `@ScaledMetric`、`dynamicTypeSize` 或 SwiftUI Preview 文字尺寸矩阵。macOS 的文字放大行为与 iOS Dynamic Type 不完全相同；现有自定义缩放不能视为已满足未来 iOS Dynamic Type 要求。

### 间距、形状与质感

- 主页面水平边距出现 25、30、34pt；卡片内边距有 12、14、16、18、20、23、24pt；列表项间距有 9、10、13、16pt，未形成 4pt 步进。`LayoutDensity` 目前只有 8、12、18 的组件间距偏好，其他值仍在页面硬编码。
- 圆角常见 9、10、12、13、14、15、16、17、18、19pt，并与 `preferences.cornerRadius` 混用。任务卡片、蓝图卡片、今日卡片的描边和阴影各自定义，悬停态不一致。
- 已有 `.regularMaterial` 的局部用法，也有卡片、侧边栏和顶部栏的半透明背景；需定义何时使用系统材质、何时使用不透明表面，避免层层叠加使层级模糊。

## 4. 组件复用与原生控件

已复用的项目组件/辅助：`PageHeader`、`TaskCard`、`TaskList`、`AddTaskControl`、`TaskCategoryField`、`WorkbenchPressStyle`、`comfortableIconTarget`、`AppSurfaceModifier`；还有 `BlueprintCard`、`AnniversaryCard`、`TodayActionRow` 等业务专用组件。原生 `Button`、`Menu`、`Picker`、`Form`、`List`、`ProgressView`、`ContentUnavailableView`、`SettingsLink` 和 `ConfirmationDialog` 使用较多。

**缺口是复用边界与视觉参数，而非缺少十个通用包装器。** 空态已有大量 `ContentUnavailableView`，不宜另造通用空态视图；搜索目前是命令面板文本框和工作流选择器文本框，是否抽取 `AppSearchField` 应看试点需求；表单优先保留原生控件。已有业务卡片应先共用表面/描边/间距 token，再考虑抽取 `AppCard`。

## 5. 深色模式、动态字体和无障碍

| 项目 | 已有基础 | 缺口 / 待实测风险 |
| --- | --- | --- |
| 深色模式 | 系统外观、自定义暗色预设、`.preferredColorScheme`，部分系统语义色 | 无浅/深 Asset Color Set；自定义 HEX 和状态色需逐主题核查；白色文字/半透明底的对比度未系统验证。 |
| 减少动态效果 | 多处读取 `accessibilityReduceMotion`，`WorkbenchPressStyle` 和今日页动画可降级；另有用户偏好开关 | `AppSurfaceModifier` 的 transaction 只检查用户开关，其他文件需盘点动画与系统设置覆盖范围。 |
| VoiceOver | 部分图标按钮有 `.accessibilityLabel`、`.help`，进度有组合描述，侧边栏有选中 trait | 部分 `TaskCard`/`BlueprintCard` 用 `onTapGesture` 打开详情，语义、键盘激活和焦点路径需实测；部分仅图标按钮只提供 `.help` 或没有可读操作名。 |
| 点击区域 | 顶部栏 `comfortableIconTarget(40)`、侧边栏行 46pt、添加按钮 40pt | `TaskCard` 的状态按钮 28×30、分类菜单 30×30、部分省略号/箭头按钮未统一点击区域。 |
| 放大文字 | 一些 Text 使用语义字体；部分多行文本允许纵向扩展 | 全局固定 13pt、多个固定高度/宽度、单行截断；缺少 Preview 和实际放大测试。 |
| 高对比度 | 自定义高对比度开关及部分对比度提示 | 未检测系统 `accessibilityContrast`；现有计算只覆盖有限颜色对。 |

以上均为源码观察，不等同于已执行 Accessibility Inspector、VoiceOver、键盘导航或实际亮/暗模式测试。

## 6. 优先级与试点建议

| 优先级 | 问题 | 影响 | 试点处理方向 |
| --- | --- | --- | --- |
| P0 | 平台目标与“iOS 设计系统”要求不一致 | iOS API/Tab Bar/Preview 无法直接用于当前 target | 先确定是优化现有 macOS 应用，还是另建 iOS target；跨平台 token 层可共用。 |
| P1 | 缺少语义 token，视觉数值分散 | 新页面继续出现不同标题、间距、圆角、边框与色值 | 建立语义色、字体、间距、形状、动效规则并迁移一页。 |
| P1 | 固定字号/尺寸与小点击区域 | 放大文字、长内容、VoiceOver 与键盘体验不稳定 | 以语义字体、弹性布局、可访问按钮修正试点页。 |
| P1 | 自定义主题与暗色对比度缺乏完整映射 | 某些主题下可读性与层级不可预测 | 为系统外观和预设定义语义映射，检查文本/底色组合。 |
| P2 | 空态、卡片、按钮用法跨页面不一 | 页面间质感和操作反馈不一致 | 先复用系统控件与已有业务组件，仅抽象确有重复的样式。 |
| P2 | 没有组件 Preview/Gallery | 后续样式回归难以发现 | 创建只在 Preview 呈现的 Gallery，覆盖外观、字号和交互状态。 |

建议以 `TodayWorkbenchView` 为首个 UI 试点：这是默认落地页，同时包含标题、强调卡片、任务行、分组表面、空态、进度、按钮与自适应侧栏，足以检验 token 和组件组合。保留 `TodayBlueprintOrganizer`、`TaskStore` 的调用及原有操作路径，只处理呈现层；不把工作流画布或所有设置页一起重构。

## 7. 参考准则

- Apple [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/) 与 [Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)：以平台导航模式为基础。
- Apple [Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode) 与 [Color](https://developer.apple.com/design/human-interface-guidelines/color)：优先语义系统色，自定义颜色提供外观变体并检查对比度。
- Apple [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)：审查可读性、交互目标与辅助技术体验。
