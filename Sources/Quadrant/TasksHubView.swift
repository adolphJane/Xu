import SwiftUI

enum TasksPresentation: String, CaseIterable, Identifiable {
    case list = "列表"
    case quadrants = "四象限"
    var id: Self { self }
}

enum TasksScope: String, CaseIterable, Identifiable {
    case active = "待处理"
    case inbox = "收集箱"
    case processed = "已处理"
    case all = "全部"
    var id: Self { self }

    func includes(_ task: TaskItem, in tasks: [TaskItem]) -> Bool {
        let rootID = TaskTreeProjection.rootID(containing: task.id, in: tasks)
        let seriesTask = tasks.first { $0.id == rootID } ?? task
        return switch self {
        case .active: seriesTask.needsAction
        case .inbox: seriesTask.isUnscheduled && seriesTask.needsAction
        case .processed: seriesTask.isCompleted || seriesTask.isCancelled
        case .all: true
        }
    }
}

/// A single task collection grouped into independently collapsible task series.
struct TasksHubView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Binding var showsBlueprintLibrary: Bool
    let onSelect: (TaskItem) -> Void
    let onAddTask: () -> Void

    @State private var presentation: TasksPresentation = .list
    @State private var scope: TasksScope = .active
    @State private var searchText = ""
    @State private var selectedCategory = "全部分类"
    @State private var expandedSeriesIDs: Set<UUID> = []
    @State private var expandedQuadrantSeries: Set<String> = []
    @State private var completingOriginalTasks: [UUID: TaskItem] = [:]
    @State private var revealedCompletionIDs: Set<UUID> = []
    private enum DetailAction {
        case edit(TaskItem)
        case blueprint(TaskItem)
    }
    @State private var detailTask: TaskItem?
    @State private var pendingDetailAction: DetailAction?

    init(showsBlueprintLibrary: Binding<Bool>, onSelect: @escaping (TaskItem) -> Void,
         onAddTask: @escaping () -> Void, initialPresentation: TasksPresentation = .list,
         initiallyExpandedSeriesIDs: Set<UUID> = [], initialScope: TasksScope = .active) {
        _showsBlueprintLibrary = showsBlueprintLibrary
        self.onSelect = onSelect
        self.onAddTask = onAddTask
        _presentation = State(initialValue: initialPresentation)
        _expandedSeriesIDs = State(initialValue: initiallyExpandedSeriesIDs)
        _scope = State(initialValue: initialScope)
    }

    private func font(_ style: NSFont.TextStyle, weight: Font.Weight = .regular) -> Font {
        AppTypography.desktop(style, scale: preferences.fontScale, weight: weight,
                              design: preferences.fontStyle.design)
    }

    private var cardSpacing: CGFloat {
        switch preferences.density {
        case .compact: AppSpacing.x2
        case .standard: AppSpacing.list
        case .spacious: AppSpacing.x4
        }
    }

    private var categories: [String] {
        Array(Set(store.tasks.map(\.categoryName))).sorted()
    }

    private var matchingSourceTasks: [TaskItem] {
        store.tasks.map { completingOriginalTasks[$0.id] ?? $0 }
    }

    private var displayedTasks: [TaskItem] {
        store.tasks.map { task in
            if let original = completingOriginalTasks[task.id], !revealedCompletionIDs.contains(task.id) {
                return original
            }
            return task
        }
    }

    private var matchedTasks: [TaskItem] {
        let source = matchingSourceTasks
        return source.filter { task in
            scope.includes(task, in: source)
                && (selectedCategory == "全部分类" || task.categoryName == selectedCategory)
                && (searchText.isEmpty || task.title.localizedCaseInsensitiveContains(searchText))
        }
        .sorted {
            if $0.needsAction != $1.needsAction { return $0.needsAction }
            if ($0.dueDate ?? .distantFuture) != ($1.dueDate ?? .distantFuture) {
                return ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture)
            }
            return $0.createdAt > $1.createdAt
        }
    }

    private var listGroups: [TaskSeriesGroup] {
        TaskSeriesProjection.groups(matches: matchedTasks, allTasks: displayedTasks)
    }

    private func seriesCount(for option: TasksScope) -> Int {
        let tasks = store.tasks
        return Set(tasks.filter { option.includes($0, in: tasks) }
            .map { TaskTreeProjection.rootID(containing: $0.id, in: tasks) }).count
    }

    private func completeWithSharedAnimation(_ task: TaskItem) {
        guard !preferences.reduceMotion && !systemReduceMotion else {
            store.markCompleted(task)
            return
        }
        let before = Dictionary(store.tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        store.markCompleted(task)
        let newlyCompleted = store.tasks.filter { $0.isCompleted && before[$0.id]?.isCompleted == false }
        guard !newlyCompleted.isEmpty else { return }
        let ids = Set(newlyCompleted.map(\.id))
        for id in ids { completingOriginalTasks[id] = before[id] }

        var expandedListRoot: UUID?
        var expandedQuadrantKeys: Set<String> = []
        if newlyCompleted.count > 1 {
            let rootID = TaskTreeProjection.rootID(containing: task.id, in: store.tasks)
            if presentation == .list, expandedSeriesIDs.insert(rootID).inserted {
                expandedListRoot = rootID
            } else if presentation == .quadrants {
                for item in newlyCompleted {
                    let key = "\(item.quadrant.rawValue):\(rootID.uuidString)"
                    if expandedQuadrantSeries.insert(key).inserted { expandedQuadrantKeys.insert(key) }
                }
            }
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(60))
            withAnimation(AppTheme.standardAnimation) {
                revealedCompletionIDs.formUnion(ids)
            }
            try? await Task.sleep(for: .milliseconds(450))
            for id in ids { completingOriginalTasks.removeValue(forKey: id) }
            revealedCompletionIDs.subtract(ids)
            if let expandedListRoot { expandedSeriesIDs.remove(expandedListRoot) }
            expandedQuadrantSeries.subtract(expandedQuadrantKeys)
        }
    }

    var body: some View {
        Group {
            if showsBlueprintLibrary {
                VStack(alignment: .leading, spacing: 0) {
                    Button("返回事项", systemImage: "chevron.left") { showsBlueprintLibrary = false }
                        .buttonStyle(.plain)
                        .foregroundStyle(preferences.accentColor)
                        .padding(.horizontal, AppSpacing.x8)
                        .padding(.top, AppSpacing.x4)
                    BlueprintsView()
                }
            } else {
                GeometryReader { geometry in
                    ScrollView {
                        VStack(alignment: .leading, spacing: AppSpacing.section) {
                            header
                            VStack(spacing: AppSpacing.x4) {
                                controls
                                searchControls
                            }
                            if matchedTasks.isEmpty {
                                emptyState
                            } else {
                                VStack(alignment: .leading, spacing: AppSpacing.list) {
                                    resultsHeading
                                    if presentation == .list {
                                        listContent
                                    } else {
                                        quadrantContent(columns: geometry.size.width >= 780 ? 2 : 1)
                                    }
                                    resultsFooter
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.horizontal, AppSpacing.page)
                        .padding(.vertical, AppSpacing.x8)
                    }
                }
            }
        }
        .appDialog(item: $detailTask, onDismiss: performDetailAction) { task in
            taskDetails(store.tasks.first { $0.id == task.id } ?? task)
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: AppSpacing.x4) {
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                Text("事项")
                    .font(AppTypography.desktop(.largeTitle, scale: preferences.fontScale,
                                                weight: .semibold, design: preferences.fontStyle.design))
                Text("收集、安排与推进每一件事。")
                    .font(AppTypography.desktop(.subheadline, scale: preferences.fontScale,
                                                design: preferences.fontStyle.design))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            AppButton(title: "添加事项", systemImage: "plus", size: .prominent,
                      tint: preferences.accentColor, action: onAddTask)
        }
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.x4) {
                scopeButtons
                Spacer(minLength: 0)
                presentationPicker
            }
            VStack(alignment: .leading, spacing: AppSpacing.x3) {
                scopeButtons
                presentationPicker
            }
        }
    }

    private var scopeButtons: some View {
        HStack(spacing: AppSpacing.x1) {
            ForEach(TasksScope.allCases) { option in
                Button {
                    scope = option
                    expandedSeriesIDs.removeAll()
                    expandedQuadrantSeries.removeAll()
                    detailTask = nil
                } label: {
                    HStack(spacing: AppSpacing.x1) {
                        Text(option.rawValue)
                        Text("\(seriesCount(for: option))")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .font(AppTypography.desktop(.subheadline, scale: preferences.fontScale,
                                                weight: scope == option ? .semibold : .regular,
                                                design: preferences.fontStyle.design))
                    .padding(.horizontal, AppSpacing.x3)
                    .frame(minHeight: 32)
                    .background(scope == option ? preferences.accentColor.opacity(0.11) : .clear,
                                in: RoundedRectangle(cornerRadius: AppRadius.small))
                }
                .buttonStyle(.plain)
                .foregroundStyle(scope == option ? preferences.accentColor : AppColors.textSecondary)
                .accessibilityAddTraits(scope == option ? [.isSelected] : [])
            }
        }
    }

    private var presentationPicker: some View {
        Picker("展示方式", selection: $presentation) {
            ForEach(TasksPresentation.allCases) {
                Label($0.rawValue, systemImage: $0 == .list ? "list.bullet" : "square.grid.2x2").tag($0)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 210)
    }

    private var searchControls: some View {
        HStack(spacing: AppSpacing.x3) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索事项", text: $searchText)
                .textFieldStyle(.plain)
                .accessibilityLabel("搜索事项")
            Picker("分类", selection: $selectedCategory) {
                Text("全部分类").tag("全部分类")
                ForEach(categories, id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .frame(maxWidth: 150)
            .accessibilityLabel("按分类筛选")
        }
        .padding(AppSpacing.x3)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.control).stroke(AppColors.border))
    }

    private var emptyState: some View {
        AppEmptyState(
            title: searchText.isEmpty && selectedCategory == "全部分类"
                ? (scope == .inbox ? "收集箱已整理完毕" : scope == .processed ? "还没有已处理事项" : scope == .all ? "还没有事项" : "没有待处理事项")
                : "没有找到匹配的事项",
            message: searchText.isEmpty && selectedCategory == "全部分类"
                ? (scope == .inbox ? "暂不安排日期的事项会出现在这里。" : scope == .processed ? "已完成和已取消的事项会保留在这里。" : "添加一项新的事项，开始下一步。")
                : "试试其他关键词，或清除当前筛选。",
            systemImage: searchText.isEmpty ? "checklist" : "magnifyingglass",
            actionTitle: searchText.isEmpty && selectedCategory == "全部分类" ? nil : "清除筛选",
            tint: preferences.accentColor,
            action: searchText.isEmpty && selectedCategory == "全部分类" ? nil : {
                searchText = ""
                selectedCategory = "全部分类"
            }
        )
        .frame(maxWidth: .infinity, minHeight: 300)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
    }

    private var resultsHeading: some View {
            HStack {
                Text("任务系列")
                    .font(AppTypography.desktop(.headline, scale: preferences.fontScale,
                                                weight: .semibold, design: preferences.fontStyle.design))
                Spacer()
                Text("\(listGroups.count) 个系列 · 含 \(matchedTasks.filter { $0.parentTaskID != nil }.count) 项子任务")
                    .font(font(.caption1).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
    }

    private var listContent: some View {
        LazyVStack(alignment: .leading, spacing: cardSpacing) {
            ForEach(listGroups) { group in
                seriesCard(group)
            }
        }
        .animation(preferences.reduceMotion || systemReduceMotion ? nil : AppTheme.standardAnimation,
                   value: listGroups.map(\.id))
    }

    private var resultsFooter: some View {
        HStack(spacing: AppSpacing.x3) {
            Text(presentation == .list ? "各系列默认收起 · 展开不改变事项总数" : "每项任务按自身象限展示一次")
                .font(font(.caption1))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            blueprintLibraryButton
        }
        .padding(.top, AppSpacing.x2)
    }

    private func quadrantContent(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: AppSpacing.x4, alignment: .top), count: columns),
                  alignment: .leading, spacing: AppSpacing.x4) {
            ForEach(Quadrant.allCases) { quadrant in
                let matches = matchedTasks.filter { $0.quadrant == quadrant }
                let groups = TaskSeriesProjection.groups(matches: matches, allTasks: displayedTasks,
                                                         quadrant: quadrant)
                AppCard(surface: preferences.cardBackground, elevated: false) {
                VStack(alignment: .leading, spacing: AppSpacing.list) {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: AppSpacing.x1) {
                            Text(quadrant.title).font(font(.headline, weight: .semibold))
                            Text(quadrant.subtitle).font(font(.caption1)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(groups.count) 个系列")
                            .font(font(.caption1).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if matches.isEmpty {
                        Text("暂无事项")
                            .font(font(.callout))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 90)
                    } else {
                        ForEach(groups) { group in
                            quadrantSeriesCard(group, quadrant: quadrant)
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 180, alignment: .topLeading)
                }
            }
        }
    }

    private var blueprintLibraryButton: some View {
        Button("蓝图库", systemImage: "point.3.connected.trianglepath.dotted") {
            showsBlueprintLibrary = true
        }
        .buttonStyle(.plain)
        .foregroundStyle(preferences.accentColor)
        .help("查看已有蓝图和任务树")
    }

    private func seriesCard(_ group: TaskSeriesGroup) -> some View {
        let expanded = expandedSeriesIDs.contains(group.id)
        return AppCard(surface: preferences.cardBackground, elevated: false) {
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                seriesHeading(group)
                taskRow(TaskSeriesRow(task: group.root, depth: 0,
                                      isContext: !group.matches.contains { $0.id == group.id }),
                        in: group)
                if group.isSeries && expanded {
                    VStack(spacing: 0) {
                        ForEach(group.rows.filter { $0.id != group.id }) { row in
                            taskRow(row, in: group)
                        }
                    }
                    .animation(preferences.reduceMotion || systemReduceMotion ? nil : AppTheme.standardAnimation,
                               value: group.rows.map(\.id))
                }
            }
        }
        .overlay {
            if expanded {
                RoundedRectangle(cornerRadius: AppRadius.card)
                    .stroke(preferences.accentColor.opacity(0.52), lineWidth: 1)
            }
        }
    }

    private func seriesHeading(_ group: TaskSeriesGroup) -> some View {
        HStack(spacing: AppSpacing.x2) {
            Label(group.isSeries ? "任务系列" : "独立事项",
                  systemImage: group.isSeries ? "point.3.connected.trianglepath.dotted" : "circle.dotted")
            Spacer()
            if group.isSeries {
                Text("\(group.completedDirectChildren)/\(group.directChildrenCount) 子任务已完成")
                    .monospacedDigit()
                if group.blockedCount > 0 { Text("· \(group.blockedCount) 项阻塞") }
            } else {
                Text(group.root.categoryName)
            }
        }
        .font(font(.caption1))
        .foregroundStyle(.secondary)
    }

    private func toggleSeries(_ group: TaskSeriesGroup) {
        withAnimation(preferences.reduceMotion || systemReduceMotion ? nil : AppTheme.standardAnimation) {
            if expandedSeriesIDs.contains(group.id) {
                expandedSeriesIDs.remove(group.id)
            } else {
                expandedSeriesIDs.insert(group.id)
            }
        }
    }

    private func taskRow(_ row: TaskSeriesRow, in group: TaskSeriesGroup) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            HStack(alignment: .top, spacing: AppSpacing.x2) {
                if row.depth == 0 && group.isSeries {
                    Button {
                        toggleSeries(group)
                    } label: {
                        Image(systemName: expandedSeriesIDs.contains(group.id) ? "chevron.down" : "chevron.right")
                            .frame(width: AppSpacing.x4, height: 36)
                    }
                    .buttonStyle(.plain)
                    .offset(y: row.isContext ? -AppSpacing.x2 : 0)
                    .accessibilityLabel("\(expandedSeriesIDs.contains(group.id) ? "收起" : "展开")\(group.root.title)系列")
                    .accessibilityValue(expandedSeriesIDs.contains(group.id) ? "已展开" : "已收起")
                } else {
                    Color.clear.frame(width: AppSpacing.x4, height: 1)
                }
                if row.isContext {
                    HStack(alignment: .top, spacing: AppSpacing.x2) {
                        contextStatusControl(row.task)
                        Button {
                            onSelect(row.task)
                        } label: {
                            VStack(alignment: .leading, spacing: AppSpacing.x1) {
                                Text(row.task.title)
                                    .font(font(.body, weight: .semibold))
                                    .strikethrough(row.task.isCompleted || row.task.isCancelled)
                                Text("\(row.task.displayStatusTitle) · 父任务上下文 · 不计入结果")
                                    .font(font(.caption1))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 36)
                        }
                        .buttonStyle(.plain)
                        Button("查看详情", systemImage: "info.circle") { detailTask = row.task }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.plain)
                            .frame(width: 36, height: 36)
                    }
                } else {
                    TaskCard(task: row.task, embedded: true,
                             onSelect: onSelect,
                             onCompleteTask: completeWithSharedAnimation,
                             completionInProgress: completingOriginalTasks[row.id] != nil,
                             onShowDetails: { detailTask = $0 })
                }
            }
            .padding(.leading, CGFloat(min(row.depth, 6)) * AppSpacing.x6)
            .overlay(alignment: .leading) {
                if row.depth > 0 {
                    GeometryReader { geometry in
                        Path { path in
                            for level in 1...min(row.depth, 6) {
                                let x = CGFloat(level) * AppSpacing.x6 - AppSpacing.x3
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: geometry.size.height))
                            }
                            let x = CGFloat(min(row.depth, 6)) * AppSpacing.x6 - AppSpacing.x3
                            path.move(to: CGPoint(x: x, y: geometry.size.height / 2))
                            path.addLine(to: CGPoint(x: x + AppSpacing.x3, y: geometry.size.height / 2))
                        }
                        .stroke(AppColors.border)
                    }
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
        }
    }

    @ViewBuilder
    private func contextStatusControl(_ task: TaskItem) -> some View {
        let symbol = task.isCompleted ? "checkmark.circle.fill" : task.isCancelled ? "xmark.circle.fill" : "circle"
        let icon = Image(systemName: symbol)
            .font(.title3)
            .foregroundStyle(task.isCompleted ? AppColors.success : AppColors.textSecondary)
            .frame(width: 36, height: 36)
            .contentShape(Rectangle())
        if task.isCompleted {
            Button {
                withAnimation(preferences.reduceMotion || systemReduceMotion ? nil : AppTheme.standardAnimation) {
                    store.restore(task)
                }
            } label: { icon }
                .buttonStyle(.plain)
                .help("恢复为待完成")
                .accessibilityLabel("恢复\(task.title)")
                .offset(y: -AppSpacing.x2)
        } else {
            icon
                .offset(y: -AppSpacing.x2)
                .accessibilityLabel(task.displayStatusTitle)
        }
    }

    private func taskDetails(_ task: TaskItem) -> some View {
        let children = TaskTreeProjection.directChildren(of: task.id, in: store.tasks)
        let parent = task.parentTaskID.flatMap { id in store.tasks.first { $0.id == id } }
        let blockReason = task.needsAction ? store.executionBlockReason(for: task) : nil
        return VStack(spacing: 0) {
            HStack {
                Label("事项详情", systemImage: "square.text.square")
                    .font(font(.headline, weight: .semibold))
                Spacer()
                Button("关闭事项详情", systemImage: "xmark") { detailTask = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .frame(width: 36, height: 36)
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, AppSpacing.page)
            .padding(.vertical, AppSpacing.x3)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.x5) {
                    VStack(alignment: .leading, spacing: AppSpacing.x3) {
                        if let parent {
                            Label("属于 \(parent.title)", systemImage: "arrow.turn.down.right")
                                .font(font(.callout))
                                .foregroundStyle(AppColors.textSecondary)
                                .lineLimit(2)
                        }
                        Text(task.title)
                            .font(font(.title2, weight: .semibold))
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: AppSpacing.x2) {
                            AppBadge(title: task.displayStatusTitle, tone: detailTone(for: task))
                            AppBadge(title: task.quadrant.title, tone: .neutral)
                        }
                    }
                    if let blockReason {
                        Label(blockReason, systemImage: "exclamationmark.octagon")
                            .font(font(.callout))
                            .foregroundStyle(AppColors.warning)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(AppSpacing.x3)
                            .background(AppColors.warning.opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.control))
                    }
                    HStack(alignment: .top, spacing: AppSpacing.x3) {
                        detailTile("计划", value: task.isUnscheduled ? "待安排" : task.scheduledFor.formatted(date: .abbreviated, time: .omitted), symbol: "calendar")
                        detailTile("截止", value: task.dueDate?.formatted(date: .abbreviated, time: .shortened) ?? "未设置", symbol: "calendar.badge.clock")
                    }
                    HStack(alignment: .top, spacing: AppSpacing.x3) {
                        detailTile("分类", value: task.categoryName, symbol: "tag")
                        detailTile("项目", value: task.projectName, symbol: "folder")
                    }
                    HStack(spacing: AppSpacing.x2) {
                        Label("预计 \(task.estimatedMinutes) 分钟", systemImage: "hourglass")
                        if task.planLocked { Label("计划已锁定", systemImage: "lock") }
                    }
                    .font(font(.callout))
                    .foregroundStyle(AppColors.textSecondary)
                    if !children.isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.x3) {
                            HStack {
                                Label("下一步", systemImage: "checklist")
                                    .font(font(.headline, weight: .semibold))
                                Spacer()
                                Text("\(children.filter(\.isCompleted).count) / \(children.count) 已完成")
                                    .font(font(.callout))
                                    .foregroundStyle(AppColors.textSecondary)
                                    .monospacedDigit()
                            }
                            ProgressView(value: Double(children.filter(\.isCompleted).count), total: Double(children.count))
                                .tint(preferences.accentColor)
                                .accessibilityLabel("子任务进度")
                            ForEach(children) { child in
                                HStack(alignment: .top, spacing: AppSpacing.x2) {
                                    Image(systemName: child.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(child.isCompleted ? AppColors.success : AppColors.textSecondary)
                                    Text(child.title)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(child.displayStatusTitle)
                                        .foregroundStyle(AppColors.textSecondary)
                                }
                                .font(font(.callout))
                                .accessibilityElement(children: .combine)
                            }
                        }
                        .padding(AppSpacing.cardContent)
                        .background(preferences.pageBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border))
                    }
                    if !task.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: AppSpacing.x2) {
                            Label("备注", systemImage: "text.alignleft")
                                .font(font(.headline, weight: .semibold))
                            Text(task.notes)
                                .font(font(.body))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(AppSpacing.cardContent)
                        .background(preferences.pageBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
                        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(AppSpacing.page)
            }
            Divider()
            HStack(spacing: AppSpacing.x3) {
                Button("查看任务蓝图", systemImage: "point.3.connected.trianglepath.dotted") {
                    pendingDetailAction = .blueprint(task)
                    detailTask = nil
                }
                if task.needsAction {
                    Menu {
                        Button("标记完成", systemImage: "checkmark.circle") { store.markCompleted(task) }
                            .disabled(blockReason != nil)
                        if !task.isUnscheduled {
                            Button("延期到明天", systemImage: "calendar.badge.clock") { store.postpone(task) }
                        }
                        Button("取消事项", systemImage: "xmark.circle") { store.cancel(task) }
                    } label: {
                        Label("更多操作", systemImage: "ellipsis.circle")
                    }
                    .fixedSize()
                }
                Spacer()
                Button("编辑", systemImage: "pencil") {
                    pendingDetailAction = .edit(task)
                    detailTask = nil
                }
                if task.isCompleted || task.isCancelled {
                    AppButton(title: "恢复事项", systemImage: "arrow.uturn.backward", tint: preferences.accentColor) {
                        store.restore(task)
                    }
                } else if task.isUnscheduled {
                    AppButton(title: "安排到今天", systemImage: "calendar.badge.plus", tint: preferences.accentColor) {
                        store.scheduleToday(task)
                    }
                } else if !task.isInProgress {
                    AppButton(title: "开始执行", systemImage: "play.fill", tint: preferences.accentColor) {
                        store.start(task)
                    }
                    .disabled(blockReason != nil)
                    .help(blockReason ?? "开始执行")
                } else {
                    AppButton(title: "完成事项", systemImage: "checkmark", tint: preferences.accentColor) {
                        store.markCompleted(task)
                    }
                    .disabled(blockReason != nil)
                    .help(blockReason ?? "完成事项")
                }
            }
            .padding(AppSpacing.cardContent)
        }
        .frame(width: 620, height: 560)
        .background(preferences.cardBackground)
        .tint(preferences.accentColor)
    }

    private func detailTile(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            Label(title, systemImage: symbol)
                .font(font(.callout))
                .foregroundStyle(AppColors.textSecondary)
            Text(value)
                .font(font(.body, weight: .medium))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(AppSpacing.cardContent)
        .background(preferences.pageBackground, in: RoundedRectangle(cornerRadius: AppRadius.card))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.card).stroke(AppColors.border))
        .accessibilityElement(children: .combine)
    }

    private func detailTone(for task: TaskItem) -> AppBadge.Tone {
        switch task.effectiveStatus {
        case .completed: .success
        case .blocked: .danger
        case .postponed: .warning
        default: .neutral
        }
    }

    private func performDetailAction() {
        let action = pendingDetailAction
        pendingDetailAction = nil
        switch action {
        case .edit(let task): onSelect(task)
        case .blueprint(let task): TaskBlueprintNavigation.open(task)
        case nil: break
        }
    }

    private func quadrantSeriesCard(_ group: TaskSeriesGroup, quadrant: Quadrant) -> some View {
        let key = "\(quadrant.rawValue):\(group.id.uuidString)"
        let expanded = expandedQuadrantSeries.contains(key)
        return VStack(alignment: .leading, spacing: AppSpacing.x2) {
                Button {
                    if expanded { expandedQuadrantSeries.remove(key) }
                    else { expandedQuadrantSeries.insert(key) }
                } label: {
                    HStack(alignment: .top, spacing: AppSpacing.x2) {
                        VStack(alignment: .leading, spacing: AppSpacing.x1) {
                            Text(group.root.title).font(font(.body, weight: .semibold))
                            Text("\(group.matches.count) 项 · \(group.isSeries ? "任务系列" : "独立事项")")
                                .font(font(.caption1)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(expanded ? "收起" : "展开")\(group.root.title)在\(quadrant.title)中的事项")
                .accessibilityValue(expanded ? "已展开" : "已收起")
                if expanded {
                    Divider()
                    ForEach(group.rows) { row in
                        TaskCard(task: row.task, embedded: true,
                                 onSelect: onSelect,
                                 onCompleteTask: completeWithSharedAnimation,
                                 completionInProgress: completingOriginalTasks[row.id] != nil,
                                 onShowDetails: { detailTask = $0 })
                    }
                }
        }
        .padding(AppSpacing.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(preferences.pageBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.control)
            .stroke(expanded ? preferences.accentColor.opacity(0.52) : AppColors.border))
    }
}

#Preview("事项 · 系列默认收起") {
    let store = TaskStore(inMemory: true)
    let root = TaskItem(title: "准备新版首页发布", quadrant: .doNow)
    store.add(root)
    _ = store.addChild(title: "确认事项页面", to: root.id)
    _ = store.addChild(title: "适配窄窗口", to: root.id)
    store.add(TaskItem(title: "整理本周复盘", quadrant: .schedule))
    return TasksHubView(showsBlueprintLibrary: .constant(false), onSelect: { _ in }, onAddTask: {})
        .environmentObject(store)
        .environmentObject(AppPreferences())
        .frame(width: 1000, height: 700)
}
