import SwiftUI

private enum IOSCategorySelection: Hashable {
    case all
    case uncategorized
    case named(String)

    var title: String {
        switch self {
        case .all: "所有类别"
        case .uncategorized: "未分类"
        case .named(let name): name
        }
    }

    var categoryName: String? {
        if case .named(let name) = self { return name }
        return nil
    }

    func includes(_ task: TaskItem) -> Bool {
        switch self {
        case .all: true
        case .uncategorized: task.category?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false
        case .named(let name): task.category == name
        }
    }
}

private enum IOSCategoryScope: String, CaseIterable, Identifiable {
    case active = "待处理"
    case processed = "已处理"
    case all = "全部"

    var id: Self { self }

    func includes(_ task: TaskItem) -> Bool {
        switch self {
        case .active: task.needsAction
        case .processed: !task.needsAction
        case .all: true
        }
    }
}

struct IOSCategoriesView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: IOSCategorySelection = .all
    @State private var scope: IOSCategoryScope = .active
    @State private var newCategory = ""
    @State private var renameValue = ""
    @State private var showingCreateCategory = false
    @State private var showingRename = false
    @State private var showingDelete = false
    @State private var showingComposer = false
    @State private var selectedTask: TaskItem?

    private var selectedTasks: [TaskItem] { store.tasks.filter { selection.includes($0) } }
    private var visibleTasks: [TaskItem] {
        selectedTasks.filter { scope.includes($0) }.sorted {
            if scope == .active {
                if $0.isUnscheduled != $1.isUnscheduled { return !$0.isUnscheduled }
                return $0.scheduledFor < $1.scheduledFor
            }
            return $0.createdAt > $1.createdAt
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    heading
                    categories
                    taskPanel
                }
                .frame(maxWidth: AppTheme.contentMaxWidth)
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.x5)
                .frame(maxWidth: .infinity)
            }
            .background(AppColors.canvas)
            .navigationTitle("分类")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加类别", systemImage: "plus") { showingCreateCategory = true }
                        .accessibilityLabel("添加类别")
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Spacer()
                    Button { showingComposer = true } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.medium))
                            .foregroundStyle(AppColors.foreground(on: AppColors.brandAction, colorScheme: colorScheme))
                            .frame(width: 56, height: 56)
                            .background(AppColors.brandAction, in: RoundedRectangle(cornerRadius: AppRadius.card))
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("新建任务")
                }
                .padding(.horizontal, AppSpacing.page)
                .padding(.bottom, AppSpacing.x2)
                .background(.clear)
            }
            .sheet(isPresented: $showingComposer) { IOSTaskComposerView(category: selection.categoryName) }
            .sheet(item: $selectedTask) { task in IOSTaskDetailView(taskID: task.id) }
            .alert("新建类别", isPresented: $showingCreateCategory) {
                TextField("类别名称", text: $newCategory)
                Button("取消", role: .cancel) { newCategory = "" }
                Button("添加") { addCategory() }
                    .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .alert("重命名类别", isPresented: $showingRename) {
                TextField("类别名称", text: $renameValue)
                Button("取消", role: .cancel) {}
                Button("保存") { renameCategory() }
            }
            .confirmationDialog("删除类别后，所属任务会变为未分类。", isPresented: $showingDelete) {
                Button("删除类别", role: .destructive) {
                    if let name = selection.categoryName { store.deleteCategory(name) }
                    selection = .uncategorized
                }
            }
            .alert("操作提示", isPresented: Binding(
                get: { store.actionMessage != nil },
                set: { if !$0 { store.actionMessage = nil } }
            )) { Button("知道了") { store.actionMessage = nil } }
                message: { Text(store.actionMessage ?? "") }
        }
    }

    private var heading: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            Text("ORGANIZE YOUR WORK")
                .font(AppTypography.caption.weight(.bold))
                .tracking(2)
                .foregroundStyle(AppColors.brand)
            Text("任务分类")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
            Text("把相近的事放在一起，让每一步都更清晰。")
                .font(AppTypography.callout)
                .foregroundStyle(AppColors.textSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var categories: some View {
        ScrollView(.horizontal) {
            HStack(spacing: AppSpacing.x2) {
                categoryChip(.all)
                categoryChip(.uncategorized)
                ForEach(store.categories, id: \.self) { categoryChip(.named($0)) }
                Button { showingCreateCategory = true } label: {
                    Label("新类别", systemImage: "plus")
                        .font(AppTypography.callout.weight(.medium))
                        .frame(minHeight: AppTheme.minimumTouchTarget)
                        .padding(.horizontal, AppSpacing.x3)
                        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.control))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("添加类别")
            }
            .padding(.vertical, AppSpacing.x1)
        }
        .scrollIndicators(.hidden)
        .contentMargins(.trailing, AppSpacing.page)
    }

    private func categoryChip(_ category: IOSCategorySelection) -> some View {
        let count = store.tasks.filter { category.includes($0) }.count
        return Button { selection = category } label: {
            Text("\(category.title) \(count)")
                .font(AppTypography.callout.weight(selection == category ? .semibold : .regular))
                .foregroundStyle(selection == category ? AppColors.brand : AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.x3)
                .frame(minHeight: AppTheme.minimumTouchTarget)
                .background(selection == category ? AppColors.brand.opacity(0.12) : AppColors.surface,
                            in: RoundedRectangle(cornerRadius: AppRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.control)
                    .stroke(selection == category ? AppColors.brand.opacity(0.22) : AppColors.border))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title)，\(count) 项任务")
        .accessibilityAddTraits(selection == category ? .isSelected : [])
    }

    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AppSpacing.x3) {
                Image(systemName: selection == .all ? "square.stack" : "tag")
                    .font(AppTypography.headline)
                    .foregroundStyle(AppColors.brand)
                    .frame(width: AppSpacing.x8, height: AppSpacing.x8)
                    .background(AppColors.brand.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.small))
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    Text(selection.title).font(AppTypography.title)
                    Text("\(selectedTasks.count) 项任务 · \(selectedTasks.filter(\.needsAction).count) 项待处理")
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: AppSpacing.x1)
                if selection.categoryName != nil {
                    Menu {
                        Button("重命名类别") { renameValue = selection.title; showingRename = true }
                        Button("删除类别", role: .destructive) { showingDelete = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: AppTheme.minimumTouchTarget, height: AppTheme.minimumTouchTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel("管理\(selection.title)类别")
                }
            }
            .padding(AppSpacing.cardContent)
            Picker("任务状态", selection: $scope) {
                ForEach(IOSCategoryScope.allCases) { option in
                    Text("\(option.rawValue) \(selectedTasks.filter { option.includes($0) }.count)").tag(option)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, AppSpacing.cardContent)
            .padding(.bottom, AppSpacing.cardContent)
            Divider()
            if visibleTasks.isEmpty {
                AppEmptyState(
                    title: scope == .active ? "这个类别还没有待处理任务" : "这里还没有任务",
                    message: scope == .active ? "新建一项任务，或切换状态查看已有记录。" : "可以切换任务状态，或新建任务。",
                    systemImage: "tag",
                    actionTitle: "新建任务"
                ) { showingComposer = true }
                .frame(maxWidth: .infinity, minHeight: 290)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleTasks) { task in
                        taskRow(task)
                        if task.id != visibleTasks.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, AppSpacing.cardContent)
                Text("共 \(visibleTasks.count) 项\(scope.rawValue)任务")
                    .font(AppTypography.caption.monospacedDigit())
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(AppSpacing.cardContent)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColors.surface, in: RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border))
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.x2) {
            Button {
                withAnimation(AppTheme.animation(reduceMotion: reduceMotion)) { store.toggle(task) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.square.fill" : "square")
                    .font(.title3)
                    .frame(minWidth: AppTheme.minimumTouchTarget, minHeight: AppTheme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(task.isCompleted ? AppColors.success : AppColors.brand)
            .disabled(!task.isCompleted && store.executionBlockReason(for: task) != nil)
            .accessibilityLabel(task.isCompleted ? "恢复\(task.title)" : "完成\(task.title)")
            Button { selectedTask = task } label: {
                VStack(alignment: .leading, spacing: AppSpacing.x2) {
                    Text(task.title)
                        .font(AppTypography.body.weight(.medium))
                        .foregroundStyle(AppColors.textPrimary)
                        .strikethrough(task.isCompleted || task.isCancelled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    HStack(spacing: AppSpacing.x2) {
                        if !task.isUnscheduled {
                            Text(task.scheduledFor, format: .dateTime.month().day().hour().minute())
                        }
                        if task.projectName != "未归类项目" { Text("· \(task.projectName)") }
                        if !task.isPending { Text("· \(task.effectiveStatus.title)") }
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
                }
                .frame(minHeight: AppTheme.minimumTouchTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看\(task.title)，\(task.effectiveStatus.title)")
            Menu {
                Menu("更改类别") {
                    Button("未分类") { move(task, to: nil) }.disabled(task.category == nil)
                    ForEach(store.categories, id: \.self) { name in
                        Button(name) { move(task, to: name) }.disabled(task.category == name)
                    }
                }
                Button("查看任务") { selectedTask = task }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: AppTheme.minimumTouchTarget, height: AppTheme.minimumTouchTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("更多\(task.title)操作及更改类别")
        }
        .padding(.vertical, AppSpacing.x3)
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

    private func renameCategory() {
        guard let oldName = selection.categoryName else { return }
        if store.renameCategory(oldName, to: renameValue) {
            selection = .named(renameValue.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            store.actionMessage = "类别名称不能为空或与现有类别重复。"
        }
    }

    private func move(_ task: TaskItem, to category: String?) {
        guard task.category != category else { return }
        var updated = task
        updated.category = category
        store.update(updated)
    }
}

#Preview("分类 · 浅色") {
    let store = TaskStore(inMemory: true)
    store.addCategory("工作")
    store.add(TaskItem(title: "整理产品发布清单，确认最后一轮细节", category: "工作", quadrant: .schedule))
    return IOSCategoriesView().environmentObject(store).preferredColorScheme(.light)
}

#Preview("分类 · 深色 · 大字") {
    IOSCategoriesView()
        .environmentObject(TaskStore(inMemory: true))
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility1)
}
