import SwiftUI

private enum CategoryLayout {
    static let sidebarWidth: CGFloat = 228
    static let taskPanelMinimumHeight: CGFloat = 280
    static let checkboxSize: CGFloat = 18
    static let checkboxTargetWidth: CGFloat = 28
}

enum CategorySelection: Hashable {
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

enum CategoryTaskScope: String, CaseIterable, Identifiable {
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

private struct CategoryEditRoute: Identifiable {
    let id = UUID()
    let name: String?
    let symbol: String
}

struct TaskCategoriesView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onSelect: (TaskItem) -> Void

    @State private var selection: CategorySelection = .all
    @State private var scope: CategoryTaskScope = .active
    @State private var categoryEditRoute: CategoryEditRoute?
    @State private var isAddingTask = false
    @State private var blockingTask: TaskItem?
    @State private var addingChildTask: TaskItem?
    @State private var deletingTask: TaskItem?

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
    private var visibleGroups: [TaskSeriesGroup] {
        TaskSeriesProjection.groups(matches: visibleTasks, allTasks: store.tasks)
    }

    init(initialSelection: CategorySelection = .all, initialScope: CategoryTaskScope = .active,
         onSelect: @escaping (TaskItem) -> Void) {
        _selection = State(initialValue: initialSelection)
        _scope = State(initialValue: initialScope)
        self.onSelect = onSelect
    }

    private var isFirstUse: Bool { store.tasks.isEmpty && store.categories.isEmpty }
    private var selectedSymbol: String { symbol(for: selection) }
    private func font(_ role: NSFont.TextStyle, weight: Font.Weight = .regular) -> Font {
        AppTypography.desktop(role, scale: preferences.fontScale, weight: weight, design: preferences.fontStyle.design)
    }
    private func symbol(for category: CategorySelection) -> String {
        switch category {
        case .all: "square.stack"
        case .uncategorized: "tray"
        case .named(let name): store.categoryAppearance.symbol(for: name)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.x7) {
                    heading
                    Divider()
                    if geometry.size.width >= 800 * preferences.fontScale {
                        HStack(alignment: .top, spacing: AppSpacing.x8) {
                            categoryPanel.frame(width: CategoryLayout.sidebarWidth)
                            Rectangle().fill(AppColors.border).frame(width: 1)
                                .frame(minHeight: 560)
                            taskPanel.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        compactCategoryPicker
                        taskPanel
                    }
                }
                .frame(maxWidth: 1180, alignment: .leading)
                .padding(AppSpacing.x8)
                .frame(maxWidth: .infinity)
            }
        }
        .appDialog(isPresented: $isAddingTask) {
            TaskComposerView(category: selection.categoryName)
        }
        .appDialog(item: $blockingTask) { task in BlockTaskEditor(task: task) }
        .appDialog(item: $addingChildTask) { task in TaskChildQuickAddView(parentTaskID: task.id) }
        .confirmationDialog("删除任务及其后代？", isPresented: Binding(
            get: { deletingTask != nil },
            set: { if !$0 { deletingTask = nil } }
        )) {
            Button("删除任务", role: .destructive) {
                if let deletingTask { store.delete(deletingTask) }
                deletingTask = nil
            }
            Button("取消", role: .cancel) { deletingTask = nil }
        } message: {
            if let deletingTask {
                let count = TaskTreeProjection.descendants(of: deletingTask.id, in: store.tasks).count
                Text(count == 0 ? "此操作无法撤销。" : "该任务及全部 \(count) 项后代任务都会删除。")
            }
        }
        .appDialog(item: $categoryEditRoute) { route in
            CategoryEditor(name: route.name, symbol: route.symbol,
                           onSave: { selection = .named($0) },
                           onDelete: { selection = .uncategorized })
        }
        .onChange(of: store.categories) { _, names in
            if let name = selection.categoryName, !names.contains(name) { selection = .all }
        }
    }

