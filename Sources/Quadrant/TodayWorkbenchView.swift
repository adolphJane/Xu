import SwiftUI

struct TodayWorkbenchView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selectedBlueprint: BlueprintItem?

    let onSelect: (TaskItem) -> Void
    let onReport: () -> Void
    let onAddTask: () -> Void
    let onAddCompleted: () -> Void
    let onAddWithAI: () -> Void

    private var actionableTasks: [TaskItem] {
        TodayBlueprintOrganizer.sortedTasks(store.todayTasks.filter(\.needsAction))
    }
    private var focusTask: TaskItem? {
        actionableTasks.first(where: { $0.isInProgress })
            ?? actionableTasks.first(where: { store.executionBlockReason(for: $0) == nil })
            ?? actionableTasks.first
    }
    private var groups: [TodayBlueprintTaskGroup] {
        TodayBlueprintOrganizer.groups(tasks: store.tasks, blueprints: store.blueprints)
    }
    private var unassigned: [TaskItem] {
        TodayBlueprintOrganizer.unassignedTasks(tasks: store.tasks, blueprints: store.blueprints)
    }
    private var completionCount: Int { store.todayTasks.filter(\.isCompleted).count }
    private var trackableCount: Int { store.todayTasks.filter { !$0.isCancelled }.count }
    private var dayProgress: Double {
        guard trackableCount > 0 else { return 0 }
        return Double(completionCount) / Double(trackableCount)
    }
    private var motion: Animation? {
        preferences.reduceMotion || systemReduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.85)
    }

    var body: some View {
        GeometryReader { geometry in
            let showRail = geometry.size.width >= 875
            ScrollView {
                HStack(alignment: .top, spacing: 25) {
                    VStack(alignment: .leading, spacing: 0) {
                        pageIntroduction
                        if let focusTask {
                            focusCard(focusTask)
                                .padding(.top, 27)
                        } else {
                            emptyFocus
                                .padding(.top, 27)
                        }
                        sectionHeading
                            .padding(.top, 30)
                        VStack(spacing: 13) {
                            ForEach(groups) { group in
                                let otherTasks = group.tasks.filter { $0.id != focusTask?.id }
                                if !otherTasks.isEmpty {
                                    blueprintGroup(group, tasks: otherTasks)
                                }
                            }
                            let otherUnassigned = unassigned.filter { $0.id != focusTask?.id }
                            if !otherUnassigned.isEmpty {
                                unassignedGroup(otherUnassigned)
                            }
                            if store.todayTasks.isEmpty {
                                emptyActionTips
                            } else if groups.allSatisfy({ $0.tasks.allSatisfy { $0.id == focusTask?.id } }) && unassigned.allSatisfy({ $0.id == focusTask?.id }) {
                                Text("其余今日事项都已处理。保持这个节奏。")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, minHeight: 90)
                            }
                        }
                        .padding(.top, 17)
                        .animation(motion, value: store.todayTasks)
                        if !showRail {
                            contextPanel
                                .padding(.top, 24)
                        }
                    }
                    .frame(maxWidth: 760, alignment: .leading)
                    if showRail {
                        contextPanel
                            .frame(width: 244)
                            .padding(.top, 4)
                    }
                }
                .frame(maxWidth: 1100, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 30)
                .padding(.top, 30)
                .padding(.bottom, 42)
            }
        }
        .sheet(item: $selectedBlueprint) { BlueprintDetailView(blueprintID: $0.id) }
    }

    private var pageIntroduction: some View {
        HStack(alignment: .bottom, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Text(Date.now.formatted(.dateTime.month(.wide).day().weekday(.wide)) + "  /  今日执行")
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(preferences.accentColor)
                Text("今天，推进最重要的事")
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.7)
                Text("任务围绕蓝图组织，先做当前重点，再处理其余事项。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text("\(completionCount) / \(trackableCount)")
                    .font(.system(size: 23, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                Text("今日完成")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: dayProgress)
                    .tint(preferences.accentColor)
                    .frame(width: 100)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("今日完成 \(completionCount) 项，共 \(trackableCount) 项")
        }
    }

    private func focusCard(_ task: TaskItem) -> some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack {
                Label(task.isInProgress ? "正在执行" : "当前重点 · 01", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .tracking(0.6)
                Spacer()
                Text("预计 \(task.estimatedMinutes) 分钟")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
            Text(task.title)
                .font(.system(size: 23, weight: .semibold, design: .rounded))
                .lineLimit(2)
                .contentTransition(.opacity)
            HStack(spacing: 8) {
                if let blueprint = store.blueprints.first(where: { $0.id == task.blueprintID }) {
                    Text(blueprint.name)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                if let stage = store.stages.first(where: { $0.id == task.stageID }) {
                    Text(stage.name)
                    Image(systemName: "chevron.right").font(.caption2)
                }
                Text(task.projectName.isEmpty ? task.quadrant.title : task.projectName)
            }
            .font(.caption)
            .foregroundStyle(.white.opacity(0.76))
            .lineLimit(1)
            if let reason = store.executionBlockReason(for: task) {
                Label(reason, systemImage: "lock")
                    .font(.caption).foregroundStyle(.white.opacity(0.84)).lineLimit(2)
            }
            HStack(spacing: 12) {
                Label(task.dueDate.map { "截止 \($0.formatted(.dateTime.month().day().hour().minute()))" } ?? "今天安排", systemImage: "flag")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.77))
                Spacer()
                if task.isInProgress {
                    Button("查看事项", systemImage: "arrow.up.right") { onSelect(task) }
                        .buttonStyle(.borderedProminent)
                        .tint(.white.opacity(0.2))
                } else {
                    Button("开始执行", systemImage: "play.fill") {
                        withAnimation(motion) { store.start(task) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(preferences.accentColor)
                    .disabled(store.executionBlockReason(for: task) != nil)
                    .help(store.executionBlockReason(for: task) ?? "开始执行当前重点")
                }
            }
        }
        .foregroundStyle(.white)
        .padding(23)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(focusBackground.gradient, in: RoundedRectangle(cornerRadius: 19))
        .overlay(RoundedRectangle(cornerRadius: 19).stroke(.white.opacity(0.12)))
        .shadow(color: focusBackground.opacity(0.2), radius: 17, y: 8)
        .animation(motion, value: task.id)
    }

    private var focusBackground: Color {
        switch preferences.resolvedPreset {
        case .paper: Color(appHex: "604439")
        case .ocean, .ink: Color(appHex: "294B61")
        case .forest: Color(appHex: "285244")
        case .system, .stone: Color(appHex: "203F42")
        }
    }

    private var emptyFocus: some View {
        HStack(spacing: 17) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 28))
                .foregroundStyle(preferences.accentColor)
            VStack(alignment: .leading, spacing: 5) {
                Text(store.todayTasks.isEmpty ? "从一件重要的事开始" : "今天的待办已全部处理")
                    .font(.headline)
                Text(store.todayTasks.isEmpty ? "添加事项，或从蓝图中安排今天的行动。" : "可以记录完成事项，或生成日报回顾进展。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(store.todayTasks.isEmpty ? "添加事项" : "生成日报", action: store.todayTasks.isEmpty ? onAddTask : onReport)
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, minHeight: 133)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 19))
    }

    private var sectionHeading: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                Text("今日行动")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                Text("按蓝图汇总，完成一项就推进一格。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            AddTaskControl(onAddTask: onAddTask, onAddCompleted: onAddCompleted, onAddWithAI: onAddWithAI)
                .buttonStyle(.borderless)
                .tint(preferences.accentColor)
        }
    }

    private var emptyActionTips: some View {
        HStack(spacing: 12) {
            Button("新增待办", systemImage: "plus.circle", action: onAddTask)
            Button("记录已完成", systemImage: "checkmark.circle", action: onAddCompleted)
            Button("AI 一句话生成", systemImage: "sparkles", action: onAddWithAI)
        }
        .buttonStyle(.bordered)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 16))
    }

    private func blueprintGroup(_ group: TodayBlueprintTaskGroup, tasks: [TaskItem]) -> some View {
        let completed = group.tasks.filter(\.isCompleted).count
        let total = group.tasks.filter { !$0.isCancelled }.count
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(Color(appHex: group.blueprint.colorHex)).frame(width: 8, height: 8)
                Button(group.blueprint.name) { selectedBlueprint = group.blueprint }
                    .buttonStyle(.plain)
                    .font(.headline)
                Spacer()
                Text("\(completed) / \(total)")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
                Button { selectedBlueprint = group.blueprint } label: {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(.plain)
                .help("查看蓝图")
            }
            .padding(.horizontal, 18)
            .padding(.top, 17)
            .padding(.bottom, 12)
            ProgressView(value: total == 0 ? 0 : Double(completed) / Double(total))
                .tint(Color(appHex: group.blueprint.colorHex))
                .padding(.horizontal, 18)
                .padding(.bottom, 7)
            ForEach(tasks) { task in
                TodayActionRow(task: task, onSelect: onSelect)
            }
        }
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.primary.opacity(0.07)))
    }

    private func unassignedGroup(_ tasks: [TaskItem]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Circle().fill(.secondary.opacity(0.5)).frame(width: 8, height: 8)
                Text("未归入蓝图").font(.headline)
                Text("可稍后归类").font(.caption).foregroundStyle(.tertiary)
                Spacer()
                Text("\(tasks.count) 项").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            .padding(18)
            ForEach(tasks) { task in
                TodayActionRow(task: task, onSelect: onSelect, showAssignment: true)
            }
        }
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.primary.opacity(0.07)))
    }

    private var contextPanel: some View {
        VStack(alignment: .leading, spacing: 20) {
            blueprintContext
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Label("接下来", systemImage: "calendar.badge.clock")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(nextTaskText)
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let anniversary = store.upcomingAnniversaries.first(where: { $0.showOnHome }) {
                Divider()
                VStack(alignment: .leading, spacing: 9) {
                    Label("重要日子", systemImage: "heart")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack {
                        Text(anniversary.displayName).lineLimit(2)
                        Spacer()
                        if let days = anniversary.daysRemaining() {
                            Text(days == 0 ? "今天" : "还有 \(days) 天")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(preferences.accentColor)
                        }
                    }
                }
            }
            Divider()
            Button("生成今日日报", systemImage: "sparkles", action: onReport)
                .frame(maxWidth: .infinity)
                .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).stroke(.primary.opacity(0.07)))
    }

    @ViewBuilder
    private var blueprintContext: some View {
        if let blueprint = store.blueprints.first(where: { $0.id == focusTask?.blueprintID })
            ?? store.blueprints.first(where: { $0.status == .active && $0.archivedAt == nil }) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Text("蓝图进度").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button { selectedBlueprint = blueprint } label: { Image(systemName: "arrow.up.right") }
                        .buttonStyle(.plain)
                        .help("查看蓝图")
                }
                HStack(spacing: 10) {
                    Text(String(blueprint.name.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(preferences.accentColor)
                        .frame(width: 36, height: 36)
                        .background(preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 3) {
                        Text(blueprint.name).font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(blueprint.dueDate, format: .dateTime.month().day())
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Text("\(Int(store.blueprintProgress(blueprint.id) * 100))%")
                    .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                    .contentTransition(.numericText())
                ProgressView(value: store.blueprintProgress(blueprint.id))
                    .tint(preferences.accentColor)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(store.stages(for: blueprint.id).prefix(3)) { stage in
                        let stageTasks = store.tasks.filter { $0.stageID == stage.id }
                        let isFinished = !stageTasks.isEmpty && stageTasks.allSatisfy(\.isCompleted)
                        HStack(spacing: 9) {
                            Image(systemName: isFinished ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 10))
                                .foregroundStyle(isFinished ? preferences.accentColor : .secondary)
                            Text(stage.name).font(.caption).lineLimit(1)
                            Spacer()
                        }
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                Label("蓝图进度", systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption.weight(.semibold))
                Text("创建蓝图，把每天的行动连接到长期目标。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var nextTaskText: String {
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        if let task = TodayBlueprintOrganizer.sortedTasks(store.tasks.filter {
            $0.needsAction && Calendar.current.isDate($0.scheduledFor, inSameDayAs: tomorrow)
        }).first {
            return "明天 · \(task.title)"
        }
        return "明天还没有安排事项，留点余量给重要任务。"
    }
}

private struct TodayActionRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var isHovered = false

    let task: TaskItem
    let onSelect: (TaskItem) -> Void
    var showAssignment = false

    private var motion: Animation? {
        preferences.reduceMotion || systemReduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82)
    }

    var body: some View {
        HStack(spacing: 12) {
            Button {
                withAnimation(motion) {
                    if task.isCompleted || task.isCancelled { store.restore(task) }
                    else { store.markCompleted(task) }
                }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : task.isCancelled ? "xmark.circle.fill" : task.isInProgress ? "play.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .light))
                    .foregroundStyle(task.isCompleted ? preferences.accentColor : task.isCancelled ? .orange : task.isInProgress ? preferences.accentColor : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
            .disabled(task.needsAction && store.executionBlockReason(for: task) != nil)
            .help(task.isCompleted || task.isCancelled ? "恢复为待完成" : (store.executionBlockReason(for: task) ?? "标记完成"))
            Button { onSelect(task) } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .strikethrough(task.isCompleted || task.isCancelled)
                        .foregroundStyle(task.isCompleted || task.isCancelled ? .secondary : .primary)
                        .lineLimit(1)
                    Text(task.isCompleted ? "已完成" : task.isCancelled ? "已取消" : task.effectiveStatus == .blocked ? "已阻塞 · \(task.blockReason ?? "待处理")" : "\(task.quadrant.title) · 预计 \(task.estimatedMinutes) 分钟")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    if task.needsAction, let reason = store.executionBlockReason(for: task) {
                        Text(reason).font(.caption2).foregroundStyle(.orange).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if showAssignment {
                Menu {
                    ForEach(store.blueprints.filter { $0.archivedAt == nil && $0.status == .active }) { blueprint in
                        Button(blueprint.name) { withAnimation(motion) { store.assign(task, to: blueprint) } }
                    }
                } label: { Image(systemName: "arrowshape.turn.up.right").comfortableIconTarget() }
                    .help("归入蓝图")
            }
            Menu {
                if task.needsAction && !task.isInProgress {
                    Button("开始执行", systemImage: "play") { withAnimation(motion) { store.start(task) } }
                        .disabled(store.executionBlockReason(for: task) != nil)
                }
                if !task.isCompleted {
                    Button("标记完成", systemImage: "checkmark.circle") { withAnimation(motion) { store.markCompleted(task) } }
                        .disabled(store.executionBlockReason(for: task) != nil)
                }
                if task.needsAction {
                    Button("延期到明天", systemImage: "calendar.badge.clock") { withAnimation(motion) { store.postpone(task) } }
                    Button("取消任务", systemImage: "xmark.circle") { withAnimation(motion) { store.cancel(task) } }
                } else {
                    Button("恢复为待完成", systemImage: "arrow.uturn.backward") { withAnimation(motion) { store.restore(task) } }
                }
                Divider()
                Button("编辑事项", systemImage: "pencil") { onSelect(task) }
            } label: { Image(systemName: "ellipsis").comfortableIconTarget() }
                .help("更多操作")
        }
        .padding(.horizontal, 18)
        .frame(minHeight: 66)
        .background(isHovered ? preferences.accentColor.opacity(0.045) : .clear)
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.055)).frame(height: 1).padding(.horizontal, 18) }
        .onHover { hovering in withAnimation(motion) { isHovered = hovering } }
        .animation(motion, value: task.effectiveStatus)
    }
}
