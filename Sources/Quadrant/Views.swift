import Combine
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case inbox = "收集箱"
    case today = "今日"
    case blueprints = "蓝图"
    case quadrants = "四象限"
    case categories = "分类"
    case calendar = "日历计划"
    case anniversaries = "纪念日"
    case completed = "已处理"
    case report = "日报"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .inbox: "tray"
        case .today: "sun.max"
        case .blueprints: "point.3.connected.trianglepath.dotted"
        case .quadrants: "square.grid.2x2"
        case .categories: "tag"
        case .calendar: "calendar"
        case .anniversaries: "heart.circle"
        case .completed: "checkmark.circle"
        case .report: "doc.text"
        }
    }
}

struct ContentView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selection: AppSection? = .today
    @State private var composerMode: TaskComposerMode?
    @State private var selectedTask: TaskItem?
    @State private var isReportPresented = false
    @State private var isCommandPalettePresented = false
    @State private var isAIBlueprintPresented = false
    @State private var isSyncConflictPresented = false
    private let syncTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selection,
                onCommand: { isCommandPalettePresented = true }
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 250)
        } detail: {
            VStack(spacing: 0) {
                WorkbenchTopBar(
                    section: selection ?? .today,
                    onCommand: { isCommandPalettePresented = true },
                    onAddTask: { composerMode = .task },
                    onAddCompleted: { composerMode = .completed },
                    onAddWithAI: { composerMode = .ai }
                )
                Group {
                    switch selection ?? .today {
                    case .inbox: InboxView(onSelect: { selectedTask = $0 })
                    case .today: TodayWorkbenchView(
                        onSelect: { selectedTask = $0 },
                        onReport: { isReportPresented = true },
                        onAddTask: { composerMode = .task },
                        onAddCompleted: { composerMode = .completed },
                        onAddWithAI: { composerMode = .ai }
                    )
                    case .blueprints: BlueprintsView()
                    case .quadrants: QuadrantBoard(onSelect: { selectedTask = $0 })
                    case .categories: TaskCategoriesView(onSelect: { selectedTask = $0 })
                    case .calendar: PlanView(onSelect: { selectedTask = $0 })
                    case .anniversaries: AnniversariesView()
                    case .completed: CompletedView(onSelect: { selectedTask = $0 })
                    case .report: ReportLanding(onGenerate: { isReportPresented = true })
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selection ?? .today)
                .transition(preferences.reduceMotion || systemReduceMotion ? .identity : .opacity.combined(with: .offset(x: 10)))
            }
            .appSurface()
            .ignoresSafeArea(.container, edges: .top)
        }
        .sheet(item: $composerMode) { TaskComposerView(mode: $0) }
        .sheet(item: $selectedTask) { task in TaskEditor(task: task) }
        .sheet(isPresented: $isReportPresented) { DailyReportView() }
        .sheet(isPresented: $isCommandPalettePresented) { CommandPaletteView(perform: performCommand) }
        .sheet(isPresented: $isAIBlueprintPresented) { AIBlueprintCreatorView() }
        .sheet(isPresented: $isSyncConflictPresented) {
            if let conflict = store.syncConflict { SyncConflictView(conflict: conflict) }
        }
        .alert("操作提示", isPresented: Binding(
            get: { store.actionMessage != nil },
            set: { if !$0 { store.actionMessage = nil } }
        )) {
            Button("知道了") { store.actionMessage = nil }
        } message: {
            Text(store.actionMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in isCommandPalettePresented = true }
        .onReceive(syncTimer) { _ in
            guard preferences.syncEnabled, !preferences.syncFolderPath.isEmpty, store.syncConflict == nil else { return }
            do {
                try store.performFolderSync(folderPath: preferences.syncFolderPath)
                isSyncConflictPresented = store.syncConflict != nil
            } catch { store.syncMessage = error.localizedDescription }
        }
        .task {
            if preferences.autoCheckUpdates { await preferences.checkForUpdates() }
            if preferences.syncEnabled, !preferences.syncFolderPath.isEmpty {
                do {
                    try store.performFolderSync(folderPath: preferences.syncFolderPath)
                    isSyncConflictPresented = store.syncConflict != nil
                } catch { store.syncMessage = error.localizedDescription }
            }
        }
    }

    private func performCommand(_ command: CommandPaletteAction) {
        switch command {
        case .addTask: composerMode = .task
        case .addCompleted: composerMode = .completed
        case .aiTask: composerMode = .ai
        case .aiBlueprint: isAIBlueprintPresented = true
        case .dailyReport: isReportPresented = true
        case .openToday: selection = .today
        case .openBlueprints: selection = .blueprints
        case .openAnniversaries: selection = .anniversaries
        case .openWidget: openWindow(id: "widget")
        case .toggleFocusTheme: preferences.focusThemeActive.toggle()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Binding var selection: AppSection?
    let onCommand: () -> Void

    private let primarySections: [AppSection] = [.today, .blueprints, .quadrants, .categories, .calendar]
    private let recordSections: [AppSection] = [.inbox, .anniversaries, .completed, .report]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 11) {
                Text("序")
                    .font(.system(size: 18, weight: .semibold, design: .serif))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(preferences.accentColor.gradient, in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 1) {
                    Text("序").font(.system(size: 16, weight: .semibold))
                    Text("把计划变成行动").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 22)
            .padding(.bottom, 26)

            ScrollView {
                VStack(alignment: .leading, spacing: 7) {
                    sidebarCaption("工作区")
                    ForEach(primarySections) { section in sidebarItem(section) }
                    sidebarCaption("记录")
                        .padding(.top, 20)
                    ForEach(recordSections) { section in sidebarItem(section) }
                }
                .padding(.horizontal, 11)
            }

            VStack(spacing: 12) {
                Button(action: onCommand) {
                    HStack(spacing: 8) {
                        Image(systemName: "command").font(.caption)
                        Text("快速操作").font(.caption)
                        Spacer()
                        Text("⌘⇧␣").font(.caption2.monospaced()).foregroundStyle(.tertiary)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .frame(height: 42)
                    .background(preferences.cardBackground.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(.plain)
                SettingsLink {
                    Label("应用设置", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(minHeight: 40)
                }
                .buttonStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
            }
            .padding(14)
        }
        .background(preferences.pageBackground.opacity(0.9))
    }

    private func sidebarCaption(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
            .padding(.bottom, 4)
    }

    private func sidebarItem(_ section: AppSection) -> some View {
        Button {
            withAnimation(preferences.reduceMotion || systemReduceMotion ? nil : .easeInOut(duration: 0.22)) {
                selection = section
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: section.icon)
                    .font(.system(size: 16, weight: .medium))
                    .frame(width: 22)
                Text(section.rawValue).font(.system(size: 14, weight: selection == section ? .semibold : .medium))
                Spacer()
                if section == .today && !store.todayTasks.isEmpty {
                    Text("\(store.todayTasks.filter(\.needsAction).count)")
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(selection == section ? preferences.accentColor : .secondary)
                }
            }
            .foregroundStyle(selection == section ? preferences.accentColor : .secondary)
            .padding(.horizontal, 12)
            .frame(height: 46)
            .background(selection == section ? preferences.accentColor.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
        .accessibilityAddTraits(selection == section ? [.isSelected] : [])
    }
}

struct AddTaskControl: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let onAddTask: () -> Void
    let onAddCompleted: () -> Void
    let onAddWithAI: () -> Void
    var compact = false
    var shortcut: KeyboardShortcut? = nil

    var body: some View {
        HStack(spacing: 1) {
            Button(action: onAddTask) {
                Label(compact ? "" : "添加事项", systemImage: "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(minWidth: compact ? 40 : 92, minHeight: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
            .keyboardShortcut(shortcut)
            .help(shortcut == nil ? "直接添加待办事项" : "直接添加待办事项（⌘N）")
            .accessibilityLabel("添加待办事项")
            Menu {
                Button("新增待办", systemImage: "plus.circle", action: onAddTask)
                Button("记录已完成", systemImage: "checkmark.circle", action: onAddCompleted)
                Button("AI 一句话生成", systemImage: "sparkles", action: onAddWithAI)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("选择添加方式")
            .accessibilityLabel("选择添加方式")
        }
        .foregroundStyle(.white)
        .background(preferences.accentColor, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(.white.opacity(0.13)))
    }
}

struct PageHeader: View {
    @EnvironmentObject private var preferences: AppPreferences
    let eyebrow: String
    let title: String
    let description: String
    var action: (() -> Void)?
    var actionTitle = "新建事项"

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text(eyebrow.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(1.1)
                    .foregroundStyle(preferences.accentColor)
                Text(title)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                Text(description).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if let action {
                Button(action: action) { Label(actionTitle, systemImage: "plus") }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var selectedBlueprint: BlueprintItem?
    let onSelect: (TaskItem) -> Void
    let onReport: () -> Void
    let onAddTask: () -> Void
    let onAddCompleted: () -> Void
    let onAddWithAI: () -> Void

    private var actionableTasks: [TaskItem] { store.todayTasks.filter(\.needsAction) }
    private var focusTasks: [TaskItem] {
        actionableTasks.sorted {
            if $0.isInProgress != $1.isInProgress { return $0.isInProgress }
            if ($0.quadrant == .doNow) != ($1.quadrant == .doNow) { return $0.quadrant == .doNow }
            return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
        }.prefix(3).map { $0 }
    }
    private var groupedTasks: [TodayBlueprintTaskGroup] {
        TodayBlueprintOrganizer.groups(tasks: store.tasks, blueprints: store.blueprints)
    }
    private var unassignedTasks: [TaskItem] {
        TodayBlueprintOrganizer.unassignedTasks(tasks: store.tasks, blueprints: store.blueprints)
    }
    private var availableBlueprints: [BlueprintItem] {
        store.blueprints.filter { $0.archivedAt == nil && ![BlueprintStatus.completed, .cancelled].contains($0.status) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("TODAY").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("今天，做好最重要的事").font(.largeTitle.weight(.bold))
                        Text("已完成 \(store.completionText) 项 · 先完成重要且紧急的事项")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    AddTaskControl(onAddTask: onAddTask, onAddCompleted: onAddCompleted, onAddWithAI: onAddWithAI)
                        .buttonStyle(.borderedProminent)
                    SettingsLink {
                        Label("设置", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .help("应用设置")
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 12)], spacing: 12) {
                    StatCard(title: "今日完成", value: store.completionText, icon: "checkmark.circle.fill", color: .green)
                    StatCard(title: "进行中", value: "\(store.todayTasks.filter(\.isInProgress).count)", icon: "play.circle.fill", color: .blue)
                    StatCard(title: "已取消", value: "\(store.cancelledTodayCount)", icon: "xmark.circle.fill", color: .orange)
                    StatCard(title: "今日延期", value: "\(store.postponedTodayCount)", icon: "calendar.badge.clock", color: .purple)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("按蓝图执行").font(.title2.weight(.bold))
                        Text("把今天的动作放回目标路径中，完成一项就推进一格。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("预计 \(actionableTasks.reduce(0) { $0 + $1.estimatedMinutes }) 分钟")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("生成日报", systemImage: "sparkles", action: onReport)
                }
                if store.todayTasks.isEmpty {
                    ContentUnavailableView("今天还没有安排事项", systemImage: "point.3.connected.trianglepath.dotted", description: Text("添加任务并归入蓝图，让今天的行动推动长期目标。"))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    ForEach(groupedTasks) { group in
                        TodayBlueprintSection(
                            group: group,
                            focusTasks: focusTasks,
                            onOpenBlueprint: { selectedBlueprint = group.blueprint },
                            onSelect: onSelect
                        )
                    }
                    if !unassignedTasks.isEmpty {
                        UnassignedTodaySection(
                            tasks: unassignedTasks,
                            focusTasks: focusTasks,
                            blueprints: availableBlueprints,
                            onSelect: onSelect
                        )
                    }
                }
                let anniversaries = store.upcomingAnniversaries.filter { $0.showOnHome }.prefix(3)
                if !anniversaries.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("即将到来的重要日子").font(.title2.weight(.bold))
                        ForEach(Array(anniversaries)) { item in
                            HStack {
                                Image(systemName: item.type.icon).foregroundStyle(.pink)
                                Text(item.displayName)
                                Spacer()
                                if let days = item.daysRemaining() { Text(days == 0 ? "今天" : "还有 \(days) 天").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                            }
                            .padding(12).background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.horizontal, 34)
            .padding(.vertical, 30)
        }
        .sheet(item: $selectedBlueprint) { BlueprintDetailView(blueprintID: $0.id) }
    }
}

struct TodayBlueprintSection: View {
    @EnvironmentObject private var store: TaskStore
    let group: TodayBlueprintTaskGroup
    let focusTasks: [TaskItem]
    let onOpenBlueprint: () -> Void
    let onSelect: (TaskItem) -> Void

    private var completedCount: Int { group.tasks.filter(\.isCompleted).count }
    private var trackableCount: Int { group.tasks.filter { !$0.isCancelled }.count }
    private var progress: Double {
        guard trackableCount > 0 else { return 0 }
        return Double(completedCount) / Double(trackableCount)
    }
    private var remainingMinutes: Int {
        group.tasks.filter(\.needsAction).reduce(0) { $0 + $1.estimatedMinutes }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color(appHex: group.blueprint.colorHex))
                    .frame(width: 8, height: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text(group.blueprint.name).font(.headline)
                    Text("今日 \(completedCount)/\(trackableCount) · 待投入 \(remainingMinutes) 分钟")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("蓝图总进度 \(Int(store.blueprintProgress(group.blueprint.id) * 100))%")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Button("查看蓝图", systemImage: "arrow.up.right", action: onOpenBlueprint)
                    .buttonStyle(.borderless)
            }
            ProgressView(value: progress)
                .tint(Color(appHex: group.blueprint.colorHex))
            LazyVStack(spacing: 9) {
                ForEach(group.tasks) { task in
                    TodayTaskRow(task: task, focusRank: focusRank(for: task), onSelect: onSelect)
                }
            }
        }
        .padding(18)
        .background(Color(appHex: group.blueprint.colorHex).opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color(appHex: group.blueprint.colorHex).opacity(0.18)))
    }

    private func focusRank(for task: TaskItem) -> Int? {
        focusTasks.firstIndex(where: { $0.id == task.id }).map { $0 + 1 }
    }
}

struct TodayTaskRow: View {
    let task: TaskItem
    let focusRank: Int?
    let onSelect: (TaskItem) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 9) {
            Group {
                if let focusRank {
                    Text("\(focusRank)")
                        .font(.caption.monospacedDigit().weight(.bold))
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(Color.accentColor, in: Circle())
                        .help("今日重点第 \(focusRank) 项")
                } else {
                    Color.clear.frame(width: 24, height: 24)
                }
            }
            TaskCard(task: task, onSelect: onSelect)
        }
    }
}

struct UnassignedTodaySection: View {
    @EnvironmentObject private var store: TaskStore
    let tasks: [TaskItem]
    let focusTasks: [TaskItem]
    let blueprints: [BlueprintItem]
    let onSelect: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack {
                Image(systemName: "tray.full").foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text("暂未归入蓝图").font(.headline)
                    Text("这些事项能执行，但还没有连接到长期目标。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(tasks.count) 项").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            ForEach(tasks) { task in
                HStack(spacing: 9) {
                    TodayTaskRow(
                        task: task,
                        focusRank: focusTasks.firstIndex(where: { $0.id == task.id }).map { $0 + 1 },
                        onSelect: onSelect
                    )
                    Menu {
                        if blueprints.isEmpty {
                            Text("请先创建可执行的蓝图")
                        } else {
                            ForEach(blueprints) { blueprint in
                                Button(blueprint.name) { store.assign(task, to: blueprint) }
                            }
                        }
                    } label: {
                        Label("归入蓝图", systemImage: "arrowshape.turn.up.right")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }
        }
        .padding(18)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(style: StrokeStyle(lineWidth: 1, dash: [5])))
    }
}

struct StatCard: View {
    @EnvironmentObject private var preferences: AppPreferences
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 37, height: 37)
                .background(color.opacity(0.11), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(value).font(.title3.weight(.semibold)).contentTransition(.numericText())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .frame(minHeight: 78)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 15))
        .overlay(RoundedRectangle(cornerRadius: 15).stroke(.primary.opacity(0.07)))
    }
}

struct QuadrantBoard: View {
    @EnvironmentObject private var store: TaskStore
    let onSelect: (TaskItem) -> Void
    private let columns = [GridItem(.flexible(), spacing: 16), GridItem(.flexible(), spacing: 16)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "EISENHOWER MATRIX", title: "四象限", description: "把注意力留给真正重要的事情")
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(Quadrant.allCases) { quadrant in
                        QuadrantPanel(quadrant: quadrant, tasks: store.tasks(in: quadrant), onSelect: onSelect)
                    }
                }
            }
            .padding(30)
        }
    }
}

