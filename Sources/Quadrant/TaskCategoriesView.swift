import SwiftUI

private enum CategoryLayout {
    static let sidebarWidth: CGFloat = 258
    static let sidebarMinimumHeight: CGFloat = 368
    static let taskPanelMinimumHeight: CGFloat = 280
    static let checkboxSize: CGFloat = 18
    static let checkboxTargetWidth: CGFloat = 28
}

private enum CategorySelection: Hashable {
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

private enum CategoryTaskScope: String, CaseIterable, Identifiable {
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

struct TaskCategoriesView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onSelect: (TaskItem) -> Void

    @State private var selection: CategorySelection = .all
    @State private var scope: CategoryTaskScope = .active
    @State private var newCategory = ""
    @State private var renameValue = ""
    @State private var isRenaming = false
    @State private var isDeleting = false
    @State private var isAddingTask = false
    @State private var blockingTask: TaskItem?

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
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.x8) {
                heading
                HStack(alignment: .top, spacing: AppSpacing.x5) {
                    categoryPanel.frame(width: CategoryLayout.sidebarWidth)
                    taskPanel.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: 1180, alignment: .leading)
            .padding(AppSpacing.x8)
            .frame(maxWidth: .infinity)
        }
        .clickAwayPopover(isPresented: $isAddingTask) { request, close in
            TaskComposerView(category: selection.categoryName, cancelRequest: request, onClose: close)
        }
        .sheet(item: $blockingTask) { task in BlockTaskEditor(task: task) }
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

