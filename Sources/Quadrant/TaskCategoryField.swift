import SwiftUI

struct TaskCategoryField: View {
    @EnvironmentObject private var store: TaskStore
    @Binding var category: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "tag")
                .foregroundStyle(.secondary)
            TextField("类别（可输入新类别）", text: $category)
                .textFieldStyle(.plain)
            if !store.categories.isEmpty {
                Menu {
                    Button("未分类") { category = "" }
                    ForEach(store.categories, id: \.self) { name in
                        Button(name) { category = name }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("选择已有类别")
            }
        }
    }
}
