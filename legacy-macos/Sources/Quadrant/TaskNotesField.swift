import SwiftUI

/// Multiline task notes shared by the creation and editing flows.
struct TaskNotesField: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Binding var text: String
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            if showsTitle {
                Label("备注", systemImage: "text.alignleft")
                    .font(AppTypography.desktop(.body, scale: preferences.fontScale,
                                                weight: .semibold, design: preferences.fontStyle.design))
            }
            TextField("补充背景、链接或下一步说明…", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.plain)
                .font(AppTypography.desktop(.body, scale: preferences.fontScale,
                                            design: preferences.fontStyle.design))
                .padding(AppSpacing.x3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.control).stroke(AppColors.border))
                .accessibilityLabel("备注，可选")
        }
    }
}

#Preview("备注 · 长文本") {
    @Previewable @State var notes = "项目背景和下一步计划可以写在这里。\n附上必要的链接，方便回看。"
    TaskNotesField(text: $notes)
        .environmentObject(AppPreferences())
        .padding()
}