    private var heading: some View {
        HStack(alignment: .center, spacing: AppSpacing.x5) {
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                Text("分类").font(font(.largeTitle, weight: .semibold))
                Text("按生活与工作的不同侧面，整理每一件事。")
                    .font(font(.callout)).foregroundStyle(AppColors.textSecondary)
            }
            Spacer(minLength: AppSpacing.x3)
            if !isFirstUse {
                AppButton(title: "添加事项", systemImage: "plus", size: .prominent,
                          tint: preferences.accentColor) { isAddingTask = true }
            }
        }
    }

    private var categoryPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x1) {
            HStack { caption("任务范围"); Spacer(); caption("总数") }
                .padding(.horizontal, AppSpacing.x3).padding(.bottom, AppSpacing.x2)
            categoryButton(.all, count: store.tasks.count)
            categoryButton(.uncategorized, count: store.tasks.filter { CategorySelection.uncategorized.includes($0) }.count)
            Divider().padding(.vertical, AppSpacing.x5).padding(.horizontal, AppSpacing.x3)
            HStack { caption("我的类别"); Spacer(); caption("\(store.categories.count)") }
                .padding(.horizontal, AppSpacing.x3).padding(.bottom, AppSpacing.x2)
            ForEach(store.categories, id: \.self) { name in
                categoryButton(.named(name), count: store.tasks.filter { $0.category == name }.count)
            }
            Button { editCategory(nil) } label: {
                Label("新建类别", systemImage: "plus")
                    .font(font(.callout)).foregroundStyle(preferences.accentColor)
                    .padding(.horizontal, AppSpacing.x3).frame(minHeight: 44)
            }
            .buttonStyle(.plain).padding(.top, AppSpacing.x3)
            Text("右侧数字为全部状态的任务数")
                .font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.x3).padding(.top, AppSpacing.x3)
        }
    }

    private var compactCategoryPicker: some View {
        HStack(spacing: AppSpacing.x3) {
            Picker("类别", selection: $selection) {
                Label("所有类别（\(store.tasks.count)）", systemImage: "square.stack").tag(CategorySelection.all)
                Label("未分类", systemImage: "tray").tag(CategorySelection.uncategorized)
                ForEach(store.categories, id: \.self) { name in
                    Label(name, systemImage: store.categoryAppearance.symbol(for: name)).tag(CategorySelection.named(name))
                }
            }
            .labelsHidden().accessibilityLabel("选择类别")
            Spacer(minLength: 0)
            Button { editCategory(nil) } label: { Label("新建类别", systemImage: "plus") }
        }
    }

    private func editCategory(_ name: String?) {
        categoryEditRoute = CategoryEditRoute(name: name,
                                             symbol: name.map { store.categoryAppearance.symbol(for: $0) } ?? "tag")
    }

    private var taskPanel: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x5) {
            if !isFirstUse {
                HStack(alignment: .center, spacing: AppSpacing.x3) {
                    Image(systemName: selectedSymbol).font(font(.title2))
                        .foregroundStyle(preferences.accentColor).frame(width: 48, height: 48)
                        .background(preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control))
                    VStack(alignment: .leading, spacing: AppSpacing.x1) {
                        Text(selection.title).font(font(.title1, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(selectedTasks.count) 项任务 · \(selectedTasks.filter(\.needsAction).count) 项待处理 · \(visibleGroups.filter(\.isSeries).count) 个系列")
                            .font(font(.caption1)).monospacedDigit().foregroundStyle(AppColors.textSecondary)
                    }
                    Spacer(minLength: AppSpacing.x2)
                    if let name = selection.categoryName {
                        Button { editCategory(name) } label: { Label("编辑类别", systemImage: "pencil") }
                            .buttonStyle(.plain).font(font(.callout)).foregroundStyle(AppColors.textSecondary)
                            .frame(minHeight: 36).accessibilityLabel("编辑类别")
                    }
                }
                ViewThatFits(in: .horizontal) {
                    HStack {
                        scopeControls
                        Spacer(minLength: AppSpacing.x3)
                        sortLabel
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.x2) { scopeControls; sortLabel }
                }
                Divider()
            }
            if visibleTasks.isEmpty {
                emptyState.frame(maxWidth: .infinity, minHeight: 350)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(visibleGroups) { group in
                        if group.isSeries {
                            HStack(spacing: AppSpacing.x2) {
                                Label("任务系列", systemImage: "point.3.connected.trianglepath.dotted")
                                    .font(font(.callout, weight: .semibold))
                                Text(group.root.title).lineLimit(2)
                                Spacer()
                                Text("\(group.matches.count) 项")
                                    .font(font(.caption1)).monospacedDigit()
                            }
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.vertical, AppSpacing.x3)
                            .accessibilityElement(children: .combine)
                        }
                        ForEach(group.rows.filter { !$0.isContext }) { row in
                            taskRow(row.task)
                                .padding(.leading, group.isSeries ? CGFloat(min(row.depth, 4)) * AppSpacing.x4 : 0)
                            Divider()
                        }
                    }
                }
                HStack(alignment: .top) {
                    Text("显示 \(visibleTasks.count) 项" + (scope == .processed ? " · 包含已完成与已取消" : ""))
                    Spacer()
                    Text(scope == .active ? "未安排时间的事项置于末尾" : "按任务创建时间展示")
                }
                .font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: CategoryLayout.taskPanelMinimumHeight, alignment: .topLeading)
    }

    private var scopeControls: some View {
        HStack(spacing: AppSpacing.x1) {
            ForEach(CategoryTaskScope.allCases) { scopeButton($0) }
        }
        .accessibilityElement(children: .contain).accessibilityLabel("任务状态")
    }

    private var sortLabel: some View {
        Label(scope == .active ? "按计划时间升序" : "按创建时间降序",
              systemImage: scope == .active ? "clock" : "arrow.up.arrow.down")
            .font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
    }

    @ViewBuilder private var emptyState: some View {
        if isFirstUse {
            AppEmptyState(title: "先从一个类别开始", message: "为工作、生活或兴趣留一个位置。", systemImage: "tag",
                          actionTitle: "新建类别", tint: preferences.accentColor) { editCategory(nil) }
        } else if selectedTasks.isEmpty {
            AppEmptyState(title: selection == .uncategorized ? "所有任务都已有归属" : "这个类别还没有事项",
                          message: selection == .uncategorized ? "新收集、尚未归类的事项会出现在这里。" : "添加第一件事，让计划从这里开始。",
                          systemImage: selectedSymbol)
        } else if scope == .active {
            AppEmptyState(title: "这里的事项都已处理", message: "可以查看已处理记录，或添加新的事项。",
                          systemImage: "checkmark.circle", actionTitle: "查看已处理", tint: preferences.accentColor) { scope = .processed }
        } else {
            AppEmptyState(title: "还没有已处理的事项", message: "完成或取消的事项会保留在这里。",
                          systemImage: "tray", actionTitle: "查看待处理", tint: preferences.accentColor) { scope = .active }
        }
    }

    private func caption(_ title: String) -> some View {
        Text(title).font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
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
            .font(font(.caption1, weight: isSelected ? .medium : .regular))
            .foregroundStyle(isSelected ? preferences.accentColor : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.x3)
            .frame(minHeight: AppSpacing.x8)
            .background(isSelected ? preferences.cardBackground : .clear,
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
                Image(systemName: symbol(for: category))
                    .font(font(.callout)).frame(width: AppSpacing.x5)
                Text(category.title).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppSpacing.x1)
                Text("\(count)").font(font(.caption1)).monospacedDigit()
            }
            .font(font(.body, weight: selection == category ? .medium : .regular))
            .foregroundStyle(selection == category ? preferences.accentColor : AppColors.textPrimary)
            .padding(.horizontal, AppSpacing.x3)
            .frame(minHeight: 44)
            .background(selection == category ? preferences.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: AppRadius.small))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(category.title)，全部状态共 \(count) 项任务")
        .accessibilityAddTraits(selection == category ? .isSelected : [])
    }

    private func taskRow(_ task: TaskItem) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Button {
                withAnimation(AppTheme.animation(reduceMotion: preferences.reduceMotion || reduceMotion)) {
                    if task.isCancelled { store.restore(task) } else { store.toggle(task) }
                }
            } label: {
                Circle()
                    .fill(task.isCompleted ? AppColors.taskCompleted(for: preferences) : .clear)
                    .overlay {
                        Circle()
                            .stroke(task.isCompleted ? AppColors.taskCompleted(for: preferences) : AppColors.textSecondary.opacity(0.65), lineWidth: 1.5)
                    }
                    .overlay {
                        if task.isCompleted || task.isCancelled {
                            Image(systemName: task.isCancelled ? "minus" : "checkmark")
                                .font(font(.caption1, weight: .semibold))
                                .foregroundStyle(task.isCancelled ? AppColors.textSecondary : AppColors.foreground(on: AppColors.taskCompleted(for: preferences)))
                        }
                    }
                    .frame(width: CategoryLayout.checkboxSize, height: CategoryLayout.checkboxSize)
                    .padding(.top, AppSpacing.x1 / 2)
                    .frame(width: CategoryLayout.checkboxTargetWidth, height: 44, alignment: .topLeading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(task.needsAction && store.executionBlockReason(for: task) != nil)
            .help(!task.needsAction ? "恢复为待完成" : (store.executionBlockReason(for: task) ?? "标记完成"))
            .accessibilityLabel(!task.needsAction ? "恢复\(task.title)" : "完成\(task.title)")
            Button { onSelect(task) } label: {
                VStack(alignment: .leading, spacing: AppSpacing.x2) {
                    Text(task.title)
                        .font(font(.body, weight: .medium))
                        .foregroundStyle(task.needsAction ? AppColors.textPrimary : AppColors.textSecondary)
                        .strikethrough(task.isCompleted || task.isCancelled)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    VStack(alignment: .leading, spacing: AppSpacing.x1) {
                        HStack(spacing: AppSpacing.x3) {
                            Label(task.isUnscheduled ? "未安排时间" : scheduleLabel(for: task), systemImage: "calendar")
                            if task.needsAction && task.estimatedMinutes > 0 { Text("预计 \(task.estimatedMinutes) 分钟") }
                            if !task.isPending { Text(task.displayStatusTitle) }
                        }
                        if let reason = task.blockReason, task.effectiveStatus == .blocked, !reason.isEmpty {
                            Text("受阻 · \(reason)")
                        }
                        if let parentID = task.parentTaskID, let parent = store.tasks.first(where: { $0.id == parentID }) {
                            Text("父任务：\(parent.title)")
                        }
                        if selection == .all {
                            Label(task.categoryName, systemImage: store.categoryAppearance.symbol(for: task.category))
                        }
                        if task.projectName != "未归类项目" { Text(task.projectName) }
                    }
                    .font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.leading, AppSpacing.x1)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .accessibilityLabel("查看\(task.title)，\(task.displayStatusTitle)")
            HStack(alignment: .center, spacing: AppSpacing.x3) {
                if task.needsAction {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: AppSpacing.x2) {
                            Circle().fill(AppColors.textSecondary).frame(width: AppSpacing.x1, height: AppSpacing.x1)
                            Text(task.quadrant.title).font(font(.caption1))
                        }.foregroundStyle(AppColors.textSecondary)
                        Text(task.quadrant.title).font(font(.caption1)).foregroundStyle(AppColors.textSecondary)
                    }
                    .accessibilityLabel(task.quadrant.title)
                }
                Menu {
                    Menu("更改类别") {
                        Button { move(task, to: nil) } label: { Label("未分类", systemImage: "tray") }.disabled(task.category == nil)
                        ForEach(store.categories, id: \.self) { name in
                            Button { move(task, to: name) } label: { Label(name, systemImage: store.categoryAppearance.symbol(for: name)) }.disabled(task.category == name)
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
                    Button("编辑任务") { onSelect(task) }
                    Button("添加子任务") { addingChildTask = task }
                    Button("删除", role: .destructive) {
                        if TaskTreeProjection.descendants(of: task.id, in: store.tasks).isEmpty { store.delete(task) }
                        else { deletingTask = task }
                    }
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
        .padding(.vertical, preferences.density == .compact ? AppSpacing.x3 : preferences.density == .spacious ? AppSpacing.x6 : AppSpacing.x5)
    }

    private func scheduleLabel(for task: TaskItem) -> String {
        let date = task.scheduledFor
        let time = date.formatted(.dateTime.hour().minute())
        if Calendar.current.isDateInToday(date) { return "今天 \(time)" }
        if Calendar.current.isDateInTomorrow(date) { return "明天 \(time)" }
        return date.formatted(.dateTime.month().day().hour().minute())
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

#Preview("分类 · 深色空态") {
    TaskCategoriesView(onSelect: { _ in })
        .environmentObject(TaskStore(inMemory: true))
        .environmentObject(AppPreferences())
        .preferredColorScheme(.dark).frame(width: 1000, height: 700)
}
