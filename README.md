# 序

一个原生 macOS SwiftUI 应用：在菜单栏快速记录事项，通过蓝图、今日任务和四象限执行计划，并可调用 DeepSeek 生成日报。

完整的产品需求与三阶段开发计划见 [产品路线文档](docs/PRODUCT-ROADMAP.md)。
第一阶段的实现与内测清单见 [第一阶段交付记录](docs/PHASE-1-DELIVERY.md)。

## 已实现

- 主窗口：今日、收集箱、蓝图、四象限、日历计划、纪念日、已处理和日报入口
- 聚焦工作台：当前重点、按蓝图汇总的今日行动、进度侧栏、全局快速添加与皮肤切换；交互动画支持“减少动态效果”
- 统一添加面板：主按钮或 ⌘N 直接新增待办，箭头可切换补记完成或 AI 草稿；支持连续添加、蓝图关联、日期快捷选择和按需展开设置
- 艾森豪威尔四象限任务板；任务可编辑、完成、删除或跨象限移动
- 菜单栏窗口：查看今日待办、勾选完成、快速新增、打开主界面
- 可从菜单栏或今日页“补记已完成”事项，立即计入今日完成数和日报
- 任务、蓝图、纪念日和日报持久化到本机 SwiftData；旧版任务可从 `UserDefaults` 迁移
- 设置页保存 DeepSeek API Key 至 macOS 钥匙串
- 应用设置：外观模式、新事项默认象限与时长、每日复盘通知、DeepSeek 模型与接口地址
- DeepSeek `deepseek-chat` 日报生成、结果编辑及复制 Markdown
- SwiftData 业务数据持久化与旧版任务迁移
- 蓝图节点工作流：任务连线支持串行、并行和汇合，前置任务完成后才可执行后续任务；支持快速添加、批量创建、自动排版与撤销重做
- 节点可选图片：选择、拖入或粘贴图片，无图节点保持紧凑；图片随本地数据和 JSON 备份保存
- 蓝图阶段、里程碑、关联任务和进度统计
- AI 一句话生成可编辑任务草稿
- 日报字数预设/自定义、长度校验和历史归档
- 任务进行中、延期、阻塞等执行状态

## 运行

在 macOS 14 或更新版本、已安装 Xcode 16 的环境中执行：

```bash
swift run
```

首次使用 AI 任务、蓝图、重新规划或日报前，请在“设置”中填写 DeepSeek API Key。日报请求包含当天相关任务的项目、标题、分类、象限、状态、预计时长，以及用户主动填写的备注、阻塞原因和日报补充。

## 无账号内测打包

可在具备 Xcode 的 Mac 上执行下列命令，生成适用于 Apple Silicon 与 Intel Mac 的未公证 `.dmg`：

```bash
zsh scripts/package-unsigned.sh
```

产物保存在 `dist/`，并附带 [内测安装说明](Packaging/INSTALL-TEST.md)。该包为 ad-hoc 签名，首次打开会出现 macOS 安全确认；正式分发仍需 Developer ID 签名与 Apple 公证。

## GitHub Releases 自动打包

将 `Packaging/Info.plist` 中的应用版本更新并提交后，推送对应的版本标签即可触发 GitHub Actions 自动构建通用架构 DMG，并创建 GitHub Release：

```bash
git tag v0.4.2
git push origin v0.4.2
```

标签版本必须与 `CFBundleShortVersionString` 一致。生成的 `Xu-v版本号.dmg` 会作为 Release 附件发布，说明会自动列出上一个版本标签之后的提交内容，并附上安装提示。构建使用 ad-hoc 签名，首次打开仍需按内测安装说明确认；正式分发仍需 Developer ID 签名与 Apple 公证。

## 工程结构

- `Sources/Quadrant/QuadrantApp.swift`：应用入口、任务模型、持久化、钥匙串和 DeepSeek 服务
- `Sources/Quadrant/Views.swift`：主界面、菜单栏、任务编辑、日报与设置界面
- `Sources/Quadrant/TodayWorkbenchView.swift`、`WorkbenchStyle.swift`：今日工作台和主窗口视觉交互组件
- `Sources/Quadrant/TaskComposerView.swift`：待办、已完成及 AI 草稿共用的添加流程
- [模块关联与业务逻辑审查](docs/ARCHITECTURE-AND-LOGIC-AUDIT.md)：当前数据流、已修复问题及后续架构重点
