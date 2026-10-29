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

`AppCard` 默认保留轻阴影；事项等密集列表可传 `elevated: false` 使用平面边框卡片，`surface` 可接入用户主题表面。默认参数兼容既有 macOS 与 iOS 调用，Gallery 提供平面系列卡示例。

## 类别选择

macOS 创建与编辑事项的类别统一使用 `TaskCategoryField`，通过宽度固定、值与箭头两端对齐的按钮打开自绘 `TaskCategoryOptions`，不使用系统菜单选项样式。面板顶部显示「未分类」，下方类别列表支持滚动、长名称换行、悬停反馈与勾选状态；主题强调色跟随 `AppPreferences`，VoiceOver 可识别选中项。点击选项即更新表单并关闭，关闭按钮或点弹层外侧可退出。新增类别统一到分类页面管理。Gallery 和 Preview 覆盖有类别、长中文和空态。

创建与编辑事项共用 `TaskNotesField`：清晰的备注标题、原生多行输入、语义正文文字和表面边框；编辑表单已有分区标题时隐藏组件内的重复标题。Gallery 和 Preview 覆盖长备注。

类别选择按钮、`TaskCategoryOptions` 与任务改类菜单均读取 `TaskStore.categoryAppearance` 的同一份图标偏好；未分类使用托盘，旧类别或不可用图标回退为标签。`TaskCategoryOptions.symbols` 为可选参数，独立 Preview 无须连接持久化。

## macOS 类别编辑与图标库

`CategoryEditor` 用 `appDialog` 同时编辑名称和图标。名称与图标保持为草稿，保存时才更新类别；重名错误留在输入处，取消、外侧点击与 Escape 经 `onAppDialogCancel` 统一检查未保存修改。删除类别使用系统确认，说明受影响任务数及移至未分类的结果。

`CategoryIconPicker` 为嵌套 `appDialog`，提供 55 个精选 SF Symbols、中文/关键词/英文符号名搜索、分组、最近使用和已选预览。点击只更改候选，“使用此图标”返回上层草稿；取消不修改草稿。最近使用最多 9 个，无记录时隐藏该分区。不可用符号不进入网格，已保存符号不可用时回退 `tag`。所有图标具有名称与选中读屏语义；网格按钮保留可见焦点、方向键导航与至少 44pt 点击区域，选中同时使用边框和勾号。主题、字号与字体偏好跟随 `AppPreferences`；间距、圆角和文字采用现有 token。

图标和历史记录为本机显示偏好，保存到独立的 `quadrant.categoryAppearance.v1`；不增加 `TaskItem`、SwiftData 或备份/同步字段。重命名迁移图标键，删除清理映射；内存预览不读写真实类别偏好。Gallery 提供真实编辑/嵌套选择入口，Preview 覆盖长中文与深色。

## 页面按钮尺寸

| 尺寸 | 字体 | 水平内边距 | 可见高度 iOS / macOS | 圆角 | 用途 |
| --- | --- | --- | --- | --- | --- |
| `compact` | 系统 Subheadline Medium | 12pt | 32 / 28pt | 8pt | 紧凑卡片、辅助操作 |
| `regular`（默认） | 系统 Subheadline Semibold | 16pt | 36 / 32pt | 12pt | 页面主要/次要操作 |
| `prominent` | 系统 Body Semibold | 20pt | 44 / 38pt | 12pt | 独立且重要的主要操作 |

iOS 的 `compact` 和 `regular` 将点击区域扩展到至少 44pt，视觉背景仍保持表中高度。图标与文字之间为 4pt。主要按钮使用实心强调色，文字根据底色明度选黑或白；次要按钮使用轻底色和清晰边框。按下时有轻微透明度反馈；Reduce Motion 下不缩放。禁用态、加载态由组件统一处理，外层仍可用 `.disabled(...)` 表达业务规则。避免在按钮标签内部再加固定高度或额外系统按钮样式。

macOS 顶部的 `AddTaskControl` 是保留菜单行为的分段操作，整体高 34pt、右侧菜单段宽 32pt；其颜色跟随 `AppPreferences`。系统工具栏、表单确认/取消、危险操作、列表行和菜单项沿用平台原生尺寸，不套用页面按钮样式。

