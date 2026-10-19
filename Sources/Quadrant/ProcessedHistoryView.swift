import SwiftUI

enum ProcessedDateRange: String, CaseIterable, Identifiable {
    case today = "今天"
    case sevenDays = "近 7 天"
    case all = "全部"

    var id: Self { self }
}

enum ProcessedStatusFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case completed = "已完成"
    case cancelled = "已取消"
    case postponed = "已延期"

    var id: Self { self }

    func includes(_ task: TaskItem) -> Bool {
        switch self {
        case .all: task.isCompleted || task.isCancelled || task.effectiveStatus == .postponed
        case .completed: task.isCompleted
        case .cancelled: task.isCancelled
        case .postponed: task.effectiveStatus == .postponed
        }
    }
}

enum ProcessedHistoryProjection {
    static func processedAt(_ task: TaskItem) -> Date? {
        switch task.effectiveStatus {
        case .completed: task.completedAt ?? task.statusChangedAt
        case .cancelled, .postponed: task.statusChangedAt
        default: nil
        }
    }

    static func tasks(_ tasks: [TaskItem], in range: ProcessedDateRange,
                      status: ProcessedStatusFilter = .all, now: Date = .now,
                      calendar: Calendar = .current) -> [TaskItem] {
        let startOfSevenDays = calendar.date(byAdding: .day, value: -6,
                                             to: calendar.startOfDay(for: now)) ?? now
        return tasks.filter { task in
            guard status.includes(task) else { return false }
            switch range {
            case .all: return true
            case .today:
                return processedAt(task).map { calendar.isDate($0, inSameDayAs: now) } == true
            case .sevenDays:
                return processedAt(task).map { $0 >= startOfSevenDays && $0 <= now } == true
            }
        }
        .sorted {
            let left = processedAt($0) ?? .distantPast
            let right = processedAt($1) ?? .distantPast
            if left != right { return left > right }
            return $0.id.uuidString < $1.id.uuidString
        }
    }
}

