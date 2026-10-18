# 设计基础

原则：Modern、Minimal、Elegant、Native、Consistent、Accessible。内容、状态与操作优先于装饰；只在语义确实不同的地方引入自定义视觉。

## 颜色

| 角色 | Token | 用途 |
| --- | --- | --- |
| Brand | `AppColors.brand` | 主要操作、选中和强调；避免同时用作普通正文。 |
| Brand action | `AppColors.brandAction` | 实心按钮底色，浅/深色均保持白色按钮文字可读。 |
| Background | `AppColors.canvas` | 页面底色。 |
| Surface | `AppColors.surface` | 卡片等抬升内容。 |
| Text | `textPrimary` / `textSecondary` | 标题正文与辅助文字，使用系统动态前景色。 |
| Border | `AppColors.border` | 表面分隔。 |
| Status | `success` / `warning` / `danger` | 完成、需注意、危险操作；状态始终同时配文字或图标。 |

macOS 任务的持久完成态使用 `AppColors.taskCompleted(for:)`：纸张主题为暖灰褐，石墨及深色主题使用各自的低饱和灰调，高对比度模式使用黑／白。它与短暂的 `success` 成功反馈分开；任务同时保留勾选图标、划线和状态文字。

iOS 颜色由 `Colors.xcassets` 的 Any/Dark 变体提供，采用与分类设计稿一致的暖纸张色系；macOS 先使用系统动态色，现有个性化主题通过 `AppPreferences` 保留。新增主题映射必须验证浅色、深色及高对比度。避免把 HEX 直接写进业务视图。不要仅靠颜色传达状态。

实心按钮文字通过 `AppColors.foreground(on:)` 按背景明度选择黑或白；macOS 自定义强调色也走同一规则，避免浅色主题出现白字低对比度。

## 字体

`AppTypography` 提供 Large Title、Title、Headline、Body、Callout、Caption 语义角色。优先系统字体、系统字重，不固定行高。iOS 用系统 Dynamic Type 自动缩放；布局允许纵向增长，非必要不截断主要信息。macOS 保留现有字体偏好，但新页面采用角色样式，不新增一套固定字号。数字进度可使用 `monospacedDigit()`。

macOS 需要应用用户字号与字体偏好时，使用 `AppTypography.desktop(_:scale:weight:design:)`。它从 AppKit 的系统文字角色读取基准大小，再应用用户的缩放与字体设计；「今日」页已接入此 API。iOS 继续使用现有系统语义字体与 Dynamic Type。

## 间距与形状

4pt 基础序列：4、8、12、16、20、24、28、32pt，对应 `AppSpacing.x1` 至 `x8`。页面水平边距使用 `AppSpacing.page`（20pt），卡片内部使用 `cardContent`（16pt），区域之间使用 `section`（24pt），列表卡片之间使用 `list`（12pt）。`AppRadius`：8pt 小元素、12pt 控件、16pt 卡片、20pt 重点容器。边框使用语义 `border`；阴影只用于需要层级的卡片，使用 `AppShadows`，深色外观下卡片通过表面和边框区分层级。

## 动效

轻微状态切换可用约 0.22 秒 easeInOut；连续交互可用约 0.35 秒弹簧。优先系统转场；加载用 `ProgressView`，保存/错误用清楚的文字反馈。读取 `accessibilityReduceMotion`，减少动态效果时移除非必要动画，保留状态提示。添加事项使用 `AppTheme.composerEnterAnimation` 的轻柔弹簧放大与渐入，`composerExitAnimation` 的短促缩小与渐出；比例分别由 `composerInitialScale` / `composerDismissedScale` 管理。叠加弹窗的固定轮廓阴影使用 `AppShadows.modalColor` / `modalRadius` / `modalOffset`。

## 布局与导航

- iPhone：单一试点页面用 `NavigationStack`、系统导航栏和 sheet；不为一个入口强加 Tab Bar。未来有多个一级区域时再评估 Tab Bar。
- iPad：同一内容使用弹性最大宽度和自适应列；信息层级适合时可扩展到 `NavigationSplitView`。
- macOS：维持现有 `NavigationSplitView`、侧边栏、顶部工具区、设置标签页和菜单栏场景。
- 页面尊重系统 Safe Area；滚动内容用 `ScrollView`/`List`，编辑使用 `Form`，确认使用系统 sheet/alert/confirmation dialog。触控目标至少 44pt；桌面图标按钮提供可见焦点、键盘与 VoiceOver 路径。

设计参考：Apple [Color](https://developer.apple.com/design/human-interface-guidelines/color)、[Dark Mode](https://developer.apple.com/design/human-interface-guidelines/dark-mode)、[Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility)、[Sidebars](https://developer.apple.com/design/human-interface-guidelines/sidebars)。
