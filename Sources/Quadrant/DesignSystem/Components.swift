import SwiftUI

/// Consistent page actions. Toolbars, form rows, menus, and destructive actions stay native.
struct AppButton: View {
    @Environment(\.colorScheme) private var colorScheme
    enum Kind: Equatable {
        case primary
        case secondary
    }

    enum Size: Equatable {
        case compact
        case regular
        case prominent

        var font: Font {
            switch self {
            case .compact: .subheadline.weight(.medium)
            case .regular: .subheadline.weight(.semibold)
            case .prominent: .body.weight(.semibold)
            }
        }

        var horizontalInset: CGFloat {
            switch self {
            case .compact: AppSpacing.x3
            case .regular: AppSpacing.x4
            case .prominent: AppSpacing.x5
            }
        }

        var visualHeight: CGFloat {
            #if os(iOS)
            switch self {
            case .compact: 32
            case .regular: 36
            case .prominent: 44
            }
            #else
            switch self {
            case .compact: 28
            case .regular: 32
            case .prominent: 38
            }
            #endif
        }

        var hitHeight: CGFloat {
            #if os(iOS)
            max(AppTheme.minimumTouchTarget, visualHeight)
            #else
            visualHeight
            #endif
        }

        var radius: CGFloat {
            switch self {
            case .compact: AppRadius.small
            case .regular: AppRadius.control
            case .prominent: AppRadius.control
            }
        }
    }

    let title: String
    var systemImage: String? = nil
    var kind: Kind = .primary
    var size: Size = .regular
    var tint: Color? = nil
    var isLoading = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.x1) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .tint(kind == .primary ? AppColors.foreground(on: effectiveTint, colorScheme: colorScheme) : effectiveTint)
                } else if let systemImage {
                    Image(systemName: systemImage)
                }
                Text(title)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.center)
            }
        }
        .buttonStyle(AppActionButtonStyle(kind: kind, size: size, tint: effectiveTint))
        .disabled(isLoading)
        .accessibilityLabel(isLoading ? "\(title)，处理中" : title)
    }

    private var effectiveTint: Color { tint ?? AppColors.brandAction }
}

private struct AppActionButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    let kind: AppButton.Kind
    let size: AppButton.Size
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: size.radius, style: .continuous)
        return configuration.label
            .font(size.font)
            .foregroundStyle(kind == .primary ? AppColors.foreground(on: tint, colorScheme: colorScheme) : tint)
            .padding(.horizontal, size.horizontalInset)
            .frame(minHeight: size.visualHeight)
            .background(kind == .primary ? tint : tint.opacity(contrast == .increased ? 0.16 : 0.09), in: shape)
            .overlay(shape.strokeBorder(kind == .primary ? .clear : tint.opacity(contrast == .increased ? 0.48 : 0.24), lineWidth: 1))
            .opacity(isEnabled ? (configuration.isPressed ? 0.82 : 1) : 0.42)
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : 0.985)
            .animation(reduceMotion ? nil : AppTheme.springAnimation, value: configuration.isPressed)
            .frame(minHeight: size.hitHeight)
            .contentShape(Rectangle())
    }
}

struct AppCard<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(AppSpacing.cardContent)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.card))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border))
            .shadow(color: colorScheme == .dark ? .clear : AppShadows.cardColor,
                    radius: AppShadows.cardRadius, y: AppShadows.cardOffset)
    }
}

struct AppSectionHeader: View {
    let title: String
    var subtitle: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x1) {
            Text(title).font(AppTypography.title)
            if let subtitle { Text(subtitle).font(AppTypography.callout).foregroundStyle(AppColors.textSecondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct AppBadge: View {
    enum Tone {
        case brand
        case neutral
        case success
        case warning
        case danger

        var color: Color {
            switch self {
            case .brand: AppColors.brand
            case .neutral: AppColors.textSecondary
            case .success: AppColors.success
            case .warning: AppColors.warning
            case .danger: AppColors.danger
            }
        }
    }

    let title: String
    var tone: Tone = .brand

    var body: some View {
        Text(title)
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(tone.color)
            .padding(.horizontal, AppSpacing.x2)
            .padding(.vertical, AppSpacing.x1)
            .background(tone.color.opacity(0.12), in: Capsule())
    }
}

/// Consistent full-page empty content while keeping the system presentation.
struct AppEmptyState: View {
    let title: String
    let message: String
    var systemImage = "tray"
    var actionTitle: String? = nil
    var tint: Color? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                AppButton(title: actionTitle, tint: tint, action: action)
            }
        }
    }
}

struct AppErrorState: View {
    let title: String
    let message: String
    var retry: (() -> Void)? = nil

    var body: some View {
        AppEmptyState(title: title, message: message, systemImage: "exclamationmark.triangle",
                      actionTitle: retry == nil ? nil : "重试", action: retry)
    }
}

struct AppLoadingView: View {
    var title = "正在加载…"

    var body: some View {
        ProgressView(title)
            .font(AppTypography.callout)
            .frame(maxWidth: .infinity, minHeight: AppTheme.minimumTouchTarget)
            .padding(AppSpacing.section)
            .accessibilityLabel(title)
    }
}

#Preview("Button · Light") {
    VStack(spacing: AppSpacing.x3) {
        AppButton(title: "添加事项", systemImage: "plus", size: .prominent) {}
        AppButton(title: "稍后再说", kind: .secondary) {}
        AppButton(title: "简洁操作", kind: .secondary, size: .compact) {}
        AppButton(title: "保存", isLoading: true) {}
        AppButton(title: "不可使用", kind: .secondary) {}.disabled(true)
    }
    .padding()
    .preferredColorScheme(.light)
}
#Preview("Button · Dark / Large Text") {
    AppButton(title: "添加事项", systemImage: "plus") {}
        .padding().preferredColorScheme(.dark).dynamicTypeSize(.accessibility1)
}
#Preview("Button · Long Text") {
    AppButton(title: "保存当前计划并返回今日页面", kind: .secondary) {}
        .frame(width: 220)
        .padding()
        .dynamicTypeSize(.accessibility1)
}
#if os(macOS)
#Preview("Add task menu · macOS") {
    AddTaskControl(onAddTask: {}, onAddCompleted: {}, onAddWithAI: {})
        .environmentObject(AppPreferences())
        .padding()
}
#endif
#Preview("Card · Dark") {
    AppCard { Text("今日重点").font(AppTypography.headline) }
        .padding().preferredColorScheme(.dark)
}
#Preview("Section header · Large Text") {
    AppSectionHeader(title: "今日行动", subtitle: "按蓝图整理任务")
        .padding().dynamicTypeSize(.accessibility1)
}
#Preview("Badge · Light and Dark") {
    HStack {
        AppBadge(title: "进行中")
        AppBadge(title: "已完成", tone: .success)
        AppBadge(title: "需关注", tone: .warning)
    }
    .padding().preferredColorScheme(.dark)
}
#Preview("Empty state") {
    AppEmptyState(title: "暂无事项", message: "添加任务后会显示在这里。", actionTitle: "添加事项") {}
}
#Preview("Error state") {
    AppErrorState(title: "加载失败", message: "请检查连接后重试。", retry: {})
        .preferredColorScheme(.dark)
}
#Preview("Loading · Large Text") {
    AppLoadingView().dynamicTypeSize(.accessibility1)
}
