# 组件与原生控件

| 需求 | 当前选择 | 原则 |
| --- | --- | --- |
| 页面主要/次要操作 | `AppButton` | 保留原生 `Button` 的交互语义，用统一 `ButtonStyle` 管理视觉尺寸、内边距、圆角和状态；工具栏、表单、危险操作及图标按钮仍直接使用原生 `Button`。 |
| 卡片表面 | `AppCard` | 只统一内边距、表面、边框、圆角与轻阴影，不持有业务数据。 |
| 分区标题 | `AppSectionHeader` | 标题与说明采用语义字体，允许换行。 |
| 状态标签 | `AppBadge` | 使用 `brand`、`neutral`、`success`、`warning`、`danger` 语义色；状态有文字，色彩只是辅助。 |
| 文本与搜索 | 原生 `TextField` / `.searchable` | 不重复建立 `AppTextField`、`AppSearchField`。 |
| 页面空态与错误态 | `AppEmptyState` / `AppErrorState` | 复用系统 `ContentUnavailableView`；可提供操作或重试，错误不伪装为普通空态。轻量错误提示仍用系统 `alert`。 |
| 页面加载 | `AppLoadingView` | 复用系统 `ProgressView`，提供统一的可读状态说明；行内进度直接使用 `ProgressView`。 |
| 列表行 | 原生 `List` 或业务行 | `AppListRow` 暂不抽取；任务行含状态规则，需保留业务语义。 |

## 页面按钮尺寸

| 尺寸 | 字体 | 水平内边距 | 可见高度 iOS / macOS | 圆角 | 用途 |
| --- | --- | --- | --- | --- | --- |
| `compact` | 系统 Subheadline Medium | 12pt | 32 / 28pt | 8pt | 紧凑卡片、辅助操作 |
| `regular`（默认） | 系统 Subheadline Semibold | 16pt | 36 / 32pt | 12pt | 页面主要/次要操作 |
| `prominent` | 系统 Body Semibold | 20pt | 44 / 38pt | 12pt | 独立且重要的主要操作 |

iOS 的 `compact` 和 `regular` 将点击区域扩展到至少 44pt，视觉背景仍保持表中高度。图标与文字之间为 4pt。主要按钮使用实心强调色，文字根据底色明度选黑或白；次要按钮使用轻底色和清晰边框。按下时有轻微透明度反馈；Reduce Motion 下不缩放。禁用态、加载态由组件统一处理，外层仍可用 `.disabled(...)` 表达业务规则。避免在按钮标签内部再加固定高度或额外系统按钮样式。

macOS 顶部的 `AddTaskControl` 是保留菜单行为的分段操作，整体高 34pt、右侧菜单段宽 32pt；其颜色跟随 `AppPreferences`。系统工具栏、表单确认/取消、危险操作、列表行和菜单项沿用平台原生尺寸，不套用页面按钮样式。

macOS `TaskCard` 的状态、恢复/取消和更多操作图标使用 36×36pt 点击区域，并提供清楚的辅助功能名称；iOS 任务行图标继续保持至少 44×44pt 的触控区域。

`AppEmptyState` 的操作可选；没有可执行操作时不显示按钮。`AppErrorState` 的重试可选，不能代替实际错误处理。

macOS 页面使用用户自定义强调色时，可为 `AppEmptyState` 的操作传入 `tint`，使空态按钮与页面主操作一致。

新增组件必须复用 token，提供 Preview，覆盖浅/深色、长文案及大字号；图标操作需有可读的 `.accessibilityLabel` 与合适目标尺寸。`DesignSystemGallery.swift` 集中展示当前已实现的样式与原生控件。原生控件无需额外封装即可使用设计系统的 `.tint` 与语义字体。