macOS「今日」页使用单一的 `AppButton`（`prominent`，加号与「添加事项」文字），创建类型在现有弹窗的 Tab 中选择。空状态将唯一入口放在说明下方，有任务时移至页头；同一状态不重复显示，也不添加下拉菜单或分隔段。其他页面的既有 `AddTaskControl` 在各自迁移时处理。

macOS `TaskCard` 的状态、恢复/取消和更多操作图标使用 36×36pt 点击区域，并提供清楚的辅助功能名称；iOS 任务行图标继续保持至少 44×44pt 的触控区域。

`AppEmptyState` 的操作可选；没有可执行操作时不显示按钮。`AppErrorState` 的重试可选，不能代替实际错误处理。

macOS 页面使用用户自定义强调色时，可为 `AppEmptyState` 的操作传入 `tint`，使空态按钮与页面主操作一致。

新增组件必须复用 token，提供 Preview，覆盖浅/深色、长文案及大字号；图标操作需有可读的 `.accessibilityLabel` 与合适目标尺寸。`DesignSystemGallery.swift` 集中展示当前已实现的样式与原生控件。原生控件无需额外封装即可使用设计系统的 `.tint` 与语义字体。

## macOS 统一业务弹窗

所有 macOS 短流程详情、创建、编辑、选择和预览使用 `appDialog(isPresented:)` 或 `appDialog(item:)`。任务蓝图与项目蓝图是主窗口工作区页面，通过页面路由打开；其中的节点编辑等短流程继续使用 `appDialog`。添加事项的预加载入口与其他弹窗共用 `AppDialogPanel`、`AppDialogContainer` 和 `AppDialogPresentation`：透明 `NSPanel` 跟随宿主窗口，统一居中遮罩、`AppRadius.prominent` 表面、modal 阴影，以及 92% 放大淡入 / 96% 缩小淡出。内容在展示前测量尺寸，超出宿主可用区域时可滚动，不裁掉操作按钮。系统/应用 Reduce Motion 均跳过位移、缩放与动画等待。

内容用 `@AppDismiss` 关闭；呈现绑定也可直接设为 false。外侧点击与 Escape 默认关闭当前层，有草稿的表单用 `onAppDialogCancel` 复用取消按钮的未保存确认；确认未完成时面板继续保留。嵌套弹窗只关闭最上层并恢复上层焦点，关闭完成后才执行 `onDismiss` 和后续导航。普通业务页面禁止直接使用 sheet、popover 或独立窗口动画；系统错误提示、危险操作确认、文件选择与授权继续使用原生系统面板，iOS/iPadOS 继续原生 sheet。

简单文本输入使用 `AppTextInputDialog`：绑定输入文本，提交闭包返回校验错误时留在弹窗，返回 nil 时关闭。类别重命名和节点阻塞输入采用此组件。Gallery 与 Preview 展示普通、嵌套、输入及浅深色状态。

## macOS 编辑事项

`TaskEditor` 使用独立名称区、原生分组表单和固定底部操作。基本信息、时间安排、备注和子任务按使用频率排列；父任务与旧蓝图的阶段、里程碑、依赖放入「任务归属与更多设置」。编辑模式保持类别纯选择，名称在进场完成后聚焦并全选。

编辑事项和类别选择都由统一面板承载，不再持有窗口动画对象。名称聚焦和全选保留，日期与高级设置展开使用现有标准动效。编辑取消、外侧点击与 Escape 共用未保存确认；进入子任务编辑时使用同一 `appDialog` 建立下一层。Gallery 和 Preview 包含编辑、新建、大字号与深色示例。

## macOS 添加事项动效

主窗口由 `TaskComposerPresentation` 持有弹窗模式，`TaskComposerPanelHost` 缓存三种未编辑表单，但使用与其他业务弹窗相同的 `AppDialogPanel` 和统一生命周期。表单内容负责输入与业务状态，遮罩、表面、透明度和缩放由容器统一管理，避免双重动画和系统 sheet 白底。取消、外侧点击、放弃草稿和创建成功均经统一退场完成后移除；连续添加保留当前面板。

主窗口空闲时预先构建并布局待办、已完成和 AI 生成三种未激活表单；打开时激活对应面板，每次关闭释放已使用表单并准备新的空白实例。宿主窗口尺寸和配色变化时更新缓存，关闭恢复宿主焦点。分类/蓝图中的上下文创建也使用 `appDialog`；菜单栏创建入口打开主窗口并调用同一预加载入口，避免把完整表单限制在菜单栏小窗口内。
