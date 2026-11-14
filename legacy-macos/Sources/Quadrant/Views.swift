import Combine
import SwiftUI

enum AppSection: String, CaseIterable, Identifiable {
    case inbox = "收集箱"
    case today = "今日"
    case tasks = "事项"
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
        case .tasks: "checklist"
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
    private struct TaskBlueprintRoute: Identifiable {
        let id = UUID()
        let taskID: UUID
        let blueprintID: UUID?
    }
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openWindow) private var openWindow
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selection: AppSection? = .today
    // The reference stays stable while only the overlay observes mode changes.
    @State private var composerPresentation = TaskComposerPresentation()
    @State private var selectedTask: TaskItem?
    @State private var editorBlueprintDestination: TaskItem?
    @State private var taskBlueprintRoute: TaskBlueprintRoute?
    @State private var projectBlueprintID: UUID?
    @State private var showsBlueprintLibrary = false
    @State private var isReportPresented = false
    @State private var isInboxComposerPresented = false
    @State private var isCommandPalettePresented = false
    @State private var isAIBlueprintPresented = false
    @State private var isSyncConflictPresented = false
    private let syncTimer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationSplitView {
            SidebarView(
                selection: $selection
            )
            .navigationSplitViewColumnWidth(min: 190, ideal: 216, max: 250)
        } detail: {
            VStack(spacing: 0) {
                WorkbenchTopBar(
                    section: taskBlueprintRoute != nil || projectBlueprintID != nil ? .blueprints : selection ?? .today,
                    isCommandPalettePresented: $isCommandPalettePresented,
                    performCommand: performCommand
                )
                Group {
                    if let route = taskBlueprintRoute {
                        if let blueprintID = route.blueprintID,
                           store.blueprints.contains(where: { $0.id == blueprintID }) {
                            BlueprintDetailView(blueprintID: blueprintID, focusTaskID: route.taskID,
                                                onClose: { taskBlueprintRoute = nil })
                        } else {
                            TaskBlueprintView(
                                rootTaskID: TaskTreeProjection.rootID(containing: route.taskID, in: store.tasks),
                                focusTaskID: route.taskID,
                                onClose: { taskBlueprintRoute = nil }
                            )
                        }
                    } else if let projectBlueprintID {
                        BlueprintDetailView(blueprintID: projectBlueprintID,
                                            onClose: { self.projectBlueprintID = nil })
                    } else {
                    switch selection ?? .today {
                    case .inbox: InboxView(onSelect: { selectedTask = $0 },
                                           onAddTask: { isInboxComposerPresented = true })
                    case .today: TodayWorkbenchView(
                        onSelect: { selectedTask = $0 },
                        onReport: { isReportPresented = true },
                        onAddTask: { composerPresentation.show(.task) }
                    )
                    case .tasks: TasksHubView(
                        showsBlueprintLibrary: $showsBlueprintLibrary,
                        onSelect: { selectedTask = $0 },
                        onAddTask: { composerPresentation.show(.task) }
                    )
                    case .blueprints: BlueprintsView()
                    case .quadrants: QuadrantBoard(onSelect: { selectedTask = $0 })
                    case .categories: TaskCategoriesView(onSelect: { selectedTask = $0 })
                    case .calendar: PlanView(onSelect: { selectedTask = $0 }, onAddTask: { composerPresentation.show(.task) })
                    case .anniversaries: AnniversariesView()
                    case .completed: CompletedView(onSelect: { selectedTask = $0 })
                    case .report: ReportLanding(onGenerate: { isReportPresented = true })
                    }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(selection ?? .today)
                .transition(preferences.reduceMotion || systemReduceMotion ? .identity : .opacity.combined(with: .offset(x: 10)))
            }
            .appSurface()
            .ignoresSafeArea(.container, edges: .top)
        }
        .overlay {
            TaskComposerPanelHost(presentation: composerPresentation)
        }
        .appDialog(item: $selectedTask, onDismiss: {
            if let task = editorBlueprintDestination {
                editorBlueprintDestination = nil
                TaskBlueprintNavigation.open(task)
            }
        }) { task in
            TaskEditor(task: task, onRequestBlueprint: { editorBlueprintDestination = $0 })
        }
        .appDialog(isPresented: $isReportPresented) { DailyReportView() }
        .appDialog(isPresented: $isInboxComposerPresented) { TaskComposerView(startsInInbox: true) }
        .appDialog(isPresented: $isAIBlueprintPresented) { AIBlueprintCreatorView() }
        .appDialog(isPresented: $isSyncConflictPresented) {
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
        .alert("发现应用更新", isPresented: $preferences.shouldPresentUpdatePrompt) {
            Button("下载并安装") { Task { await preferences.downloadAndInstallUpdate() } }
            Button("稍后", role: .cancel) { }
        } message: {
            Text("发现版本 \(preferences.availableUpdate?.version ?? "")。可在“设置 → 数据与集成”查看更新内容；安装完成后应用会重新打开。")
        }
        .onReceive(NotificationCenter.default.publisher(for: .showCommandPalette)) { _ in isCommandPalettePresented = true }
        .onReceive(NotificationCenter.default.publisher(for: .runCommandFromSettings)) { notification in
            guard let rawValue = notification.object as? String,
                  let command = CommandPaletteAction(rawValue: rawValue) else { return }
            performCommand(command)
        }
        .onReceive(NotificationCenter.default.publisher(for: .showTaskComposer)) { _ in composerPresentation.show(.task) }
        .onReceive(NotificationCenter.default.publisher(for: .showTaskBlueprint)) { notification in
            guard let taskID = notification.object as? UUID else { return }
            projectBlueprintID = nil
            taskBlueprintRoute = TaskBlueprintRoute(
                taskID: taskID,
                blueprintID: notification.userInfo?["blueprintID"] as? UUID
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .showBlueprint)) { notification in
            guard let blueprintID = notification.object as? UUID else { return }
            taskBlueprintRoute = nil
            projectBlueprintID = blueprintID
        }
        .onChange(of: selection) { _, _ in
            taskBlueprintRoute = nil
            projectBlueprintID = nil
        }
        .onReceive(syncTimer) { _ in
            guard preferences.syncEnabled, !preferences.syncFolderPath.isEmpty, store.syncConflict == nil else { return }
            do {
                try store.performFolderSync(folderPath: preferences.syncFolderPath)
                isSyncConflictPresented = store.syncConflict != nil
            } catch { store.syncMessage = error.localizedDescription }
        }
        .task {
            if preferences.autoCheckUpdates { await preferences.checkForUpdates(notify: true) }
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
        case .addTask: composerPresentation.show(.task)
        case .addCompleted: composerPresentation.show(.completed)
        case .aiTask: composerPresentation.show(.ai)
        case .aiBlueprint: isAIBlueprintPresented = true
        case .dailyReport: isReportPresented = true
        case .openToday: selection = .today
        case .openBlueprints:
            showsBlueprintLibrary = true
            selection = .tasks
        case .openAnniversaries: selection = .anniversaries
        case .openWidget: openWindow(id: "widget")
        case .toggleFocusTheme: preferences.focusThemeActive.toggle()
        }
    }
}

struct SidebarView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Binding var selection: AppSection?

    private let primarySections: [AppSection] = [.today, .tasks, .categories, .calendar]
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
                    Text("把计划变成行动").font(AppTypography.caption).foregroundStyle(.secondary)
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

            SettingsLink {
                HStack(spacing: 12) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .medium))
                        .frame(width: 22)
                    Text("应用设置")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 46)
                .contentShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
            .padding(.horizontal, 11)
            .padding(.vertical, 14)
        }
        .background(preferences.pageBackground.opacity(0.9))
    }

    private func sidebarCaption(_ title: String) -> some View {
        Text(title)
            .font(AppTypography.caption.weight(.semibold))
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
                if section == .today { SidebarTodayCount(isSelected: selection == section) }
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

private struct SidebarTodayCount: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let isSelected: Bool

    var body: some View {
        Group {
            if !store.todayTasks.isEmpty {
                Text("\(store.todayTasks.filter(\.needsAction).count)")
                    .font(AppTypography.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(isSelected ? preferences.accentColor : .secondary)
            }
        }
        .transaction { $0.animation = nil }
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
        HStack(spacing: 0) {
            Button(action: onAddTask) {
                HStack(spacing: AppSpacing.x2) {
                    Image(systemName: "plus")
                    if !compact { Text("添加事项") }
                }
                    .font(AppTypography.callout.weight(.semibold))
                    .padding(.horizontal, compact ? 0 : AppSpacing.x3)
                    .frame(minWidth: compact ? 34 : 92, minHeight: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
            .keyboardShortcut(shortcut)
            .help(shortcut == nil ? "直接添加待办事项" : "直接添加待办事项（⌘N）")
            .accessibilityLabel("添加待办事项")
            Rectangle()
                .fill(AppColors.foreground(on: preferences.accentColor).opacity(0.22))
                .frame(width: 1, height: 18)
            Menu {
                Button("新增待办", systemImage: "plus.circle", action: onAddTask)
                Button("记录已完成", systemImage: "checkmark.circle", action: onAddCompleted)
                Button("AI 生成任务", systemImage: "sparkles", action: onAddWithAI)
            } label: {
                Color.clear
                    .frame(width: 32, height: 34)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .overlay {
                Image(systemName: "chevron.down")
                    .font(AppTypography.caption.weight(.semibold))
                    .foregroundStyle(AppColors.foreground(on: preferences.accentColor))
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .help("选择添加方式")
            .accessibilityLabel("选择添加方式")
        }
        .foregroundStyle(AppColors.foreground(on: preferences.accentColor))
        .background(preferences.accentColor, in: RoundedRectangle(cornerRadius: AppRadius.control))
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
                    .font(AppTypography.callout.weight(.semibold))
                    .tracking(1.1)
                    .foregroundStyle(preferences.accentColor)
                Text(title)
                    .font(.system(size: 29, weight: .bold, design: .rounded))
                    .tracking(-0.6)
                Text(description).font(AppTypography.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if let action {
                AppButton(title: actionTitle, systemImage: "plus", tint: preferences.accentColor, action: action)
            }
        }
    }
}

struct TodayView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
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
                        Text("TODAY").font(AppTypography.caption.weight(.semibold)).foregroundStyle(.secondary)
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
                    StatCard(title: "今日完成", value: store.completionText, icon: "checkmark.circle.fill", color: AppColors.taskCompleted(for: preferences))
                    StatCard(title: "进行中", value: "\(store.todayTasks.filter(\.isInProgress).count)", icon: "play.circle.fill", color: .blue)
                    StatCard(title: "已取消", value: "\(store.cancelledTodayCount)", icon: "xmark.circle.fill", color: .orange)
                    StatCard(title: "今日延期", value: "\(store.postponedTodayCount)", icon: "calendar.badge.clock", color: .purple)
                }
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("按蓝图执行").font(.title2.weight(.bold))
                        Text("把今天的动作放回目标路径中，完成一项就推进一格。")
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("预计 \(actionableTasks.reduce(0) { $0 + $1.estimatedMinutes }) 分钟")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
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
                            onOpenBlueprint: {
                                NotificationCenter.default.post(name: .showBlueprint, object: group.blueprint.id)
                            },
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
                                if let days = item.daysRemaining() { Text(days == 0 ? "今天" : "还有 \(days) 天").font(AppTypography.caption.monospacedDigit()).foregroundStyle(.secondary) }
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
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("蓝图总进度 \(Int(store.blueprintProgress(group.blueprint.id) * 100))%")
                    .font(AppTypography.caption.monospacedDigit()).foregroundStyle(.secondary)
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
                        .font(AppTypography.caption.monospacedDigit().weight(.bold))
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
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(tasks.count) 项").font(AppTypography.caption.monospacedDigit()).foregroundStyle(.secondary)
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
                Text(title).font(AppTypography.caption).foregroundStyle(.secondary)
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
                    Text(quadrant.subtitle).font(AppTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(tasks.count)").font(AppTypography.caption.weight(.bold)).foregroundStyle(preferences.color(for: quadrant))
            }
            Divider()
            if tasks.isEmpty {
                Text("暂无事项").font(AppTypography.callout).foregroundStyle(.tertiary).frame(maxWidth: .infinity, minHeight: 52)
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
    @State private var collapsedRootIDs: Set<UUID> = []
    let tasks: [TaskItem]
    let onSelect: (TaskItem) -> Void
    var onEditTask: ((TaskItem) -> Void)? = nil
    var onAddChildTask: ((TaskItem) -> Void)? = nil
    var onShowBlueprint: ((TaskItem) -> Void)? = nil
    var selectedTaskID: UUID? = nil
    var revealRequest = false
    var hidesDefaultMetadata = false
    var clarifiesChildScope = false

    private var visibleRoots: [TaskItem] {
        let ids = Set(tasks.map(\.id))
        return tasks.filter { $0.parentTaskID.map { !ids.contains($0) } ?? true }
    }

    private func revealSelected() {
        guard let selectedTaskID else { return }
        collapsedRootIDs.subtract(TaskTreeProjection.path(to: selectedTaskID, in: tasks).map(\.id))
    }

    var body: some View {
        LazyVStack(spacing: 9) {
            if tasks.isEmpty {
                ContentUnavailableView("今天还没有安排事项", systemImage: "checklist", description: Text("从收集箱开始，安排一件重要的事。"))
                    .frame(maxWidth: .infinity, minHeight: 220)
            }
            ForEach(visibleRoots) { task in
                TaskListTreeRow(task: task, tasks: tasks, depth: 0,
                                visited: [], collapsedRootIDs: $collapsedRootIDs, onSelect: onSelect,
                                onEditTask: onEditTask, onAddChildTask: onAddChildTask,
                                onShowBlueprint: onShowBlueprint,
                                selectedTaskID: selectedTaskID, hidesDefaultMetadata: hidesDefaultMetadata,
                                clarifiesChildScope: clarifiesChildScope)
            }
        }
        .onChange(of: revealRequest) { _, _ in revealSelected() }
    }
}

private struct TaskListTreeRow: View {
    let task: TaskItem
    let tasks: [TaskItem]
    let depth: Int
    let visited: Set<UUID>
    @Binding var collapsedRootIDs: Set<UUID>
    let onSelect: (TaskItem) -> Void
    let onEditTask: ((TaskItem) -> Void)?
    let onAddChildTask: ((TaskItem) -> Void)?
    let onShowBlueprint: ((TaskItem) -> Void)?
    let selectedTaskID: UUID?
    let hidesDefaultMetadata: Bool
    let clarifiesChildScope: Bool

    private var children: [TaskItem] {
        TaskTreeProjection.directChildren(of: task.id, in: tasks).filter { !visited.contains($0.id) }
    }

    var body: some View {
        HStack(spacing: AppSpacing.x2) {
            if !children.isEmpty {
                Button {
                    if collapsedRootIDs.contains(task.id) { collapsedRootIDs.remove(task.id) }
                    else { collapsedRootIDs.insert(task.id) }
                } label: {
                    Image(systemName: collapsedRootIDs.contains(task.id) ? "chevron.right" : "chevron.down")
                        .frame(width: 36, height: 36)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(collapsedRootIDs.contains(task.id) ? "展开\(task.title)的子任务" : "收起\(task.title)的子任务")
            } else if depth > 0 {
                Color.clear.frame(width: 36, height: 1)
            }
            TaskCard(task: task, onSelect: onSelect, onEditTask: onEditTask,
                     onAddChildTask: onAddChildTask, onShowBlueprint: onShowBlueprint,
                     isSelected: selectedTaskID == task.id,
                     hidesDefaultMetadata: hidesDefaultMetadata,
                     clarifiesChildScope: clarifiesChildScope)
        }
        .id(task.id)
        .padding(.leading, CGFloat(min(depth, 6)) * AppSpacing.x6)
        if !collapsedRootIDs.contains(task.id) {
            ForEach(children) { child in
                TaskListTreeRow(task: child, tasks: tasks, depth: depth + 1,
                                visited: visited.union([task.id]),
                                collapsedRootIDs: $collapsedRootIDs, onSelect: onSelect,
                                onEditTask: onEditTask, onAddChildTask: onAddChildTask,
                                onShowBlueprint: onShowBlueprint,
                                selectedTaskID: selectedTaskID, hidesDefaultMetadata: hidesDefaultMetadata,
                                clarifiesChildScope: clarifiesChildScope)
            }
        }
    }
}

struct TaskCard: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var isBlocking = false
    @State private var isAddingChild = false
    @State private var isConfirmingDelete = false
    @State private var isHovered = false
    let task: TaskItem
    var compact = false
    var embedded = false
    let onSelect: (TaskItem) -> Void
    var onEditTask: ((TaskItem) -> Void)? = nil
    var onAddChildTask: ((TaskItem) -> Void)? = nil
    var onShowBlueprint: ((TaskItem) -> Void)? = nil
    var onCompleteTask: ((TaskItem) -> Void)? = nil
    var completionInProgress = false
    var onShowDetails: ((TaskItem) -> Void)? = nil
    var isSelected = false
    var hidesDefaultMetadata = false
    var clarifiesChildScope = false

    private var childTasks: [TaskItem] { store.tasks.filter { $0.parentTaskID == task.id } }

    var body: some View {
        HStack(spacing: 12) {
            Button { primaryAction() } label: {
                Image(systemName: embedded && task.isCompleted
                      ? "checkmark.circle.fill" : embedded && task.needsAction ? "circle" : statusIcon)
                    .font(.title3)
                    .foregroundStyle(statusColor)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
                .offset(y: embedded ? -AppSpacing.x2 : 0)
                .disabled(completionInProgress || (!task.isCompleted && store.executionBlockReason(for: task) != nil))
                .help(task.isCompleted ? "恢复为待完成" : (store.executionBlockReason(for: task) ?? "标记完成"))
                .accessibilityLabel(task.isCompleted ? "恢复\(task.title)" : "完成\(task.title)")
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    if task.parentTaskID != nil && !embedded { Image(systemName: "arrow.turn.down.right").font(AppTypography.caption).foregroundStyle(.tertiary) }
                    if task.planLocked { Image(systemName: "lock.fill").font(AppTypography.caption).foregroundStyle(.secondary).help("计划日期已锁定") }
                    Text(task.title).strikethrough(task.isCompleted || task.isCancelled).lineLimit(compact ? 1 : 2)
                        .foregroundStyle(task.isCompleted ? AppColors.textSecondary : AppColors.textPrimary)
                        .font(embedded ? AppTypography.desktop(.body, scale: preferences.fontScale,
                                                              weight: .semibold, design: preferences.fontStyle.design) : nil)
                }
                if !childTasks.isEmpty && !embedded {
                    Text(clarifiesChildScope
                         ? "直接子任务 \(childTasks.filter(\.isCompleted).count)/\(childTasks.count) 已完成"
                         : "\(childTasks.filter(\.isCompleted).count)/\(childTasks.count) 项子任务已完成")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                }
                if embedded {
                    Text(task.displayStatusTitle)
                    .font(AppTypography.desktop(.caption1, scale: preferences.fontScale,
                                                design: preferences.fontStyle.design))
                    .foregroundStyle(task.isCompleted ? AppColors.textSecondary : statusColor)
                    if task.effectiveStatus == .blocked, let reason = task.blockReason, !reason.isEmpty {
                        Label(reason, systemImage: "lock")
                            .font(AppTypography.desktop(.caption1, scale: preferences.fontScale,
                                                        design: preferences.fontStyle.design))
                            .foregroundStyle(AppColors.warning)
                            .lineLimit(2)
                    } else if task.needsAction, let reason = store.executionBlockReason(for: task) {
                        Label(reason, systemImage: "lock")
                            .font(AppTypography.caption)
                            .foregroundStyle(AppColors.warning)
                            .lineLimit(2)
                    }
                } else if !compact {
                    HStack(spacing: 7) {
                        if !task.isPending { Text(task.displayStatusTitle).foregroundStyle(statusColor) }
                        if !hidesDefaultMetadata || !(task.project ?? "").isEmpty {
                            Label(task.projectName, systemImage: "folder").foregroundStyle(.secondary)
                        }
                        if !hidesDefaultMetadata || !(task.category ?? "").isEmpty {
                            Label(task.categoryName, systemImage: "tag").foregroundStyle(.secondary)
                        }
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
                    .font(AppTypography.caption).foregroundStyle(.secondary)
                    if task.effectiveStatus == .blocked, let reason = task.blockReason, !reason.isEmpty {
                        Label(reason, systemImage: "exclamationmark.octagon")
                            .font(AppTypography.caption).foregroundStyle(.red)
                    }
                    if task.needsAction, let reason = store.executionBlockReason(for: task) {
                        Label(reason, systemImage: "lock")
                            .font(AppTypography.caption).foregroundStyle(.orange).lineLimit(1)
                    }
                }
            }
            Spacer()
            if embedded {
                Group {
                    if let dueDate = task.dueDate {
                        Text("截止 \(dueDate, format: .dateTime.month().day())")
                    } else if task.isUnscheduled {
                        Text("暂未安排")
                    } else {
                        Text("计划 \(task.scheduledFor, format: .dateTime.month().day())")
                    }
                }
                .font(AppTypography.desktop(.caption1, scale: preferences.fontScale,
                                            design: preferences.fontStyle.design))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: true, vertical: false)
            }
            if !embedded { Button { secondaryAction() } label: {
                Image(systemName: task.needsAction ? "xmark.circle" : "arrow.uturn.backward.circle")
                    .foregroundStyle(task.needsAction ? AppColors.textSecondary : preferences.accentColor)
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
            .help(task.needsAction ? "取消任务（无需完成）" : "恢复为待完成")
            .accessibilityLabel(task.needsAction ? "取消\(task.title)" : "恢复\(task.title)") }
            Menu {
                if let onShowDetails {
                    Button("查看详情", systemImage: "info.circle") { onShowDetails(task) }
                }
                Button("编辑任务", systemImage: "pencil") { (onEditTask ?? onSelect)(task) }
                Button("添加子任务", systemImage: "plus") {
                    if let onAddChildTask { onAddChildTask(task) }
                    else { isAddingChild = true }
                }
                Button("查看蓝图", systemImage: "point.3.connected.trianglepath.dotted") {
                    if let onShowBlueprint { onShowBlueprint(task) }
                    else { TaskBlueprintNavigation.open(task) }
                }
                Divider()
                if task.isUnscheduled {
                    Button("安排到今天", systemImage: "calendar.badge.plus") { store.scheduleToday(task) }
                }
                if task.needsAction && !task.isInProgress {
                    Button("开始执行", systemImage: "play.circle") { store.start(task) }
                        .disabled(store.executionBlockReason(for: task) != nil)
                }
                if !task.isCompleted {
                    Button("标记为已完成", systemImage: "checkmark.circle") { complete(task) }
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
                Button("删除", role: .destructive) {
                    if TaskTreeProjection.descendants(of: task.id, in: store.tasks).isEmpty { store.delete(task) }
                    else { isConfirmingDelete = true }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(embedded ? .hidden : .automatic)
            .fixedSize(horizontal: embedded, vertical: false)
            .accessibilityLabel("更多\(task.title)操作")
        }
        .padding(embedded ? 0 : (compact ? max(6, preferences.density.spacing - 2) : preferences.density.spacing + 1))
        .padding(.vertical, embedded ? AppSpacing.x2 : 0)
        .background {
            if !embedded {
                RoundedRectangle(cornerRadius: compact ? max(6, preferences.cornerRadius - 3) : preferences.cornerRadius)
                    .fill(preferences.cardBackground)
            }
        }
        .overlay {
            if !embedded {
                RoundedRectangle(cornerRadius: compact ? max(6, preferences.cornerRadius - 3) : preferences.cornerRadius)
                    .stroke(isSelected ? preferences.accentColor :
                            (isHovered ? preferences.accentColor.opacity(0.28) : .primary.opacity(0.07)),
                            lineWidth: isSelected ? 2 : 1)
            }
        }
        .shadow(color: embedded ? .clear : .black.opacity(isHovered ? max(0.1, preferences.shadowStrength) : preferences.shadowStrength), radius: isHovered ? 12 : 7, y: isHovered ? 4 : 2)
        .offset(y: embedded || preferences.reduceMotion || systemReduceMotion ? 0 : (isHovered ? -1 : 0))
        .onHover { hovering in
            withAnimation(preferences.reduceMotion || systemReduceMotion ? nil : .easeOut(duration: 0.2)) { isHovered = hovering }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect(task) }
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .appDialog(isPresented: $isBlocking) { BlockTaskEditor(task: task) }
        .appDialog(isPresented: $isAddingChild) { TaskChildQuickAddView(parentTaskID: task.id) }
        .confirmationDialog("删除“\(task.title)”及其后代？", isPresented: $isConfirmingDelete) {
            Button("删除任务", role: .destructive) { store.delete(task) }
            Button("取消", role: .cancel) { }
        } message: {
            let count = TaskTreeProjection.descendants(of: task.id, in: store.tasks).count
            Text(count == 0 ? "此操作无法撤销。" : "该任务及全部 \(count) 项后代任务都会删除。")
        }
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
        case .completed: AppColors.taskCompleted(for: preferences)
        case .cancelled: .orange
        case .postponed: .purple
        case .blocked: .red
        }
    }

    private func primaryAction() {
        if task.isCompleted { store.restore(task) } else { complete(task) }
    }

    private func complete(_ task: TaskItem) {
        if let onCompleteTask { onCompleteTask(task) } else { store.markCompleted(task) }
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

struct TaskChildQuickAddView: View {
    @AppDismiss private var dismiss
    @EnvironmentObject private var store: TaskStore
    let parentTaskID: UUID
    @State private var title = ""
    @State private var error: String?

    private var parent: TaskItem? { store.tasks.first { $0.id == parentTaskID } }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x4) {
            Text("添加子任务").font(AppTypography.title)
            if let parent {
                Text("归属：\(TaskTreeProjection.path(to: parent.id, in: store.tasks).map(\.title).joined(separator: " › "))")
                    .font(AppTypography.callout)
                    .foregroundStyle(.secondary)
            }
            TextField("子任务名称", text: $title)
                .onSubmit(add)
            if let error { Text(error).foregroundStyle(AppColors.danger).font(AppTypography.caption) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("添加", action: add)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppSpacing.page)
        .frame(width: 430)
    }

    private func add() {
        guard store.addChild(title: title, to: parentTaskID) else {
            error = store.actionMessage ?? "无法添加子任务。"
            store.actionMessage = nil
            return
        }
        dismiss()
    }
}

#Preview("新增下级任务") {
    let store = TaskStore(inMemory: true)
    let parent = TaskItem(title: "准备新版首页发布", quadrant: .schedule)
    store.add(parent)
    return TaskChildQuickAddView(parentTaskID: parent.id)
        .environmentObject(store)
}

struct BlockTaskEditor: View {
    @AppDismiss private var dismiss
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
    let onAddTask: () -> Void
    var tasks: [TaskItem] { store.tasks.filter(\.isUnscheduled).sorted { $0.createdAt > $1.createdAt } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.section) {
                PageHeader(eyebrow: "CAPTURE", title: "收集箱", description: "快速记下，稍后再判断优先级")
                if tasks.isEmpty {
                    AppEmptyState(title: "收集箱里还没有事项",
                                  message: "新建事项时选择“暂不安排”，就可以先收集、稍后再规划。",
                                  systemImage: "tray", actionTitle: "收集事项", action: onAddTask)
                        .frame(maxWidth: .infinity, minHeight: 240)
                } else {
                    TaskList(tasks: tasks, onSelect: onSelect)
                }
            }.padding(AppSpacing.x8)
        }
    }
}

struct ReportLanding: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let onGenerate: () -> Void
    @State private var selectedReport: DailyReportItem?
    @State private var isReviewPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom) {
                    PageHeader(eyebrow: "REPORTS", title: "日报与复盘", description: "记录计划执行、会议结论和明日重点。")
                    Spacer()
                    AppButton(title: "新建复盘", systemImage: "calendar.badge.checkmark",
                              kind: .secondary, tint: preferences.accentColor) {
                        isReviewPresented = true
                    }
                    if !store.reports.isEmpty {
                        AppButton(title: "生成今日日报", systemImage: "sparkles", tint: preferences.accentColor,
                                  action: onGenerate)
                    }
                }
                if !store.weeklyReviews.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("复盘记录").font(AppTypography.title)
                        ForEach(store.weeklyReviews.prefix(4)) { review in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(review.weekStart.formatted(.dateTime.year().month().day()) + " · " + review.effectivePeriod.title + "复盘")
                                    .font(AppTypography.headline)
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
                    AppEmptyState(title: "记录今天的进展", message: "生成并保存日报后，可以在这里回顾。",
                                  systemImage: "doc.text", actionTitle: "生成今日日报",
                                  tint: preferences.accentColor, action: onGenerate)
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
                                    Text("\(report.content.count) 字").font(AppTypography.caption).foregroundStyle(.secondary)
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
        .appDialog(item: $selectedReport) { ReportDetailView(report: $0) }
        .appDialog(isPresented: $isReviewPresented) {
            ReviewEditor()
        }
    }
}

struct ReportDetailView: View {
    @AppDismiss private var dismiss
    let report: DailyReportItem

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading) {
                    Text(report.reportDate.formatted(date: .long, time: .omitted)).font(.title2.weight(.bold))
                    Text("字数范围 \(report.minimumLength)～\(report.maximumLength) · 实际 \(report.content.count) 字")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
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


struct QuickCompletedEditor: View {
    @AppDismiss private var dismiss
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
                        .font(AppTypography.caption).foregroundStyle(.secondary)
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
    @AppDismiss private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var content = ""
    @State private var supplement = ""
    @State private var template: ReportTemplatePreset = .classic
    @State private var filtersCategories = false
    @State private var selectedCategories: Set<String> = []
    @State private var lengthPreset: ReportLengthPreset = .short
    @State private var customMinimum = 125
    @State private var customMaximum = 180
    @State private var savedContent: String?
    @State private var savedReportID: UUID?
    @State private var lastGeneratedContent = ""
    @State private var showReplaceConfirmation = false
    @State private var showDiscardConfirmation = false
    @State private var generationID = UUID()
    @State private var generationTask: Task<Void, Never>?

    private var candidateTasks: [TaskItem] {
        ReportSourceBuilder.candidates(today: store.todayTasks, completed: store.completedToday,
                                       processed: store.processedToday)
    }
    private var categoryKeys: [String] {
        Array(Set(candidateTasks.map { $0.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "" }))
            .sorted { $0.isEmpty ? true : $1.isEmpty ? false : $0 < $1 }
    }
    private var sourceTasks: [TaskItem] {
        filtersCategories ? candidateTasks.filter {
            selectedCategories.contains($0.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "")
        } : candidateTasks
    }
    private var canGenerate: Bool {
        lengthIsValid && (!sourceTasks.isEmpty || !supplement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var selectedMinimum: Int { lengthPreset == .custom ? customMinimum : lengthPreset.range.lowerBound }
    private var selectedMaximum: Int { lengthPreset == .custom ? customMaximum : lengthPreset.range.upperBound }
    private var lengthIsValid: Bool { (50...3000).contains(selectedMinimum) && selectedMaximum >= selectedMinimum && selectedMaximum <= 5000 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text("今日日报").font(.title2.weight(.bold))
                    Text("选择模板和今日关联分类，确认来源后生成。")
                        .font(AppTypography.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { requestClose() }
            }
            .padding(AppSpacing.x6)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.x5) {
                    Picker("日报模板", selection: $template) {
                        ForEach(ReportTemplatePreset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    HStack {
                        Label("今日关联分类", systemImage: "tag")
                            .font(AppTypography.headline)
                        Spacer()
                        Text("\(sourceTasks.count) / \(candidateTasks.count) 项来源")
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                    }
                    Toggle("全部类别", isOn: Binding(
                        get: { !filtersCategories },
                        set: { filtersCategories = !$0 }
                    ))
                        .onChange(of: filtersCategories) { _, filters in
                            if filters { selectedCategories = Set(categoryKeys) }
                        }
                    if filtersCategories {
                        if categoryKeys.isEmpty {
                            Text("今天尚无关联任务分类，可填写补充内容。")
                                .foregroundStyle(.secondary)
                        } else {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140))], alignment: .leading,
                                      spacing: AppSpacing.x2) {
                                ForEach(categoryKeys, id: \.self) { key in
                                    Toggle(key.isEmpty ? "未分类" : key, isOn: Binding(
                                        get: { selectedCategories.contains(key) },
                                        set: { selected in
                                            if selected { selectedCategories.insert(key) }
                                            else { selectedCategories.remove(key) }
                                        }
                                    ))
                                }
                            }
                        }
                    }
                    if !sourceTasks.isEmpty {
                        Text(sourceTasks.prefix(6).map(\.title).joined(separator: " · ") +
                             (sourceTasks.count > 6 ? " 等" : ""))
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                    DisclosureGroup("字数设置") {
                        HStack(spacing: AppSpacing.x3) {
                            Picker("字数", selection: $lengthPreset) {
                                ForEach(ReportLengthPreset.allCases) { Text($0.rawValue).tag($0) }
                            }
                            .pickerStyle(.segmented)
                            if lengthPreset == .custom {
                                TextField("最少", value: $customMinimum, format: .number).frame(width: 62)
                                Text("～").foregroundStyle(.secondary)
                                TextField("最多", value: $customMaximum, format: .number).frame(width: 62)
                            } else {
                                Text("\(selectedMinimum)～\(selectedMaximum) 字")
                                    .font(AppTypography.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !lengthIsValid {
                        Text("最少字数须在 50～3000 之间；最多字数不得小于最少字数且不超过 5000。")
                            .font(AppTypography.caption).foregroundStyle(AppColors.danger)
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.x2) {
                        Label("日报补充", systemImage: "text.badge.plus")
                            .font(AppTypography.headline)
                        TextField("会议信息、结论、风险或想强调的内容…", text: $supplement, axis: .vertical)
                            .lineLimit(3...6)
                            .textFieldStyle(.plain)
                            .padding(AppSpacing.x3)
                            .background(preferences.cardBackground,
                                        in: RoundedRectangle(cornerRadius: AppRadius.control))
                            .overlay(RoundedRectangle(cornerRadius: AppRadius.control).stroke(AppColors.border))
                    }
                    Divider()
                    if store.isReportLoading {
                        ProgressView("正在生成日报…").frame(maxWidth: .infinity, minHeight: 80)
                    }
                    if let error = store.reportError {
                        Label(error, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(AppColors.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if content.isEmpty && !store.isReportLoading {
                        AppEmptyState(title: sourceTasks.isEmpty ? "还没有可生成的内容" : "可以生成日报了",
                                      message: sourceTasks.isEmpty ? "选择今日任务分类或填写日报补充。" : "当前选中的任务与补充内容将作为生成来源。",
                                      systemImage: "doc.text")
                            .frame(maxWidth: .infinity, minHeight: 170)
                    } else if !content.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.x2) {
                            Label("日报正文 · 可编辑", systemImage: "square.and.pencil")
                                .font(AppTypography.headline)
                            TextEditor(text: $content)
                                .font(AppTypography.body)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 250)
                                .padding(AppSpacing.x2)
                                .overlay(RoundedRectangle(cornerRadius: AppRadius.control).stroke(AppColors.border))
                        }
                    }
                    if let warning = store.reportLengthWarning {
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(AppTypography.caption).foregroundStyle(AppColors.warning)
                    }
                }
                .padding(AppSpacing.x6)
            }
            Divider()
            HStack {
                if !content.isEmpty {
                    Button("复制 Markdown") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(content, forType: .string) }
                    Button(content == savedContent ? "已保存" : "保存日报", systemImage: content == savedContent ? "checkmark" : "tray.and.arrow.down") {
                        savedReportID = store.saveReport(content: content, supplement: supplement,
                                                         minimumLength: selectedMinimum,
                                                         maximumLength: selectedMaximum,
                                                         updating: savedReportID)
                        savedContent = content
                    }
                    .disabled(content == savedContent)
                    Text("\(content.count) 字").font(AppTypography.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(content.isEmpty ? "生成日报" : "重新生成", systemImage: "sparkles") { requestGeneration() }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isReportLoading || !canGenerate)
            }
            .padding(AppSpacing.x4)
        }
        .font(AppTypography.desktop(.body, scale: preferences.fontScale,
                                    design: preferences.fontStyle.design))
        .frame(width: min(800, (NSScreen.main?.visibleFrame.width ?? 1000) - 80),
               height: min(640, (NSScreen.main?.visibleFrame.height ?? 800) - 160))
        .onAppDialogCancel { requestClose() }
        .onDisappear { generationID = UUID(); generationTask?.cancel() }
        .confirmationDialog("替换已编辑的日报？", isPresented: $showReplaceConfirmation) {
            Button("重新生成", role: .destructive) { generate() }
            Button("保留当前内容", role: .cancel) { }
        } message: { Text("新结果会覆盖当前正文；已保存的历史内容仍可在日报页面查看。") }
        .confirmationDialog("放弃未保存的日报？", isPresented: $showDiscardConfirmation) {
            Button("放弃修改", role: .destructive) { generationID = UUID(); generationTask?.cancel(); dismiss() }
            Button("继续编辑", role: .cancel) { }
        }
    }

    private func requestGeneration() {
        if !content.isEmpty && content != lastGeneratedContent { showReplaceConfirmation = true }
        else { generate() }
    }

    private func generate() {
        let request = ReportRequest(tasks: sourceTasks, template: template, supplement: supplement,
                                    minimumLength: selectedMinimum, maximumLength: selectedMaximum,
                                    sendNotes: preferences.aiSendNotes, sendProject: preferences.aiSendProject)
        let id = UUID()
        generationID = id
        generationTask = Task {
            let result = await store.generateReport(endpoint: preferences.deepSeekEndpoint,
                                                    model: preferences.deepSeekModel, request: request)
            guard generationID == id, let result else { return }
            content = result
            lastGeneratedContent = result
        }
    }

    private func requestClose() {
        if (!content.isEmpty && content != savedContent) ||
            (content.isEmpty && !supplement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
            showDiscardConfirmation = true
        } else {
            generationID = UUID()
            generationTask?.cancel()
            dismiss()
        }
    }
}

struct MenuBarView: View {
    @EnvironmentObject private var store: TaskStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("今天的计划").font(.headline)
                    Text("已完成 \(store.completionText) 项").font(AppTypography.caption).foregroundStyle(.secondary)
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
                        if let days = item.daysRemaining() { Text(days == 0 ? "今天" : "\(days)天").font(AppTypography.caption).foregroundStyle(.secondary) }
                    }
                }
            }
            if store.todayTasks.filter(\.needsAction).isEmpty { Text("今天的待办已处理完毕。🎉").foregroundStyle(.secondary) }
            Divider()
            AddTaskControl(onAddTask: { openComposer(.addTask) }, onAddCompleted: { openComposer(.addCompleted) }, onAddWithAI: { openComposer(.aiTask) })
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
    }

    private func openComposer(_ action: CommandPaletteAction) {
        openWindow(id: "main")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .runCommandFromSettings, object: action.rawValue)
        }
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
                            .font(AppTypography.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .tabItem { Label("通用", systemImage: "gearshape") }

            QuickActionsSettingsView()
                .tabItem { Label("快速操作", systemImage: "command") }

            Form {
                Section("DeepSeek 连接") {
                    SecureField("API Key", text: $store.apiKey)
                    TextField("模型", text: $preferences.deepSeekModel)
                    TextField("图片识别模型", text: $preferences.deepSeekVisionModel)
                    TextField("接口地址", text: $preferences.deepSeekEndpoint)
                    Text("图片识别默认使用 deepseek-flash。选择图片并生成草稿时，图片和补充说明会发送到所设接口；密钥保存在 macOS 钥匙串中。")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
                }
                Section("AI 数据范围") {
                    Toggle("重新规划时发送项目名称", isOn: $preferences.aiSendProject)
                    Toggle("重新规划时发送任务备注", isOn: $preferences.aiSendNotes)
                    Text("任务标题、日期、时长、状态、阻塞原因和蓝图截止日期是重新规划所需字段。完整蓝图生成功能只发送你当次填写的目标。")
                        .font(AppTypography.caption).foregroundStyle(.secondary)
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

private struct QuickActionsSettingsView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Form {
            Section("快速操作") {
                ForEach(CommandPaletteAction.allCases) { command in
                    HStack {
                        Label(command.rawValue, systemImage: command.icon)
                        Spacer()
                        Button("执行") { run(command) }
                    }
                }
            }
            Section("快捷键") {
                Label("打开快速操作面板", systemImage: "command")
                Text("⌘⇧Space")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func run(_ command: CommandPaletteAction) {
        if command == .openWidget {
            openWindow(id: "widget")
            return
        }
        openWindow(id: "main")
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .runCommandFromSettings, object: command.rawValue)
        }
    }
}
