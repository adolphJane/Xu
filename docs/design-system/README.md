# 序 · Design System

当前 macOS 主应用使用 Flutter。**新页面与改版以 [Flutter macOS 设计规范](flutter/README.md) 为准**；本目录其余文档及 `mockups/` 是旧 SwiftUI 应用的设计记录和迁移参照，不再作为 Flutter 组件 API 或实现状态的说明。

## Flutter 规范

1. [总览、使用方式与迁移边界](flutter/README.md)
2. [基础 Token：主题、文字、间距、响应式与动效](flutter/foundations.md)
3. [组件契约：状态、交互、弹窗与桌面能力](flutter/components.md)
4. [页面模式：任务、蓝图及其他工作台](flutter/page-patterns.md)
5. [验收矩阵与落地顺序](flutter/validation.md)

## 旧版参考

- [SwiftUI 设计基础](foundations.md)、[SwiftUI 组件规范](components.md)：保留旧版语义和参数，**不能照搬其中的 `AppColors`、`AppCard`、`appDialog` 等 SwiftUI API**；旧版源码在 `legacy-macos/`。
- [事项 V3](mockups/tasks-macos-v3.md)、[今日工作台](mockups/today-macos-redesign-v3.md)、[分类 V2](mockups/categories-macos-v2.md)、[日历规划](calendar-plan-redesign.md)：作为信息结构、交互规则和视觉方向的参考；其中尚未在 Flutter 落地的功能不视为已交付。
- [迁移记录](rollout.md)、[旧版 UI 审计](ui-audit.md)：记录 SwiftUI 阶段的决策和发现。

Flutter 实际功能与待办以 [迁移进度](../FLUTTER-MIGRATION.md) 为准。旧 `legacy-macos/Sources/` 与 `iOS/` 不因本规范而改动。
