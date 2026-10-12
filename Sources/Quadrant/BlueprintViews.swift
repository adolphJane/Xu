import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BlueprintsView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var isAdding = false
    @State private var selectedBlueprint: BlueprintItem?
    @State private var selectedTaskRoot: TaskItem?
    @State private var isChoosingTemplate = false
    @State private var showArchived = false
    @State private var importMessage: String?
    @State private var isAICreating = false
    @State private var isShowingHistory = false

    private let columns = [GridItem(.adaptive(minimum: 280), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "BLUEPRINTS",
                    title: "蓝图",
                    description: "从任务出发，按步骤持续推进。",
                    action: { isAdding = true },
                    actionTitle: "新建蓝图"
                )
                HStack {
                    Button("AI 生成蓝图", systemImage: "sparkles") { isAICreating = true }.buttonStyle(.borderedProminent)
                    Button("从模板创建", systemImage: "square.stack.3d.up.fill") { isChoosingTemplate = true }
                        .popover(isPresented: $isChoosingTemplate, arrowEdge: .bottom) {
                            BlueprintTemplatePicker()
                        }
                    Button("导入蓝图", systemImage: "square.and.arrow.down") { importBlueprint() }
                    Button("AI 变更记录", systemImage: "clock.arrow.circlepath") { isShowingHistory = true }
                        .popover(isPresented: $isShowingHistory, arrowEdge: .bottom) {
                            PlanChangeHistoryView()
                        }
                    Spacer()
                    Toggle("显示已归档", isOn: $showArchived).toggleStyle(.switch)
                }
                .controlSize(.large)

                let visibleBlueprints = store.blueprints.filter { showArchived || $0.archivedAt == nil }
                let taskRoots = TaskTreeProjection.roots(in: store.tasks)
                if visibleBlueprints.isEmpty && taskRoots.isEmpty {
                    ContentUnavailableView(
                        "还没有蓝图",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        description: Text("创建一份蓝图，把长期目标拆成可执行的步骤。")
                    )
                    .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(columns: columns, spacing: 16) {
                        ForEach(taskRoots) { root in
                            Button { selectedTaskRoot = root } label: {
                                TaskBlueprintCard(root: root)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("打开\(root.title)任务蓝图")
                        }
                        ForEach(visibleBlueprints) { blueprint in
                            BlueprintCard(blueprint: blueprint)
                                .onTapGesture { selectedBlueprint = blueprint }
                        }
                    }
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
        }
        .clickAwayPopover(isPresented: $isAdding) { request, close in
            BlueprintEditor(cancelRequest: request, onClose: close)
        }
        .sheet(isPresented: $isAICreating) { AIBlueprintCreatorView() }
        .sheet(item: $selectedBlueprint) { BlueprintDetailView(blueprintID: $0.id) }
        .sheet(item: $selectedTaskRoot) { TaskBlueprintView(rootTaskID: $0.id) }
        .alert("导入蓝图", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("知道了") { importMessage = nil }
        } message: { Text(importMessage ?? "") }
    }

    private func importBlueprint() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let item = try store.importBlueprint(from: Data(contentsOf: url))
            importMessage = "已导入“\(item.name)”。"
        } catch {
            importMessage = "导入失败：\(error.localizedDescription)"
        }
    }
}

private struct TaskBlueprintCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let root: TaskItem

    private var children: [TaskItem] { TaskTreeProjection.descendants(of: root.id, in: store.tasks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.title3)
                    .foregroundStyle(preferences.accentColor)
                    .frame(width: 38, height: 38)
                    .background(preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(root.title).font(.headline).lineLimit(2)
                    Text("任务蓝图").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Text("\(children.count) 项子任务 · \(children.filter(\.isCompleted).count) 项已完成")
                .font(.subheadline).foregroundStyle(.secondary)
            ProgressView(value: children.isEmpty ? 0 : Double(children.filter(\.isCompleted).count) / Double(children.count))
                .tint(preferences.accentColor)
            Text("与列表、四象限共用任务")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(preferences.accentColor.opacity(0.16)))
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
    }
}

