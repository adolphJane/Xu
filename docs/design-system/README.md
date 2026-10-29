# 序 Design System

本规范服务于现有 **macOS 14+** 应用和新增 **iOS/iPadOS 17+** 试点。新增界面先阅读 [设计基础](foundations.md) 与 [组件规范](components.md)，再使用 `Sources/Quadrant/DesignSystem/` 中的语义 token。现有 macOS 主题偏好仍由 `AppPreferences` 管理；iOS 试点默认跟随系统外观。

## 使用顺序

1. 先采用 `NavigationStack`、`NavigationSplitView`、`Form`、`Button`、`ProgressView`、`ContentUnavailableView` 等平台原生控件；页面操作、空态与加载等重复样式使用已有基础组件。
2. 用 `AppColors`、`AppTypography`、`AppSpacing`、`AppRadius`、`AppShadows`、`AppTheme` 表达新增或迁移页面的视觉参数。业务类别颜色应通过主题映射，不将背景/文字色写成业务数据常量。
3. 有跨页面重复的结构才抽成组件；新增组件需说明用途、状态、可访问性，并提供 SwiftUI Preview。
4. 在浅色、深色、大字号、长中文、窄屏或窄窗口、VoiceOver、Reduce Motion 下核对关键流程。

`DesignSystemGallery.swift` 只通过 Preview 展示，不挂入正式导航。当前 iOS 工程位于 `iOS/SequenceIOS.xcodeproj`，已接入“今日”和“分类”两个页面；桌面应用仍使用 SwiftPM 与 `scripts/build-app.sh`。

macOS 业务弹窗统一通过 `appDialog` 使用添加事项同款透明面板，内容用 `@AppDismiss` 关闭、`onAppDialogCancel` 处理草稿确认。添加事项的预加载也复用同一底层；详情、编辑、选择、预览不再使用业务 sheet/popover。系统提示与 iOS/iPadOS 原生呈现保持各平台规则，详见[组件规范](components.md)。

[分类页面设计稿](mockups/categories-design.md) 展示 macOS 与 iPhone 的浅色、深色及空状态布局，供后续渐进式页面改造参考。

[macOS 分类与图标库 V2](mockups/categories-macos-v2.md) 的轻量双栏、类别编辑和可搜索 SF Symbols 图标库已迁移到 macOS 应用；图标作为本机显示偏好保存，不改变任务、备份和同步格式，验证见[迁移记录](rollout.md)。

[任务添加体验分析](task-entry-analysis.md) 对照现有 macOS 与 iOS 入口，提出聚焦式捕获方案；[交互设计稿](mockups/task-entry-concept.html)展示两平台的首屏与上下文预设。

当前优先推进 [macOS 聚焦添加与快速子任务方案](task-entry-macos-subtasks.md)；[macOS 专项交互设计稿](mockups/task-entry-macos-subtasks.html)展示单项添加及按回车连续录入子任务。

[任务视图架构](task-views-architecture.md)明确 `TaskItem` 是唯一任务数据，蓝图、列表与四象限是同一批任务的视图；子任务保存后进入蓝图视图，兼容现有蓝图元数据的边界也记录在其中。

[macOS 日历计划重规划](calendar-plan-redesign.md)定义日期计划、执行时间块、截止时间、日容量和冲突规则，并规划周／日时间轴、月度忙闲与只读系统日历叠加；当前为评审方案，尚未迁移业务页面。

[macOS 事项页面设计稿](mockups/tasks-macos-design.md)梳理范围、展示方式、父子层级、计数与蓝图入口，并提供「层级工作台 / 轻量浏览」两种交互预览及浅深色截图；当前为设计提案，尚未迁移业务页面。

[macOS 事项 V2](mockups/tasks-macos-v2.md)以「轻量浏览」为主方案，强化树形层级、计划/截止标识与按需详情，包含列表、四象限、筛选上下文、深色及无结果设计稿；仍为设计阶段。

[macOS 事项 V3](mockups/tasks-macos-v3.md)按任务系列分为独立卡片，所有系列默认收起，点击后只展开当前系列；四象限也按系列分组，提供浅深色及展开状态设计稿。

逐页迁移范围、组件映射与验证结果记在 [迁移记录](rollout.md)；新增页面参照最近的同平台示例。

[macOS 20 项体验优化技术方案](macos-experience-roadmap-2026-10.md)梳理项目、任务系列、分类与蓝图的边界，以及创建表单、主窗口蓝图、日报模板和周/月/年复盘的实施顺序；文末记录本轮已实施范围与后续数据迁移。[字体审计](typography-audit-2026-10.md)保留实施前的字号基线。

## 背景与进度

[第一阶段审计](ui-audit.md) 记录了迁移前状态；[实施计划](implementation-plan.md) 记录阶段和边界。iOS 与 macOS 的 SwiftData 模型、任务状态规则、旧 JSON 迁移逻辑复用同一批源文件；两平台各有独立沙盒数据，当前不承诺跨设备自动同步。
