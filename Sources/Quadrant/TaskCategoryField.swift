import SwiftUI

struct TaskCategoryField: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var category: String
    var allowsCustomInput = true
    @State private var isPickerPresented = false

    private var selectedCategory: String {
        category.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var availableCategories: [String] {
        guard !selectedCategory.isEmpty,
              !store.categories.contains(where: { $0.localizedCaseInsensitiveCompare(selectedCategory) == .orderedSame })
        else { return store.categories }
        return [selectedCategory] + store.categories
    }

    var body: some View {
        HStack(spacing: AppSpacing.x3) {
            Label("类别", systemImage: "tag")
                .font(AppTypography.callout)
                .foregroundStyle(AppColors.textSecondary)
            Spacer(minLength: AppSpacing.x2)
            HStack(spacing: AppSpacing.x2) {
                if allowsCustomInput {
                    TextField("输入新类别", text: $category)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("类别，可输入新类别")
                        .frame(minWidth: 100, maxWidth: 170)
                }
                Button {
                    isPickerPresented = true
                } label: {
                    HStack(spacing: AppSpacing.x3) {
                        Text(selectedCategory.isEmpty ? "未分类" : selectedCategory)
                            .font(AppTypography.callout.weight(.medium))
                            .foregroundStyle(selectedCategory.isEmpty ? AppColors.textSecondary : AppColors.textPrimary)
                            .lineLimit(1)
                        Spacer(minLength: AppSpacing.x2)
                        Image(systemName: "chevron.up.chevron.down")
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .padding(.horizontal, AppSpacing.x3)
                    .padding(.vertical, AppSpacing.x2)
                    .frame(minHeight: AppSpacing.x8 + AppSpacing.x1)
                    .background(preferences.accentColor.opacity(isPickerPresented ? 0.12 : 0.05),
                                in: RoundedRectangle(cornerRadius: AppRadius.small))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.small)
                            .stroke(isPickerPresented ? preferences.accentColor : AppColors.border, lineWidth: 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: AppRadius.small))
                }
                .buttonStyle(.plain)
                .frame(width: allowsCustomInput ? 130 : 220)
                .help(selectedCategory.isEmpty ? "选择类别" : selectedCategory)
                .accessibilityLabel("选择类别")
                .accessibilityValue(selectedCategory.isEmpty ? "未分类" : selectedCategory)
                .appDialog(isPresented: $isPickerPresented) {
                    TaskCategoryOptions(
                        categories: availableCategories, selection: selectedCategory,
                        tint: preferences.accentColor, surface: preferences.cardBackground,
                        onSelect: { category = $0; isPickerPresented = false },
                        onClose: { isPickerPresented = false }
                    )
                }
            }
        }
    }
}

/// Custom category chooser shared by the field and design previews; it never creates categories.
struct TaskCategoryOptions: View {
    let categories: [String]
    let selection: String
    var tint: Color = AppColors.brand
    var surface: Color = AppColors.surface
    let onSelect: (String) -> Void
    let onClose: () -> Void
    @State private var hoveredCategory: String?

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x3) {
            HStack(spacing: AppSpacing.x2) {
                Text("选择类别").font(AppTypography.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: AppSpacing.x7, height: AppSpacing.x7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭类别选择")
            }
            .padding(.leading, AppSpacing.x1)

            option("", title: "未分类", subtitle: "暂不归入任何类别")

            if categories.isEmpty {
                Text("可在「分类」页面添加类别")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.x3)
                    .padding(.bottom, AppSpacing.x2)
            } else {
                Divider()
                HStack {
                    Text("已有类别")
                    Spacer()
                    Text("\(categories.count)")
                        .monospacedDigit()
                }
                .font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.x3)

                ScrollView {
                    VStack(spacing: AppSpacing.x1) {
                        ForEach(categories, id: \.self) { name in
                            option(name, title: name)
                        }
                    }
                    .padding(AppSpacing.x1)
                }
                .frame(height: min(CGFloat(categories.count) * (AppSpacing.x8 + AppSpacing.x5) + AppSpacing.x1, 280))
                .scrollIndicators(.automatic)
            }
        }
        .padding(AppSpacing.x3)
        .frame(width: 300)
        .foregroundStyle(AppColors.textPrimary)
        .background(surface, in: RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay {
            RoundedRectangle(cornerRadius: AppRadius.card)
                .stroke(AppColors.border.opacity(0.6), lineWidth: 1)
        }
    }

    private func option(_ name: String, title: String, subtitle: String? = nil) -> some View {
        let isSelected = selection.localizedCaseInsensitiveCompare(name) == .orderedSame
        let isHovered = hoveredCategory == name
        return Button { onSelect(name) } label: {
            HStack(spacing: AppSpacing.x3) {
                Image(systemName: name.isEmpty ? "tray" : "tag")
                    .font(AppTypography.callout)
                    .foregroundStyle(isSelected ? tint : AppColors.textSecondary)
                    .frame(width: AppSpacing.x8, height: AppSpacing.x8)
                    .background(tint.opacity(isSelected ? 0.12 : 0.05),
                                in: RoundedRectangle(cornerRadius: AppRadius.small))
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    Text(title)
                        .font(AppTypography.callout.weight(isSelected ? .semibold : .regular))
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                }
                Spacer(minLength: AppSpacing.x2)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(AppTypography.body)
                    .foregroundStyle(isSelected ? tint : AppColors.border)
                    .accessibilityHidden(true)
            }
            .padding(AppSpacing.x2)
            .frame(maxWidth: .infinity, minHeight: AppSpacing.x8 + AppSpacing.x4, alignment: .leading)
            .background(isSelected ? tint.opacity(0.1) : (isHovered ? tint.opacity(0.05) : Color.clear),
                        in: RoundedRectangle(cornerRadius: AppRadius.control))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control))
        }
        .buttonStyle(.plain)
        .onHover { hoveredCategory = $0 ? name : nil }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview("类别选择 · 长中文") {
    TaskCategoryOptions(categories: ["工作", "生活", "需要持续跟进的长期学习与个人成长计划"],
                        selection: "工作", onSelect: { _ in }, onClose: {})
}

#Preview("类别选择 · 深色空态") {
    TaskCategoryOptions(categories: [], selection: "", onSelect: { _ in }, onClose: {})
        .preferredColorScheme(.dark)
}