struct QuadrantPanel: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let quadrant: Quadrant
    let tasks: [TaskItem]
    let onSelect: (TaskItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(quadrant.title).font(.headline)
                    Text(quadrant.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(tasks.count)").font(.caption.weight(.bold)).foregroundStyle(preferences.color(for: quadrant))
            }
            Divider()
            if tasks.isEmpty {
                Text("暂无事项").font(.subheadline).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 52)
            } else {
                ForEach(tasks) { task in
                    TaskCard(task: task, compact: true, onSelect: onSelect)
                }
            }
        }
        .padding(17)
        .frame(maxWidth: .infinity, minHeight: 176, alignment: .topLeading)
        .background(preferences.color(for: quadrant).opacity(0.07), in: RoundedRectangle(cornerRadius: preferences.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: preferences.cornerRadius).stroke(preferences.color(for: quadrant).opacity(0.16)))
    }
}

struct TaskList: View {
    let tasks: [TaskItem]
    let onSelect: (TaskItem) -> Void

    var body: some View {
        LazyVStack(spacing: 9) {
            if tasks.isEmpty {
                ContentUnavailableView("今天还没有安排事项", systemImage: "checklist", description: Text("从收集箱开始，安排一件重要的事。"))
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
            ForEach(tasks) { task in TaskCard(task: task, onSelect: onSelect) }
        }
    }
}

struct TaskCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var isBlocking = false
    @State private var isHovered = false
    let task: TaskItem
    var compact = false
    let onSelect: (TaskItem) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button { primaryAction() } label: {
                Image(systemName: statusIcon)
                    .font(.title3).foregroundStyle(statusColor)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 28, height: 30)
                    .contentShape(Rectangle())
            }.buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
                .disabled(!task.isCompleted && store.executionBlockReason(for: task) != nil)
                .help(task.isCompleted ? "恢复为待完成" : (store.executionBlockReason(for: task) ?? "标记完成"))
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if task.parentTaskID != nil { Image(systemName: "arrow.turn.down.right").font(.caption).foregroundStyle(.tertiary) }
                    if task.planLocked { Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).help("计划日期已锁定") }
                    Text(task.title).strikethrough(task.isCompleted || task.isCancelled).lineLimit(compact ? 1 : 2)
                }
                if !compact {
                    HStack(spacing: 7) {
                        if !task.isPending { Text(task.effectiveStatus.title).foregroundStyle(statusColor) }
                        Label(task.projectName, systemImage: "folder").foregroundStyle(.secondary)
                        Label(task.categoryName, systemImage: "tag").foregroundStyle(.secondary)
                        Label(task.quadrant.title, systemImage: "square.grid.2x2").foregroundStyle(preferences.color(for: task.quadrant))
                        Text("· \(task.estimatedMinutes) 分钟")
                        if let dueDate = task.dueDate { Text("· 截止 \(dueDate, format: .dateTime.month().day())") }
                        if task.isInProgress, let startedAt = task.startedAt {
                            TimelineView(.periodic(from: .now, by: 1)) { context in
                                Text("· 已执行 \(elapsedText(from: startedAt, to: context.date))")
                                    .monospacedDigit().foregroundStyle(.blue)
                            }
                        }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    if task.effectiveStatus == .blocked, let reason = task.blockReason, !reason.isEmpty {
                        Label(reason, systemImage: "exclamationmark.octagon")
                            .font(.caption).foregroundStyle(.red)
                    }
                    if task.needsAction, let reason = store.executionBlockReason(for: task) {
                        Label(reason, systemImage: "lock")
                            .font(.caption).foregroundStyle(.orange).lineLimit(1)
                    }
                }
            }
            Spacer()
            Button { secondaryAction() } label: {
                Image(systemName: task.needsAction ? "xmark.circle" : "arrow.uturn.backward.circle")
                    .foregroundStyle(task.needsAction ? Color.secondary : .blue)
            }
            .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
            .help(task.needsAction ? "取消任务（无需完成）" : "恢复为待完成")
            Menu {
                if task.isUnscheduled {
                    Button("安排到今天", systemImage: "calendar.badge.plus") { store.scheduleToday(task) }
                }
                if task.needsAction && !task.isInProgress {
                    Button("开始执行", systemImage: "play.circle") { store.start(task) }
                        .disabled(store.executionBlockReason(for: task) != nil)
                }
                if !task.isCompleted {
                    Button("标记为已完成", systemImage: "checkmark.circle") { store.markCompleted(task) }
                        .disabled(store.executionBlockReason(for: task) != nil)
                }
                if task.needsAction && !task.isUnscheduled {
                    Button("延期到明天", systemImage: "calendar.badge.clock") { store.postpone(task) }
                }
                if task.needsAction {
                    Button("标记为阻塞", systemImage: "exclamationmark.octagon") { isBlocking = true }
                }
                if !task.isCancelled {
                    Button("取消任务（无需完成）", systemImage: "xmark.circle") { store.cancel(task) }
                }
                if !task.isPending {
                    Button("恢复为待完成", systemImage: "arrow.uturn.backward") { store.restore(task) }
                }
                Divider()
                if preferences.calendarIntegrationEnabled && !task.isUnscheduled {
                    Button("写入系统日历", systemImage: "calendar.badge.plus") {
                        Task {
                            do {
                                guard try await CalendarIntegration.shared.requestAccess() else { throw NSError(domain: "日历", code: 1, userInfo: [NSLocalizedDescriptionKey: "未获得日历授权。"] ) }
                                try CalendarIntegration.shared.write(task: task)
                                store.actionMessage = "已写入系统日历。"
                            } catch { store.actionMessage = "日历写入失败：\(error.localizedDescription)" }
                        }
                    }
                    Divider()
                }
                ForEach(Quadrant.allCases) { quadrant in
                    Button("移至\(quadrant.title)") { store.move(task, to: quadrant) }
                }
                Divider()
                Button("删除", role: .destructive) { store.delete(task) }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton)
        }
        .padding(compact ? max(6, preferences.density.spacing - 2) : preferences.density.spacing + 1)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: compact ? max(6, preferences.cornerRadius - 3) : preferences.cornerRadius))
        .overlay(RoundedRectangle(cornerRadius: compact ? max(6, preferences.cornerRadius - 3) : preferences.cornerRadius).stroke(isHovered ? preferences.accentColor.opacity(0.28) : .primary.opacity(0.07)))
        .shadow(color: .black.opacity(isHovered ? max(0.1, preferences.shadowStrength) : preferences.shadowStrength), radius: isHovered ? 12 : 7, y: isHovered ? 4 : 2)
        .offset(y: isHovered && !(preferences.reduceMotion || systemReduceMotion) ? -1 : 0)
        .onHover { hovering in
            withAnimation(preferences.reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.2)) { isHovered = hovering }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(task) }
        .sheet(isPresented: $isBlocking) { BlockTaskEditor(task: task) }
    }

    private var statusIcon: String {
        if preferences.iconStyle == .minimal {
            return task.isCompleted ? "checkmark" : task.isInProgress ? "play.fill" : task.isCancelled ? "xmark" : "circle"
        }
        return switch task.effectiveStatus {
        case .unscheduled: "calendar.badge.questionmark"
        case .pending: "circle"
        case .inProgress: "play.circle.fill"
        case .completed: "checkmark.circle.fill"
        case .cancelled: "xmark.circle.fill"
        case .postponed: "calendar.badge.clock"
        case .blocked: "exclamationmark.octagon.fill"
        }
    }

    private var statusColor: Color {
        if preferences.iconStyle == .monochrome { return .secondary }
        return switch task.effectiveStatus {
        case .unscheduled: .secondary
        case .pending: .secondary
        case .inProgress: .blue
        case .completed: .green
        case .cancelled: .orange
        case .postponed: .purple
        case .blocked: .red
        }
    }

    private func primaryAction() {
        withAnimation(preferences.reduceMotion || systemReduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
            if task.isCompleted { store.restore(task) } else { store.markCompleted(task) }
        }
    }

    private func secondaryAction() {
        withAnimation(preferences.reduceMotion || systemReduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.84)) {
            if task.needsAction { store.cancel(task) } else { store.restore(task) }
        }
    }

    private func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }
}