struct CompletedView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var range: ProcessedDateRange = .today
    @State private var status: ProcessedStatusFilter = .all
    @State private var selectedTaskID: UUID?
    let onSelect: (TaskItem) -> Void

    private var rangeTasks: [TaskItem] {
        ProcessedHistoryProjection.tasks(store.tasks, in: range)
    }

    private var visibleTasks: [TaskItem] {
        rangeTasks.filter(status.includes)
    }

    private var selectedTask: TaskItem? {
        visibleTasks.first { $0.id == selectedTaskID } ?? visibleTasks.first
    }

    private var timeColumnWidth: CGFloat { range == .today ? 72 : 120 }

    private func font(_ style: NSFont.TextStyle, weight: Font.Weight = .regular) -> Font {
        AppTypography.desktop(style, scale: preferences.fontScale, weight: weight,
                              design: preferences.fontStyle.design)
    }

    var body: some View {
        GeometryReader { geometry in
            let contentWidth = max(0, geometry.size.width - AppSpacing.page * 2)
            let detailWidth = min(320, max(280, contentWidth * 0.30))
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.section) {
                    header
                    controls(detailWidth: detailWidth, hasDetail: !visibleTasks.isEmpty && geometry.size.width >= 850)
                    if visibleTasks.isEmpty {
                        emptyState
                    } else if geometry.size.width >= 850 {
                        HStack(alignment: .top, spacing: AppSpacing.list) {
                            historyList(compact: geometry.size.width < 1080)
                                .frame(maxWidth: .infinity)
                            if let selectedTask {
                                detailPanel(for: selectedTask)
                                    .frame(width: detailWidth)
                            }
                        }
                    } else {
                        VStack(spacing: AppSpacing.list) {
                            historyList(compact: true)
                            if let selectedTask { detailPanel(for: selectedTask) }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, AppSpacing.page)
                .padding(.vertical, AppSpacing.x8)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            Text(range == .today ? "今天的处理" : "已处理")
                .font(font(.largeTitle, weight: .semibold))
            Text("完成、取消与延期，按处理时间记录。")
                .font(font(.subheadline))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func controls(detailWidth: CGFloat, hasDetail: Bool) -> some View {
        Group {
            if hasDetail {
                HStack(alignment: .center, spacing: AppSpacing.list) {
                    HStack(spacing: AppSpacing.x2) {
                        summary
                        Spacer(minLength: AppSpacing.x2)
                        rangeControl.fixedSize()
                    }
                    .frame(maxWidth: .infinity)
                    statusControl
                        .frame(width: detailWidth, alignment: .trailing)
                }
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: AppSpacing.x4) {
                        summary
                        Spacer(minLength: AppSpacing.x2)
                        filters
                    }
                    VStack(alignment: .leading, spacing: AppSpacing.x3) {
                        summary
                        filters
                    }
                }
            }
        }
    }

    private var summary: some View {
        Text("\(range == .today ? "今天处理" : range == .sevenDays ? "近 7 天处理" : "共处理") \(rangeTasks.count) 项 · 完成 \(rangeTasks.filter(\.isCompleted).count) · 取消 \(rangeTasks.filter(\.isCancelled).count) · 延期 \(rangeTasks.filter { $0.effectiveStatus == .postponed }.count)")
            .font(font(.subheadline))
            .foregroundStyle(AppColors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var filters: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: AppSpacing.x4) {
                rangeControl
                statusControl
            }
            VStack(alignment: .leading, spacing: AppSpacing.x2) {
                rangeControl
                statusControl
            }
        }
    }

    private var rangeControl: some View {
        HStack(spacing: AppSpacing.x1) {
            ForEach(ProcessedDateRange.allCases) { option in
                filterButton(option.rawValue, selected: range == option) {
                    range = option
                    selectedTaskID = nil
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("时间范围")
    }

    private var statusControl: some View {
        HStack(spacing: AppSpacing.x1) {
            ForEach(ProcessedStatusFilter.allCases) { option in
                filterButton(option.rawValue, selected: status == option) {
                    status = option
                    selectedTaskID = nil
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("处理结果")
    }

    private func filterButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(font(.subheadline, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? preferences.accentColor : AppColors.textSecondary)
                .padding(.horizontal, AppSpacing.x3)
                .frame(minHeight: 32)
                .background(selected ? preferences.accentColor.opacity(0.11) : .clear,
                            in: RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var emptyState: some View {
        AppCard(surface: preferences.cardBackground, elevated: false) {
            AppEmptyState(
                title: rangeTasks.isEmpty ? "这个时间范围还没有已处理事项" : "没有符合条件的事项",
                message: rangeTasks.isEmpty ? "完成、取消或延期的事项会显示在这里。" : "试试切换处理结果。",
                systemImage: "checkmark.circle"
            )
            .frame(maxWidth: .infinity, minHeight: 300)
        }
    }

    private func historyList(compact: Bool) -> some View {
        AppCard(surface: preferences.cardBackground, elevated: false) {
            LazyVStack(spacing: 0) {
                if !compact {
                    HStack(spacing: AppSpacing.x3) {
                        Text("处理时间").frame(width: timeColumnWidth, alignment: .leading)
                        Text("状态").frame(width: 90, alignment: .leading)
                        Text("事项标题")
                        Spacer()
                        Text("所属路径").frame(width: 85, alignment: .leading)
                    }
                    .font(font(.caption1))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.horizontal, AppSpacing.x2)
                    .padding(.vertical, AppSpacing.x3)
                    Divider()
                }
                ForEach(visibleTasks) { task in
                    Button { selectedTaskID = task.id } label: {
                        historyRow(task, compact: compact)
                            .padding(.horizontal, AppSpacing.x2)
                            .padding(.vertical, AppSpacing.x4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(selectedTask?.id == task.id ? preferences.accentColor.opacity(0.10) : .clear,
                                        in: RoundedRectangle(cornerRadius: AppRadius.small))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(task.title)，\(task.displayStatusTitle)，\(taskPath(task))，\(processedTime(task))")
                    .accessibilityHint("选择后显示处理详情")
                    .accessibilityAddTraits(selectedTask?.id == task.id ? [.isSelected] : [])
                    .help("选择事项并查看处理详情")
                    if task.id != visibleTasks.last?.id { Divider() }
                }
            }
        }
    }

    private func historyRow(_ task: TaskItem, compact: Bool) -> some View {
        Group {
            if compact {
                HStack(alignment: .center, spacing: AppSpacing.x3) {
                    statusSymbol(task)
                    VStack(alignment: .leading, spacing: AppSpacing.x1) {
                        Text(task.title).font(font(.body, weight: .semibold))
                        HStack(spacing: AppSpacing.x2) {
                            Text(task.displayStatusTitle).foregroundStyle(statusColor(task))
                            Text(taskPath(task)).foregroundStyle(AppColors.textSecondary)
                            Text(processedTime(task)).foregroundStyle(AppColors.textSecondary)
                        }
                        .font(font(.caption1))
                    }
                    Spacer(minLength: AppSpacing.x1)
                    Image(systemName: "chevron.right").foregroundStyle(AppColors.textSecondary)
                }
            } else {
                HStack(spacing: AppSpacing.x3) {
                    Text(processedTime(task))
                        .font(font(.subheadline))
                        .foregroundStyle(AppColors.textSecondary)
                        .monospacedDigit()
                        .frame(width: timeColumnWidth, alignment: .leading)
                    HStack(spacing: AppSpacing.x1) {
                        statusSymbol(task)
                        Text(task.displayStatusTitle)
                            .font(font(.subheadline))
                            .lineLimit(1)
                    }
                    .foregroundStyle(statusColor(task))
                    .frame(width: 90, alignment: .leading)
                    Text(task.title)
                        .font(font(.body, weight: .semibold))
                        .lineLimit(2)
                    Spacer(minLength: AppSpacing.x1)
                    Text(taskPath(task))
                        .font(font(.subheadline))
                        .foregroundStyle(AppColors.textSecondary)
                        .lineLimit(1)
                        .frame(width: 85, alignment: .leading)
                    Image(systemName: "chevron.right")
                        .foregroundStyle(AppColors.textSecondary)
                }
            }
        }
        .contentShape(Rectangle())
    }

    private func detailPanel(for task: TaskItem) -> some View {
        let children = TaskTreeProjection.directChildren(of: task.id, in: store.tasks)
        let completedChildren = children.filter(\.isCompleted).count
        let rootID = TaskTreeProjection.rootID(containing: task.id, in: store.tasks)
        let root = store.tasks.first { $0.id == rootID }
        return AppCard(surface: preferences.cardBackground, elevated: false) {
            VStack(alignment: .leading, spacing: AppSpacing.x4) {
                VStack(alignment: .leading, spacing: AppSpacing.x3) {
                    Text(task.title)
                        .font(font(.title2, weight: .semibold))
                        .fixedSize(horizontal: false, vertical: true)
                    Label(task.displayStatusTitle, systemImage: statusIcon(task))
                        .font(font(.subheadline, weight: .semibold))
                        .foregroundStyle(statusColor(task))
                        .padding(.horizontal, AppSpacing.x2)
                        .padding(.vertical, AppSpacing.x1)
                        .background(statusColor(task).opacity(0.10), in: RoundedRectangle(cornerRadius: AppRadius.small))
                }
                Divider()
                if !children.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.x2) {
                        HStack {
                            Text("子任务进度").font(font(.headline, weight: .semibold))
                            Spacer()
                            Text("\(completedChildren)/\(children.count)")
                                .font(font(.subheadline))
                                .monospacedDigit()
                        }
                        ProgressView(value: Double(completedChildren), total: Double(children.count))
                            .tint(preferences.accentColor)
                            .accessibilityLabel("子任务进度")
                            .accessibilityValue("已完成 \(completedChildren) 项，共 \(children.count) 项")
                        Text("已完成 \(completedChildren) 项 · 待处理 \(children.count - completedChildren) 项")
                            .font(font(.caption1))
                            .foregroundStyle(AppColors.textSecondary)
                    }
                    Divider()
                }
                VStack(spacing: AppSpacing.x3) {
                    if let root, root.id != task.id { detailRow("所属系列", value: root.title) }
                    detailRow("处理时间", value: processedDateTime(task))
                    if let dueDate = task.dueDate {
                        detailRow("截止时间", value: dueDate.formatted(.dateTime.month().day().weekday(.wide)))
                    }
                    Divider()
                    detailRow("所属分类", value: task.categoryName)
                    detailRow("象限", value: task.quadrant.title)
                    detailRow("预计用时", value: "\(task.estimatedMinutes) 分钟")
                    let notes = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notes.isEmpty { detailRow("备注", value: notes) }
                }
                Divider()
                HStack(spacing: AppSpacing.x2) {
                    AppButton(title: "查看事项", systemImage: "arrow.up.right.square", size: .regular,
                              tint: preferences.accentColor) { onSelect(task) }
                    AppButton(title: "恢复为待完成", systemImage: "arrow.uturn.backward", kind: .secondary,
                              size: .regular, tint: preferences.accentColor) { store.restore(task) }
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .frame(maxWidth: .infinity, minHeight: 490, alignment: .topLeading)
        }
    }

    private func detailRow(_ title: String, value: String) -> some View {
        HStack(alignment: .top, spacing: AppSpacing.x3) {
            Text(title)
                .font(font(.subheadline))
                .foregroundStyle(AppColors.textSecondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(font(.subheadline))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func taskPath(_ task: TaskItem) -> String {
        let path = TaskTreeProjection.path(to: task.id, in: store.tasks)
        return path.count > 1 ? path.dropLast().map(\.title).joined(separator: " / ") : task.categoryName
    }

    private func processedTime(_ task: TaskItem) -> String {
        guard let date = ProcessedHistoryProjection.processedAt(task) else { return "时间未记录" }
        if range == .today { return date.formatted(.dateTime.hour().minute()) }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private func processedDateTime(_ task: TaskItem) -> String {
        guard let date = ProcessedHistoryProjection.processedAt(task) else { return "时间未记录" }
        return date.formatted(.dateTime.month().day().hour().minute())
    }

    private func statusIcon(_ task: TaskItem) -> String {
        if task.isCompleted { return "checkmark.circle" }
        if task.isCancelled { return "xmark.circle" }
        return "clock.arrow.circlepath"
    }

    private func statusSymbol(_ task: TaskItem) -> some View {
        Image(systemName: statusIcon(task))
            .font(font(.body))
            .foregroundStyle(statusColor(task))
            .accessibilityHidden(true)
    }

    private func statusColor(_ task: TaskItem) -> Color {
        if task.isCompleted { return AppColors.taskCompleted(for: preferences) }
        if task.isCancelled { return AppColors.danger }
        return AppColors.warning
    }
}

#Preview("已处理 · 有数据") {
    let store = TaskStore(inMemory: true)
    let root = TaskItem(title: "新版首页发布", category: "工作", quadrant: .doNow)
    var postponed = TaskItem(title: "检查发布清单", notes: "检查发布前配置与素材", category: "工作",
                             quadrant: .doNow, dueDate: .now.addingTimeInterval(3 * 86400),
                             parentTaskID: root.id)
    postponed.status = .postponed
    postponed.statusChangedAt = .now
    store.tasks = [root, postponed]
    return CompletedView(onSelect: { _ in })
        .environmentObject(store)
        .environmentObject(AppPreferences())
        .frame(width: 1100, height: 760)
}
