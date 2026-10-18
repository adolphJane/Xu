import SwiftUI

struct DesignSystemGallery: View {
    #if os(macOS)
    @State private var composerPresentation = TaskComposerPresentation()
    @StateObject private var composerStore = TaskStore(inMemory: true)
    @StateObject private var composerPreferences = AppPreferences()
    #endif
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                AppSectionHeader(title: "Colors", subtitle: "语义颜色随浅色和深色外观切换")
                VStack(spacing: AppSpacing.x2) {
                    HStack(spacing: AppSpacing.x3) {
                        swatch("Brand", AppColors.brand)
                        swatch("Action", AppColors.brandAction)
                        swatch("Canvas", AppColors.canvas)
                        swatch("Surface", AppColors.surface)
                    }
                    HStack(spacing: AppSpacing.x3) {
                        swatch("Border", AppColors.border)
                        swatch("Success", AppColors.success)
                        swatch("Warning", AppColors.warning)
                        swatch("Danger", AppColors.danger)
                    }
                }
                AppSectionHeader(title: "Typography")
                Text("Large Title").font(AppTypography.largeTitle)
                Text("Title").font(AppTypography.title)
                Text("Headline").font(AppTypography.headline)
                Text("Body · 一切从清晰的层级开始").font(AppTypography.body)
                Text("Callout · 次要说明").font(AppTypography.callout)
                Text("Caption · 辅助信息").font(AppTypography.caption)
                #if os(macOS)
                AppSectionHeader(title: "统一弹窗", subtitle: "添加事项同款面板，支持嵌套与外侧取消")
                AppDialogExample()
                Text("Desktop · 系统语义字体支持 125% 字号偏好")
                    .font(AppTypography.desktop(.body, scale: 1.25))
                #endif
                AppSectionHeader(title: "Buttons")
                HStack(spacing: AppSpacing.x3) {
                    AppButton(title: "主要操作", systemImage: "plus", size: .prominent) {}
                    AppButton(title: "次要操作", kind: .secondary) {}
                }
                AppButton(title: "紧凑操作", kind: .secondary, size: .compact) {}
                AppButton(title: "处理中", isLoading: true) {}
                AppButton(title: "不可使用", kind: .secondary) {}.disabled(true)
                AppSectionHeader(title: "Forms")
                Form {
                    TextField("事项名称", text: .constant(""))
                    Toggle("每日提醒", isOn: .constant(true))
                }
                .frame(height: 150)
                #if os(macOS)
                AppSectionHeader(title: "Task Composer", subtitle: "淡入放大，缩小淡出，遮罩独立过渡")
                Button("打开添加事项") { composerPresentation.show(.task) }
                AppSectionHeader(title: "Task Editor", subtitle: "分区表单，支持进退场动画与未保存确认")
                TaskEditorExample()
                AppSectionHeader(title: "Category Selection", subtitle: "直接选择类别，支持长名称与明确的选中状态")
                TaskCategoryOptions(
                    categories: ["工作", "生活", "需要持续跟进的长期学习与个人成长计划"],
                    selection: "工作", onSelect: { _ in }, onClose: {}
                )
                #endif
                AppSectionHeader(title: "Cards & Components")
                AppCard {
                    VStack(alignment: .leading, spacing: AppSpacing.x2) {
                        Text("今天，推进最重要的事").font(AppTypography.headline)
                        Text("统一的表面、边框、圆角与间距。").font(AppTypography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                        HStack(spacing: AppSpacing.x2) {
                            AppBadge(title: "进行中")
                            AppBadge(title: "已完成", tone: .success)
                            AppBadge(title: "需关注", tone: .warning)
                        }
                    }
                }
                AppCard(elevated: false) {
                    VStack(alignment: .leading, spacing: AppSpacing.x2) {
                        Label("任务系列 · 默认收起", systemImage: "point.3.connected.trianglepath.dotted")
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                        Text("准备新版首页发布").font(AppTypography.headline)
                        Text("平面卡片通过表面与边框区分系列。").font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                AppSectionHeader(title: "Lists")
                List {
                    Label("整理今日任务", systemImage: "checkmark.circle")
                    Label("复盘蓝图进度", systemImage: "square.stack")
                }
                .frame(height: 112)
                AppSectionHeader(title: "States")
                AppLoadingView(title: "正在同步事项…")
                AppEmptyState(title: "暂无事项", message: "添加任务后会显示在这里。",
                              systemImage: "checkmark.circle", actionTitle: "添加事项") {}
                AppErrorState(title: "加载失败", message: "请检查连接后重试。", retry: {})
            }
            .frame(maxWidth: AppTheme.contentMaxWidth, alignment: .leading)
            .padding(AppSpacing.page)
        }
        .background(AppColors.canvas)
        .tint(AppColors.brand)
        #if os(macOS)
        .environmentObject(composerStore)
        .environmentObject(composerPreferences)
        .overlay {
            TaskComposerPanelHost(presentation: composerPresentation)
                .environmentObject(composerStore)
                .environmentObject(composerPreferences)
        }
        #endif
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.x1) {
            RoundedRectangle(cornerRadius: AppRadius.small)
                .fill(color)
                .frame(height: 42)
            Text(name).font(AppTypography.caption)
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview("Gallery · Light") { DesignSystemGallery().preferredColorScheme(.light) }
#Preview("Gallery · Dark") { DesignSystemGallery().preferredColorScheme(.dark) }
#Preview("Gallery · Large Text") { DesignSystemGallery().dynamicTypeSize(.accessibility1) }
