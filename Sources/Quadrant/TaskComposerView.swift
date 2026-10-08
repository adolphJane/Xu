import SwiftUI

enum TaskComposerMode: String, CaseIterable, Identifiable {
    case task = "待办"
    case completed = "已完成"
    case ai = "AI 生成"

    var id: Self { self }

    var icon: String {
        switch self {
        case .task: "plus.circle"
        case .completed: "checkmark.circle"
        case .ai: "sparkles"
        }
    }
}

private enum TaskPlanChoice: String, CaseIterable, Identifiable {
    case today = "今天"
    case tomorrow = "明天"
    case custom = "选日期"
    case inbox = "收集箱"

    var id: Self { self }
}

/// One creation surface for tasks, completed work, and editable AI drafts.
struct TaskComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @FocusState private var titleFocused: Bool
    @FocusState private var sentenceFocused: Bool

    @State private var mode: TaskComposerMode
    @State private var title = ""
    @State private var sentence = ""
    @State private var hasAIDraft = false
    @State private var subtasks: [String] = []
    @State private var blueprintID: UUID?
    @State private var stageID: UUID?
    @State private var milestoneID: UUID?
    @State private var dependencyIDs: Set<UUID> = []
    @State private var project = ""
    @State private var notes = ""
    @State private var quadrant: Quadrant = .schedule
    @State private var reportCategory: ReportCategory = .projectProgress
    @State private var planChoice: TaskPlanChoice = .today
    @State private var customDate = Date.now
    @State private var completedAt = Date.now
    @State private var estimatedMinutes = 30
    @State private var hasDeadline = false
    @State private var dueDate = Date.now
    @State private var isPlanLocked = false
    @State private var showDetails = false
    @State private var keepOpen = false
    @State private var feedback: String?
    @State private var appliedDefaults = false

    init(mode: TaskComposerMode = .task, blueprintID: UUID? = nil) {
        _mode = State(initialValue: mode)
        _blueprintID = State(initialValue: blueprintID)
    }

    private var motion: Animation? {
        preferences.reduceMotion || systemReduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    private var isAIInput: Bool { mode == .ai && !hasAIDraft }
    private var composerHeight: CGFloat {
        if isAIInput { return 390 }
        if showDetails || (mode == .ai && !subtasks.isEmpty) { return 640 }
        return 505
    }
    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanSentence: String { sentence.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var activeBlueprints: [BlueprintItem] { store.blueprints.filter { $0.archivedAt == nil } }

    var body: some View {
        VStack(spacing: 0) {
            header
            modeSelector
                .padding(.horizontal, 25)
                .padding(.bottom, 13)
            ScrollView {
                VStack(alignment: .leading, spacing: 19) {
                    if isAIInput { aiInput } else { taskFields }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 25)
                .padding(.vertical, 15)
            }
            footer
        }
        .frame(width: 630, height: composerHeight)
        .animation(motion, value: composerHeight)
        .background(preferences.pageBackground)
        .tint(preferences.accentColor)
        .onAppear {
            guard !appliedDefaults else { return }
            quadrant = preferences.defaultQuadrant
            estimatedMinutes = preferences.defaultDuration
            if let blueprintID {
                project = store.blueprints.first(where: { $0.id == blueprintID })?.name ?? ""
            }
            appliedDefaults = true
            if mode == .ai { store.aiTaskError = nil }
            focusInput()
        }
        .onChange(of: blueprintID) { oldValue, newValue in
            stageID = nil
            milestoneID = nil
            dependencyIDs = []
            let oldName = store.blueprints.first(where: { $0.id == oldValue })?.name ?? ""
            if project.isEmpty || project == oldName {
                project = store.blueprints.first(where: { $0.id == newValue })?.name ?? ""
            }
        }
        .onChange(of: stageID) { _, _ in milestoneID = nil }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(preferences.accentColor)
                .frame(width: 40, height: 40)
                .background(preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("添加事项")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("快速记录，再决定如何安排。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 27, height: 27)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭")
            .accessibilityLabel("关闭添加事项")
        }
        .padding(.horizontal, 25)
        .padding(.top, 23)
        .padding(.bottom, 20)
    }

    private var modeSelector: some View {
        HStack(spacing: 5) {
            ForEach(TaskComposerMode.allCases) { option in
                Button {
                    withAnimation(motion) {
                        mode = option
                        feedback = nil
                    }
                    if option == .ai { store.aiTaskError = nil }
                    focusInput()
                } label: {
                    Label(option.rawValue, systemImage: option.icon)
                        .font(.system(size: 12, weight: mode == option ? .semibold : .medium))
                        .frame(maxWidth: .infinity)
                        .frame(height: 35)
                        .foregroundStyle(mode == option ? preferences.accentColor : .secondary)
                        .background(mode == option ? preferences.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(mode == option ? preferences.accentColor.opacity(0.23) : .clear))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
                .accessibilityAddTraits(mode == option ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(preferences.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
    }

    private var aiInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("用一句话描述你要做的事")
                .font(.headline)
            TextField("例如：明天下午完成渠道适配测试，预计一小时", text: $sentence, axis: .vertical)
                .lineLimit(3...5)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .focused($sentenceFocused)
                .padding(16)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(preferences.accentColor.opacity(0.25)))
                .onSubmit { if !cleanSentence.isEmpty { Task { await parseAI() } } }
            Text("AI 会生成可编辑草稿；确认后才会保存到任务列表。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let feedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(preferences.accentColor)
            }
            if let error = store.aiTaskError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                Button("直接作为普通待办", systemImage: "arrow.right") {
                    title = cleanSentence
                    hasAIDraft = false
                    mode = .task
                    focusInput()
                }
                .buttonStyle(.link)
            }
        }
        .overlay {
            if store.isAIParsing {
                ProgressView("正在生成草稿…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }

    private var taskFields: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 8) {
                Text(mode == .completed ? "完成了什么？" : "要做什么？")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                TextField(mode == .completed ? "例如：完成支付链路回归" : "例如：完成渠道适配登录联调", text: $title)
                    .font(.system(size: 19, weight: .medium))
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit { if !cleanTitle.isEmpty { save() } }
                    .padding(.horizontal, 16)
                    .frame(height: 57)
                    .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(preferences.accentColor.opacity(0.25)))
            }
            HStack(spacing: 13) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(preferences.accentColor)
                    .frame(width: 17)
                Text("关联蓝图")
                    .font(.subheadline)
                Spacer()
                Picker("关联蓝图", selection: $blueprintID) {
                    Text("不关联").tag(nil as UUID?)
                    ForEach(activeBlueprints) { blueprint in
                        Text(blueprint.name).tag(blueprint.id as UUID?)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 250)
            }
            .padding(.horizontal, 15)
            .frame(height: 50)
            .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 12))

            if mode == .completed {
                HStack {
                    Label("完成时间", systemImage: "checkmark.circle")
                        .font(.subheadline)
                    Spacer()
                    DatePicker("完成时间", selection: $completedAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                .padding(.horizontal, 15)
                .frame(height: 50)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Text("安排到")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Picker("安排到", selection: $planChoice) {
                        ForEach(TaskPlanChoice.allCases) { choice in Text(choice.rawValue).tag(choice) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    if planChoice == .custom {
                        DatePicker("计划日期", selection: $customDate, displayedComponents: .date)
                            .padding(.top, 3)
                    }
                }
            }

            DisclosureGroup(isExpanded: $showDetails) {
                advancedFields
                    .padding(.top, 13)
            } label: {
                Label("更多设置", systemImage: "slider.horizontal.3")
                    .font(.subheadline.weight(.medium))
            }
            .padding(15)
            .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 13))

            if mode == .ai && hasAIDraft && !subtasks.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    Text("AI 建议的子任务")
                        .font(.subheadline.weight(.semibold))
                    ForEach(subtasks, id: \.self) { subtask in
                        HStack(spacing: 10) {
                            Image(systemName: "arrow.turn.down.right")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(subtask).font(.subheadline)
                            Spacer()
                            Button { subtasks.removeAll { $0 == subtask } } label: {
                                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("移除子任务")
                        }
                    }
                }
                .padding(15)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 13))
            }
            if let feedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(preferences.accentColor)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 13) {
            TextField("所属项目（日报按项目归类）", text: $project)
            if let blueprintID, !store.stages(for: blueprintID).isEmpty {
                Picker("所属阶段", selection: $stageID) {
                    Text("不指定").tag(nil as UUID?)
                    ForEach(store.stages(for: blueprintID)) { stage in
                        Text(stage.name).tag(stage.id as UUID?)
                    }
                }
            }
            if let stageID, !store.milestones(for: stageID).isEmpty {
                Picker("关联里程碑", selection: $milestoneID) {
                    Text("不指定").tag(nil as UUID?)
                    ForEach(store.milestones(for: stageID)) { milestone in
                        Text(milestone.name).tag(milestone.id as UUID?)
                    }
                }
            }
            if let blueprintID, mode != .completed {
                let candidates = store.tasks(for: blueprintID).filter { !$0.isCompleted && !$0.isCancelled }
                if !candidates.isEmpty {
                    DisclosureGroup("前置依赖") {
                        ForEach(candidates) { candidate in
                            Toggle(candidate.title, isOn: Binding(
                                get: { dependencyIDs.contains(candidate.id) },
                                set: { selected in
                                    if selected { dependencyIDs.insert(candidate.id) }
                                    else { dependencyIDs.remove(candidate.id) }
                                }
                            ))
                        }
                    }
                }
            }
            Picker("四象限", selection: $quadrant) {
                ForEach(Quadrant.allCases) { Text($0.title).tag($0) }
            }
            Picker("日报分类", selection: $reportCategory) {
                ForEach(ReportCategory.allCases) { Text($0.title).tag($0) }
            }
            Stepper("预计时长：\(estimatedMinutes) 分钟", value: $estimatedMinutes, in: 5...480, step: 5)
            if mode != .completed {
                Toggle("设置截止时间", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("截止时间", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
                if planChoice != .inbox {
                    Toggle("锁定计划日期", isOn: $isPlanLocked)
                }
            }
            TextField("备注（可选）", text: $notes, axis: .vertical)
                .lineLimit(2...4)
        }
        .font(.subheadline)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if !isAIInput {
                Toggle("连续添加", isOn: $keepOpen)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            Spacer()
            Button("取消") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(primaryTitle, systemImage: primaryIcon) {
                if isAIInput { Task { await parseAI() } }
                else { save() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(isAIInput ? cleanSentence.isEmpty || store.isAIParsing : cleanTitle.isEmpty)
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 17)
        .background(preferences.cardBackground.opacity(0.82))
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 1) }
    }

    private var primaryTitle: String {
        if isAIInput { return "生成草稿" }
        if mode == .completed { return "记录完成" }
        return "添加待办"
    }

    private var primaryIcon: String {
        if isAIInput { return "sparkles" }
        return mode == .completed ? "checkmark" : "plus"
    }

    private func focusInput() {
        DispatchQueue.main.async {
            if isAIInput { sentenceFocused = true }
            else { titleFocused = true }
        }
    }

    private func parseAI() async {
        guard !cleanSentence.isEmpty else { return }
        guard let parsed = await store.parseTask(
            sentence: cleanSentence,
            endpoint: preferences.deepSeekEndpoint,
            model: preferences.deepSeekModel,
            defaultQuadrant: preferences.defaultQuadrant,
            defaultDuration: preferences.defaultDuration
        ) else { return }
        withAnimation(motion) {
            title = parsed.task.title
            notes = parsed.task.notes
            quadrant = parsed.task.quadrant
            reportCategory = parsed.task.effectiveReportCategory
            estimatedMinutes = parsed.task.estimatedMinutes
            project = parsed.task.project ?? ""
            if let match = store.blueprints.first(where: { $0.name.localizedCaseInsensitiveCompare(project) == .orderedSame }) {
                blueprintID = match.id
            }
            customDate = parsed.task.scheduledFor
            planChoice = Calendar.current.isDateInToday(customDate) ? .today : Calendar.current.isDateInTomorrow(customDate) ? .tomorrow : .custom
            hasDeadline = parsed.task.dueDate != nil
            dueDate = parsed.task.dueDate ?? customDate
            subtasks = parsed.subtasks
            hasAIDraft = true
            showDetails = true
        }
        focusInput()
    }

    private func save() {
        guard !cleanTitle.isEmpty else { return }
        let normalizedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCompleted = mode == .completed
        let scheduledFor: Date
        switch planChoice {
        case .today: scheduledFor = .now
        case .tomorrow: scheduledFor = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        case .custom: scheduledFor = customDate
        case .inbox: scheduledFor = .now
        }
        let actualDate = isCompleted ? completedAt : scheduledFor
        let status: TaskStatus = isCompleted ? .completed : planChoice == .inbox ? .unscheduled : .pending
        let parentID = UUID()
        let parent = TaskItem(
            id: parentID,
            title: cleanTitle,
            notes: notes,
            project: normalizedProject.isEmpty ? nil : normalizedProject,
            reportCategory: reportCategory,
            quadrant: quadrant,
            scheduledFor: actualDate,
            dueDate: isCompleted || !hasDeadline ? nil : dueDate,
            estimatedMinutes: estimatedMinutes,
            isComplete: isCompleted,
            status: status,
            completedAt: isCompleted ? completedAt : nil,
            blueprintID: blueprintID,
            stageID: stageID,
            milestoneID: milestoneID,
            statusChangedAt: isCompleted ? completedAt : nil,
            dependencyIDs: isCompleted || dependencyIDs.isEmpty ? nil : Array(dependencyIDs),
            isPlanLocked: !isCompleted && planChoice != .inbox && isPlanLocked
        )
        if mode == .ai && hasAIDraft {
            for subtask in subtasks.reversed() where !subtask.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                store.add(TaskItem(
                    title: subtask.trimmingCharacters(in: .whitespacesAndNewlines),
                    project: parent.project,
                    reportCategory: parent.reportCategory,
                    quadrant: parent.quadrant,
                    scheduledFor: parent.scheduledFor,
                    dueDate: parent.dueDate,
                    estimatedMinutes: max(5, parent.estimatedMinutes / max(subtasks.count, 1)),
                    status: parent.status,
                    blueprintID: parent.blueprintID,
                    stageID: parent.stageID,
                    parentTaskID: parentID
                ))
            }
        }
        store.add(parent)
        if keepOpen {
            withAnimation(motion) {
                title = ""
                notes = ""
                sentence = ""
                subtasks = []
                hasAIDraft = false
                completedAt = .now
                feedback = "已添加，继续输入下一项"
            }
            focusInput()
        } else {
            dismiss()
        }
    }
}