struct BlockTaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    let task: TaskItem
    @State private var reason = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("标记为阻塞").font(.title2.weight(.bold))
            Text(task.title).foregroundStyle(.secondary)
            TextField("阻塞原因", text: $reason, axis: .vertical)
                .lineLimit(3...6)
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存阻塞原因") { store.block(task, reason: reason); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 440, height: 230)
    }
}

struct InboxView: View {
    @EnvironmentObject private var store: TaskStore
    let onSelect: (TaskItem) -> Void
    var tasks: [TaskItem] { store.tasks.filter(\.isUnscheduled).sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "CAPTURE", title: "收集箱", description: "快速记下，稍后再判断优先级")
                if tasks.isEmpty {
                    ContentUnavailableView("收集箱已清空", systemImage: "tray", description: Text("新建事项时选择“暂不安排日期”，就可以先收集、稍后再规划。"))
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    TaskList(tasks: tasks, onSelect: onSelect)
                }
            }.padding(30)
        }
    }
}

struct PlanView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let onSelect: (TaskItem) -> Void
    @State private var days = 7

    private var scopedTasks: [TaskItem] {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        return store.tasks.filter { !$0.isUnscheduled && $0.scheduledFor >= start && $0.scheduledFor < end && !$0.isCancelled }
            .sorted { $0.scheduledFor < $1.scheduledFor }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    PageHeader(eyebrow: "PLAN", title: "日历计划", description: "按周或月查看计划容量，给重要事项预留时间。")
                    Spacer()
                    Picker("周期", selection: $days) {
                        Text("未来 7 天").tag(7)
                        Text("未来 30 天").tag(30)
                    }.pickerStyle(.segmented).frame(width: 210)
                }
                HStack(spacing: 14) {
                    StatCard(title: "计划事项", value: "\(scopedTasks.count)", icon: "calendar", color: .blue)
                    StatCard(title: "预计投入", value: "\(scopedTasks.reduce(0) { $0 + $1.estimatedMinutes }) 分钟", icon: "clock", color: .purple)
                    StatCard(title: "已阻塞", value: "\(scopedTasks.filter { $0.effectiveStatus == .blocked }.count)", icon: "exclamationmark.octagon", color: .red)
                }
                if preferences.calendarIntegrationEnabled {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("系统日历").font(.title2.weight(.bold))
                            Spacer()
                            Button("刷新", systemImage: "arrow.clockwise") {
                                Task {
                                    do {
                                        guard try await CalendarIntegration.shared.requestAccess() else { return }
                                        store.calendarEvents = CalendarIntegration.shared.events(days: days)
                                    } catch { store.actionMessage = "读取日历失败：\(error.localizedDescription)" }
                                }
                            }
                        }
                        if store.calendarEvents.isEmpty {
                            Text("授权后点击刷新，系统日程会显示在这里。")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            ForEach(store.calendarEvents.prefix(8)) { event in
                                HStack {
                                    Image(systemName: "calendar").foregroundStyle(.blue)
                                    Text(event.title).lineLimit(1)
                                    Spacer()
                                    Text(event.startDate, format: .dateTime.month().day().hour().minute())
                                        .font(.caption).foregroundStyle(.secondary)
                                    Text(event.calendarTitle).font(.caption2).foregroundStyle(.tertiary)
                                }.padding(9).background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                }
                if scopedTasks.isEmpty {
                    ContentUnavailableView("这个周期还没有计划", systemImage: "calendar", description: Text("通过添加事项或编辑任务日期安排计划。"))
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    ForEach(Dictionary(grouping: scopedTasks, by: { Calendar.current.startOfDay(for: $0.scheduledFor) }).keys.sorted(), id: \.self) { date in
                        VStack(alignment: .leading, spacing: 9) {
                            HStack {
                                Text(date, format: .dateTime.month().day().weekday(.wide)).font(.headline)
                                Spacer()
                                let dayTasks = scopedTasks.filter { Calendar.current.isDate($0.scheduledFor, inSameDayAs: date) }
                                Text("\(dayTasks.count) 项 · \(dayTasks.reduce(0) { $0 + $1.estimatedMinutes }) 分钟")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            ForEach(scopedTasks.filter { Calendar.current.isDate($0.scheduledFor, inSameDayAs: date) }) { task in
                                TaskCard(task: task, onSelect: onSelect)
                            }
                        }
                    }
                }
            }.padding(30)
        }
    }
}

