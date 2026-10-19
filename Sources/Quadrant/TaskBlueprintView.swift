import SwiftUI

extension Notification.Name {
    static let showTaskBlueprint = Notification.Name("sequence.showTaskBlueprint")
    static let focusBlueprintTask = Notification.Name("sequence.focusBlueprintTask")
}

enum TaskBlueprintNavigation {
    static func open(_ task: TaskItem) {
        NotificationCenter.default.post(
            name: .showTaskBlueprint,
            object: task.id,
            userInfo: task.blueprintID.map { ["blueprintID": $0] }
        )
    }
}

enum TaskBlueprintMode: String, CaseIterable, Identifiable {
    case blueprint = "蓝图"
    case list = "列表"
    case quadrants = "四象限"
    var id: Self { self }
}

private enum TaskQuadrantFilter: String, CaseIterable, Identifiable {
    case actionable = "待处理"
    case all = "全部"
    var id: Self { self }
}

/// A blueprint is a presentation of the existing task IDs, not a second task model.
struct TaskBlueprintView: View {
    @AppDismiss private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let rootTaskID: UUID
    var focusTaskID: UUID? = nil
    @State private var mode: TaskBlueprintMode = .blueprint
    @State private var editingTask: TaskItem?
    @State private var newSubtaskTitle = ""
    @State private var selectedTaskID: UUID?
    @State private var collapsedTaskIDs: Set<UUID> = []
    @State private var quadrantFilter: TaskQuadrantFilter = .all
    @State private var graphFit = true
    @State private var locateSelected = false
    @State private var addError: String?
    @FocusState private var addFieldFocused: Bool

    init(rootTaskID: UUID, focusTaskID: UUID? = nil, initialMode: TaskBlueprintMode = .blueprint) {
        self.rootTaskID = rootTaskID
        self.focusTaskID = focusTaskID
        _mode = State(initialValue: initialMode)
    }