struct BlueprintCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var isHovered = false
    let blueprint: BlueprintItem

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color(hex: blueprint.colorHex))
                    .frame(width: 10, height: 34)
                VStack(alignment: .leading, spacing: 3) {
                    Text(blueprint.name).font(.headline)
                Text(blueprint.status.title).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(Int(store.blueprintProgress(blueprint.id) * 100))%")
                    .font(.title3.monospacedDigit().weight(.semibold))
            }
            Text(blueprint.goal.isEmpty ? "尚未填写目标说明" : blueprint.goal)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ProgressView(value: store.blueprintProgress(blueprint.id))
                .tint(Color(hex: blueprint.colorHex))
            HStack {
                Label("\(store.stages(for: blueprint.id).count) 个阶段", systemImage: "square.stack.3d.up")
                Spacer()
                if blueprint.archivedAt != nil { Label("已归档", systemImage: "archivebox") }
                Label(blueprint.dueDate.formatted(date: .abbreviated, time: .omitted), systemImage: "flag")
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(18)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(isHovered ? preferences.accentColor.opacity(0.28) : Color.primary.opacity(0.07)))
        .shadow(color: .black.opacity(isHovered ? 0.08 : preferences.shadowStrength), radius: isHovered ? 13 : 6, y: isHovered ? 5 : 2)
        .offset(y: isHovered && !(preferences.reduceMotion || systemReduceMotion) ? -2 : 0)
        .onHover { hovering in
            withAnimation(preferences.reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.22)) { isHovered = hovering }
        }
    }
}

struct BlueprintEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    private let original: BlueprintItem?
    @State private var name: String
    @State private var goal: String
    @State private var startDate: Date
    @State private var dueDate: Date
    @State private var status: BlueprintStatus
    @State private var colorHex: String
    @State private var showDiscardConfirmation = false
    private let initialDueDate: Date
    private let cancelRequest: Int
    private let onClose: (() -> Void)?

    init(blueprint: BlueprintItem? = nil, cancelRequest: Int = 0, onClose: (() -> Void)? = nil) {
        let defaultDueDate = blueprint?.dueDate ?? Calendar.current.date(byAdding: .month, value: 1, to: .now) ?? .now
        original = blueprint
        _name = State(initialValue: blueprint?.name ?? "")
        _goal = State(initialValue: blueprint?.goal ?? "")
        _startDate = State(initialValue: blueprint?.startDate ?? .now)
        _dueDate = State(initialValue: defaultDueDate)
        initialDueDate = defaultDueDate
        self.cancelRequest = cancelRequest
        self.onClose = onClose
        _status = State(initialValue: blueprint?.status ?? .active)
        _colorHex = State(initialValue: blueprint?.colorHex ?? "4F65D9")
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(original == nil ? "新建蓝图" : "编辑蓝图").font(.title2.weight(.bold)); Spacer() }.padding(22)
            Form {
                TextField("蓝图名称", text: $name)
                TextField("目标说明", text: $goal, axis: .vertical)
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                DatePicker("目标完成日期", selection: $dueDate, in: startDate..., displayedComponents: .date)
                Picker("初始状态", selection: $status) {
                    ForEach(BlueprintStatus.allCases) { Text($0.title).tag($0) }
                }
                Picker("主题色", selection: $colorHex) {
                    Label("靛蓝", systemImage: "circle.fill").foregroundStyle(.indigo).tag("4F65D9")
                    Label("蓝绿", systemImage: "circle.fill").foregroundStyle(.teal).tag("349B8F")
                    Label("橙色", systemImage: "circle.fill").foregroundStyle(.orange).tag("D9823B")
                    Label("紫色", systemImage: "circle.fill").foregroundStyle(.purple).tag("815AC2")
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消") { cancel() }
                Button(original == nil ? "创建蓝图" : "保存修改") {
                    let item = BlueprintItem(
                        id: original?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), goal: goal,
                        startDate: startDate, dueDate: dueDate, status: status, colorHex: colorHex,
                        createdAt: original?.createdAt ?? .now,
                        originalDueDate: original?.originalDueDate, archivedAt: original?.archivedAt
                    )
                    if original == nil { store.addBlueprint(item) } else { store.updateBlueprint(item) }
                    close()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 520, height: 470)
        .onChange(of: cancelRequest) { _, _ in
            if !showDiscardConfirmation { cancel() }
        }
        .onExitCommand { cancel() }
        .confirmationDialog("放弃未保存的蓝图？", isPresented: $showDiscardConfirmation) {
            Button("放弃", role: .destructive) { close() }
            Button("继续编辑", role: .cancel) { }
        } message: { Text("当前填写的内容将丢失。") }
    }

    private func cancel() {
        let hasChanges = name != (original?.name ?? "")
            || goal != (original?.goal ?? "")
            || !Calendar.current.isDate(startDate, inSameDayAs: original?.startDate ?? startDate)
            || !Calendar.current.isDate(dueDate, inSameDayAs: initialDueDate)
            || status != (original?.status ?? .active)
            || colorHex != (original?.colorHex ?? "4F65D9")
        if hasChanges { showDiscardConfirmation = true } else { close() }
    }

    private func close() { if let onClose { onClose() } else { dismiss() } }
}