struct CompletedView: View {
    @EnvironmentObject private var store: TaskStore
    let onSelect: (TaskItem) -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(eyebrow: "HISTORY", title: "今日已处理", description: "完成、取消和延期都有记录，便于复盘计划变化。")
                TaskList(tasks: store.processedToday.sorted { ($0.statusChangedAt ?? $0.completedAt ?? .distantPast) > ($1.statusChangedAt ?? $1.completedAt ?? .distantPast) }, onSelect: onSelect)
            }.padding(30)
        }
    }
}

struct ReportLanding: View {
    @EnvironmentObject private var store: TaskStore
    let onGenerate: () -> Void
    @State private var selectedReport: DailyReportItem?
    @State private var isWeeklyReviewPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    PageHeader(eyebrow: "REPORTS", title: "日报与复盘", description: "记录计划执行、会议结论和明日重点。")
                    Spacer()
                    Button("本周复盘", systemImage: "calendar.badge.checkmark") { isWeeklyReviewPresented = true }
                    Button("生成今日日报", systemImage: "sparkles", action: onGenerate).buttonStyle(.borderedProminent)
                }
                if !store.weeklyReviews.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("周复盘").font(.title2.weight(.bold))
                        ForEach(store.weeklyReviews.prefix(4)) { review in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(review.weekStart.formatted(.dateTime.year().month().day()) + " 当周").font(.headline)
                                Text(review.summary).lineLimit(2)
                                if !review.nextWeekFocus.isEmpty { Label(review.nextWeekFocus, systemImage: "arrow.right.circle").foregroundStyle(.secondary) }
                            }
                            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 13))
                            .overlay(RoundedRectangle(cornerRadius: 13).stroke(.quaternary))
                        }
                    }
                }
                if store.reports.isEmpty {
                    ContentUnavailableView("还没有保存的日报", systemImage: "doc.text", description: Text("生成日报后点击“保存日报”，即可在这里回顾。"))
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVStack(spacing: 10) {
                        ForEach(store.reports) { report in
                            Button { selectedReport = report } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "doc.text.fill").font(.title2).foregroundStyle(.indigo)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(report.reportDate.formatted(date: .long, time: .omitted)).font(.headline)
                                        Text(report.content.replacingOccurrences(of: "\n", with: " ")).lineLimit(2).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text("\(report.content.count) 字").font(.caption).foregroundStyle(.secondary)
                                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                                }
                                .padding(16)
                                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.quaternary))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxWidth: 1000, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(30)
        }
        .sheet(item: $selectedReport) { ReportDetailView(report: $0) }
        .sheet(isPresented: $isWeeklyReviewPresented) { WeeklyReviewEditor() }
    }
}

