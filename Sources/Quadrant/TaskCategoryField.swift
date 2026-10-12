import SwiftUI

struct TaskCategoryField: View {
    @EnvironmentObject private var store: TaskStore
    @Binding var category: String
    @FocusState private var isEditingCategory: Bool

    private var selectedCategory: String {
        category.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func selectCategory(_ name: String) {
        isEditingCategory = false
        category = name
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .foregroundStyle(.secondary)
                .frame(width: 17)
            Text("类别")
                .font(.subheadline)
            Spacer(minLength: 8)
            HStack(spacing: 6) {
                TextField("未分类 / 输入新类别", text: $category)
                    .textFieldStyle(.roundedBorder)
                    .focused($isEditingCategory)
                    .accessibilityLabel("类别，可输入新类别")
                Menu {
                    Button {
                        selectCategory("")
                    } label: {
                        if selectedCategory.isEmpty {
                            Label("未分类", systemImage: "checkmark")
                        } else {
                            Text("未分类")
                        }
                    }
                    ForEach(store.categories, id: \.self) { name in
                        Button {
                            selectCategory(name)
                        } label: {
                            if selectedCategory.localizedCaseInsensitiveCompare(name) == .orderedSame {
                                Label(name, systemImage: "checkmark")
                            } else {
                                Text(name)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                        .frame(width: 20, height: 24)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("选择类别或设为未分类")
                .accessibilityLabel("选择类别")
            }
            .frame(maxWidth: 250)
        }
    }
}
