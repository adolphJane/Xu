# macOS 字体审计 · 2026-10-20

范围：`Sources/Quadrant/**/*.swift`；包含共享 DesignSystem、Gallery 与 Preview，不包含 iOS 独立源文件。本报告只读检索，不修改字号。

## 检索结果

- `.font(...)` 调用共 432 处。
- 其中以 `.font(.system(size: 数字))` 直接声明固定字号 22 处，低于 13pt 的有 8 处；包含装饰图标，不能全部视为正文缺陷。
- 直接使用 `.caption` / `.caption2` / `.footnote` / `.subheadline` 的调用 122 处；**这不是全部小字号**：`font(.caption1)` 等辅助函数、`AppTypography.caption`、继承自父容器的字体还需按调用链检查。
- 当前已经迁移到 token 的页面也可能过小。`AppTypography.desktop` 直接映射 `NSFont.preferredFont`，没有业务文字最小字号；并非“使用 token 就已经解决可读性”。

## 本机 AppKit 测量

用 `NSFont.preferredFont(forTextStyle:)` 在当前执行环境读取，单位为 pt；不是所有 macOS 设备的固定保证值。

| 系统角色 | 本机点数 |
| --- | ---: |
| largeTitle | 26 |
| title1 | 22 |
| title2 | 17 |
| title3 | 15 |
| headline / body | 13 |
| callout | 12 |
| subheadline | 11 |
| footnote / caption1 / caption2 | 10 |

## 文件分布

下表列的是语法出现次数；调用次数不能直接代表屏幕上实际出现的文字数量。`直接小角色`只统计直接 `.font(.caption...)` 这一类写法。

| 文件 | font 调用 | 固定数字字号 | 数字 <13pt | 直接小角色 |
| --- | ---: | ---: | ---: | ---: |
| [TaskComposerView.swift](../../Sources/Quadrant/TaskComposerView.swift) | 23 | 8 | 4 | 14 |
| [Views.swift](../../Sources/Quadrant/Views.swift) | 77 | 11 | 3 | 36 |
| [WorkbenchStyle.swift](../../Sources/Quadrant/WorkbenchStyle.swift) | 2 | 2 | 1 | 0 |
| [PhaseTwoViews.swift](../../Sources/Quadrant/PhaseTwoViews.swift) | 30 | 1 | 0 | 12 |
| [AITaskView.swift](../../Sources/Quadrant/AITaskView.swift) | 7 | 0 | 0 | 5 |
| [AppDialog.swift](../../Sources/Quadrant/AppDialog.swift) | 4 | 0 | 0 | 0 |
| [BlueprintViews.swift](../../Sources/Quadrant/BlueprintViews.swift) | 24 | 0 | 0 | 11 |
| [BlueprintWorkflowView.swift](../../Sources/Quadrant/BlueprintWorkflowView.swift) | 37 | 0 | 0 | 25 |
| [CalendarPlanView.swift](../../Sources/Quadrant/CalendarPlanView.swift) | 48 | 0 | 0 | 0 |
| [CategoryEditor.swift](../../Sources/Quadrant/CategoryEditor.swift) | 23 | 0 | 0 | 0 |
| [Components.swift](../../Sources/Quadrant/DesignSystem/Components.swift) | 6 | 0 | 0 | 0 |
| [DesignSystemGallery.swift](../../Sources/Quadrant/DesignSystem/DesignSystemGallery.swift) | 13 | 0 | 0 | 0 |
| [PhaseThreeViews.swift](../../Sources/Quadrant/PhaseThreeViews.swift) | 30 | 0 | 0 | 18 |
| [ProcessedHistoryView.swift](../../Sources/Quadrant/ProcessedHistoryView.swift) | 19 | 0 | 0 | 0 |
| [TaskBlueprintView.swift](../../Sources/Quadrant/TaskBlueprintView.swift) | 13 | 0 | 0 | 1 |
| [TaskCategoriesView.swift](../../Sources/Quadrant/TaskCategoriesView.swift) | 20 | 0 | 0 | 0 |
| [TaskCategoryField.swift](../../Sources/Quadrant/TaskCategoryField.swift) | 11 | 0 | 0 | 0 |
| [TaskEditor.swift](../../Sources/Quadrant/TaskEditor.swift) | 16 | 0 | 0 | 0 |
| [TasksHubView.swift](../../Sources/Quadrant/TasksHubView.swift) | 28 | 0 | 0 | 0 |
| [TodayWorkbenchView.swift](../../Sources/Quadrant/TodayWorkbenchView.swift) | 1 | 0 | 0 | 0 |

## 固定小字号位置

- `Sources/Quadrant/TaskComposerView.swift:201`：12pt。
- `Sources/Quadrant/TaskComposerView.swift:226`：12pt。
- `Sources/Quadrant/TaskComposerView.swift:319`：12pt。
- `Sources/Quadrant/TaskComposerView.swift:351`：12pt。
- `Sources/Quadrant/WorkbenchStyle.swift:35`：9pt。
- `Sources/Quadrant/Views.swift:208`：10pt。
- `Sources/Quadrant/Views.swift:251`：10pt。
- `Sources/Quadrant/Views.swift:366`：11pt。

## 执行建议

先定义应用文字角色，再逐文件替换。优先添加事项、日报与复盘、顶部工具区，再处理蓝图画布、列表元信息、分类和记录页；统一检查自定义 `font(...)` 的 `.caption1/.caption2` 映射。字体设计、用户缩放、最小可读字号由一个 resolver 处理，密度只改变间距。图标符号与正文文字分开验收，避免为消除扫描结果而放大所有装饰图形。

建议加入静态审计：业务页禁止新增 `.font(.system(size: ...))`，例外仅在 token 定义、图表几何或有明确理由的装饰图形白名单。静态扫描是提醒，不替代布局、截断、读屏及真实字号验收。

详细角色、分批范围与验收见 [20 项体验优化技术方案](macos-experience-roadmap-2026-10.md)。