struct ReportDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let report: DailyReportItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(report.reportDate.formatted(date: .long, time: .omitted)).font(.title2.weight(.bold))
                    Text("字数范围 \(report.minimumLength)～\(report.maximumLength) · 实际 \(report.content.count) 字")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Button("关闭") { dismiss() }
            }
            ScrollView { Text(report.content).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
            HStack {
                Spacer()
                Button("复制 Markdown", systemImage: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(report.content, forType: .string)
                }
            }
        }
        .padding(24)
        .frame(width: 720, height: 600)
    }
}

struct TaskEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    private var original: TaskItem?
    @State private var title = ""
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
    @State private var appliedDefaults = false

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
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack { Text(original == nil ? "新建事项" : "编辑事项").font(.title2.weight(.bold)); Spacer() }
                .padding(22)
            Form {
                TextField("事项名称", text: $title)
                TextField("所属项目（日报按项目归类）", text: $project)
                TaskCategoryField(category: $category)
                TextField("备注（可选）", text: $notes, axis: .vertical)
                Picker("日报分类", selection: $reportCategory) {
                    ForEach(ReportCategory.allCases) { Text($0.title).tag($0) }
                }
                Picker("关联蓝图", selection: $blueprintID) {
                    Text("不关联蓝图").tag(nil as UUID?)
                    ForEach(store.blueprints) { Text($0.name).tag($0.id as UUID?) }
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
                                .disabled(original.map { DependencyRule.wouldCreateCycle(taskID: $0.id, adding: candidate.id, tasks: store.tasks) } ?? false)
                            }
                        }
                    }
                }
                Picker("四象限", selection: $quadrant) {
                    ForEach(Quadrant.allCases) { Text($0.title).tag($0) }
                }
                if original == nil || original?.isPending == true || original?.isUnscheduled == true {
                    Toggle("安排到日期", isOn: $isScheduled)
                }
                if isScheduled { DatePicker("安排日期", selection: $scheduledFor, displayedComponents: .date) }
                Toggle("设置截止日期", isOn: $hasDeadline)
                if hasDeadline { DatePicker("截止日期", selection: $dueDate, displayedComponents: [.date, .hourAndMinute]) }
                Stepper("预计时长：\(estimatedMinutes) 分钟", value: $estimatedMinutes, in: 5...480, step: 5)
                if isScheduled { Toggle("锁定计划日期（AI 重新规划不可修改）", isOn: $isPlanLocked) }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("保存") { save() }.buttonStyle(.borderedProminent).disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 540, height: 700)
        .onAppear {
            guard original == nil, !appliedDefaults else { return }
            quadrant = preferences.defaultQuadrant
            estimatedMinutes = preferences.defaultDuration
            if let blueprintID, project.isEmpty {
                project = store.blueprints.first { $0.id == blueprintID }?.name ?? ""
            }
            appliedDefaults = true
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
    }

    private func save() {
        let task = TaskItem(
            id: original?.id ?? UUID(), title: title.trimmingCharacters(in: .whitespacesAndNewlines), notes: notes,
            project: project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : project.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : category.trimmingCharacters(in: .whitespacesAndNewlines),
            reportCategory: reportCategory,
            quadrant: quadrant, scheduledFor: scheduledFor, dueDate: hasDeadline ? dueDate : nil,
            estimatedMinutes: estimatedMinutes, isComplete: original?.isComplete ?? false,
            status: isScheduled ? (original?.isUnscheduled == true ? .pending : original?.status) : .unscheduled,
            completedAt: original?.completedAt, createdAt: original?.createdAt ?? .now,
            blueprintID: blueprintID, stageID: stageID, milestoneID: milestoneID,
            startedAt: original?.startedAt, originalScheduledFor: original?.originalScheduledFor,
            blockReason: original?.blockReason, statusChangedAt: original?.statusChangedAt,
            parentTaskID: original?.parentTaskID,
            dependencyIDs: dependencyIDs.isEmpty ? nil : Array(dependencyIDs),
            originalDueDate: original?.originalDueDate,
            isPlanLocked: isScheduled && isPlanLocked
        )
        if original == nil { store.add(task) }
        else { guard store.update(task) else { return } }
        dismiss()
    }
}

