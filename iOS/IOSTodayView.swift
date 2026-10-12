import SwiftUI

struct IOSTodayView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingComposer = false
    @State private var selectedTask: TaskItem?

    private var todayTasks: [TaskItem] { TodayBlueprintOrganizer.sortedTasks(store.todayTasks) }
    private var actionable: [TaskItem] { todayTasks.filter(\.needsAction) }
    private var remainingTasks: [TaskItem] { todayTasks.filter { $0.id != focusTask?.id } }
    private var completedCount: Int { todayTasks.filter(\.isCompleted).count }
    private var totalCount: Int { todayTasks.filter { !$0.isCancelled }.count }
    private var focusTask: TaskItem? {
        actionable.first(where: { $0.isInProgress })
            ?? actionable.first(where: { store.executionBlockReason(for: $0) == nil })
            ?? actionable.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    introduction
                    if let focusTask { focusCard(focusTask) }
                    AppSectionHeader(title: "今日行动", subtitle: "按优先级处理今天的事项")
                    if todayTasks.isEmpty {
                        AppEmptyState(title: "从一件重要的事开始", message: "添加任务，开始推进今天的计划。",
                                      systemImage: "checkmark.circle", actionTitle: "添加事项") {
                            showingComposer = true
                        }
                    } else if remainingTasks.isEmpty {
                        Text("当前重点之外暂无其他事项。")
                            .font(AppTypography.callout)
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        LazyVStack(spacing: AppSpacing.list) {
                            ForEach(remainingTasks) { task in
                                taskRow(task)
                            }
                        }
                    }
                }
                .frame(maxWidth: AppTheme.contentMaxWidth)
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.section)
                .frame(maxWidth: .infinity)
            }
            .background(AppColors.canvas)
            .navigationTitle("今日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("添加事项", systemImage: "plus") { showingComposer = true }
                        .accessibilityLabel("添加事项")
                }
            }
            .sheet(isPresented: $showingComposer) { IOSTaskComposerView() }
            .sheet(item: $selectedTask) { task in IOSTaskDetailView(taskID: task.id) }
            .alert("操作提示", isPresented: Binding(
                get: { store.actionMessage != nil },
                set: { if !$0 { store.actionMessage = nil } }
            )) { Button("知道了") { store.actionMessage = nil } }
                message: { Text(store.actionMessage ?? "") }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x3) {
            Text(Date.now, format: .dateTime.month(.wide).day().weekday(.wide))
                .font(AppTypography.callout.weight(.medium))
                .foregroundStyle(AppColors.brand)
            Text("今天，推进最重要的事")
                .font(AppTypography.largeTitle)
                .foregroundStyle(AppColors.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: AppSpacing.x3) {
                ProgressView(value: totalCount == 0 ? 0 : Double(completedCount) / Double(totalCount))
                    .tint(AppColors.brand)
                Text("\(completedCount) / \(totalCount)")
                    .font(AppTypography.caption.monospacedDigit())
                    .foregroundStyle(AppColors.textSecondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("今日完成 \(completedCount) 项，共 \(totalCount) 项")
        }
    }

    private func focusCard(_ task: TaskItem) -> some View {
        AppCard {
            VStack(alignment: .leading, spacing: AppSpacing.x3) {
                AppBadge(title: task.isInProgress ? "正在执行" : "当前重点")
                Text(task.title)
                    .font(AppTypography.title)
                    .fixedSize(horizontal: false, vertical: true)
                Text(task.projectName.isEmpty ? task.quadrant.title : task.projectName)
                    .font(AppTypography.callout)
                    .foregroundStyle(AppColors.textSecondary)
                HStack {
                    Label("预计 \(task.estimatedMinutes) 分钟", systemImage: "clock")
                        .font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    AppButton(title: task.isInProgress ? "查看" : "开始执行") {
                        if task.isInProgress { selectedTask = task }
                        else { withAnimation(AppTheme.animation(reduceMotion: reduceMotion)) { store.start(task) } }
                    }
                    .disabled(!task.isInProgress && store.executionBlockReason(for: task) != nil)
                }
            }
        }
    }

    private func taskRow(_ task: TaskItem) -> some View {
        AppCard {
            HStack(spacing: AppSpacing.x3) {
                Button {
                    withAnimation(AppTheme.animation(reduceMotion: reduceMotion)) { store.toggle(task) }
                } label: {
                    Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .frame(minWidth: AppTheme.minimumTouchTarget, minHeight: AppTheme.minimumTouchTarget)
                }
                .buttonStyle(.plain)
                .foregroundStyle(task.isCompleted ? AppColors.success : AppColors.brand)
                .disabled(!task.isCompleted && store.executionBlockReason(for: task) != nil)
                .accessibilityLabel(task.isCompleted ? "恢复\(task.title)" : "完成\(task.title)")

                Button { selectedTask = task } label: {
                    VStack(alignment: .leading, spacing: AppSpacing.x1) {
                        Text(task.title)
                            .font(AppTypography.body.weight(.medium))
                            .foregroundStyle(AppColors.textPrimary)
                            .strikethrough(task.isCompleted)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(task.effectiveStatus.title)
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    .frame(minHeight: AppTheme.minimumTouchTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("查看\(task.title)，\(task.effectiveStatus.title)")
            }
        }
    }
}

struct IOSTaskComposerView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    var category: String? = nil
    @State private var title = ""
    @State private var notes = ""
    @State private var quadrant: Quadrant = .schedule

    var body: some View {
        NavigationStack {
            Form {
                Section("事项") {
                    TextField("事项名称", text: $title)
                        .font(AppTypography.body)
                        .accessibilityLabel("事项名称")
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                        .font(AppTypography.body)
                        .lineLimit(3...6)
                        .accessibilityLabel("备注")
                }
                Section("安排") {
                    Picker("四象限", selection: $quadrant) {
                        ForEach(Quadrant.allCases) { item in Text(item.title).tag(item) }
                    }
                }
            }
            .navigationTitle("添加事项")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.add(TaskItem(title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes,
                                           category: category, quadrant: quadrant))
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

struct IOSTaskDetailView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID

    private var task: TaskItem? { store.tasks.first { $0.id == taskID } }

    private func statusTone(for task: TaskItem) -> AppBadge.Tone {
        switch task.effectiveStatus {
        case .inProgress: .brand
        case .completed: .success
        case .postponed, .blocked: .warning
        case .unscheduled, .pending, .cancelled: .neutral
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let task {
                    Form {
                        Section("事项") {
                            Text(task.title).font(AppTypography.headline)
                            if !task.notes.isEmpty { Text(task.notes).font(AppTypography.body) }
                        }
                        Section("状态") {
                            LabeledContent("状态") {
                                AppBadge(title: task.effectiveStatus.title, tone: statusTone(for: task))
                            }
                            LabeledContent("四象限", value: task.quadrant.title)
                            LabeledContent("预计时长", value: "\(task.estimatedMinutes) 分钟")
                        }
                        Section {
                            if task.needsAction {
                                Button("开始执行") { store.start(task) }
                                    .disabled(store.executionBlockReason(for: task) != nil)
                                Button("标记完成") { store.markCompleted(task) }
                                    .disabled(store.executionBlockReason(for: task) != nil)
                                Button("延期到明天") { store.postpone(task) }
                            } else {
                                Button("恢复为待完成") { store.restore(task) }
                            }
                        }
                    }
                } else {
                    AppEmptyState(title: "事项不存在", message: "此事项可能已经被删除。",
                                  systemImage: "exclamationmark.triangle")
                }
            }
            .navigationTitle("事项详情")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
    }
}

#Preview("Today · Light") {
    let store = TaskStore(inMemory: true)
    store.add(TaskItem(title: "完成设计系统试点", quadrant: .doNow))
    return IOSTodayView().environmentObject(store).preferredColorScheme(.light)
}

#Preview("Today · Dark · Large Text") {
    let store = TaskStore(inMemory: true)
    store.add(TaskItem(title: "核对放大文字和 VoiceOver 的实际效果", quadrant: .schedule))
    return IOSTodayView().environmentObject(store).preferredColorScheme(.dark).dynamicTypeSize(.accessibility1)
}

#Preview("Composer · Dark") {
    IOSTaskComposerView()
        .environmentObject(TaskStore(inMemory: true))
        .preferredColorScheme(.dark)
}

#Preview("Detail · Large Text") {
    let store = TaskStore(inMemory: true)
    let task = TaskItem(title: "核对新增事项和详情页的语义样式", quadrant: .schedule)
    store.add(task)
    return IOSTaskDetailView(taskID: task.id)
        .environmentObject(store)
        .dynamicTypeSize(.accessibility1)
}