struct BlueprintDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    let blueprintID: UUID
    @State private var isAddingStage = false
    @State private var milestoneStage: StageItem?
    @State private var isAddingTask = false
    @State private var isEditing = false
    @State private var showDeleteConfirmation = false
    @State private var mode: PlanViewMode = .workflow
    @State private var isRescheduling = false
    @State private var operationMessage: String?
    @State private var editingTask: TaskItem?
    @State private var focusedTaskID: UUID?
    @State private var isAIReplanning = false

    init(blueprintID: UUID, focusTaskID: UUID? = nil) {
        self.blueprintID = blueprintID
        _focusedTaskID = State(initialValue: focusTaskID)
    }

    private var blueprint: BlueprintItem? { store.blueprints.first { $0.id == blueprintID } }

    var body: some View {
        NavigationStack {
            Group {
                if let blueprint {
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 14) {
                            blueprintHeader(blueprint)
                            Picker("蓝图视图", selection: $mode) { ForEach(PlanViewMode.allCases) { Text($0.rawValue).tag($0) } }
                                .pickerStyle(.segmented)
                        }
                        .padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 14)
                        Divider()
                        if mode == .workflow {
                            BlueprintWorkflowView(blueprint: blueprint, focusTaskID: focusedTaskID)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else {
                            ScrollView {
                                VStack(alignment: .leading, spacing: 22) {
                                    switch mode {
                                    case .workflow: EmptyView()
                                    case .overview: overview(blueprint)
                                    case .timeline: BlueprintTimelineView(blueprint: blueprint)
                                    case .week: BlueprintScheduleView(blueprint: blueprint, days: 7)
                                    case .month: BlueprintScheduleView(blueprint: blueprint, days: 30)
                                    }
                                }
                                .padding(26)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView("蓝图不存在", systemImage: "exclamationmark.triangle")
                }
            }
            .frame(minWidth: 1100, minHeight: 740)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } }
                ToolbarItem { Button("编辑", systemImage: "pencil") { isEditing = true } }
                ToolbarItem {
                    Menu {
                        Button("AI 重新规划", systemImage: "sparkles") { isAIReplanning = true }
                        Button("批量重新规划", systemImage: "calendar.badge.clock") { isRescheduling = true }
                        Button("复制蓝图", systemImage: "doc.on.doc") {
                            if let blueprint {
                                let copy = store.duplicateBlueprint(blueprint)
                                operationMessage = "已创建“\(copy.name)”。"
                            }
                        }
                        Button(blueprint?.archivedAt == nil ? "归档蓝图" : "取消归档", systemImage: "archivebox") {
                            if let blueprint { store.archiveBlueprint(blueprint) }
                        }
                        Button("导出蓝图", systemImage: "square.and.arrow.up") {
                            if let blueprint { exportBlueprint(blueprint) }
                        }
                    } label: { Label("更多", systemImage: "ellipsis.circle") }
                }
                ToolbarItem(placement: .destructiveAction) {
                    Button("删除蓝图", role: .destructive) { showDeleteConfirmation = true }
                }
            }
        }
        .sheet(isPresented: $isAddingStage) { StageEditor(blueprintID: blueprintID) }
        .sheet(item: $milestoneStage) { MilestoneEditor(blueprintID: blueprintID, stage: $0) }
        .clickAwayPopover(isPresented: $isAddingTask) { request, close in
            TaskComposerView(blueprintID: blueprintID, opensBlueprintOnSave: false,
                             cancelRequest: request, onClose: close)
        }
        .sheet(item: $editingTask) { TaskEditor(task: $0) }
        .sheet(isPresented: $isRescheduling) { ReschedulePreviewView(blueprintID: blueprintID) }
        .sheet(isPresented: $isAIReplanning) { if let blueprint { AIReplanView(blueprint: blueprint) } }
        .clickAwayPopover(isPresented: $isEditing) { request, close in
            if let blueprint { BlueprintEditor(blueprint: blueprint, cancelRequest: request, onClose: close) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .focusBlueprintTask)) { notification in
            if notification.userInfo?["blueprintID"] as? UUID == blueprintID {
                focusedTaskID = notification.object as? UUID
                mode = .workflow
            }
        }
        .confirmationDialog("删除蓝图？", isPresented: $showDeleteConfirmation) {
            Button("删除蓝图", role: .destructive) {
                if let blueprint { store.deleteBlueprint(blueprint); dismiss() }
            }
        } message: {
            Text("阶段和里程碑会被删除，关联任务将保留并解除蓝图关联。")
        }
        .alert("蓝图操作", isPresented: Binding(get: { operationMessage != nil }, set: { if !$0 { operationMessage = nil } })) {
            Button("知道了") { operationMessage = nil }
        } message: { Text(operationMessage ?? "") }
    }

    private func blueprintHeader(_ blueprint: BlueprintItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(blueprint.name).font(.title2.weight(.bold))
                    Text(blueprint.goal.isEmpty ? "尚未填写目标说明" : blueprint.goal)
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer()
                Menu(blueprint.status.title) {
                    ForEach(BlueprintStatus.allCases) { status in
                        Button(status.title) { store.setBlueprintStatus(blueprint, status: status) }
                    }
                }
            }
            HStack(spacing: 16) {
                Label("完成 \(Int(store.blueprintProgress(blueprint.id) * 100))%", systemImage: "checkmark.circle")
                Label("可开始 \(store.tasks(for: blueprint.id).filter { $0.needsAction && store.executionBlockReason(for: $0) == nil }.count)", systemImage: "play.circle")
                Label("等待 \(store.tasks(for: blueprint.id).filter { $0.needsAction && store.executionBlockReason(for: $0) != nil }.count)", systemImage: "lock")
                Spacer()
                if let original = blueprint.originalDueDate {
                    Text("原定 \(original.formatted(date: .abbreviated, time: .omitted)) · 当前 \(blueprint.dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .foregroundStyle(.purple)
                } else {
                    Text("目标日期 \(blueprint.dueDate.formatted(date: .abbreviated, time: .omitted))")
                }
            }
            .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func overview(_ blueprint: BlueprintItem) -> some View {
        let todayTasks = TodayBlueprintOrganizer.sortedTasks(
            store.tasks(for: blueprint.id).filter { TaskPlacement.isInToday($0) }
        )
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("今日行动").font(.title2.weight(.bold))
                Text(todayTasks.isEmpty ? "今天还没有从蓝图中安排动作" : "\(todayTasks.filter(\.isCompleted).count)/\(todayTasks.filter { !$0.isCancelled }.count) 已完成 · 待投入 \(todayTasks.filter(\.needsAction).reduce(0) { $0 + $1.estimatedMinutes }) 分钟")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("添加今日任务", systemImage: "plus.circle") { isAddingTask = true }
        }
        if todayTasks.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "sun.max").font(.title2).foregroundStyle(Color(hex: blueprint.colorHex))
                Text("从阶段或里程碑中挑选一个最小行动，安排到今天。")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("立即添加") { isAddingTask = true }.buttonStyle(.borderedProminent)
            }
            .padding(18)
            .background(Color(hex: blueprint.colorHex).opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
        } else {
            ForEach(todayTasks) { task in
                TaskCard(task: task, onSelect: { editingTask = $0 })
            }
        }

        Divider().padding(.vertical, 3)
        HStack {
            Text("阶段与里程碑").font(.title2.weight(.bold))
            Spacer()
            Button("添加阶段", systemImage: "square.stack.3d.up.badge.plus") { isAddingStage = true }
        }
        let scopedStages = store.stages(for: blueprint.id)
        if scopedStages.isEmpty {
            ContentUnavailableView("还没有阶段", systemImage: "square.stack.3d.up", description: Text("先添加阶段，再为阶段设定里程碑。"))
                .frame(maxWidth: .infinity, minHeight: 220)
        } else {
            ForEach(Array(scopedStages.enumerated()), id: \.element.id) { index, stage in
                StagePanel(stage: stage, isFirst: index == 0, isLast: index == scopedStages.count - 1, onAddMilestone: { milestoneStage = stage })
            }
        }
        let scopedTasks = store.tasks(for: blueprint.id)
            .filter { !TaskPlacement.isInToday($0) }
            .sorted { $0.scheduledFor < $1.scheduledFor }
        if !scopedTasks.isEmpty {
            Text("后续与历史任务").font(.title2.weight(.bold)).padding(.top, 6)
            ForEach(scopedTasks) { task in
                TaskCard(task: task, onSelect: { editingTask = $0 })
            }
        }
    }

    private func exportBlueprint(_ blueprint: BlueprintItem) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(blueprint.name).xu-blueprint.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try store.exportPackage(for: blueprint).write(to: url, options: .atomic)
            operationMessage = "蓝图已导出。"
        } catch {
            operationMessage = "导出失败：\(error.localizedDescription)"
        }
    }
}

