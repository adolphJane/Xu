# 序

一个原生 macOS SwiftUI 应用：在菜单栏快速记录事项，通过蓝图、今日任务和四象限执行计划，并可调用 DeepSeek 生成日报。

完整的产品需求与三阶段开发计划见 [产品路线文档](docs/PRODUCT-ROADMAP.md)。
第一阶段的实现与内测清单见 [第一阶段交付记录](docs/PHASE-1-DELIVERY.md)。

## 已实现

- 主窗口：今日、收集箱、蓝图、四象限、日历计划、纪念日、已处理和日报入口
- 聚焦工作台：当前重点、按蓝图汇总的今日行动、进度侧栏、全局快速添加与皮肤切换；交互动画支持“减少动态效果”
- 统一添加面板：主按钮或 ⌘N 直接新增待办，箭头可切换补记完成或 AI 草稿；支持连续添加、蓝图关联、日期快捷选择和按需展开设置
- 艾森豪威尔四象限任务板；任务可编辑、完成、删除或跨象限移动
- 自定义任务类别：创建或编辑时填写类别，在“分类”页面按类别查看、重命名和删除；类别随 JSON 备份与文件夹同步保存
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

## 本地开发调试

开发时直接生成当前 Mac 架构的 `.app`，可双击打开调试：

```bash
zsh scripts/build-app.sh
open dist/序.app
```

产物位于 `dist/序.app`。本地使用临时签名；首次打开可能出现 macOS 安全提示，操作见[内测安装说明](Packaging/INSTALL-TEST.md)。

推送到 `main` 后，GitHub Actions 会生成 Apple Silicon 与 Intel 通用架构的预览 `.dmg` 和包含 `序.app` 的 `-app.zip`，两者分别出现在对应运行记录的 **Artifacts** 中。预览包使用临时签名，不会创建 Release。

## GitHub Releases 自动打包

正式发布时，将 `Packaging/Info.plist` 中的应用版本更新并提交，再推送对应的版本标签。GitHub Actions 会构建通用架构 DMG、独立应用包 ZIP，并创建 GitHub Release：

```bash
git tag v0.5.1
git push origin v0.5.1
```

标签版本必须与 `CFBundleShortVersionString` 一致。`Xu-v版本号.dmg` 和 `Xu-v版本号-app.zip` 会同时作为 Release 附件；ZIP 解压后可直接获得 `序.app`。发布说明会自动列出上一个版本标签之后的提交内容。配置下列 GitHub Actions Secrets 后，工作流会使用 Developer ID 签名、提交 Apple 公证并将公证票据附在 DMG 上：

- `APPLE_CERTIFICATE_P12_BASE64`：Developer ID Application 证书及私钥的 `.p12` 文件内容，以 Base64 编码
- `APPLE_CERTIFICATE_PASSWORD`：导出 `.p12` 时设置的密码
- `APPLE_NOTARY_KEY_P8`：有公证权限的 App Store Connect API Key 文件内容
- `APPLE_NOTARY_KEY_ID`、`APPLE_NOTARY_ISSUER_ID`：对应的 Key ID 和 Issuer ID

五项凭据都未配置时，工作流仍会自动打包，但会将 Release 标记为内测预发布并明确说明 macOS 安全提示。凭据只配置一部分时，构建会失败，避免误发未经公证的正式包。macOS 对来自互联网的应用可能仍会显示一次常规打开确认；Developer ID 签名和公证解决的是“无法验证开发者／无法检查恶意软件”警告。

## 工程结构

- `Sources/Quadrant/QuadrantApp.swift`：应用入口、任务模型、持久化、钥匙串和 DeepSeek 服务
- `Sources/Quadrant/Views.swift`：主界面、菜单栏、任务编辑、日报与设置界面
- `Sources/Quadrant/TodayWorkbenchView.swift`、`WorkbenchStyle.swift`：今日工作台和主窗口视觉交互组件
- `Sources/Quadrant/TaskComposerView.swift`：待办、已完成及 AI 草稿共用的添加流程
- [模块关联与业务逻辑审查](docs/ARCHITECTURE-AND-LOGIC-AUDIT.md)：当前数据流、已修复问题及后续架构重点
