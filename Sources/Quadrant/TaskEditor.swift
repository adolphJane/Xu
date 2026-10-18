import AppKit
import SwiftUI

struct TaskEditor: View {
    @AppDismiss private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.appDialogPresentation) private var presentation
    @State private var showAdvancedSettings = false
    private var original: TaskItem?
    @State private var title = ""
    @FocusState private var titleFieldFocused: Bool
    @State private var notes = ""
    @State private var project = ""
    @State private var category = ""
    @State private var reportCategory: ReportCategory = .projectProgress
    @State private var quadrant: Quadrant = .schedule
    @State private var scheduledFor = Date.now
    @State private var isScheduled = true
    @State private var hasDeadline = false
    @State private var dueDate = Date.now
    @State private var estimatedMinutes = 30
    @State private var blueprintID: UUID?
    @State private var stageID: UUID?
    @State private var milestoneID: UUID?
    @State private var dependencyIDs: Set<UUID>
    @State private var isPlanLocked: Bool
    @State private var parentTaskID: UUID?
    @State private var newChildTitle = ""
    @State private var editingChild: TaskItem?
    @State private var formError: String?
    @State private var showDiscardConfirmation = false
    @State private var appliedDefaults = false
    @State private var openBlueprintOnDismiss = false

    init(task: TaskItem? = nil, blueprintID: UUID? = nil) {
        original = task
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _project = State(initialValue: task?.project ?? "")
        _category = State(initialValue: task?.category ?? "")
        _reportCategory = State(initialValue: task?.effectiveReportCategory ?? .projectProgress)
        _quadrant = State(initialValue: task?.quadrant ?? .schedule)
        _scheduledFor = State(initialValue: task?.scheduledFor ?? .now)
        _isScheduled = State(initialValue: task?.effectiveStatus != .unscheduled)
        _hasDeadline = State(initialValue: task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? .now)
        _estimatedMinutes = State(initialValue: task?.estimatedMinutes ?? 30)
        _blueprintID = State(initialValue: task?.blueprintID ?? blueprintID)
        _stageID = State(initialValue: task?.stageID)
        _milestoneID = State(initialValue: task?.milestoneID)
        _dependencyIDs = State(initialValue: Set(task?.effectiveDependencyIDs ?? []))
        _isPlanLocked = State(initialValue: task?.planLocked ?? false)
        _parentTaskID = State(initialValue: task?.parentTaskID)
    }

    private var reduceMotion: Bool { systemReduceMotion || preferences.reduceMotion }
    private var children: [TaskItem] {
        original.map { TaskTreeProjection.directChildren(of: $0.id, in: store.tasks) } ?? []
    }
    private var editorHeight: CGFloat {
        min(720, (NSScreen.main?.visibleFrame.height ?? 900) - AppSpacing.x8 * 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            Form {
                Section {
                    TaskCategoryField(category: $category, allowsCustomInput: original == nil)
                    Picker("四象限", selection: $quadrant) {
                        ForEach(Quadrant.allCases) { Text($0.title).tag($0) }
                    }
                    TextField("所属项目", text: $project, prompt: Text("可选，用于日报归类"))
                    Picker("日报分类", selection: $reportCategory) {
                        ForEach(ReportCategory.allCases) { Text($0.title).tag($0) }
                    }
                } header: {
                    sectionTitle("基本信息", symbol: "slider.horizontal.3")
                }

                Section {
                    if original == nil || original?.isPending == true || original?.isUnscheduled == true {
                        Toggle("安排到日期", isOn: $isScheduled)
                    }
                    if isScheduled {
                        DatePicker("安排日期", selection: $scheduledFor, displayedComponents: .date)
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Toggle("设置截止日期", isOn: $hasDeadline)
                    if hasDeadline {
                        DatePicker("截止日期", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    Stepper(value: $estimatedMinutes, in: 5...480, step: 5) {
                        HStack {
                            Text("预计时长")
                            Spacer()
                            Text("\(estimatedMinutes) 分钟")
                                .monospacedDigit()
                                .foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    if isScheduled {
                        Toggle("锁定计划日期", isOn: $isPlanLocked)
                            .help("AI 重新规划时保留此日期")
                    }
                } header: {
                    sectionTitle("时间安排", symbol: "calendar")
                }

                Section {
                    TextField("添加备注…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel("备注，可选")
                } header: {
                    sectionTitle("备注", symbol: "text.alignleft")
                }

                if let original {
                    Section {
                        if children.isEmpty {
                            Label("还没有子任务，从下一步开始拆解", systemImage: "list.bullet.indent")
                                .foregroundStyle(AppColors.textSecondary)
                                .font(AppTypography.callout)
                        }
                        ForEach(children) { child in
                            Button {
                                editingChild = child
                            } label: {
                                HStack(spacing: AppSpacing.x3) {
                                    Image(systemName: child.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(child.isCompleted ? AppColors.success : AppColors.textSecondary)
                                    Text(child.title).foregroundStyle(AppColors.textPrimary)
                                    Spacer()
                                    Text(child.displayStatusTitle)
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                    Image(systemName: "chevron.right")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .padding(.vertical, AppSpacing.x1)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("编辑子任务\(child.title)")
                        }
                        HStack(spacing: AppSpacing.x2) {
                            TextField("添加下一步，按回车保存", text: $newChildTitle)
                                .onSubmit(addChild)
                                .accessibilityLabel("给当前任务添加子任务")
                            Button("添加", systemImage: "plus", action: addChild)
                                .disabled(newChildTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                        Text("子任务会立即保存到“\(original.title)”下。")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    } header: {
                        HStack {
                            sectionTitle("子任务", symbol: "checklist")
                            Spacer()
                            Text("\(children.count)").font(AppTypography.caption.monospacedDigit())
                        }
                    }
                }

                Section {
                    DisclosureGroup("任务归属与更多设置", isExpanded: $showAdvancedSettings) {
                        advancedSettings
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .animation(AppTheme.animation(reduceMotion: reduceMotion), value: isScheduled)
            .animation(AppTheme.animation(reduceMotion: reduceMotion), value: hasDeadline)
            .animation(AppTheme.animation(reduceMotion: reduceMotion), value: showAdvancedSettings)
            Divider()
            footer
        }
        .frame(width: 620, height: editorHeight)
        .background(preferences.pageBackground, in: RoundedRectangle(cornerRadius: AppRadius.prominent))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.prominent))
        .font(AppTypography.desktop(.body, scale: preferences.fontScale, design: preferences.fontStyle.design))
        .tint(preferences.accentColor)
        .onAppear {
            guard original == nil, !appliedDefaults else { return }
            quadrant = preferences.defaultQuadrant
            estimatedMinutes = preferences.defaultDuration
            if let blueprintID, project.isEmpty {
                project = store.blueprints.first { $0.id == blueprintID }?.name ?? ""
            }
            appliedDefaults = true
        }
        .task {
            if original != nil { titleFieldFocused = true }
        }
        .onChange(of: titleFieldFocused) { _, focused in
            guard focused, original != nil else { return }
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
        .onChange(of: blueprintID) { _, newValue in
            stageID = nil
            milestoneID = nil
            dependencyIDs = []
            if let newValue, project.isEmpty {
                project = store.blueprints.first { $0.id == newValue }?.name ?? ""
            }
        }
        .onChange(of: stageID) { _, _ in milestoneID = nil }
        .onDisappear {
            if openBlueprintOnDismiss, let original { TaskBlueprintNavigation.open(original) }
        }
        .appDialog(item: $editingChild) { child in TaskEditor(task: child) }
        .interactiveDismissDisabled(true)
        .onAppDialogCancel {
            if !showDiscardConfirmation { cancel() }
        }
        .confirmationDialog("放弃未保存的修改？", isPresented: $showDiscardConfirmation) {
            Button("放弃修改", role: .destructive) { closeEditor() }
            Button("继续编辑", role: .cancel) { }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x5) {
            HStack(spacing: AppSpacing.x3) {
                Image(systemName: original == nil ? "plus.circle" : "square.and.pencil")
                    .font(AppTypography.headline)
                    .foregroundStyle(preferences.accentColor)
                Text(original == nil ? "新建事项" : "编辑事项")
                    .font(AppTypography.headline)
                Spacer()
                if original != nil {
                    Button("查看蓝图", systemImage: "point.3.connected.trianglepath.dotted") {
                        openBlueprintOnDismiss = true
                        closeEditor()
                    }
                    .controlSize(.small)
                }
                Button(action: cancel) {
                    Image(systemName: "xmark")
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: AppSpacing.x8, height: AppSpacing.x8)
                        .background(AppColors.border.opacity(0.12), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭编辑事项")
            }
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                Text("事项名称")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                TextField("想要完成什么？", text: $title)
                    .textFieldStyle(.plain)
                    .font(AppTypography.desktop(.title2, scale: preferences.fontScale, weight: .semibold,
                                                design: preferences.fontStyle.design))
                    .focused($titleFieldFocused)
                    .accessibilityLabel("事项名称")
            }
        }
        .padding(AppSpacing.x6)
        .background(preferences.cardBackground)
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            if let formError {
                Label(formError, systemImage: "exclamationmark.triangle")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
            }
            HStack(spacing: AppSpacing.x3) {
                Text("⌘ ↩ 保存")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
                Button("取消", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(original == nil ? "创建事项" : "保存修改", action: save)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .controlSize(.large)
        }
        .padding(.horizontal, AppSpacing.x6)
        .padding(.vertical, AppSpacing.x4)
        .background(preferences.cardBackground)
    }

    private func sectionTitle(_ title: String, symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .font(AppTypography.caption.weight(.semibold))
            .foregroundStyle(AppColors.textSecondary)
    }

    @ViewBuilder
    private var advancedSettings: some View {
        if let original {
            Picker("父任务", selection: $parentTaskID) {
                Text("无（顶层任务）").tag(nil as UUID?)
                ForEach(store.tasks.filter { candidate in
                    candidate.id != original.id && candidate.blueprintID == blueprintID &&
                    TaskTreeProjection.canAssignParent(candidate.id, to: original.id, in: store.tasks)
                }) { candidate in
                    Text(TaskTreeProjection.path(to: candidate.id, in: store.tasks).map(\.title).joined(separator: " › "))
                        .tag(candidate.id as UUID?)
                }
            }
        } else {
            Picker("关联蓝图", selection: $blueprintID) {
                Text("不关联蓝图").tag(nil as UUID?)
                ForEach(store.blueprints) { Text($0.name).tag($0.id as UUID?) }
            }
        }
        if let blueprintID, !store.stages(for: blueprintID).isEmpty {
            Picker("所属阶段", selection: $stageID) {
                Text("不指定阶段").tag(nil as UUID?)
                ForEach(store.stages(for: blueprintID)) { Text($0.name).tag($0.id as UUID?) }
            }
        }
        if let stageID, !store.milestones(for: stageID).isEmpty {
            Picker("关联里程碑", selection: $milestoneID) {
                Text("不关联里程碑").tag(nil as UUID?)
                ForEach(store.milestones(for: stageID)) { Text($0.name).tag($0.id as UUID?) }
            }
        }
        if let blueprintID {
            let candidates = store.tasks(for: blueprintID).filter { $0.id != original?.id }
            if !candidates.isEmpty {
                DisclosureGroup("前置依赖（完成后才能开始）") {
                    ForEach(candidates) { candidate in
                        Toggle(candidate.title, isOn: Binding(
                            get: { dependencyIDs.contains(candidate.id) },
                            set: { selected in
                                if selected { dependencyIDs.insert(candidate.id) }
                                else { dependencyIDs.remove(candidate.id) }
                            }
                        ))
                        .disabled(original.map {
                            DependencyRule.wouldCreateCycle(taskID: $0.id, adding: candidate.id, tasks: store.tasks)
                        } ?? false)
                    }
                }
            }
        }
    }

    private func closeEditor() {
        titleFieldFocused = false
        dismiss()
    }

    private var hasUnsavedChanges: Bool {
        guard let original else {
            return !title.isEmpty || !notes.isEmpty || !project.isEmpty || !category.isEmpty
        }
        return title != original.title || notes != original.notes || project != (original.project ?? "") ||
            category != (original.category ?? "") || reportCategory != original.effectiveReportCategory ||
            quadrant != original.quadrant ||
            scheduledFor != original.scheduledFor || hasDeadline != (original.dueDate != nil) ||
            (hasDeadline && dueDate != original.dueDate) || estimatedMinutes != original.estimatedMinutes ||
            blueprintID != original.blueprintID || stageID != original.stageID ||
            milestoneID != original.milestoneID || dependencyIDs != Set(original.effectiveDependencyIDs) ||
            parentTaskID != original.parentTaskID || isPlanLocked != original.planLocked ||
            isScheduled != !original.isUnscheduled
    }

    private func cancel() {
        guard presentation?.isClosing != true else { return }
        if hasUnsavedChanges { showDiscardConfirmation = true }
        else { closeEditor() }
    }

    private func save() {
        guard presentation?.isClosing != true else { return }
        let task = TaskItem(
            id: original?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes,
            project: project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : project.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : category.trimmingCharacters(in: .whitespacesAndNewlines),
            reportCategory: reportCategory,
            quadrant: quadrant, scheduledFor: scheduledFor, dueDate: hasDeadline ? dueDate : nil,
            estimatedMinutes: estimatedMinutes, isComplete: original?.isComplete ?? false,
            status: isScheduled ? (original?.isUnscheduled == true ? .pending : original?.status) : .unscheduled,
            completedAt: original?.completedAt, autoCompletedAt: original?.autoCompletedAt,
            createdAt: original?.createdAt ?? .now,
            blueprintID: blueprintID, stageID: stageID, milestoneID: milestoneID,
            startedAt: original?.startedAt, originalScheduledFor: original?.originalScheduledFor,
            blockReason: original?.blockReason, statusChangedAt: original?.statusChangedAt,
            parentTaskID: parentTaskID,
            dependencyIDs: dependencyIDs.isEmpty ? nil : Array(dependencyIDs),
            originalDueDate: original?.originalDueDate,
            isPlanLocked: isScheduled && isPlanLocked
        )
        if original == nil { store.add(task) }
        else {
            guard store.update(task) else {
                formError = store.actionMessage ?? "保存失败，请重试。"
                store.actionMessage = nil
                return
            }
        }
        closeEditor()
    }

    private func addChild() {
        guard let original else { return }
        guard store.addChild(title: newChildTitle, to: original.id) else {
            formError = store.actionMessage ?? "无法添加子任务。"
            store.actionMessage = nil
            return
        }
        newChildTitle = ""
        formError = nil
    }
}


/// Preview-only entry point; sample changes use an isolated in-memory task store.
struct TaskEditorExample: View {
    @StateObject private var store = TaskStore(inMemory: true)
    @State private var isPresented = false
    private let task = TaskItem(title: "整理下周的工作安排", notes: "梳理重点，预留专注时间。", quadrant: .schedule)

    var body: some View {
        Button("打开编辑事项") { isPresented = true }
            .onAppear {
                if store.tasks.isEmpty { store.tasks = [task] }
            }
            .appDialog(isPresented: $isPresented) {
                TaskEditor(task: task)
                    .environmentObject(store)
                    .environmentObject(AppPreferences())
            }
    }
}

#Preview("编辑事项 · 弹窗与动画") {
    TaskEditorExample().frame(width: 900, height: 800)
}

#Preview("编辑事项 · 深色") {
    TaskEditor(task: TaskItem(title: "为长期学习与个人成长计划安排下一步行动", quadrant: .schedule))
        .environmentObject(TaskStore(inMemory: true))
        .environmentObject(AppPreferences())
        .preferredColorScheme(.dark)
}

#Preview("编辑事项 · 新建与大字号") {
    TaskEditor()
        .environmentObject(TaskStore(inMemory: true))
        .environmentObject(AppPreferences())
        .dynamicTypeSize(.accessibility1)
}