    private var heading: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x3) {
            HStack(spacing: AppSpacing.x2) {
                Rectangle().fill(preferences.accentColor).frame(width: AppSpacing.x5, height: 1)
                Text("ORGANIZE YOUR WORK")
                    .font(AppTypography.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(preferences.accentColor)
            }
            HStack(alignment: .bottom, spacing: AppSpacing.x5) {
                VStack(alignment: .leading, spacing: AppSpacing.x2) {
                    Text("任务分类").font(AppTypography.largeTitle)
                    Text("把相近的事放在一起，让每一步都更清晰。")
                        .font(AppTypography.callout).foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: AppSpacing.x4)
                AppButton(title: "新建任务", systemImage: "plus", size: .prominent,
                          tint: preferences.accentColor) { isAddingTask = true }
            }
        }
    }

    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            HStack {
                caption("类别概览")
                Spacer()
                Text("\(store.tasks.count) 项任务")
                    .font(AppTypography.caption.monospacedDigit())
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppSpacing.x2)
            categoryButton(.all, count: store.tasks.count)
            categoryButton(.uncategorized, count: store.tasks.filter { CategorySelection.uncategorized.includes($0) }.count)
            Divider().padding(.vertical, AppSpacing.x2)
            caption("我的类别").padding(.horizontal, AppSpacing.x2)
            ForEach(store.categories, id: \.self) { name in
                categoryButton(.named(name), count: store.tasks.filter { $0.category == name }.count)
            }
            Divider().padding(.top, AppSpacing.x3)
            caption("添加类别").padding(.top, AppSpacing.x2).padding(.horizontal, AppSpacing.x2)
            HStack(spacing: AppSpacing.x2) {
                TextField("输入类别名称…", text: $newCategory)
                    .font(AppTypography.callout)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, AppSpacing.x3)
                    .frame(height: 36)
                    .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.small))
                    .overlay(RoundedRectangle(cornerRadius: AppRadius.small).stroke(AppColors.border, lineWidth: 1))
                    .onSubmit(addCategory)
                    .accessibilityLabel("新类别名称")
                Button(action: addCategory) {
                    Image(systemName: "plus")
                        .font(AppTypography.callout.weight(.medium))
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.small))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.small).stroke(AppColors.border, lineWidth: 1))
                .disabled(newCategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("添加类别")
                .accessibilityLabel("添加类别")
            }
        }
        .padding(AppSpacing.x4)
        .frame(minHeight: CategoryLayout.sidebarMinimumHeight, alignment: .topLeading)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border.opacity(0.55)))
    }

    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: AppSpacing.x3) {
                Image(systemName: selection == .all ? "square.stack" : "tag")
                    .font(AppTypography.headline)
                    .foregroundStyle(preferences.accentColor)
                    .frame(width: AppSpacing.x8, height: AppSpacing.x8)
                    .background(preferences.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: AppRadius.small))
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    Text(selection.title).font(AppTypography.title)
                    Text("\(selectedTasks.count) 项任务 · \(selectedTasks.filter(\.needsAction).count) 项待处理")
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer(minLength: AppSpacing.x2)
                if selection.categoryName != nil {
                    Menu {
                        Button("重命名类别") { renameValue = selection.title; isRenaming = true }
                        Button("删除类别", role: .destructive) { isDeleting = true }
                    } label: {
                        Image(systemName: "ellipsis")
                            .frame(width: AppSpacing.x8, height: AppSpacing.x8)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .help("管理类别")
                    .accessibilityLabel("管理\(selection.title)类别")
                }
            }
            .padding(.horizontal, AppSpacing.x7)
            .padding(.top, AppSpacing.x6)
            .padding(.bottom, AppSpacing.x5)
            HStack(alignment: .center) {
                HStack(spacing: AppSpacing.x1) {
                    ForEach(CategoryTaskScope.allCases) { option in
                        scopeButton(option)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("任务状态")
                Spacer(minLength: AppSpacing.x3)
                Label("按计划时间排序", systemImage: "clock")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
            }
            .padding(.horizontal, AppSpacing.x7)
            .padding(.bottom, AppSpacing.x4)
            Divider()
            if visibleTasks.isEmpty {
                AppEmptyState(
                    title: scope == .active ? "这个类别还没有待处理任务" : "这里还没有任务",
                    message: scope == .active ? "新建一项任务，或切换状态查看已有记录。" : "可以切换任务状态，或新建任务。",
                    systemImage: "tag",
                    actionTitle: "新建任务",
                    tint: preferences.accentColor
                ) { isAddingTask = true }
                .frame(maxWidth: .infinity, minHeight: 350)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleTasks) { task in
                        taskRow(task)
                        if task.id != visibleTasks.last?.id { Divider() }
                    }
                }
                .padding(.horizontal, AppSpacing.x7)
                .padding(.top, AppSpacing.x1)
                HStack {
                    Text("显示 \(visibleTasks.count) 项任务")
                        .font(AppTypography.caption.monospacedDigit())
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    if scope != .all {
                        Button("查看全部任务 →") { scope = .all }
                            .font(AppTypography.caption.weight(.semibold))
                            .foregroundStyle(preferences.accentColor)
                            .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, AppSpacing.x7)
                .padding(.top, AppSpacing.x4)
                .padding(.bottom, AppSpacing.x5)
            }
        }
        .frame(maxWidth: .infinity, minHeight: CategoryLayout.taskPanelMinimumHeight, alignment: .topLeading)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border.opacity(0.55)))
    }

    private func caption(_ title: String) -> some View {
        Text(title).font(AppTypography.caption.weight(.semibold)).foregroundStyle(AppColors.textSecondary)
    }

    private func scopeButton(_ option: CategoryTaskScope) -> some View {
        let isSelected = scope == option
        let count = selectedTasks.filter { option.includes($0) }.count
        return Button {
            withAnimation(AppTheme.animation(reduceMotion: preferences.reduceMotion || reduceMotion)) {
                scope = option
            }
        } label: {
            HStack(spacing: AppSpacing.x1) {
                Text(option.rawValue)
                Text("\(count)").monospacedDigit()
            }
            .font(AppTypography.caption.weight(isSelected ? .bold : .medium))
            .foregroundStyle(isSelected ? preferences.accentColor : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.x3)
            .frame(minHeight: AppSpacing.x8)
            .background(isSelected ? preferences.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: AppRadius.small))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(option.rawValue)，\(count) 项任务")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func categoryButton(_ category: CategorySelection, count: Int) -> some View {
        Button { selection = category } label: {
            HStack(spacing: AppSpacing.x3) {
                Image(systemName: category == .all ? "square.stack" : "tag")
                    .font(AppTypography.callout).frame(width: AppSpacing.x4)
                Text(category.title).lineLimit(1)
                Spacer(minLength: AppSpacing.x1)
                Text("\(count)").font(AppTypography.caption.monospacedDigit())
            }
            .font(AppTypography.callout.weight(selection == category ? .semibold : .regular))
            .foregroundStyle(selection == category ? preferences.accentColor : AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.x3)
            .frame(minHeight: 44)
            .background(selection == category ? preferences.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: AppRadius.small))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title)，\(count) 项任务")
        .accessibilityAddTraits(selection == category ? .isSelected : [])
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Button {
                withAnimation(AppTheme.animation(reduceMotion: preferences.reduceMotion || reduceMotion)) {
                    store.toggle(task)
                }
            } label: {
                RoundedRectangle(cornerRadius: AppRadius.small / 2)
                    .fill(task.isCompleted ? AppColors.success : .clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: AppRadius.small / 2)
                            .stroke(task.isCompleted ? AppColors.success : AppColors.textSecondary.opacity(0.65), lineWidth: 1.5)
                    }
                    .overlay {
                        if task.isCompleted {
                            Image(systemName: "checkmark")
                                .font(AppTypography.caption.weight(.bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: CategoryLayout.checkboxSize, height: CategoryLayout.checkboxSize)
                    .padding(.top, AppSpacing.x1 / 2)
                    .frame(width: CategoryLayout.checkboxTargetWidth, height: 44, alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!task.isCompleted && store.executionBlockReason(for: task) != nil)
            .help(task.isCompleted ? "恢复为待完成" : (store.executionBlockReason(for: task) ?? "标记完成"))
            .accessibilityLabel(task.isCompleted ? "恢复\(task.title)" : "完成\(task.title)")
            Button { onSelect(task) } label: {
                VStack(alignment: .leading, spacing: AppSpacing.x2) {
                    Text(task.title)
                        .font(AppTypography.headline)
                        .foregroundStyle(AppColors.textPrimary)
                        .strikethrough(task.isCompleted || task.isCancelled)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: AppSpacing.x2) {
                        if !task.isUnscheduled {
                            Label {
                                Text(scheduleLabel(for: task))
                            } icon: { Image(systemName: "calendar") }
                        }
                        if task.projectName != "未归类项目" { Text("· \(task.projectName)") }
                        if !task.isPending { Text("· \(task.effectiveStatus.title)") }
                    }
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(2)
                }
                .padding(.leading, AppSpacing.x1)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityLabel("查看\(task.title)，\(task.effectiveStatus.title)")
            HStack(alignment: .center, spacing: AppSpacing.x3) {
                if selection == .all {
                    Text(task.categoryName)
                        .font(AppTypography.caption.weight(.medium))
                        .foregroundStyle(preferences.accentColor)
                        .lineLimit(1)
                        .frame(maxWidth: 120)
                        .padding(.horizontal, AppSpacing.x2)
                        .padding(.vertical, AppSpacing.x1)
                        .background(preferences.accentColor.opacity(0.11), in: RoundedRectangle(cornerRadius: AppRadius.small))
                        .fixedSize(horizontal: true, vertical: false)
                }
                Menu {
                    Menu("更改类别") {
                        Button("未分类") { move(task, to: nil) }.disabled(task.category == nil)
                        ForEach(store.categories, id: \.self) { name in
                            Button(name) { move(task, to: name) }.disabled(task.category == name)
                        }
                    }
                    Divider()
                    if task.isUnscheduled { Button("安排到今天") { store.scheduleToday(task) } }
                    if task.needsAction && !task.isInProgress {
                        Button("开始执行") { store.start(task) }
                            .disabled(store.executionBlockReason(for: task) != nil)
                    }
                    if !task.isCompleted {
                        Button("标记为已完成") { store.markCompleted(task) }
                            .disabled(store.executionBlockReason(for: task) != nil)
                    }
                    if task.needsAction && !task.isUnscheduled { Button("延期到明天") { store.postpone(task) } }
                    if task.needsAction { Button("标记为阻塞") { blockingTask = task } }
                    if task.needsAction { Button("取消任务（无需完成）") { store.cancel(task) } }
                    if !task.isPending { Button("恢复为待完成") { store.restore(task) } }
                    Divider()
                    if preferences.calendarIntegrationEnabled && !task.isUnscheduled {
                        Button("写入系统日历") {
                            Task {
                                do {
                                    guard try await CalendarIntegration.shared.requestAccess() else {
                                        throw NSError(domain: "日历", code: 1,
                                                      userInfo: [NSLocalizedDescriptionKey: "未获得日历授权。"])
                                    }
                                    try CalendarIntegration.shared.write(task: task)
                                    store.actionMessage = "已写入系统日历。"
                                } catch {
                                    store.actionMessage = "日历写入失败：\(error.localizedDescription)"
                                }
                            }
                        }
                    }
                    ForEach(Quadrant.allCases) { quadrant in
                        Button("移至\(quadrant.title)") { store.move(task, to: quadrant) }
                    }
                    Divider()
                    Button("打开任务详情") { onSelect(task) }
                    Button("删除", role: .destructive) { store.delete(task) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 36, height: 36).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .frame(width: 36, height: 36)
                .help("更多任务操作及更改类别")
                .accessibilityLabel("更多\(task.title)操作及更改类别")
            }
            .frame(height: 36)
            .padding(.leading, AppSpacing.x3)
        }
        .padding(.vertical, AppSpacing.x4)
    }

    private func scheduleLabel(for task: TaskItem) -> String {
        let date = task.scheduledFor
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDateInToday(date) { return "今天 \(time)" }
        if Calendar.current.isDateInTomorrow(date) { return "明天 \(time)" }
        return date.formatted(.dateTime.month().day().hour().minute())
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
    store.addCategory("生活")
    store.addCategory("学习")
    store.add(TaskItem(title: "整理产品发布清单，确认最后一轮细节", category: "工作", quadrant: .schedule))
    store.add(TaskItem(title: "和设计团队同步新版首页的交互方案", category: "工作", quadrant: .delegate))
    store.add(TaskItem(title: "预约周末的年度体检", category: "生活", quadrant: .schedule))
    store.add(TaskItem(title: "读完《设计心理学》第三章并整理笔记", category: "学习", quadrant: .delegate))
    return TaskCategoriesView(onSelect: { _ in })
        .environmentObject(store)
        .environmentObject(AppPreferences())
        .preferredColorScheme(.light)
        .frame(width: 1000, height: 700)
}