struct QuickCompletedEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var title = ""
    @State private var project = ""
    @State private var category = ""
    @State private var blueprintID: UUID?
    @State private var reportCategory: ReportCategory = .projectProgress
    @State private var quadrant: Quadrant = .doNow
    @State private var completedAt = Date.now
    @State private var estimatedMinutes = 30
    @State private var appliedDefaults = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("补记已完成事项").font(.title2.weight(.bold))
                    Text("记录刚刚完成、但还没有加入计划的事项。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(22)
            Form {
                TextField("完成了什么？", text: $title)
                TextField("所属项目（日报按项目归类）", text: $project)
                TaskCategoryField(category: $category)
                Picker("关联蓝图", selection: $blueprintID) {
                    Text("不关联蓝图").tag(nil as UUID?)
                    ForEach(store.blueprints.filter { $0.archivedAt == nil }) { blueprint in
                        Text(blueprint.name).tag(blueprint.id as UUID?)
                    }
                }
                Picker("日报分类", selection: $reportCategory) {
                    ForEach(ReportCategory.allCases) { Text($0.title).tag($0) }
                }
                Picker("所属象限", selection: $quadrant) {
                    ForEach(Quadrant.allCases) { Text($0.title).tag($0) }
                }
                DatePicker("完成时间", selection: $completedAt, displayedComponents: [.date, .hourAndMinute])
                Stepper("耗时：\(estimatedMinutes) 分钟", value: $estimatedMinutes, in: 5...480, step: 5)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("记录完成", systemImage: "checkmark") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
        .frame(width: 500, height: 430)
        .onAppear {
            guard !appliedDefaults else { return }
            quadrant = preferences.defaultQuadrant
            estimatedMinutes = preferences.defaultDuration
            appliedDefaults = true
        }
        .onChange(of: blueprintID) { _, newValue in
            if let newValue, project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                project = store.blueprints.first { $0.id == newValue }?.name ?? ""
            }
        }
    }

    private func save() {
        store.add(TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            project: project.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : project.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : category.trimmingCharacters(in: .whitespacesAndNewlines),
            reportCategory: reportCategory,
            quadrant: quadrant,
            scheduledFor: completedAt,
            estimatedMinutes: estimatedMinutes,
            isComplete: true,
            status: .completed,
            completedAt: completedAt,
            blueprintID: blueprintID,
            statusChangedAt: completedAt
        ))
        dismiss()
    }
}