struct StagePanel: View {
    @EnvironmentObject private var store: TaskStore
    let stage: StageItem
    let isFirst: Bool
    let isLast: Bool
    let onAddMilestone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(stage.name).font(.headline)
                    Text("\(stage.startDate.formatted(date: .abbreviated, time: .omitted)) → \(stage.dueDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.moveStage(stage, direction: -1) } label: { Image(systemName: "arrow.up").comfortableIconTarget(36) }.disabled(isFirst)
                Button { store.moveStage(stage, direction: 1) } label: { Image(systemName: "arrow.down").comfortableIconTarget(36) }.disabled(isLast)
                Button("里程碑", systemImage: "flag.badge.plus", action: onAddMilestone)
            }
            Divider()
            let milestones = store.milestones(for: stage.id)
            if milestones.isEmpty {
                Text("暂无里程碑").font(.subheadline).foregroundStyle(.tertiary)
            } else {
                ForEach(milestones) { milestone in
                    HStack {
                        Button { store.toggleMilestone(milestone) } label: {
                            Image(systemName: milestone.isCompleted ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(milestone.isCompleted ? .green : .secondary)
                                .comfortableIconTarget(36)
                        }.buttonStyle(.plain)
                        Text(milestone.name).strikethrough(milestone.isCompleted)
                        Spacer()
                        Text(milestone.dueDate, format: .dateTime.month().day()).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct StageEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    let blueprintID: UUID
    @State private var name = ""
    @State private var startDate = Date.now
    @State private var dueDate = Calendar.current.date(byAdding: .weekOfYear, value: 1, to: .now) ?? .now

    var body: some View {
        VStack(spacing: 0) {
            Text("添加阶段").font(.title2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading).padding(22)
            Form {
                TextField("阶段名称", text: $name)
                DatePicker("开始日期", selection: $startDate, displayedComponents: .date)
                DatePicker("结束日期", selection: $dueDate, in: startDate..., displayedComponents: .date)
            }.formStyle(.grouped)
            HStack {
                Spacer(); Button("取消") { dismiss() }
                Button("添加") {
                    store.addStage(StageItem(blueprintID: blueprintID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), order: store.stages(for: blueprintID).count, startDate: startDate, dueDate: dueDate))
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20)
        }
        .frame(width: 460, height: 330)
    }
}

struct MilestoneEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    let blueprintID: UUID
    let stage: StageItem
    @State private var name = ""
    @State private var dueDate: Date

    init(blueprintID: UUID, stage: StageItem) {
        self.blueprintID = blueprintID
        self.stage = stage
        _dueDate = State(initialValue: stage.dueDate)
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("添加里程碑").font(.title2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading).padding(22)
            Form {
                TextField("里程碑名称", text: $name)
                DatePicker("目标日期", selection: $dueDate, displayedComponents: .date)
            }.formStyle(.grouped)
            HStack {
                Spacer(); Button("取消") { dismiss() }
                Button("添加") {
                    store.addMilestone(MilestoneItem(blueprintID: blueprintID, stageID: stage.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), dueDate: dueDate))
                    dismiss()
                }.buttonStyle(.borderedProminent).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20)
        }
        .frame(width: 460, height: 290)
    }
}

private extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
