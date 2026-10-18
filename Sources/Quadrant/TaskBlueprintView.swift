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

private enum TaskBlueprintMode: String, CaseIterable, Identifiable {
    case blueprint = "蓝图"
    case list = "列表"
    case quadrants = "四象限"
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

    private var root: TaskItem? { store.tasks.first { $0.id == rootTaskID } }
    private var children: [TaskItem] { TaskTreeProjection.descendants(of: rootTaskID, in: store.tasks) }
    private var allTasks: [TaskItem] { root.map { [$0] + children } ?? [] }
    private var selectedTask: TaskItem? {
        store.tasks.first { $0.id == (selectedTaskID ?? focusTaskID ?? rootTaskID) }
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
                        Text(children.isEmpty ? "任务蓝图 · 从这项任务开始拆解" : "任务蓝图 · \(children.filter(\.isCompleted).count)/\(children.count) 项子任务已完成")
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
                    .frame(width: 330)
                    Text("所有视图使用同一批任务")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.x6)
                .padding(.bottom, AppSpacing.x4)
                VStack(alignment: .leading, spacing: AppSpacing.x2) {
                    HStack {
                        Text("添加到：\(selectedTask.map { TaskTreeProjection.path(to: $0.id, in: store.tasks).map(\.title).joined(separator: " › ") } ?? "主任务")")
                            .font(AppTypography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer()
                        Button("编辑所选任务", systemImage: "pencil") { editingTask = selectedTask }
                            .disabled(selectedTask == nil)
                    }
                    HStack(spacing: AppSpacing.x2) {
                        TextField("添加子任务，按回车保存", text: $newSubtaskTitle)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(addSubtask)
                            .accessibilityLabel("新子任务名称")
                        Button("添加子任务", systemImage: "plus", action: addSubtask)
                            .disabled(newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
        .frame(minWidth: 900, minHeight: 600)
        .background(preferences.pageBackground)
        .appDialog(item: $editingTask) { task in TaskEditor(task: task) }
        .onAppear { selectedTaskID = focusTaskID ?? rootTaskID }
        .onChange(of: focusTaskID) { _, newValue in selectedTaskID = newValue ?? rootTaskID }
    }

    private var graph: some View {
        let nodes = allTasks
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let layout = graphPositions(nodes)
        let width = max(850, (layout.values.map(\.x).max() ?? 0) + 300)
        let height = max(480, (layout.values.map(\.y).max() ?? 0) + 145)
        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    for task in nodes {
                        guard let parentID = task.parentTaskID,
                              byID[parentID] != nil,
                              let start = layout[parentID], let end = layout[task.id] else { continue }
                        var path = Path()
                        path.move(to: CGPoint(x: start.x + 246, y: start.y + 46))
                        path.addCurve(to: CGPoint(x: end.x, y: end.y + 46),
                                      control1: CGPoint(x: start.x + 285, y: start.y + 46),
                                      control2: CGPoint(x: end.x - 36, y: end.y + 46))
                        context.stroke(path, with: .color(preferences.accentColor.opacity(0.38)),
                                       style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    }
                }
                .frame(width: width, height: height)
                ForEach(nodes) { task in
                    if let position = layout[task.id] {
                        Button { selectedTaskID = task.id } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack(spacing: 7) {
                                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(task.isCompleted ? AppColors.taskCompleted(for: preferences) : preferences.accentColor)
                                    Text(task.title).font(.headline).lineLimit(2)
                                }
                                Text(task.id == rootTaskID ? "主任务" : "子任务")
                                    .font(.caption).foregroundStyle(.secondary)
                                Spacer(minLength: 0)
                                Text(task.displayStatusTitle)
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(AppSpacing.x3)
                            .frame(width: 246, height: 96, alignment: .topLeading)
                            .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
                            .overlay(RoundedRectangle(cornerRadius: AppRadius.control)
                                .stroke(task.id == (selectedTaskID ?? focusTaskID ?? rootTaskID) ? preferences.accentColor : .primary.opacity(0.1), lineWidth: task.id == (selectedTaskID ?? focusTaskID ?? rootTaskID) ? 2 : 1))
                            .contentShape(RoundedRectangle(cornerRadius: AppRadius.control))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(task.id == rootTaskID ? "主任务" : "子任务")，\(task.title)，\(task.displayStatusTitle)，选择作为添加目标")
                        .contextMenu {
                            Button("编辑任务") { selectedTaskID = task.id; editingTask = task }
                            Button("添加子任务") { selectedTaskID = task.id }
                        }
                        .position(x: position.x + 123, y: position.y + 48)
                    }
                }
            }
            .frame(width: width, height: height)
        }
        .background(preferences.accentColor.opacity(0.025))
    }

    private func graphPositions(_ tasks: [TaskItem]) -> [UUID: CGPoint] {
        var positions: [UUID: CGPoint] = [:]
        var seen = Set<UUID>()
        var row = 0
        func place(_ task: TaskItem, depth: Int) {
            guard seen.insert(task.id).inserted else { return }
            positions[task.id] = CGPoint(x: 54 + CGFloat(depth) * 330,
                                         y: 46 + CGFloat(row) * 132)
            row += 1
            for child in TaskTreeProjection.directChildren(of: task.id, in: tasks) {
                place(child, depth: depth + 1)
            }
        }
        if let root = tasks.first(where: { $0.id == rootTaskID }) { place(root, depth: 0) }
        for task in tasks where !seen.contains(task.id) { place(task, depth: 0) }
        return positions
    }

    private func addSubtask() {
        let title = newSubtaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let parent = selectedTask else { return }
        if store.addChild(title: title, to: parent.id) { newSubtaskTitle = "" }
    }

    private var taskList: some View {
        ScrollView {
            TaskList(tasks: allTasks, onSelect: { selectedTaskID = $0.id; editingTask = $0 })
            .padding(AppSpacing.x6)
        }
    }

    private var quadrantList: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: AppSpacing.x4) {
                ForEach(Quadrant.allCases) { quadrant in
                    VStack(alignment: .leading, spacing: AppSpacing.x2) {
                        Text(quadrant.title).font(.headline)
                        ForEach(allTasks.filter { $0.quadrant == quadrant }) { task in
                            TaskCard(task: task, compact: true, onSelect: { selectedTaskID = $0.id; editingTask = $0 })
                        }
                    }
                    .padding(AppSpacing.x4)
                    .frame(maxWidth: .infinity, minHeight: 170, alignment: .topLeading)
                    .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
                }
            }
            .padding(AppSpacing.x6)
        }
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
