import SwiftUI

struct TodayWorkbenchView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var selectedQuadrant: Quadrant?
    @State private var collapsedTasks: Set<UUID> = []
    @State private var showsProcessed = false

    let onSelect: (TaskItem) -> Void
    let onReport: () -> Void
    let onAddTask: () -> Void

    private var actionableTasks: [TaskItem] {
        TodayBlueprintOrganizer.sortedTasks(store.todayTasks.filter(\.needsAction))
    }
    private var focusTask: TaskItem? {
        actionableTasks.first(where: { $0.isInProgress })
            ?? actionableTasks.first(where: { store.executionBlockReason(for: $0) == nil })
            ?? actionableTasks.first
    }
    private var otherTasks: [TaskItem] {
        actionableTasks.filter { $0.id != focusTask?.id && (selectedQuadrant == nil || $0.quadrant == selectedQuadrant) }
    }
    private var processedTasks: [TaskItem] { store.todayTasks.filter { !$0.needsAction } }
    private var completedCount: Int { store.todayTasks.filter(\.isCompleted).count }
    private var trackableCount: Int { store.todayTasks.filter { !$0.isCancelled }.count }
    private var remainingMinutes: Int { actionableTasks.reduce(0) { $0 + $1.estimatedMinutes } }
    private var isEmpty: Bool { store.todayTasks.isEmpty }
    private var dayProgress: Double { trackableCount == 0 ? 0 : Double(completedCount) / Double(trackableCount) }
    private var anniversary: AnniversaryItem? { store.upcomingAnniversaries.first(where: \.showOnHome) }
    private var nextTask: TaskItem? {
        guard let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: .now) else { return nil }
        return TodayBlueprintOrganizer.sortedTasks(store.tasks.filter {
            !$0.isUnscheduled && $0.needsAction && Calendar.current.isDate($0.scheduledFor, inSameDayAs: tomorrow)
        }).first
    }
    private var motion: Animation? {
        AppTheme.animation(reduceMotion: preferences.reduceMotion || systemReduceMotion)
    }
    private var sectionSpacing: CGFloat {
        switch preferences.density {
        case .compact: AppSpacing.x4
        case .standard: AppSpacing.x5
        case .spacious: AppSpacing.x6
        }
    }

    var body: some View {
        GeometryReader { geometry in
            let railWidth = AppSpacing.x8 * 8 * CGFloat(max(1, preferences.fontScale))
            let showsRail = geometry.size.width >= 880 * max(1, preferences.fontScale)
            ScrollView {
                Group {
                    if isEmpty {
                        emptyPage(height: geometry.size.height)
                    } else {
                        VStack(alignment: .leading, spacing: sectionSpacing) {
                            HStack(alignment: .top, spacing: AppSpacing.x6) {
                                VStack(alignment: .leading, spacing: sectionSpacing) {
                                    pageHeader(showsAdd: true)
                                    if let focusTask { focusCard(focusTask) }
                                    else { allProcessedCard }
                                    actionPanel
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if showsRail {
                                    contextRail.frame(width: railWidth)
                                }
                            }
                            if !showsRail { compactContext }
                        }
                    }
                }
                .frame(maxWidth: AppTheme.contentMaxWidth + AppSpacing.x8 * 12, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(AppSpacing.x7)
            }
        }
        .onChange(of: isEmpty) { _, empty in
            if empty { selectedQuadrant = nil; showsProcessed = false; collapsedTasks.removeAll() }
        }
    }

    private func pageHeader(showsAdd: Bool) -> some View {
        HStack(alignment: .center, spacing: AppSpacing.x5) {
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                Text(Date.now, format: .dateTime.month(.wide).day().weekday(.wide))
                    .todayText(.callout, weight: .semibold)
                    .foregroundStyle(preferences.accentColor)
                Text("今日")
                    .todayText(.largeTitle, weight: .bold)
                    .accessibilityAddTraits(.isHeader)
                if !isEmpty {
                    Text("先推进重点，再从容处理其余事项。")
                        .todayText(.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            if showsAdd { addButton }
        }
    }

    private var addButton: some View {
        AppButton(title: "添加事项", systemImage: "plus", size: .prominent,
                  tint: preferences.accentColor, action: onAddTask)
            .help("添加事项（⌘N）")
            .accessibilityHint("打开创建弹窗，可切换待办、已完成和 AI 生成类型")
    }

    private func emptyPage(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            pageHeader(showsAdd: false)
            Divider().padding(.top, AppSpacing.x6)
            VStack(spacing: 0) {
                Spacer(minLength: AppSpacing.x8)
                VStack(spacing: 0) {
                    Image(systemName: "sun.horizon")
                        .resizable().scaledToFit()
                        .frame(width: AppSpacing.x8 * 2, height: AppSpacing.x6 * 2)
                        .foregroundStyle(preferences.accentColor)
                        .accessibilityHidden(true)
                        .padding(.bottom, AppSpacing.x8)
                    Text("今天还没有安排事项")
                        .todayText(.title1, weight: .semibold)
                        .padding(.bottom, AppSpacing.x3)
                    Text("从一件重要的事开始，安排好今天的节奏。")
                        .todayText(.body)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    addButton.padding(.top, AppSpacing.x6)
                    HStack(spacing: AppSpacing.x2) {
                        shortcutKey("⌘")
                        shortcutKey("N")
                        Text("快速添加").foregroundStyle(AppColors.textSecondary)
                    }
                    .todayText(.caption1)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("快捷键 Command N，快速添加事项")
                    .padding(.top, AppSpacing.x3)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                if let anniversary {
                    VStack(spacing: AppSpacing.x5) {
                        Divider()
                        anniversaryRow(anniversary, showsHeading: true)
                    }
                    .frame(maxWidth: AppTheme.contentMaxWidth * 0.8)
                    .frame(maxWidth: .infinity)
                    .padding(.top, AppSpacing.x8 * 2)
                }
                Spacer(minLength: AppSpacing.x8)
            }
            .frame(minHeight: max(AppSpacing.x8 * 14, height - AppSpacing.x8 * 5))
        }
    }

    private func shortcutKey(_ title: String) -> some View {
        Text(title)
            .padding(.horizontal, AppSpacing.x2)
            .padding(.vertical, AppSpacing.x1)
            .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.small))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.small).stroke(AppColors.border.opacity(0.5)))
    }

    private func focusCard(_ task: TaskItem) -> some View {
        panel {
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.x3) { focusLabel(task); priorityBadge(task.quadrant) }
                    VStack(alignment: .leading, spacing: AppSpacing.x2) { focusLabel(task); priorityBadge(task.quadrant) }
                }
                Button { onSelect(task) } label: {
                    Text(task.title)
                        .todayText(.title2, weight: .semibold)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("查看或编辑事项")
                focusMetadata(task)
                if let reason = store.executionBlockReason(for: task) {
                    Label(reason, systemImage: "lock")
                        .todayText(.caption1)
                        .foregroundStyle(AppColors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.x4) {
                        Text(task.isInProgress ? "专注当前，稳步推进。" : "优先完成这一项。")
                            .todayText(.caption1).foregroundStyle(AppColors.textSecondary)
                        Spacer(minLength: 0)
                        focusAction(task)
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.x3) { focusAction(task) }
                }
            }
        }
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: AppRadius.control)
                .fill(preferences.accentColor.opacity(0.55))
                .frame(width: AppSpacing.x1)
                .padding(.vertical, AppSpacing.x2)
        }
    }

    private func focusLabel(_ task: TaskItem) -> some View {
        Label(task.isInProgress ? "正在执行" : "当前重点", systemImage: "scope")
            .todayText(.headline, weight: .semibold)
            .foregroundStyle(preferences.accentColor)
    }

    private func priorityBadge(_ quadrant: Quadrant) -> some View {
        Label { Text(quadrant.title) } icon: {
            Circle().fill(preferences.color(for: quadrant)).frame(width: AppSpacing.x2, height: AppSpacing.x2)
        }
        .todayText(.caption1, weight: .medium)
        .foregroundStyle(AppColors.textPrimary)
        .padding(.horizontal, AppSpacing.x2)
        .padding(.vertical, AppSpacing.x1)
        .background(preferences.color(for: quadrant).opacity(0.09), in: Capsule())
    }

    private func focusMetadata(_ task: TaskItem) -> some View {
        let parent = TaskTreeProjection.path(to: task.id, in: store.tasks).dropLast().last
        return ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.x3) {
                if let parent {
                    Label("父任务：\(parent.title)", systemImage: "point.3.connected.trianglepath.dotted")
                }
                Label("预计 \(task.estimatedMinutes) 分钟", systemImage: "clock")
                if let due = task.dueDate { Label(dueText(due), systemImage: "calendar") }
            }
            .fixedSize()
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                if let parent {
                    Label("父任务：\(parent.title)", systemImage: "point.3.connected.trianglepath.dotted")
                        .fixedSize(horizontal: false, vertical: true)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.x3) {
                        Label("预计 \(task.estimatedMinutes) 分钟", systemImage: "clock")
                        if let due = task.dueDate { Label(dueText(due), systemImage: "calendar") }
                    }
                    .fixedSize()
                    VStack(alignment: .leading, spacing: AppSpacing.x2) {
                        Label("预计 \(task.estimatedMinutes) 分钟", systemImage: "clock")
                        if let due = task.dueDate { Label(dueText(due), systemImage: "calendar") }
                    }
                }
            }
        }
        .todayText(.callout)
        .foregroundStyle(AppColors.textSecondary)
    }

    private func dueText(_ date: Date) -> String {
        if Calendar.current.isDateInToday(date) { return "今天 \(date.formatted(.dateTime.hour().minute()))" }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private func focusAction(_ task: TaskItem) -> some View {
        AppButton(title: task.isInProgress ? "查看事项" : "开始执行",
                  systemImage: task.isInProgress ? "arrow.up.right" : "play.fill",
                  tint: preferences.accentColor) {
            if task.isInProgress { onSelect(task) }
            else { withAnimation(motion) { store.start(task) } }
        }
        .disabled(!task.isInProgress && store.executionBlockReason(for: task) != nil)
        .help(store.executionBlockReason(for: task) ?? (task.isInProgress ? "查看当前事项" : "开始执行当前重点"))
    }

    private var allProcessedCard: some View {
        panel {
            HStack(spacing: AppSpacing.x4) {
                Image(systemName: "checkmark.seal")
                    .todayText(.largeTitle)
                    .foregroundStyle(preferences.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: AppSpacing.x2) {
                    Text("今天的待办已全部处理").todayText(.headline, weight: .semibold)
                    Text("回顾今天的进展，也给自己留一点余量。")
                        .todayText(.callout).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private var actionPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: AppSpacing.x3) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: AppSpacing.x3) {
                        actionHeading
                        Spacer(minLength: 0)
                        if focusTask != nil {
                            Text("当前重点已置顶").todayText(.caption1).foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.x2) { actionHeading }
                }
                quadrantFilters
                Divider()
                if !otherTasks.isEmpty {
                    outline(otherTasks)
                } else if selectedQuadrant != nil {
                    VStack(spacing: AppSpacing.x3) {
                        Text("该象限暂无其他今日事项。")
                            .todayText(.callout).foregroundStyle(AppColors.textSecondary)
                        Button("显示全部事项") { withAnimation(motion) { selectedQuadrant = nil } }
                            .buttonStyle(.plain).foregroundStyle(preferences.accentColor)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppSpacing.x6)
                } else if focusTask != nil {
                    Text("当前重点之外暂无其他待办。")
                        .todayText(.callout).foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, AppSpacing.x5)
                }
                if !processedTasks.isEmpty {
                    if !otherTasks.isEmpty || focusTask != nil || selectedQuadrant != nil { Divider() }
                    Button {
                        withAnimation(motion) { showsProcessed.toggle() }
                    } label: {
                        HStack(spacing: AppSpacing.x3) {
                            Image(systemName: "checkmark.circle")
                            Text("\(processedTasks.allSatisfy(\.isCompleted) ? "已完成" : "已处理") \(processedTasks.count) 项")
                            Spacer()
                            Image(systemName: showsProcessed ? "chevron.up" : "chevron.down")
                        }
                        .todayText(.callout)
                        .foregroundStyle(AppColors.textSecondary)
                        .padding(.vertical, AppSpacing.x2)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(showsProcessed ? "收起" : "展开")已处理事项，\(processedTasks.count) 项")
                    if showsProcessed { outline(processedTasks) }
                }
            }
        }
    }

    private var actionHeading: some View {
        HStack(alignment: .firstTextBaseline, spacing: AppSpacing.x3) {
            Text("今日行动").todayText(.title2, weight: .semibold).accessibilityAddTraits(.isHeader)
            Text("\(focusTask == nil ? "" : "其余 ")\(otherTasks.count) 项待处理")
                .todayText(.caption1).foregroundStyle(AppColors.textSecondary)
        }
    }

    private var quadrantFilters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.x2) { filterButtons }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: AppSpacing.x8 * 4))], alignment: .leading,
                      spacing: AppSpacing.x2) { filterButtons }
        }
    }

    @ViewBuilder private var filterButtons: some View {
        quadrantFilter(nil, title: "全部", count: actionableTasks.count)
        ForEach(Quadrant.allCases) { quadrant in
            quadrantFilter(quadrant, title: quadrant.title, count: actionableTasks.filter { $0.quadrant == quadrant }.count)
        }
    }

    private func quadrantFilter(_ quadrant: Quadrant?, title: String, count: Int) -> some View {
        let selected = selectedQuadrant == quadrant
        return Button {
            withAnimation(motion) { selectedQuadrant = selectedQuadrant == quadrant ? nil : quadrant }
        } label: {
            HStack(spacing: AppSpacing.x2) {
                if let quadrant {
                    Circle().fill(preferences.color(for: quadrant)).frame(width: AppSpacing.x2, height: AppSpacing.x2)
                }
                Text(title)
                Text("\(count)").monospacedDigit()
            }
            .todayText(.caption1, weight: selected ? .semibold : .regular)
            .foregroundStyle(selected ? preferences.accentColor : AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.x2)
            .padding(.vertical, AppSpacing.x2)
            .background(selected ? preferences.accentColor.opacity(0.12) : .clear,
                        in: RoundedRectangle(cornerRadius: AppRadius.small))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(count) 项待处理")
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private func outline(_ tasks: [TaskItem]) -> some View {
        let rows = TodayTaskOutline.rows(tasks: tasks, allTasks: store.tasks, collapsed: collapsedTasks)
        return VStack(spacing: 0) {
            ForEach(rows) { row in
                TodayOutlineRow(row: row, focusID: focusTask?.id, collapsed: collapsedTasks.contains(row.id),
                                onSelect: onSelect) {
                    withAnimation(motion) {
                        if !collapsedTasks.insert(row.id).inserted { collapsedTasks.remove(row.id) }
                    }
                }
                .overlay(alignment: .bottom) {
                    if row.id != rows.last?.id {
                        Divider().opacity(0.5).padding(.leading, CGFloat(min(row.depth, 5)) * AppSpacing.x6)
                    }
                }
            }
        }
    }

    private var contextRail: some View {
        VStack(spacing: AppSpacing.x5) {
            progressPanel
            nextPanel
            daysAndReportPanel
        }
    }

    private var compactContext: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: AppSpacing.x8 * 7))], alignment: .leading,
                  spacing: AppSpacing.x5) {
            progressPanel
            nextPanel
            daysAndReportPanel
        }
    }

    private var progressPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: AppSpacing.x5) {
                Text("今日进度").todayText(.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
                HStack(alignment: .firstTextBaseline, spacing: AppSpacing.x3) {
                    Text("\(completedCount) / \(trackableCount)")
                        .todayText(.largeTitle, weight: .semibold).monospacedDigit()
                    Text("已完成").todayText(.caption1).foregroundStyle(AppColors.textSecondary)
                }
                ProgressView(value: dayProgress)
                    .progressViewStyle(TodayProgressStyle(tint: preferences.accentColor))
                    .accessibilityLabel("今日完成 \(completedCount) 项，共 \(trackableCount) 项")
                Divider()
                HStack(alignment: .top, spacing: AppSpacing.x4) {
                    statistic("待处理", value: actionableTasks.count, unit: "项")
                    Divider()
                    statistic("预计", value: remainingMinutes, unit: "分钟")
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func statistic(_ title: String, value: Int, unit: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            Text(title).todayText(.caption1).foregroundStyle(AppColors.textSecondary)
            HStack(alignment: .firstTextBaseline, spacing: AppSpacing.x1) {
                Text("\(value)").todayText(.title2, weight: .semibold).monospacedDigit()
                Text(unit).todayText(.caption1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var nextPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: AppSpacing.x4) {
                Label("接下来", systemImage: "calendar")
                    .todayText(.headline, weight: .semibold).accessibilityAddTraits(.isHeader)
                if let nextTask {
                    Text("明天").todayText(.caption1).foregroundStyle(AppColors.textSecondary)
                    Button { onSelect(nextTask) } label: {
                        Text(nextTask.title).todayText(.body, weight: .medium)
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("明天还没有安排事项。")
                        .todayText(.callout).foregroundStyle(AppColors.textSecondary)
                }
            }
        }
    }

    private var daysAndReportPanel: some View {
        panel {
            VStack(alignment: .leading, spacing: AppSpacing.x5) {
                if let anniversary {
                    Label("重要日子", systemImage: "heart")
                        .todayText(.headline, weight: .semibold)
                        .accessibilityAddTraits(.isHeader)
                    anniversaryRow(anniversary, showsHeading: false)
                    Divider()
                }
                AppButton(title: "生成今日日报", systemImage: "sparkles", kind: .secondary,
                          tint: preferences.accentColor, action: onReport)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func anniversaryRow(_ item: AnniversaryItem, showsHeading: Bool) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.x4) {
                if showsHeading {
                    Label("重要日子", systemImage: "heart").foregroundStyle(AppColors.textSecondary)
                    Divider().frame(height: AppSpacing.x4)
                }
                Text(item.displayName).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: AppSpacing.x2)
                anniversaryDays(item)
            }
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                if showsHeading { Label("重要日子", systemImage: "heart").foregroundStyle(AppColors.textSecondary) }
                Text(item.displayName).fixedSize(horizontal: false, vertical: true)
                anniversaryDays(item)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .todayText(.callout)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private func anniversaryDays(_ item: AnniversaryItem) -> some View {
        if let days = item.daysRemaining() {
            Text(days == 0 ? "今天" : "还有 \(days) 天")
                .foregroundStyle(preferences.accentColor)
                .fixedSize()
        }
    }

    private func panel<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(AppSpacing.x5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.control)
                .stroke(AppColors.border.opacity(preferences.highContrast ? 1 : 0.2)))
    }
}

private struct TodayOutlineRow: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @State private var isHovered = false
    let row: TodayTaskOutlineRow
    let focusID: UUID?
    let collapsed: Bool
    let onSelect: (TaskItem) -> Void
    let onToggleExpanded: () -> Void

    private var task: TaskItem { row.task }
    private var indent: CGFloat { CGFloat(min(row.depth, 5)) * AppSpacing.x6 }
    private var rowInset: CGFloat {
        switch preferences.density {
        case .compact: AppSpacing.x2
        case .standard: AppSpacing.x3
        case .spacious: AppSpacing.x4
        }
    }
    private var descendants: [TaskItem] { TaskTreeProjection.descendants(of: task.id, in: store.tasks) }
    private var motion: Animation? { AppTheme.animation(reduceMotion: preferences.reduceMotion || systemReduceMotion) }

    var body: some View {
        HStack(spacing: AppSpacing.x2) {
            if row.hasChildren {
                Button(action: onToggleExpanded) {
                    Image(systemName: collapsed ? "chevron.right" : "chevron.down")
                        .todayText(.caption1, weight: .semibold)
                        .frame(width: AppSpacing.x6, height: AppSpacing.x8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textSecondary)
                .help(collapsed ? "展开子任务" : "收起子任务")
                .accessibilityLabel("\(collapsed ? "展开" : "收起")\(task.title)的子任务")
            }
            if row.isContext { contextContent }
            else { taskContent }
        }
        .padding(.leading, indent)
        .padding(.vertical, row.isContext ? AppSpacing.x2 : rowInset)
        .overlay(alignment: .leading) { treeGuides.frame(width: indent).allowsHitTesting(false) }
        .background(isHovered ? preferences.accentColor.opacity(0.045) : .clear,
                    in: RoundedRectangle(cornerRadius: AppRadius.small))
        .onHover { hovering in withAnimation(motion) { isHovered = hovering } }
    }

    private var contextContent: some View {
        HStack(spacing: AppSpacing.x2) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .foregroundStyle(AppColors.textSecondary)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: AppSpacing.x2) {
                    contextTitle
                    contextMetadata
                }
                .fixedSize()
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    contextTitle
                    contextMetadata
                }
            }
            Spacer(minLength: AppSpacing.x2)
            Button { TaskBlueprintNavigation.open(task) } label: {
                Label("查看蓝图", systemImage: "point.3.connected.trianglepath.dotted")
                    .todayText(.caption1)
                    .fixedSize()
                    .padding(.vertical, AppSpacing.x2)
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var contextTitle: some View {
        Text(task.id == focusID ? "当前重点的子任务" : task.title)
            .todayText(.headline, weight: .semibold)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var contextMetadata: some View {
        HStack(spacing: AppSpacing.x2) {
            Text("父任务")
                .padding(.horizontal, AppSpacing.x2)
                .padding(.vertical, AppSpacing.x1)
                .background(AppColors.textSecondary.opacity(0.06), in: Capsule())
            if !descendants.isEmpty { Text("子任务 \(descendants.filter(\.isCompleted).count)/\(descendants.count)") }
            if row.depth > 5 { Text("第 \(row.depth + 1) 层") }
        }
        .todayText(.caption1).foregroundStyle(AppColors.textSecondary)
    }

    private var taskContent: some View {
        HStack(spacing: AppSpacing.x3) {
            Button {
                if task.isCompleted || task.isCancelled { store.restore(task) }
                else { store.markCompleted(task) }
            } label: {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : task.isCancelled ? "xmark.circle" : "circle")
                    .todayText(.title2)
                    .foregroundStyle(task.isCompleted ? AppColors.taskCompleted(for: preferences) : AppColors.textSecondary)
                    .frame(width: AppSpacing.x8, height: AppSpacing.x8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(task.needsAction && store.executionBlockReason(for: task) != nil)
            .help(store.executionBlockReason(for: task) ?? (task.needsAction ? "标记完成" : "恢复为待完成"))
            .accessibilityLabel("\(task.needsAction ? "完成" : "恢复")\(task.title)")
            Button { onSelect(task) } label: {
                VStack(alignment: .leading, spacing: AppSpacing.x2) {
                    Text(task.title)
                        .todayText(.body, weight: .medium)
                        .strikethrough(task.isCompleted || task.isCancelled)
                        .foregroundStyle(AppColors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: AppSpacing.x2) {
                        Circle().fill(preferences.color(for: task.quadrant)).frame(width: AppSpacing.x2, height: AppSpacing.x2)
                        Text(task.needsAction ? task.quadrant.title : task.displayStatusTitle)
                        Text("·")
                        Label("\(task.estimatedMinutes) 分钟", systemImage: "clock")
                    }
                    .todayText(.caption1).foregroundStyle(AppColors.textSecondary)
                    if !descendants.isEmpty {
                        Text("子任务 \(descendants.filter(\.isCompleted).count)/\(descendants.count)")
                            .todayText(.caption1).foregroundStyle(AppColors.textSecondary)
                    }
                    if let reason = store.executionBlockReason(for: task), task.needsAction {
                        Label(reason, systemImage: "lock")
                            .todayText(.caption1).foregroundStyle(AppColors.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("查看或编辑\(task.title)，\(task.displayStatusTitle)")
            Menu {
                if task.needsAction && !task.isInProgress {
                    Button("开始执行", systemImage: "play") { store.start(task) }
                        .disabled(store.executionBlockReason(for: task) != nil)
                }
                if !task.isCompleted {
                    Button("标记完成", systemImage: "checkmark.circle") { store.markCompleted(task) }
                        .disabled(store.executionBlockReason(for: task) != nil)
                }
                if task.needsAction {
                    Button("延期到明天", systemImage: "calendar.badge.clock") { withAnimation(motion) { store.postpone(task) } }
                    Button("取消任务", systemImage: "xmark.circle") { withAnimation(motion) { store.cancel(task) } }
                } else {
                    Button("恢复为待完成", systemImage: "arrow.uturn.backward") { withAnimation(motion) { store.restore(task) } }
                }
                Divider()
                Button("查看蓝图", systemImage: "point.3.connected.trianglepath.dotted") { TaskBlueprintNavigation.open(task) }
                Button("编辑事项", systemImage: "pencil") { onSelect(task) }
            } label: {
                Image(systemName: "ellipsis").frame(width: AppSpacing.x8, height: AppSpacing.x8)
                    .contentShape(Rectangle())
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("更多操作")
            .accessibilityLabel("\(task.title)的更多操作")
        }
    }

    private var treeGuides: some View {
        Canvas { context, size in
            guard row.depth > 0 else { return }
            let depth = min(row.depth, 5)
            var path = Path()
            for level in 0..<depth {
                let x = CGFloat(level) * AppSpacing.x6 + AppSpacing.x3
                if level == depth - 1 {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: row.isLastSibling ? size.height / 2 : size.height))
                    path.move(to: CGPoint(x: x, y: size.height / 2))
                    path.addLine(to: CGPoint(x: x + AppSpacing.x3, y: size.height / 2))
                } else if row.ancestorContinuations.indices.contains(level), row.ancestorContinuations[level] {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                }
            }
            context.stroke(path, with: .color(AppColors.border), lineWidth: 1)
        }
        .accessibilityHidden(true)
    }
}

private struct TodayProgressStyle: ProgressViewStyle {
    let tint: Color

    func makeBody(configuration: Configuration) -> some View {
        GeometryReader { geometry in
            Capsule().fill(AppColors.textSecondary.opacity(0.12))
                .overlay(alignment: .leading) {
                    Capsule().fill(tint)
                        .frame(width: geometry.size.width * min(1, max(0, configuration.fractionCompleted ?? 0)))
                }
        }
        .frame(height: AppSpacing.x1)
    }
}

private struct TodayTextStyle: ViewModifier {
    @EnvironmentObject private var preferences: AppPreferences
    let role: NSFont.TextStyle
    var weight: Font.Weight

    func body(content: Content) -> some View {
        content.font(AppTypography.desktop(role, scale: preferences.fontScale,
                                         weight: weight, design: preferences.fontStyle.design))
    }
}

private extension View {
    func todayText(_ role: NSFont.TextStyle, weight: Font.Weight = .regular) -> some View {
        modifier(TodayTextStyle(role: role, weight: weight))
    }
}

#Preview("今日 · 空状态") {
    TodayWorkbenchView(onSelect: { _ in }, onReport: {}, onAddTask: {})
        .appSurface()
        .environmentObject(TaskStore(inMemory: true))
        .environmentObject(AppPreferences())
        .frame(width: 1050, height: 700)
}

#if DEBUG
/// Preview fixtures only; they never enter the user's persistent store.
@MainActor
enum TodayWorkbenchPreviewData {
    static func populated() -> TaskStore {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "重设计今日页面", quadrant: .schedule, status: .unscheduled)
        let focus = TaskItem(title: "确认今日页视觉方案", quadrant: .doNow,
            dueDate: Calendar.current.date(bySettingHour: 17, minute: 30, second: 0, of: .now),
            estimatedMinutes: 45, parentTaskID: root.id)
        let child = TaskItem(title: "完善任务列表层级", quadrant: .schedule, estimatedMinutes: 25, parentTaskID: root.id)
        let other = TaskItem(title: "适配窄窗口布局", quadrant: .schedule, estimatedMinutes: 20, parentTaskID: root.id)
        let done = TaskItem(title: "梳理现有页面问题", quadrant: .schedule, status: .completed,
                            completedAt: .now, parentTaskID: root.id)
        let doneAgain = TaskItem(title: "确定页面结构", quadrant: .schedule, status: .completed,
                                 completedAt: .now, parentTaskID: root.id)
        let independent = TaskItem(title: "整理本周复盘", quadrant: .delegate, estimatedMinutes: 10)
        let tomorrow = TaskItem(title: "整理下一阶段计划", quadrant: .schedule,
                                scheduledFor: Calendar.current.date(byAdding: .day, value: 1, to: .now)!)
        store.tasks = [root, focus, child, other, done, doneAgain, independent, tomorrow]
        store.anniversaries = [AnniversaryItem(name: "阅读计划纪念日",
            date: Calendar.current.date(byAdding: .day, value: 12, to: .now)!,
            showNotification: false)]
        return store
    }
}

#Preview("今日 · 任务树") {
    TodayWorkbenchView(onSelect: { _ in }, onReport: {}, onAddTask: {})
        .appSurface()
        .environmentObject(TodayWorkbenchPreviewData.populated())
        .environmentObject(AppPreferences())
        .frame(width: 1050, height: 760)
}

#Preview("今日 · 窄窗口与长任务") {
    let store = TodayWorkbenchPreviewData.populated()
    store.tasks[2].title = "核对多层级子任务在窄窗口、长中文标题和放大字号情况下的显示与点击区域"
    return TodayWorkbenchView(onSelect: { _ in }, onReport: {}, onAddTask: {})
        .appSurface()
        .environmentObject(store)
        .environmentObject(AppPreferences())
        .frame(width: 730, height: 680)
}
#endif