enum ReportLengthPreset: String, CaseIterable, Identifiable {
    case short = "简短"
    case standard = "标准"
    case detailed = "详细"
    case custom = "自定义"

    var id: String { rawValue }
    var range: ClosedRange<Int> {
        switch self {
        case .short: 125...180
        case .standard: 180...300
        case .detailed: 300...500
        case .custom: 125...180
        }
    }
}

struct DailyReportView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var content = ""
    @State private var supplement = ""
    @State private var lengthPreset: ReportLengthPreset = .short
    @State private var customMinimum = 125
    @State private var customMaximum = 180
    @State private var isSaved = false

    private var selectedMinimum: Int { lengthPreset == .custom ? customMinimum : lengthPreset.range.lowerBound }
    private var selectedMaximum: Int { lengthPreset == .custom ? customMaximum : lengthPreset.range.upperBound }
    private var lengthIsValid: Bool { (50...3000).contains(selectedMinimum) && selectedMaximum >= selectedMinimum && selectedMaximum <= 5000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text("今日日报").font(.title2.weight(.bold))
                    Text("按项目归类输出固定三段，生成时可控制字数。") .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }
            HStack(spacing: 12) {
                Picker("字数", selection: $lengthPreset) {
                    ForEach(ReportLengthPreset.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 380)
                if lengthPreset == .custom {
                    TextField("最少", value: $customMinimum, format: .number).frame(width: 62)
                    Text("～").foregroundStyle(.secondary)
                    TextField("最多", value: $customMaximum, format: .number).frame(width: 62)
                    Text("字").foregroundStyle(.secondary)
                } else {
                    Text("\(selectedMinimum)～\(selectedMaximum) 字")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if !lengthIsValid {
                Text("最少字数须在 50～3000 之间；最多字数不得小于最少字数且不超过 5000。")
                    .font(.caption).foregroundStyle(.red)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack {
                    Label("日报补充", systemImage: "text.badge.plus")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text("会议信息、结论、风险或想强调的内容")
                        .font(.caption).foregroundStyle(.secondary)
                }
                TextEditor(text: $supplement)
                    .font(.body)
                    .padding(6)
                    .frame(height: 92)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            }
            if store.isReportLoading {
                ProgressView("正在生成日报…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if content.isEmpty {
                ContentUnavailableView("准备好复盘了吗？", systemImage: "sparkles", description: Text(store.reportError ?? "DeepSeek 将按项目合并同类事项，并给出明日重点规划。"))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: $content).font(.body).padding(6).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            }
            if let warning = store.reportLengthWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                if !content.isEmpty {
                    Button("复制 Markdown") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(content, forType: .string) }
                    Button(isSaved ? "已保存" : "保存日报", systemImage: isSaved ? "checkmark" : "tray.and.arrow.down") {
                        store.saveReport(content: content, supplement: supplement, minimumLength: selectedMinimum, maximumLength: selectedMaximum)
                        isSaved = true
                    }
                    .disabled(isSaved)
                    Text("\(content.count) 字").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("生成日报", systemImage: "sparkles") {
                    Task {
                        content = await store.generateReport(
                            endpoint: preferences.deepSeekEndpoint,
                            model: preferences.deepSeekModel,
                            supplement: supplement,
                            minimumLength: selectedMinimum,
                            maximumLength: selectedMaximum
                        ) ?? content
                        isSaved = false
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isReportLoading || !lengthIsValid)
            }
        }
        .padding(24)
        .frame(width: 760, height: 720)
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.openWindow) private var openWindow
    @State private var composerMode: TaskComposerMode?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天的计划").font(.headline)
                    Text("已完成 \(store.completionText) 项").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button { openWindow(id: "main") } label: { Image(systemName: "arrow.up.right.square") }.buttonStyle(.plain)
            }
            Divider()
            ForEach(Array(store.todayTasks.filter(\.needsAction).prefix(4))) { task in
                HStack {
                    Button { store.toggle(task) } label: { Image(systemName: "circle") }
                        .buttonStyle(.plain)
                        .disabled(store.executionBlockReason(for: task) != nil)
                    Text(task.title).lineLimit(1)
                    Spacer()
                    Button { store.cancel(task) } label: { Image(systemName: "xmark.circle") }
                        .buttonStyle(.plain)
                        .help("取消任务（无需完成）")
                }
            }
            let menuAnniversaries = store.upcomingAnniversaries.filter { $0.showInMenuBar }.prefix(2)
            if !menuAnniversaries.isEmpty {
                Divider()
                ForEach(Array(menuAnniversaries)) { item in
                    HStack {
                        Image(systemName: item.type.icon).foregroundStyle(.pink)
                        Text(item.displayName).lineLimit(1)
                        Spacer()
                        if let days = item.daysRemaining() { Text(days == 0 ? "今天" : "\(days)天").font(.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if store.todayTasks.filter(\.needsAction).isEmpty { Text("今天的待办已处理完毕。🎉").foregroundStyle(.secondary) }
            Divider()
            AddTaskControl(onAddTask: { composerMode = .task }, onAddCompleted: { composerMode = .completed }, onAddWithAI: { composerMode = .ai })
            Button("命令面板", systemImage: "command") {
                openWindow(id: "main")
                DispatchQueue.main.async { NotificationCenter.default.post(name: .showCommandPalette, object: nil) }
            }
            Button("打开桌面小组件", systemImage: "rectangle.inset.filled") { openWindow(id: "widget") }
            Button("打开主界面", systemImage: "rectangle.on.rectangle") { openWindow(id: "main") }
            SettingsLink { Label("应用设置", systemImage: "gearshape") }
            Button("退出序", role: .destructive) { NSApplication.shared.terminate(nil) }
        }
        .padding(16)
        .frame(width: 300)
        .sheet(item: $composerMode) { TaskComposerView(mode: $0) }
    }
}

struct MenuBarStatusLabel: View {
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        if let task = store.todayTasks.first(where: \.isInProgress) {
            Label(String(task.title.prefix(8)), systemImage: "play.circle.fill")
        } else if let item = store.upcomingAnniversaries.first(where: { $0.showInMenuBar }), let days = item.daysRemaining(), days <= 7 {
            Label(days == 0 ? "\(item.displayName) 今天" : "\(item.displayName) \(days)天", systemImage: item.type.icon)
        } else {
            Label("序", systemImage: "checklist")
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences

    var body: some View {
        TabView {
            Form {
                Section("外观") {
                    Picker("显示模式", selection: $preferences.appearance) {
                        ForEach(AppearanceMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                }
                Section("新事项默认值") {
                    Picker("默认四象限", selection: $preferences.defaultQuadrant) {
                        ForEach(Quadrant.allCases) { Text($0.title).tag($0) }
                    }
                    Stepper("默认预计时长：\(preferences.defaultDuration) 分钟", value: $preferences.defaultDuration, in: 5...480, step: 5)
                }
                Section("每日复盘") {
                    Toggle("开启每日复盘提醒", isOn: $preferences.dailyReviewEnabled)
                    if preferences.dailyReviewEnabled {
                        DatePicker("提醒时间", selection: $preferences.dailyReviewTime, displayedComponents: .hourAndMinute)
                        Text("到点后会通过 macOS 通知提醒你生成日报。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            Form {
                Section("DeepSeek 连接") {
                    SecureField("API Key", text: $store.apiKey)
                    TextField("模型", text: $preferences.deepSeekModel)
                    TextField("接口地址", text: $preferences.deepSeekEndpoint)
                    Text("密钥保存在 macOS 钥匙串中，仅在你主动使用 AI 任务、蓝图、重新规划或日报时发送。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("AI 数据范围") {
                    Toggle("重新规划时发送项目名称", isOn: $preferences.aiSendProject)
                    Toggle("重新规划时发送任务备注", isOn: $preferences.aiSendNotes)
                    Text("任务标题、日期、时长、状态、阻塞原因和蓝图截止日期是重新规划所需字段。完整蓝图生成功能只发送你当次填写的目标。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("DeepSeek", systemImage: "sparkles") }

            ThemeSettingsView()
                .tabItem { Label("主题皮肤", systemImage: "paintpalette") }

            DataIntegrationSettingsView()
                .tabItem { Label("数据与集成", systemImage: "externaldrive.connected.to.line.below") }
        }
        .onChange(of: preferences.dailyReviewEnabled) { _, enabled in
            Task { await DailyReviewNotification.configure(enabled: enabled, time: preferences.dailyReviewTime) }
        }
        .onChange(of: preferences.dailyReviewTime) { _, time in
            guard preferences.dailyReviewEnabled else { return }
            Task { await DailyReviewNotification.configure(enabled: true, time: time) }
        }
        .padding(16)
        .frame(width: 720, height: 520)
    }
}
