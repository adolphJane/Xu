# 分类页面设计稿

基于 `TaskCategoriesView` 的现有结构与功能绘制。示例任务和计数只用于展示排版，设计稿不连接 SwiftData，也不改变现有页面。

## 查看设计稿

- [交互式设计稿](categories-concept.html)：可切换明暗外观、类别和任务状态。网址参数 `?theme=dark&category=work` 展示深色工作类别，`?theme=dark&category=uncategorized` 展示空状态。
- [macOS 浅色](categories-desktop-light.png) · [macOS 深色](categories-desktop-dark.png)
- [iPhone 浅色](categories-iphone-light.png) · [iPhone 深色空状态](categories-iphone-empty-dark.png)

## 设计意图

现有页面用固定宽度的类别卡片加任务列表完成主要功能，但类别选择、结果标题、状态筛选和新建任务处于接近的视觉层级。新设计保留 macOS 应用侧边栏，在内容区再建立“类别概览 / 当前类别任务”两栏：左侧只负责选择与新增类别，右侧只负责筛选与处理任务。主要按钮放在页面标题旁，任务行保留改类菜单。命名类别选中时才显示管理菜单；重命名与删除仍走系统菜单及确认流程。

颜色延续现有“纸张”主题的暖色调。底色、卡片、边界和强调色建立清楚的层次；类别色点仅用于区分，文字始终承担语义。深色版采用同样的层级关系。任务行减少大面积色块，通过标题字重、日期和项目说明建立阅读顺序。

iPhone 版将类别列表改为横向滚动选择，任务列表改为单列；顶部加号用于新增类别，底部加号用于新建任务。空状态保留明确的下一步操作。最终 SwiftUI 实现应使用原生 `NavigationStack`、`Button`、`Menu`、`confirmationDialog`、`sheet` 和 `ContentUnavailableView`，由 Design Tokens 控制视觉，不直接照搬 HTML 控件。

## 现有功能映射

| 现有功能 | 设计稿位置 |
| --- | --- |
| 所有类别、未分类、自定义类别 | macOS 左侧类别栏 / iPhone 横向类别选择 |
| 新增类别 | macOS 类别栏底部输入 / iPhone 顶部加号 |
| 重命名、删除类别 | 命名类别的标题菜单 |
| 待处理、已处理、全部 | 任务区状态筛选 |
| 新建任务 | 页面主按钮 / iPhone 底部按钮 / 空状态按钮 |
| 点击任务 | 任务行标题及内容区 |
| 更改任务类别 | 任务行尾部菜单 |

## 落地尺寸与检查点

- 维持设计系统的 4pt 间距序列：内容页边距约 20–48pt 随平台和宽度变化；任务区内部 16–28pt；卡片圆角约 16pt。
- macOS 主按钮可见高度约 38pt；iPhone 主操作与分类选择的触控目标至少 44pt。图标按钮需补 `.accessibilityLabel`。
- 页面标题用系统 Title / Large Title 语义字体，任务标题用 Body 或 Subheadline；避免以 HTML 截图中的像素字号直接硬编码 SwiftUI。
- 在 Dynamic Type 下允许任务标题、类别名称和辅助文字换行；窄屏保持横向类别选择和纵向任务滚动。
- 待处理数、已处理数和类别数必须由当前数据及筛选条件实时计算。空状态只在结果确实为空时出现。
- 浅色、深色、高对比度、Reduce Motion、VoiceOver 和键盘操作需要在 SwiftUI 实现时验证。

此稿是视觉与结构方案，不是现有应用截图。HTML 中的按钮与筛选只提供设计演示，未连接业务数据。

macOS 与 iOS 的 SwiftUI 落地情况见[迁移记录](../rollout.md)。实际页面使用实时任务数据和现有平台语义色，设计稿的示例内容不写入用户数据。
