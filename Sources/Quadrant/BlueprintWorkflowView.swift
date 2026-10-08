import AppKit
import SwiftUI
import UniformTypeIdentifiers

private enum WorkflowAddMode {
    case root
    case next(UUID)
    case parallel(UUID)
    case insert(UUID, UUID)
}

private struct WorkflowEdge: Identifiable {
    let from: UUID
    let to: UUID
    var id: String { "\(from.uuidString)-\(to.uuidString)" }
}

private struct WorkflowHistoryEntry {
    let before: [TaskItem]
    let after: [TaskItem]
    let beforeAnniversaries: [AnniversaryItem]
    let afterAnniversaries: [AnniversaryItem]
    let beforeMilestones: [MilestoneItem]
    let afterMilestones: [MilestoneItem]
}

struct BlueprintWorkflowView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let blueprint: BlueprintItem

    @State private var selectedID: UUID?
    @State private var quickMode: WorkflowAddMode = .root
    @State private var quickTitle = ""
    @State private var isQuickAdding = false
    @State private var isBulkAdding = false
    @State private var isExistingPickerShowing = false
    @State private var isListShowing = false
    @State private var isStageSidebarShowing = false
    @State private var isAddingStage = false
    @State private var milestoneStage: StageItem?
    @State private var zoom = 1.0
    @State private var dragOffsets: [UUID: CGSize] = [:]
    @State private var editingTask: TaskItem?
    @State private var undoStack: [WorkflowHistoryEntry] = []
    @State private var redoStack: [WorkflowHistoryEntry] = []
    @FocusState private var quickFocused: Bool

    private let cardWidth: CGFloat = 250
    private var scopedTasks: [TaskItem] { store.tasks(for: blueprint.id) }
    private var selectedTask: TaskItem? { scopedTasks.first { $0.id == selectedID } }
    private var positions: [UUID: CGPoint] {
        let automatic = WorkflowGraph.automaticPositions(for: scopedTasks)
        var result: [UUID: CGPoint] = [:]
        for task in scopedTasks {
            result[task.id] = CGPoint(
                x: task.workflowX.map { CGFloat($0) } ?? automatic[task.id]?.x ?? 72,
                y: task.workflowY.map { CGFloat($0) } ?? automatic[task.id]?.y ?? 80
            )
        }
        return result
    }
    private var edges: [WorkflowEdge] {
        let ids = Set(scopedTasks.map(\.id))
        return scopedTasks.flatMap { task in
            task.effectiveDependencyIDs.filter { ids.contains($0) }.map { WorkflowEdge(from: $0, to: task.id) }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                if isStageSidebarShowing {
                    stageSidebar
                    Divider()
                }
                Group {
                    if isListShowing { listContent }
                    else { canvasContent }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let task = selectedTask {
                    Divider()
                    WorkflowInspector(task: task, blueprintID: blueprint.id,
                                      onSelect: { selectedID = $0 }, onEdit: { editingTask = task },
                                      onDeleted: { selectedID = nil },
                                      onMutation: { action in withHistory(action) })
                        .id(task.id)
                        .frame(width: 340)
                }
            }
        }
        .frame(minHeight: 500)
        .overlay(alignment: .top) {
            if isQuickAdding { quickAddBar.padding(.top, 58).zIndex(20) }
        }
        .sheet(isPresented: $isBulkAdding) {
            WorkflowBulkAddView { titles, parallel in
                withHistory {
                    var source = selectedID
                    for title in titles {
                        let mode: WorkflowAddMode = parallel
                            ? (selectedID.map { .parallel($0) } ?? .root)
                            : (source.map { .next($0) } ?? .root)
                        if let newID = createNode(title: title, mode: mode), !parallel { source = newID }
                    }
                }
            }
        }
        .sheet(isPresented: $isExistingPickerShowing) {
            WorkflowExistingTaskPicker(blueprint: blueprint) { task in
                withHistory { store.assign(task, to: blueprint, showMessage: false) }
                if store.tasks.first(where: { $0.id == task.id })?.blueprintID == blueprint.id {
                    selectedID = task.id
                }
            }
        }
        .sheet(isPresented: $isAddingStage) { StageEditor(blueprintID: blueprint.id) }
        .sheet(item: $milestoneStage) { MilestoneEditor(blueprintID: blueprint.id, stage: $0) }
        .sheet(item: $editingTask) { TaskEditor(task: $0) }
        .onChange(of: isQuickAdding) { _, value in if value { quickFocused = true } }
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            Label("节点工作流", systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            Text("\(scopedTasks.filter(\.isCompleted).count)/\(scopedTasks.filter { !$0.isCancelled }.count) 已完成")
                .font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Button(isStageSidebarShowing ? "收起阶段" : "阶段", systemImage: "square.stack.3d.up") {
                isStageSidebarShowing.toggle()
            }
            Button("添加节点", systemImage: "plus") { beginAdd(.root) }
                .buttonStyle(.borderedProminent)
            Menu("更多添加", systemImage: "plus.square.on.square") {
                Button("批量添加", systemImage: "text.badge.plus") { isBulkAdding = true }
                Button("加入已有任务", systemImage: "tray.and.arrow.down") { isExistingPickerShowing = true }
            }
            Button(isListShowing ? "画布" : "列表", systemImage: isListShowing ? "square.grid.2x2" : "list.bullet") {
                isListShowing.toggle()
            }
            if !isListShowing {
                Button { zoom = max(0.8, zoom - 0.1) } label: { Image(systemName: "minus.magnifyingglass").comfortableIconTarget(36) }
                    .help("缩小").accessibilityLabel("缩小画布")
                Text("\(Int(zoom * 100))%")
                    .font(.subheadline.monospacedDigit()).frame(width: 46)
                Button { zoom = min(1.5, zoom + 0.1) } label: { Image(systemName: "plus.magnifyingglass").comfortableIconTarget(36) }
                    .help("放大").accessibilityLabel("放大画布")
            }
            Menu("操作", systemImage: "ellipsis.circle") {
                if !isListShowing {
                    Button("自动排版", systemImage: "rectangle.3.group") { withHistory { autoLayout() } }
                    Divider()
                }
                Button("撤销", systemImage: "arrow.uturn.backward") { undo() }
                    .disabled(undoStack.isEmpty)
                    .keyboardShortcut("z", modifiers: [.command])
                Button("重做", systemImage: "arrow.uturn.forward") { redo() }
                    .disabled(redoStack.isEmpty)
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
        }
        .controlSize(.large)
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var stageSidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("阶段").font(.headline)
                    Spacer()
                    Button { isAddingStage = true } label: { Image(systemName: "plus").comfortableIconTarget(36) }
                        .help("添加阶段")
                }
                .padding(.horizontal, 14)
                if store.stages(for: blueprint.id).isEmpty {
                    Text("可在概览中添加阶段；任务也可以不分组。")
                        .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 14)
                }
                ForEach(store.stages(for: blueprint.id)) { stage in
                    let tasks = scopedTasks.filter { $0.stageID == stage.id }
                    VStack(alignment: .leading, spacing: 5) {
                        HStack {
                            Button {
                                selectedID = tasks.first(where: { !$0.isCompleted })?.id ?? tasks.first?.id
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(stage.name).font(.subheadline.weight(.medium)).lineLimit(1)
                                    Text("\(tasks.filter(\.isCompleted).count)/\(tasks.count) 已完成")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .frame(minHeight: 40)
                            Button { milestoneStage = stage } label: { Image(systemName: "flag.badge.plus").comfortableIconTarget(36) }
                                .help("添加里程碑")
                        }
                        ForEach(store.milestones(for: stage.id)) { milestone in
                            Button { withHistory { store.toggleMilestone(milestone) } } label: {
                                Label(milestone.name, systemImage: milestone.isCompleted ? "flag.checkered" : "flag")
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            .buttonStyle(.plain)
                            .frame(minHeight: 36)
                            .help(milestone.isCompleted ? "取消里程碑完成" : "标记里程碑完成")
                        }
                    }
                    .padding(9)
                    .background(.quaternary.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8)
                }
            }
            .padding(.top, 14)
        }
        .frame(width: 210)
    }

    private var quickAddBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "plus.circle.fill").foregroundStyle(preferences.accentColor)
            Text(quickAddHint).font(.subheadline).foregroundStyle(.secondary)
            TextField("输入任务标题，回车创建", text: $quickTitle)
                .textFieldStyle(.roundedBorder)
                .frame(width: 290)
                .focused($quickFocused)
                .onSubmit { submitQuickAdd() }
            Button("添加") { submitQuickAdd() }.disabled(quickTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button { isQuickAdding = false } label: { Image(systemName: "xmark").comfortableIconTarget(36) }.help("关闭")
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
        .shadow(radius: 12, y: 4)
        .controlSize(.large)
    }

    private var quickAddHint: String {
        switch quickMode {
        case .root: "独立节点"
        case .next: "串行下一步"
        case .parallel: "并行一步"
        case .insert: "插入连线中"
        }
    }

    private var canvasContent: some View {
        let nodes = scopedTasks
        let layout = positions
        let links = edges
        let width = max(1050, (layout.values.map(\.x).max() ?? 0) + 400)
        let height = max(650, (layout.values.map(\.y).max() ?? 0) + 350)
        return ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    var lines = Path()
                    for x in stride(from: CGFloat(0), through: size.width, by: 32) {
                        lines.move(to: CGPoint(x: x, y: 0))
                        lines.addLine(to: CGPoint(x: x, y: size.height))
                    }
                    for y in stride(from: CGFloat(0), through: size.height, by: 32) {
                        lines.move(to: CGPoint(x: 0, y: y))
                        lines.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(lines, with: .color(.secondary.opacity(0.09)), lineWidth: 1)
                    for edge in links {
                        guard let from = nodes.first(where: { $0.id == edge.from }),
                              let to = nodes.first(where: { $0.id == edge.to }),
                              let start = layout[edge.from], let end = layout[edge.to] else { continue }
                        context.stroke(
                            edgePath(from: start, fromHeight: cardHeight(from), to: end, toHeight: cardHeight(to)),
                            with: .color(from.isCompleted ? .green.opacity(0.7) : .secondary.opacity(0.55)),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round)
                        )
                    }
                }
                .frame(width: width, height: height)

                ForEach(links) { edge in
                    if let from = nodes.first(where: { $0.id == edge.from }),
                       let to = nodes.first(where: { $0.id == edge.to }),
                       let start = layout[edge.from], let end = layout[edge.to] {
                        Button { beginAdd(.insert(edge.from, edge.to)) } label: {
                            Image(systemName: "plus").font(.subheadline.weight(.bold))
                                .frame(width: 36, height: 36)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .help("在连线中插入任务")
                        .position(x: (start.x + cardWidth + end.x) / 2,
                                  y: (start.y + cardHeight(from) / 2 + end.y + cardHeight(to) / 2) / 2)
                    }
                }

                ForEach(nodes) { task in
                    if let position = layout[task.id] {
                        WorkflowNodeCard(
                            task: task,
                            stageName: task.stageID.flatMap { id in store.stages.first { $0.id == id }?.name },
                            selected: selectedID == task.id,
                            blockingReason: store.executionBlockReason(for: task),
                            onSelect: { selectedID = task.id },
                            onNext: { beginAdd(.next(task.id)) },
                            onParallel: { beginAdd(.parallel(task.id)) },
                            onMove: { translation, finished in
                                if finished {
                                    dragOffsets[task.id] = nil
                                    withHistory {
                                        store.setWorkflowPosition(for: task.id,
                                                                  x: Double(position.x + translation.width),
                                                                  y: Double(position.y + translation.height))
                                    }
                                } else {
                                    dragOffsets[task.id] = translation
                                }
                            },
                            onConnect: { sourceID in
                                guard let predecessor = nodes.first(where: { $0.id == sourceID }) else { return false }
                                return withHistory { store.connect(predecessor, to: task) }
                            },
                            onMutation: { action in withHistory(action) }
                        )
                        .frame(width: cardWidth, height: cardHeight(task))
                        .position(x: position.x + cardWidth / 2 + (dragOffsets[task.id]?.width ?? 0),
                                  y: position.y + cardHeight(task) / 2 + (dragOffsets[task.id]?.height ?? 0))
                    }
                }

                if nodes.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "point.3.connected.trianglepath.dotted").font(.largeTitle).foregroundStyle(preferences.accentColor)
                        Text("从第一步开始").font(.title3.weight(.semibold))
                        Text("输入任务标题即可创建节点，图片和详细设置可以稍后添加。")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Button("添加第一步", systemImage: "plus") { beginAdd(.root) }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(width: 460, height: 240)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
                    .position(x: width / 2, y: height / 2)
                }
            }
            .frame(width: width, height: height)
            .scaleEffect(zoom, anchor: .topLeading)
            .frame(width: width * zoom, height: height * zoom, alignment: .topLeading)
        }
        .background(preferences.pageBackground)
    }

    private var listContent: some View {
        List {
            if scopedTasks.isEmpty {
                ContentUnavailableView("还没有节点", systemImage: "point.3.connected.trianglepath.dotted")
            }
            ForEach(scopedTasks.sorted { $0.createdAt < $1.createdAt }) { task in
                Button { selectedID = task.id } label: {
                    HStack(spacing: 12) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : store.executionBlockReason(for: task) == nil ? "play.circle" : "lock.circle")
                            .foregroundStyle(task.isCompleted ? .green : .secondary)
                        VStack(alignment: .leading) {
                            Text(task.title).font(.headline)
                            if let reason = store.executionBlockReason(for: task), !task.isCompleted {
                                Text(reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        Spacer()
                        if !task.images.isEmpty { Label("\(task.images.count)", systemImage: "photo") }
                        Text("前置 \(task.effectiveDependencyIDs.count)").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func cardHeight(_ task: TaskItem) -> CGFloat {
        let stage = task.stageID == nil ? CGFloat(0) : 20
        let content = !task.images.isEmpty ? CGFloat(76) : task.notes.isEmpty ? CGFloat(0) : 36
        let blocker = store.executionBlockReason(for: task) == nil || task.isCompleted ? CGFloat(0) : 32
        return 180 + stage + content + blocker
    }

    private func edgePath(from: CGPoint, fromHeight: CGFloat, to: CGPoint, toHeight: CGFloat) -> Path {
        Path { path in
            let start = CGPoint(x: from.x + cardWidth, y: from.y + fromHeight / 2)
            let end = CGPoint(x: to.x, y: to.y + toHeight / 2)
            let bend = max(50, abs(end.x - start.x) * 0.45)
            path.move(to: start)
            path.addCurve(to: end, control1: CGPoint(x: start.x + bend, y: start.y),
                          control2: CGPoint(x: end.x - bend, y: end.y))
        }
    }

    private func beginAdd(_ mode: WorkflowAddMode) {
        quickMode = mode
        quickTitle = ""
        isQuickAdding = true
        quickFocused = true
    }

    private func submitQuickAdd() {
        guard let newID = withHistory({ createNode(title: quickTitle, mode: quickMode) }) else { return }
        quickTitle = ""
        quickMode = .next(newID)
        quickFocused = true
    }

    @discardableResult
    private func createNode(title: String, mode: WorkflowAddMode) -> UUID? {
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        var dependencies: [UUID] = []
        var stageID: UUID?
        switch mode {
        case .root: break
        case let .next(id), let .insert(id, _):
            dependencies = [id]
            stageID = scopedTasks.first { $0.id == id }?.stageID
        case let .parallel(id):
            dependencies = scopedTasks.first { $0.id == id }?.effectiveDependencyIDs ?? []
            stageID = scopedTasks.first { $0.id == id }?.stageID
        }
        var task = TaskItem(title: cleaned, project: blueprint.name, quadrant: preferences.defaultQuadrant,
                            scheduledFor: .now, estimatedMinutes: preferences.defaultDuration,
                            status: .pending, blueprintID: blueprint.id, stageID: stageID,
                            dependencyIDs: dependencies.isEmpty ? nil : dependencies)
        let automatic = WorkflowGraph.automaticPositions(for: scopedTasks + [task])
        var proposed = automatic[task.id] ?? CGPoint(x: 72, y: 80)
        while positions.values.contains(where: { abs($0.x - proposed.x) < 120 && abs($0.y - proposed.y) < 180 }) {
            proposed.y += 315
        }
        task.workflowX = Double(proposed.x)
        task.workflowY = Double(proposed.y)
        store.add(task)
        guard store.tasks.contains(where: { $0.id == task.id }) else { return nil }
        if case let .insert(from, to) = mode,
           let successor = scopedTasks.first(where: { $0.id == to }) {
            let rewired = successor.effectiveDependencyIDs.filter { $0 != from } + [task.id]
            if !store.setDependencies(for: successor, dependencyIDs: rewired) {
                store.delete(task)
                return nil
            }
        }
        selectedID = task.id
        return task.id
    }

    private func autoLayout() {
        store.setWorkflowPositions(WorkflowGraph.automaticPositions(for: scopedTasks))
    }

    @discardableResult
    private func withHistory<T>(_ operation: () -> T) -> T {
        let before = store.tasks
        let beforeAnniversaries = store.anniversaries
        let beforeMilestones = store.milestones
        let result = operation()
        let after = store.tasks
        let afterAnniversaries = store.anniversaries
        let afterMilestones = store.milestones
        if before != after || beforeAnniversaries != afterAnniversaries || beforeMilestones != afterMilestones {
            undoStack.append(WorkflowHistoryEntry(before: before, after: after,
                                                  beforeAnniversaries: beforeAnniversaries,
                                                  afterAnniversaries: afterAnniversaries,
                                                  beforeMilestones: beforeMilestones,
                                                  afterMilestones: afterMilestones))
            if undoStack.count > 30 { undoStack.removeFirst() }
            redoStack.removeAll()
        }
        return result
    }

    private func undo() {
        guard let entry = undoStack.last else { return }
        guard store.tasks == entry.after, store.anniversaries == entry.afterAnniversaries,
              store.milestones == entry.afterMilestones else {
            undoStack.removeAll(); redoStack.removeAll()
            store.actionMessage = "蓝图已在其他入口发生变化，画布撤销记录已清空。"
            return
        }
        undoStack.removeLast()
        store.tasks = entry.before
        store.anniversaries = entry.beforeAnniversaries
        store.milestones = entry.beforeMilestones
        redoStack.append(entry)
        if !store.tasks(for: blueprint.id).contains(where: { $0.id == selectedID }) { selectedID = nil }
    }

    private func redo() {
        guard let entry = redoStack.last else { return }
        guard store.tasks == entry.before, store.anniversaries == entry.beforeAnniversaries,
              store.milestones == entry.beforeMilestones else {
            undoStack.removeAll(); redoStack.removeAll()
            store.actionMessage = "蓝图已在其他入口发生变化，画布重做记录已清空。"
            return
        }
        redoStack.removeLast()
        store.tasks = entry.after
        store.anniversaries = entry.afterAnniversaries
        store.milestones = entry.afterMilestones
        undoStack.append(entry)
    }
}

private struct WorkflowNodeCard: View {
    @EnvironmentObject private var store: TaskStore
    @State private var isBlocking = false
    @State private var blockReason = ""
    let task: TaskItem
    let stageName: String?
    let selected: Bool
    let blockingReason: String?
    let onSelect: () -> Void
    let onNext: () -> Void
    let onParallel: () -> Void
    let onMove: (CGSize, Bool) -> Void
    let onConnect: (UUID) -> Bool
    let onMutation: (() -> Void) -> Void

    private var stateText: String {
        if task.isCompleted { return "已完成" }
        if task.isCancelled { return "已取消" }
        if task.effectiveStatus == .blocked { return "已阻塞" }
        if task.isInProgress { return "进行中" }
        if task.isUnscheduled { return "待安排" }
        if task.effectiveStatus == .postponed { return "已延期" }
        return blockingReason == nil ? "可开始" : "等待前置"
    }
    private var stateColor: Color {
        if task.isCompleted { return .green }
        if task.isCancelled || task.effectiveStatus == .blocked { return .orange }
        if task.effectiveStatus == .postponed { return .purple }
        return blockingReason == nil ? .blue : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Circle().fill(stateColor).frame(width: 8, height: 8)
                Text(stateText).font(.caption.weight(.semibold)).foregroundStyle(stateColor)
                Spacer()
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 2)
                        .onChanged { onMove($0.translation, false) }
                        .onEnded { onMove($0.translation, true) })
                    .help("拖动节点")
                    .accessibilityLabel("拖动节点")
                if !task.images.isEmpty { Label("\(task.images.count)", systemImage: "photo").font(.caption2).foregroundStyle(.secondary) }
                Menu {
                    Button("添加串行下一步", action: onNext)
                    Button("添加并行一步", action: onParallel)
                    Divider()
                    if !task.isCompleted && !task.isCancelled {
                        Button("开始执行") { onMutation { store.start(task) } }.disabled(blockingReason != nil)
                        Button("标记完成") { onMutation { store.markCompleted(task) } }.disabled(blockingReason != nil)
                        if task.effectiveStatus == .blocked {
                            Button("解除阻塞") { onMutation { store.restore(task) } }
                        } else {
                            Button("标记阻塞") { isBlocking = true }
                        }
                    }
                    if task.isCompleted { Button("撤销完成") { onMutation { store.restore(task) } } }
                } label: { Image(systemName: "ellipsis").comfortableIconTarget(36) }.menuStyle(.borderlessButton)
            }
            Text(task.title).font(.headline).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
            if let stageName {
                Label(stageName, systemImage: "square.stack.3d.up")
                    .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if let first = task.images.first, let image = first.nsImage {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(height: 68).frame(maxWidth: .infinity).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("节点图片：\(first.name)")
            } else if !task.notes.isEmpty {
                Text(task.notes).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    .frame(height: 32, alignment: .topLeading)
            } else {
                Spacer(minLength: 0)
            }
            if let blockingReason, !task.isCompleted {
                Text(blockingReason).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
            }
            HStack {
                Label(task.isUnscheduled ? "\(task.estimatedMinutes) 分钟 · 未安排" : "\(task.estimatedMinutes) 分钟 · \(task.scheduledFor.formatted(date: .abbreviated, time: .omitted))", systemImage: "clock")
                    .font(.caption2).lineLimit(1)
                Spacer()
                Button(action: onNext) { Image(systemName: "plus.circle.fill").font(.title3).comfortableIconTarget(36) }
                    .buttonStyle(.plain).help("添加串行下一步")
            }
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? Color.accentColor : stateColor.opacity(0.36), lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(selected ? 0.12 : 0.06), radius: selected ? 10 : 5, y: 3)
        .overlay(alignment: .leading) {
            Circle().fill(.blue).frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .dropDestination(for: String.self) { items, _ in
                    guard let first = items.first, let id = UUID(uuidString: first) else { return false }
                    return onConnect(id)
                }
                .offset(x: -18)
                .help("将其他节点的输出拖到这里，建立依赖")
        }
        .overlay(alignment: .trailing) {
            Circle().fill(.blue).frame(width: 16, height: 16)
                .overlay(Circle().stroke(.white, lineWidth: 2))
                .frame(width: 36, height: 36)
                .contentShape(Circle())
                .draggable(task.id.uuidString)
                .offset(x: 18)
                .help("拖动到后续节点，建立依赖")
        }
        .contentShape(RoundedRectangle(cornerRadius: 14))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(task.title)，\(stateText)")
        .alert("标记阻塞", isPresented: $isBlocking) {
            TextField("阻塞原因", text: $blockReason)
            Button("确认") { onMutation { store.block(task, reason: blockReason) }; blockReason = "" }
            Button("取消", role: .cancel) { blockReason = "" }
        } message: { Text("记录阻塞原因，方便之后继续执行。") }
    }
}

private struct WorkflowInspector: View {
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    let blueprintID: UUID
    let onSelect: (UUID) -> Void
    let onEdit: () -> Void
    let onDeleted: () -> Void
    let onMutation: (() -> Void) -> Void
    @State private var title: String
    @State private var notes: String
    @State private var stageID: UUID?
    @State private var enlargedImage: WorkflowImage?
    @State private var isDropTarget = false
    @State private var isRollbackConfirming = false
    @State private var isDeleteConfirming = false

    init(task: TaskItem, blueprintID: UUID, onSelect: @escaping (UUID) -> Void,
         onEdit: @escaping () -> Void, onDeleted: @escaping () -> Void,
         onMutation: @escaping (() -> Void) -> Void) {
        self.task = task
        self.blueprintID = blueprintID
        self.onSelect = onSelect
        self.onEdit = onEdit
        self.onDeleted = onDeleted
        self.onMutation = onMutation
        _title = State(initialValue: task.title)
        _notes = State(initialValue: task.notes)
        _stageID = State(initialValue: task.stageID)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("节点详情").font(.headline)
                VStack(alignment: .leading, spacing: 8) {
                    TextField("任务标题", text: $title)
                    TextField("说明（可选）", text: $notes, axis: .vertical).lineLimit(2...5)
                    Picker("阶段", selection: $stageID) {
                        Text("不分组").tag(nil as UUID?)
                        ForEach(store.stages(for: blueprintID)) { stage in Text(stage.name).tag(stage.id as UUID?) }
                    }
                    Button("保存内容") {
                        onMutation { store.setWorkflowContent(for: task.id, title: title, notes: notes, stageID: stageID) }
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                Divider()
                HStack {
                    Text("图片").font(.subheadline.weight(.semibold))
                    Spacer()
                    Button("添加", systemImage: "photo.badge.plus", action: pickImages)
                }
                if task.images.isEmpty {
                    Text("可拖入、粘贴或选择图片；不添加也可以。")
                        .font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 65)
                        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 9))
                } else {
                    ForEach(Array(task.images.enumerated()), id: \.element.id) { index, image in
                        HStack {
                            Button { enlargedImage = image } label: {
                                if let nsImage = image.nsImage {
                                    Image(nsImage: nsImage).resizable().scaledToFill()
                                        .frame(width: 62, height: 48).clipped()
                                        .clipShape(RoundedRectangle(cornerRadius: 6))
                                        .accessibilityLabel("查看图片：\(image.name)")
                                }
                            }.buttonStyle(.plain)
                            Text(image.name).font(.caption).lineLimit(2)
                            Spacer()
                            if index > 0 {
                                Button { moveImage(from: index, to: index - 1) } label: { Image(systemName: "arrow.up").comfortableIconTarget(36) }
                                    .help("前移图片")
                            }
                            if index < task.images.count - 1 {
                                Button { moveImage(from: index, to: index + 1) } label: { Image(systemName: "arrow.down").comfortableIconTarget(36) }
                                    .help("后移图片")
                            }
                            Button { onMutation { store.setWorkflowImages(for: task.id, images: task.images.filter { $0.id != image.id }) } } label: {
                                Image(systemName: "trash").comfortableIconTarget(36)
                            }.help("移除图片")
                        }
                    }
                }
                Button("粘贴图片", systemImage: "doc.on.clipboard", action: pasteImage)
                Divider()
                Text("前置任务").font(.subheadline.weight(.semibold))
                ForEach(task.effectiveDependencyIDs, id: \.self) { id in
                    HStack {
                        Button(store.tasks.first(where: { $0.id == id })?.title ?? "失效任务") { onSelect(id) }
                            .buttonStyle(.link)
                        Spacer()
                        Button { onMutation { store.disconnect(id, from: task) } } label: { Image(systemName: "xmark.circle").comfortableIconTarget(36) }
                            .help("移除连线")
                    }
                }
                Menu("添加前置任务", systemImage: "point.topleft.down.curvedto.point.bottomright.up") {
                    ForEach(store.tasks(for: blueprintID).filter { $0.id != task.id && !task.effectiveDependencyIDs.contains($0.id) }) { candidate in
                        Button(candidate.title) { onMutation { _ = store.connect(candidate, to: task) } }
                    }
                }
                if let reason = store.executionBlockReason(for: task), !task.isCompleted {
                    Label(reason, systemImage: "lock").font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Button("开始", systemImage: "play.fill") { onMutation { store.start(task) } }
                        .disabled(task.isCompleted || task.isInProgress || store.executionBlockReason(for: task) != nil)
                    Button("完成", systemImage: "checkmark") { onMutation { store.markCompleted(task) } }
                        .disabled(task.isCompleted || store.executionBlockReason(for: task) != nil)
                }
                if task.effectiveStatus == .blocked {
                    Button("解除阻塞", systemImage: "lock.open") { onMutation { store.restore(task) } }
                }
                if task.isCompleted {
                    Button("撤销完成", systemImage: "arrow.uturn.backward") {
                        if WorkflowGraph.descendants(of: task.id, tasks: store.tasks)
                            .contains(where: { $0.isInProgress || $0.isCompleted }) {
                            isRollbackConfirming = true
                        } else {
                            onMutation { store.restore(task) }
                        }
                    }
                }
                Divider()
                Button("完整任务设置", systemImage: "slider.horizontal.3", action: onEdit)
                Button("删除节点", systemImage: "trash", role: .destructive) { isDeleteConfirming = true }
            }
            .padding(16)
        }
        .background(.background.opacity(0.72))
        .dropDestination(for: URL.self) { urls, _ in
            appendImages(from: urls)
            return true
        } isTargeted: { isDropTarget = $0 }
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isDropTarget ? .blue : .clear, lineWidth: 2))
        .sheet(item: $enlargedImage) { image in
            VStack {
                HStack { Text(image.name).font(.headline); Spacer(); Button("关闭") { enlargedImage = nil } }
                if let nsImage = image.nsImage { Image(nsImage: nsImage).resizable().scaledToFit() }
            }
            .padding(20).frame(minWidth: 560, minHeight: 440)
        }
        .confirmationDialog("回退后续任务？", isPresented: $isRollbackConfirming) {
            Button("回退当前及所有后续任务", role: .destructive) { onMutation { store.rollbackWorkflow(from: task) } }
        } message: {
            Text("后续已开始或完成的任务会恢复为待完成，原有连线和图片会保留。")
        }
        .confirmationDialog("删除节点？", isPresented: $isDeleteConfirming) {
            if store.tasks.contains(where: { $0.effectiveDependencyIDs.contains(task.id) }) {
                Button("删除并连接前后节点", role: .destructive) {
                    var removed = false
                    onMutation { removed = store.removeWorkflowNode(task, reconnect: true) }
                    if removed { onDeleted() }
                }
                Button("删除并移除相关连线", role: .destructive) {
                    var removed = false
                    onMutation { removed = store.removeWorkflowNode(task, reconnect: false) }
                    if removed { onDeleted() }
                }
            } else {
                Button("删除节点", role: .destructive) {
                    var removed = false
                    onMutation { removed = store.removeWorkflowNode(task, reconnect: false) }
                    if removed { onDeleted() }
                }
            }
        } message: {
            Text("节点对应的任务也会删除。后续节点会按所选方式更新依赖。")
        }
    }

    private func pickImages() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        appendImages(from: panel.urls)
    }

    private func appendImages(from urls: [URL]) {
        var images = task.images
        for url in urls {
            do { images.append(try WorkflowImage.imported(data: Data(contentsOf: url), name: url.lastPathComponent)) }
            catch { store.actionMessage = "图片导入失败：\(error.localizedDescription)" }
        }
        onMutation { store.setWorkflowImages(for: task.id, images: images) }
    }

    private func pasteImage() {
        guard let image = NSPasteboard.general.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
              let data = image.tiffRepresentation else {
            store.actionMessage = "剪贴板中没有可用的图片。"
            return
        }
        do {
            let imported = try WorkflowImage.imported(data: data, name: "粘贴的图片")
            onMutation { store.setWorkflowImages(for: task.id, images: task.images + [imported]) }
        } catch { store.actionMessage = "图片导入失败：\(error.localizedDescription)" }
    }

    private func moveImage(from source: Int, to destination: Int) {
        var reordered = task.images
        reordered.swapAt(source, destination)
        onMutation { store.setWorkflowImages(for: task.id, images: reordered) }
    }
}

