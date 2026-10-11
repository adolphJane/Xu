import SwiftUI

private enum CategorySelection: Hashable {
    case all
    case uncategorized
    case named(String)

    var title: String {
        switch self {
        case .all: "全部任务"
        case .uncategorized: "未分类"
        case .named(let name): name
        }
    }

    var categoryName: String? {
        if case .named(let name) = self { return name }
        return nil
    }
}

struct TaskCategoriesView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let onSelect: (TaskItem) -> Void

    @State private var selection: CategorySelection = .all
    @State private var newCategory = ""
    @State private var renameValue = ""
    @State private var isRenaming = false
    @State private var isDeleting = false
    @State private var isAddingTask = false

    private var visibleTasks: [TaskItem] {
        store.tasks.filter { task in
            switch selection {
            case .all: true
            case .uncategorized: task.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
            case .named(let name): task.category == name
            }
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                PageHeader(eyebrow: "CATEGORIES", title: "任务分类", description: "按类别整理和查看任务")
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        categoryButton(.all, count: store.tasks.count)
                        categoryButton(.uncategorized, count: store.tasks.filter { $0.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false }.count)
                        Divider().padding(.vertical, 5)
                        ForEach(store.categories, id: \.self) { name in
                            categoryButton(.named(name), count: store.tasks.filter { $0.category == name }.count)
                        }
                        HStack(spacing: 6) {
                            TextField("新类别名称", text: $newCategory)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addCategory)
                            Button(action: addCategory) { Image(systemName: "plus") }
                                .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                                .help("添加类别")
                        }
                        .padding(.top, 8)
                    }
                    .padding(14)
                    .frame(width: 225)
                    .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: preferences.cornerRadius))

                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(selection.title).font(.title2.weight(.semibold))
                                Text("\(visibleTasks.count) 项任务").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selection.categoryName != nil {
                                Menu {
                                    Button("重命名类别") {
                                        renameValue = selection.title
                                        isRenaming = true
                                    }
                                    Button("删除类别", role: .destructive) { isDeleting = true }
                                } label: { Image(systemName: "ellipsis.circle") }
                                    .help("管理类别")
                            }
                            Button("新建任务", systemImage: "plus") { isAddingTask = true }
                                .buttonStyle(.borderedProminent)
                        }
                        if visibleTasks.isEmpty {
                            ContentUnavailableView("这里还没有任务", systemImage: "tag", description: Text("新建任务时选择或输入类别。"))
                                .frame(maxWidth: .infinity, minHeight: 220)
                        } else {
                            LazyVStack(spacing: 9) {
                                ForEach(visibleTasks) { task in
                                    TaskCard(task: task, onSelect: onSelect)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(30)
        }
        .sheet(isPresented: $isAddingTask) {
            TaskComposerView(category: selection.categoryName)
        }
        .alert("重命名类别", isPresented: $isRenaming) {
            TextField("类别名称", text: $renameValue)
            Button("取消", role: .cancel) {}
            Button("保存") {
                guard let oldName = selection.categoryName else { return }
                if store.renameCategory(oldName, to: renameValue) {
                    selection = .named(renameValue.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    store.actionMessage = "类别名称不能为空或与现有类别重复。"
                }
            }
        }
        .confirmationDialog("删除类别后，所属任务会变为未分类。", isPresented: $isDeleting) {
            Button("删除类别", role: .destructive) {
                if let name = selection.categoryName { store.deleteCategory(name) }
                selection = .uncategorized
            }
        }
    }

    private func categoryButton(_ category: CategorySelection, count: Int) -> some View {
        Button {
            selection = category
        } label: {
            HStack {
                Image(systemName: category == .all ? "square.stack" : "tag")
                Text(category.title).lineLimit(1)
                Spacer()
                Text("\(count)").font(.caption.monospacedDigit())
            }
            .font(.subheadline)
            .foregroundStyle(selection == category ? preferences.accentColor : .primary)
            .padding(.horizontal, 10)
            .frame(height: 38)
            .background(selection == category ? preferences.accentColor.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private func addCategory() {
        let name = newCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        store.addCategory(name)
        if let saved = store.categories.first(where: { $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            selection = .named(saved)
        }
        newCategory = ""
    }
}