    private var root: TaskItem? { store.tasks.first { $0.id == rootTaskID } }
    private var children: [TaskItem] { TaskTreeProjection.descendants(of: rootTaskID, in: store.tasks) }
    private var allTasks: [TaskItem] { root.map { [$0] + children } ?? [] }
    private var selectedTask: TaskItem? {
        allTasks.first { $0.id == (selectedTaskID ?? focusTaskID ?? rootTaskID) } ?? root
    }
    private var progress: Double {
        guard !children.isEmpty else { return 0 }
        return Double(children.filter(\.isCompleted).count) / Double(children.count)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let root {
                HStack(alignment: .top, spacing: 18) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.title2)
                        .foregroundStyle(preferences.accentColor)
                        .frame(width: 44, height: 44)
                        .background(preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control))
                    VStack(alignment: .leading, spacing: 5) {
                        Text(root.title).font(.title2.weight(.semibold))
                        Text(children.isEmpty ? "任务蓝图 · 从这项任务开始拆解" : "全部后代 \(children.filter(\.isCompleted).count)/\(children.count) 已完成")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("关闭", systemImage: "xmark") { dismiss() }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("关闭任务蓝图")
                }
                .padding(AppSpacing.x6)
                if !children.isEmpty {
                    ProgressView(value: progress)
                        .tint(preferences.accentColor)
                        .padding(.horizontal, AppSpacing.x6)
                        .padding(.bottom, AppSpacing.x4)
                }
                HStack {
                    Picker("任务视图", selection: $mode) {
                        ForEach(TaskBlueprintMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 330)
                    Spacer()
                    if mode == .blueprint {
                        Button("适应全图", systemImage: "arrow.up.left.and.arrow.down.right") { graphFit = true }
                    }
                    Button("定位所选", systemImage: "scope") { locateSelected.toggle() }
                    if mode == .quadrants {
                        Picker("显示任务", selection: $quadrantFilter) {
                            ForEach(TaskQuadrantFilter.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 150)
                    }
                }
                .padding(.horizontal, AppSpacing.x6)
                .padding(.bottom, AppSpacing.x4)
                VStack(alignment: .leading, spacing: AppSpacing.x2) {
                    Text("当前选中：\(selectedTask?.title ?? "无")")
                        .font(AppTypography.callout.weight(.semibold))
                    Text("归属路径：\(selectedTask.map { TaskTreeProjection.path(to: $0.id, in: allTasks).map(\.title).joined(separator: " › ") } ?? "主任务")")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        if let selectedTask {
                            Text("\(selectedTask.displayStatusTitle) · \(selectedTask.isUnscheduled ? "暂未安排" : "计划 \(selectedTask.scheduledFor.formatted(.dateTime.month().day()))")")
                                .font(AppTypography.caption).foregroundStyle(.secondary)
                            if let due = selectedTask.dueDate {
                                Text("截止 \(due.formatted(.dateTime.month().day()))")
                                    .font(AppTypography.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button("编辑所选任务", systemImage: "pencil") { editingTask = selectedTask }
                            .disabled(selectedTask == nil)
                    }
                    HStack(spacing: AppSpacing.x2) {
                        TextField("给\(selectedTask?.title ?? "所选任务")添加子任务，按回车保存", text: $newSubtaskTitle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addSubtask)
                            .focused($addFieldFocused)
                            .accessibilityLabel("新子任务名称")
                        Button("添加子任务", systemImage: "plus", action: addSubtask)
                            .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let addError {
                        Label(addError, systemImage: "exclamationmark.triangle")
                            .font(AppTypography.caption).foregroundStyle(AppColors.danger)
                    }
                }
                .padding(.horizontal, AppSpacing.x6)
                .padding(.bottom, AppSpacing.x4)
                Divider()
                Group {
                    switch mode {
                    case .blueprint: graph
                    case .list: taskList
                    case .quadrants: quadrantList
                    }
                }
            } else {
                ContentUnavailableView("任务不存在", systemImage: "exclamationmark.triangle")
            }
        }
        .frame(minWidth: 680, minHeight: 600)
        .background(preferences.pageBackground)
        .appDialog(item: $editingTask) { task in
            TaskEditor(task: task, onRequestBlueprint: { _ in })
        }
        .onAppear { selectedTaskID = focusTaskID ?? rootTaskID }
        .onChange(of: focusTaskID) { _, newValue in selectedTaskID = newValue ?? rootTaskID }
        .onChange(of: allTasks.map(\.id)) { _, ids in
            if let selectedTaskID, !ids.contains(selectedTaskID) {
                self.selectedTaskID = ids.contains(rootTaskID) ? rootTaskID : nil
            }
        }
        .onChange(of: selectedTaskID) { _, _ in addError = nil }
    }

    private var graph: some View {
        let nodes = allTasks
        let layout = TaskTreeLayout.arrange(nodes.map { .init(id: $0.id, parentID: $0.parentTaskID) },
                                            rootID: rootTaskID, collapsed: collapsedTaskIDs)
        let visible = nodes.filter { layout.visibleIDs.contains($0.id) }
        return GeometryReader { geometry in
            let scale = graphFit ? min(1, max(0.7, min(geometry.size.width / layout.width,
                                                     geometry.size.height / layout.height))) : 1.0
            ScrollViewReader { proxy in
                ScrollView([.horizontal, .vertical]) {
                    ZStack(alignment: .topLeading) {
                        Canvas { context, _ in
                            for task in visible {
                                guard let parentID = task.parentTaskID,
                                      let start = layout.positions[parentID],
                                      let end = layout.positions[task.id] else { continue }
                                var path = Path()
                                path.move(to: CGPoint(x: start.x + TaskTreeLayout.cardWidth,
                                                      y: start.y + TaskTreeLayout.cardHeight / 2))
                                path.addCurve(to: CGPoint(x: end.x, y: end.y + TaskTreeLayout.cardHeight / 2),
                                              control1: CGPoint(x: start.x + TaskTreeLayout.cardWidth + 28,
                                                                y: start.y + TaskTreeLayout.cardHeight / 2),
                                              control2: CGPoint(x: end.x - 28,
                                                                y: end.y + TaskTreeLayout.cardHeight / 2))
                                context.stroke(path, with: .color(preferences.accentColor.opacity(0.38)),
                                               style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            }
                        }
                        .frame(width: layout.width, height: layout.height)
                        ForEach(visible) { task in
                            if let point = layout.positions[task.id] {
                                graphNode(task, hasChildren: nodes.contains { $0.parentTaskID == task.id })
                                    .position(x: point.x + TaskTreeLayout.cardWidth / 2,
                                              y: point.y + TaskTreeLayout.cardHeight / 2)
                                    .id(task.id)
                            }
                        }
                    }
                    .frame(width: layout.width, height: layout.height)
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: layout.width * scale, height: layout.height * scale,
                           alignment: .topLeading)
                }
                .onChange(of: locateSelected) { _, _ in
                    guard let id = selectedTask?.id else { return }
                    let ancestors = TaskTreeProjection.path(to: id, in: allTasks).map(\.id)
                    collapsedTaskIDs.subtract(ancestors)
                    graphFit = false
                    DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                }
                .onAppear {
                    if locateSelected, let id = selectedTask?.id {
                        proxy.scrollTo(id, anchor: .center)
                    }
                }
            }
        }
        .background(preferences.accentColor.opacity(0.025))
    }

    private func graphNode(_ task: TaskItem, hasChildren: Bool) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.x1) {
            Button { selectedTaskID = task.id } label: {
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    HStack(spacing: AppSpacing.x1) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isCompleted ? AppColors.taskCompleted(for: preferences) : preferences.accentColor)
                        Text(task.title).font(AppTypography.callout.weight(.semibold)).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                    Text(task.id == rootTaskID ? "主任务 · \(task.displayStatusTitle)" : task.displayStatusTitle)
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(task.title)，\(task.displayStatusTitle)，选择作为添加目标")
            .accessibilityAddTraits(selectedTask?.id == task.id ? .isSelected : [])
            if hasChildren {
                Button {
                    if !collapsedTaskIDs.insert(task.id).inserted { collapsedTaskIDs.remove(task.id) }
                } label: {
                    Image(systemName: collapsedTaskIDs.contains(task.id) ? "chevron.right" : "chevron.down")
                        .frame(width: 24, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsedTaskIDs.contains(task.id) ? "展开子任务" : "收起子任务")
            }
        }
        .padding(AppSpacing.x2)
        .frame(width: TaskTreeLayout.cardWidth, height: TaskTreeLayout.cardHeight)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.control)
            .stroke(selectedTask?.id == task.id ? preferences.accentColor : .primary.opacity(0.1),
                    lineWidth: selectedTask?.id == task.id ? 2 : 1))
        .contextMenu {
            Button("编辑任务") { selectedTaskID = task.id; editingTask = task }
            Button("添加到此任务") { selectForAdding(task) }
        }
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let parent = selectedTask else { return }
        let priorIDs = Set(store.tasks.map(\.id))
        if store.addChild(title: title, to: parent.id) {
            newSubtaskTitle = ""
            addError = nil
            if let created = store.tasks.first(where: { !priorIDs.contains($0.id) && $0.parentTaskID == parent.id }) {
                selectedTaskID = created.id
            }
            addFieldFocused = true
        } else {
            addError = store.actionMessage ?? "无法添加子任务。"
            store.actionMessage = nil
            addFieldFocused = true
        }
    }

    private func selectForAdding(_ task: TaskItem) {
        selectedTaskID = task.id
        addFieldFocused = true
    }

    private var taskList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                TaskList(tasks: allTasks, onSelect: { selectedTaskID = $0.id },
                         onEditTask: { selectedTaskID = $0.id; editingTask = $0 },
                         onAddChildTask: selectForAdding,
                         onShowBlueprint: { selectedTaskID = $0.id; mode = .blueprint; locateSelected.toggle() },
                         selectedTaskID: selectedTask?.id, revealRequest: locateSelected,
                         hidesDefaultMetadata: true, clarifiesChildScope: true)
                .padding(AppSpacing.x6)
            }
            .onChange(of: locateSelected) { _, _ in
                if let id = selectedTask?.id {
                    DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
    }

    private var quadrantList: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    if geometry.size.width >= 700 {
                        Grid(alignment: .topLeading, horizontalSpacing: AppSpacing.x4, verticalSpacing: AppSpacing.x4) {
                            GridRow(alignment: .top) {
                                quadrantCell(Quadrant.allCases[0])
                                quadrantCell(Quadrant.allCases[1])
                            }
                            GridRow(alignment: .top) {
                                quadrantCell(Quadrant.allCases[2])
                                quadrantCell(Quadrant.allCases[3])
                            }
                        }
                    } else {
                        VStack(spacing: AppSpacing.x4) {
                            ForEach(Quadrant.allCases) { quadrantCell($0) }
                        }
                    }
                }
                .padding(AppSpacing.x6)
                .onChange(of: locateSelected) { _, _ in
                    if let id = selectedTask?.id {
                        quadrantFilter = .all
                        DispatchQueue.main.async { proxy.scrollTo(id, anchor: .center) }
                    }
                }
            }
        }
    }

    private func quadrantCell(_ quadrant: Quadrant) -> some View {
        let tasks = allTasks.filter { $0.quadrant == quadrant &&
            (quadrantFilter == .all || $0.needsAction) }
        return VStack(alignment: .leading, spacing: AppSpacing.x2) {
            HStack {
                Text(quadrant.title).font(AppTypography.headline)
                Spacer()
                Text("\(tasks.count)").font(AppTypography.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if tasks.isEmpty {
                Text(quadrantFilter == .all ? "暂无任务" : "暂无待处理任务")
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                    .padding(.vertical, AppSpacing.x2)
            } else {
                ForEach(tasks) { task in
                    TaskCard(task: task, compact: true, onSelect: { selectedTaskID = $0.id },
                             onEditTask: { selectedTaskID = $0.id; editingTask = $0 },
                             onAddChildTask: selectForAdding,
                             onShowBlueprint: { selectedTaskID = $0.id; mode = .blueprint; locateSelected.toggle() },
                             isSelected: selectedTask?.id == task.id, clarifiesChildScope: true)
                    .id(task.id)
                }
            }
        }
        .padding(AppSpacing.x4)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
    }
}

#Preview("任务蓝图") {
    let store = TaskStore(inMemory: true)
    let parent = TaskItem(title: "准备新版首页发布", quadrant: .schedule)
    let children = ["检查交互", "完成回归测试"].map {
        TaskItem(title: $0, quadrant: .schedule, parentTaskID: parent.id)
    }
    _ = store.addTaskTree(parent: parent, children: children)
    return TaskBlueprintView(rootTaskID: parent.id)
        .environmentObject(store)
        .environmentObject(AppPreferences())
}