private struct WorkflowBulkAddView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var parallel = false
    let onAdd: ([String], Bool) -> Void

    private var titles: [String] {
        text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("批量添加节点").font(.title2.weight(.semibold))
            Text("每行一个任务；串行会依次连接，并行会与当前选中节点处于同一层。")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.body).frame(minHeight: 220)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(.quaternary))
            Toggle("作为并行任务添加", isOn: $parallel)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加 \(titles.count) 个节点") { onAdd(titles, parallel); dismiss() }
                    .buttonStyle(.borderedProminent).disabled(titles.isEmpty)
            }
        }
        .padding(22).frame(width: 520, height: 390)
    }
}

private struct WorkflowExistingTaskPicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    let blueprint: BlueprintItem
    let onAdded: (TaskItem) -> Void
    @State private var search = ""

    private var candidates: [TaskItem] {
        store.tasks.filter {
            $0.blueprintID == nil && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("加入已有任务").font(.title2.weight(.semibold))
            TextField("搜索未归入蓝图的任务", text: $search)
                .textFieldStyle(.roundedBorder)
            List(candidates) { task in
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(task.title)
                        Text(task.effectiveStatus.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("加入") {
                        onAdded(task)
                    }
                }
            }
            HStack { Spacer(); Button("完成") { dismiss() } }
        }
        .padding(22).frame(width: 520, height: 460)
    }
}
