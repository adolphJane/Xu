# 项目协作约束

本文件适用于整个仓库。当前开发范围仅为 macOS 14+ SwiftUI 应用（Swift Package Manager 构建），任务数据由 SwiftData 持久化。仓库仍保留 `iOS/SequenceIOS.xcodeproj`，但日常开发不修改、不验证 iOS 应用逻辑；只有用户明确提出 iOS 工作时才纳入范围。

## 当前迭代优先级

- 当前阶段优先处理 macOS 应用；除非用户明确提出 iOS/iPadOS 需求，暂不主动开展 iOS/iPadOS 的界面迁移、功能迭代或专门验收。
- macOS 单平台改动只需按 macOS 流程构建并打开开发版 `.app`，不因通用迁移规范而额外要求 iOS 构建。修改共用模型、服务或持久化代码时，仍须保持 iOS/iPadOS 源码兼容；当改动可能影响 iOS/iPadOS 编译或行为时，再执行对应验证。
- 用户明确要求跨平台或 iOS/iPadOS 工作时，再按本文件的双平台要求处理，并在 `docs/design-system/rollout.md` 记录相关范围与验证结果。

## 开发与数据

- 修改任务模型或持久化结构时，兼顾已有用户数据、旧版 JSON 备份和文件夹同步格式。
- 不将 API Key、Apple 签名证书、私钥、密码或 GitHub Secrets 写入源码、文档示例值或提交记录。
- 构建产物放在 `dist/`；该目录不提交到 Git。

## 构建产物与发布

- **本地开发调试只交付 `.app`**：在仓库根目录运行 `zsh scripts/build-app.sh`，产物为 `dist/序.app`。需要打开时运行 `open dist/序.app`。本地调试不要以生成 `.dmg` 作为默认步骤。
- **每次修改代码后都必须生成并打开开发版 `.app`，让用户查看实际结果**：运行 `zsh scripts/build-app.sh` 更新 `dist/序.app`，然后运行 `open dist/序.app`。完成回复前确认应用已成功构建并打开；仅修改文档时无需重新构建应用。
- `scripts/build-app.sh` 是组装应用包的统一入口。修改应用包内容时，同时确认本地构建和 CI 打包都使用该脚本，避免两套组装逻辑分叉。
- **推送 `main` 后由 GitHub Actions 生成预览 `.dmg`**：`.github/workflows/preview.yml` 调用 `scripts/package-unsigned.sh`，产物上传为该次运行的 Artifact。预览包使用临时签名，不创建 GitHub Release。
- **发布版本通过 tag 生成 `.dmg`**：先更新 `Packaging/Info.plist` 的版本号并提交，再推送与 `CFBundleShortVersionString` 一致的 `vX.Y.Z` 标签。`.github/workflows/release.yml` 调用 `scripts/package-macos.sh`，生成通用架构 DMG，附上自上个版本以来的变更说明并创建 GitHub Release。
- GitHub Actions 的 DMG 应同时包含 Apple Silicon 和 Intel 架构，并提供将 `序.app` 拖入“应用程序”的入口。只有配置完整的 Apple 签名与公证凭据时，才将包标记为已签名、公证。
- 完成构建或发布相关修改后，核对实际产物及对应的 Actions 运行结果；不要仅凭命令已启动就报告成功。

## UI Design System

- 所有 UI 开发先阅读 `docs/design-system/README.md`，再按需查看 `foundations.md`、`components.md` 与迁移记录。已确认的方向是 Modern、Minimal、Elegant、Native、Consistent、Accessible；遵循 Apple Human Interface Guidelines。
- 优先复用平台原生控件和现有组件。页面操作、卡片、分区标题、状态标签及页面状态按 `components.md` 选用；表单、搜索、导航、列表和系统提示保持原生行为，不为统一外观而重复封装。
- 新增或迁移 UI 使用 `Sources/Quadrant/DesignSystem/` 的语义 Design Tokens：颜色按用途选 `AppColors`，系统字体选 `AppTypography`，间距遵循 4pt 阶梯及 `AppSpacing` 的页面/卡片/分区/列表角色，形状和动效分别选 `AppRadius`、`AppShadows`、`AppTheme`。不要在业务页面新增任意 HEX、固定字号、圆角或阴影。
- 页面按钮遵循 `docs/design-system/components.md` 的 `compact` / `regular` / `prominent` 尺寸与主要/次要层级；不要在 `AppButton` 内叠加系统按钮样式、重复设置高度或在业务页面另写按钮边距。工具栏、表单和菜单的系统按钮保持平台默认交互。
- **macOS 业务弹窗统一使用添加事项的弹窗方式**：详情、编辑、创建、选择、预览等入口使用统一的 `appDialog` / `AppDialogPanel`，复用透明 `NSPanel`、居中遮罩、圆角表面、淡入放大与缩小淡出、Reduce Motion 和焦点恢复；添加事项的预加载面板也必须使用相同底层实现。业务页不得直接新增 `.sheet`、`.popover`、旧 `clickAwaySheet` / `clickAwayPopover` 或独立窗口动画实现。关闭通过 `@AppDismiss` 或呈现绑定处理，外侧点击与 Escape 通过 `onAppDialogCancel` 复用表单的未保存确认；嵌套弹窗只关闭最上层，退场结束后再执行 `onDismiss` / 后续导航。系统错误提示、危险操作确认、文件选择及系统授权继续使用原生 alert、confirmationDialog 和系统面板；iOS/iPadOS 保留原生 sheet，不套用 macOS 面板。
- 同时支持浅色与深色、Dynamic Type/文字放大、VoiceOver、合理点击区域、长中文和 Reduce Motion；状态不能只靠颜色表达。迁移页面至少检查空态、有数据状态和主要操作。
- UI 修改只面向 macOS，保留 `AppPreferences` 的主题、密度和字号偏好，以及现有侧边栏和窗口交互。默认只验证 macOS 目标，不要求检查或编译 iOS 目标。
- 逐页迁移，不一次性重写应用；只替换呈现层，不改任务模型、SwiftData、API、备份格式和既有操作语义。每迁移一页，在 `docs/design-system/rollout.md` 记录范围、组件映射和验证结果。
- 保持视觉层级、间距、状态和交互一致；无明确原因不引入第三方 UI 框架，不随意修改全局设计规范。确需修改 token 或组件 API 时，先检查 macOS 调用处及现有主题。
- 新增组件时同步更新 `components.md`、`DesignSystemGallery.swift` 和 SwiftUI Preview；Gallery 只用于预览，不进入正式业务导航。
