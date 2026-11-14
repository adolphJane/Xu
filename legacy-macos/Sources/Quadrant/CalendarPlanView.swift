import SwiftUI
import EventKit

enum CalendarPlanMode: String, CaseIterable {
    case day = "日", week = "周", month = "月"
}

private struct CalendarPlanUndo {
    let before: TaskItem
    let after: TaskItem
}

private struct CalendarSeriesSpan: Identifiable {
    let id: UUID
    let title: String
    let progress: String
    let start: Date
    let end: Date
}

struct PlanView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let onSelect: (TaskItem) -> Void
    let onAddTask: () -> Void

    @State private var mode: CalendarPlanMode = .week
    @State private var selectedDate = Date.now
    @State private var selectedSeriesID: UUID?
    @State private var expandedIDs: Set<UUID> = []
    @State private var initializedExpansion = false
    @State private var showsUnscheduledOnly = false
    @State private var showsTaskList = true
    @State private var arrangingTask: TaskItem?
    @State private var proposedStart: Date?
    @State private var proposedHasTime: Bool?
    @State private var lastArrangement: CalendarPlanUndo?
    @State private var lastSeriesArrangement: [(before: TaskItem, after: TaskItem)]?
    @State private var arrangingSeries: TaskItem?
    @State private var proposedSeriesDay: Date?
    @State private var calendarState = "未连接系统日历，空闲估计仅含序内安排"
    @State private var showsWorkHours = false
    @AppStorage("calendar.workStartHour") private var workStartHour = 9
    @AppStorage("calendar.workEndHour") private var workEndHour = 18
    @AppStorage("calendar.workDaysMask") private var workDaysMask = 127
    @AppStorage("calendar.lunchBreakEnabled") private var lunchBreakEnabled = false

    private let calendar = Calendar.current

    init(initialMode: CalendarPlanMode = .week, initialDate: Date = .now,
         onSelect: @escaping (TaskItem) -> Void, onAddTask: @escaping () -> Void) {
        self.onSelect = onSelect
        self.onAddTask = onAddTask
        _mode = State(initialValue: initialMode)
        _selectedDate = State(initialValue: initialDate)
    }

    private var executable: [TaskItem] { CalendarPlanLogic.executableTasks(store.tasks) }
    private var groups: [TaskSeriesGroup] {
        let executableIDs = Set(executable.map(\.id))
        let visible = store.tasks.filter { task in
            !task.isCancelled && (!showsUnscheduledOnly ||
                (executableIDs.contains(task.id) && (task.isUnscheduled || (!task.isCompleted && task.timeBlock == nil))))
        }
        return TaskSeriesProjection.groups(matches: visible, allTasks: store.tasks)
    }
    private var selectedDay: Date { calendar.startOfDay(for: selectedDate) }
    private var seriesSpans: [CalendarSeriesSpan] {
        groups.filter(\.isSeries).compactMap { group in
            let dates = executable.filter { !$0.isUnscheduled && CalendarPlanLogic.root(of: $0, in: store.tasks).id == group.id }
                .map { calendar.startOfDay(for: $0.timeBlock?.start ?? $0.scheduledFor) }
            guard let first = dates.min(), let last = dates.max() else { return nil }
            return .init(id: group.id, title: group.root.title,
                         progress: "\(group.completedDirectChildren)/\(group.directChildrenCount)", start: first, end: last)
        }
    }
    private var weekStart: Date {
        let weekday = calendar.component(.weekday, from: selectedDay)
        let first = calendar.firstWeekday
        return calendar.date(byAdding: .day, value: -((weekday - first + 7) % 7), to: selectedDay) ?? selectedDay
    }
    private var monthStart: Date { calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDay)) ?? selectedDay }
    private var days: [Date] {
        let start = mode == .day ? selectedDay : mode == .week ? weekStart : monthGridStart
        let count = mode == .day ? 1 : mode == .week ? 7 : monthGridCount
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }
    private var monthGridStart: Date {
        let weekday = calendar.component(.weekday, from: monthStart)
        return calendar.date(byAdding: .day, value: -((weekday - calendar.firstWeekday + 7) % 7), to: monthStart) ?? monthStart
    }
    private var monthGridCount: Int {
        let end = calendar.date(byAdding: .month, value: 1, to: monthStart) ?? monthStart
        let span = calendar.dateComponents([.day], from: monthGridStart, to: end).day ?? 35
        return ((span + 6) / 7) * 7
    }
    private var periodTitle: String {
        switch mode {
        case .day: return selectedDay.formatted(.dateTime.year().month().day().weekday(.wide))
        case .week:
            let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
            return "\(weekStart.formatted(.dateTime.month().day()))—\(end.formatted(.dateTime.day()))"
        case .month: return monthStart.formatted(.dateTime.year().month())
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HStack(spacing: 0) {
                Group {
                    if mode == .month { monthView } else { timeView }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                if showsTaskList {
                    Divider()
                    seriesList
                        .frame(width: 320)
                }
            }
            Divider()
            HStack(spacing: AppSpacing.x4) {
                Label("子任务时间块", systemImage: "checklist")
                Label("系统日程", systemImage: "calendar")
                Label("系列范围不占用时间", systemImage: "rectangle.dashed")
                Spacer()
                Text(calendarState)
                Button("工作时段") { showsWorkHours = true }
                if !preferences.calendarIntegrationEnabled || !CalendarIntegration.shared.hasReadAccess {
                    Button("连接日历") {
                        Task {
                            do {
                                let granted = try await CalendarIntegration.shared.requestAccess()
                                if granted { preferences.calendarIntegrationEnabled = true; refreshCalendar() }
                                else { calendarState = "系统日历授权未开启" }
                            } catch { calendarState = "读取日历失败：\(error.localizedDescription)" }
                        }
                    }
                }
                if lastArrangement != nil || lastSeriesArrangement != nil { Button("撤销安排") { undoArrangement() } }
            }
            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, AppSpacing.page).padding(.vertical, AppSpacing.x2)
        }
        .background(AppColors.canvas)
        .appDialog(item: $arrangingTask) { task in
            CalendarArrangeDialog(task: task, initialDate: selectedDate, proposedStart: proposedStart,
                                  proposedHasTime: proposedHasTime, events: store.calendarEvents,
                                  onSaved: { before, after in
                                      lastArrangement = .init(before: before, after: after)
                                      lastSeriesArrangement = nil
                                  })
        }
        .appDialog(item: $arrangingSeries) { root in
            CalendarSeriesMoveDialog(root: root, initialDay: proposedSeriesDay ?? selectedDay,
                                     events: store.calendarEvents) { changes in
                lastSeriesArrangement = changes
                lastArrangement = nil
            }
        }
        .appDialog(isPresented: $showsWorkHours) { CalendarWorkHoursDialog() }
        .onChange(of: arrangingTask?.id) { _, newValue in
            if newValue == nil { proposedStart = nil; proposedHasTime = nil }
        }
        .onChange(of: mode) { _, _ in refreshCalendar() }
        .onChange(of: selectedDate) { _, _ in refreshCalendar() }
        .onAppear {
            if !initializedExpansion {
                expandedIDs = Set(groups.filter(\.isSeries).map(\.id))
                initializedExpansion = true
            }
            refreshCalendar()
        }
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in
            Task { @MainActor in refreshCalendar() }
        }
    }

    private var toolbar: some View {
        HStack(spacing: AppSpacing.x3) {
            Text("日历计划").font(AppTypography.title)
            Spacer(minLength: AppSpacing.x2)
            Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("上一\(mode.rawValue)")
            Text(periodTitle).font(AppTypography.headline).lineLimit(1)
                .minimumScaleFactor(0.8).frame(minWidth: 130)
            Button { shift(1) } label: { Image(systemName: "chevron.right") }
                .accessibilityLabel("下一\(mode.rawValue)")
            Button("今天") { selectedDate = .now }
            Picker("日历视图", selection: $mode) {
                ForEach(CalendarPlanMode.allCases, id: \.self) { value in Text(value.rawValue).tag(value) }
            }.pickerStyle(.segmented).labelsHidden().frame(width: 150)
            Button { showsTaskList.toggle() } label: {
                Label("任务系列", systemImage: "sidebar.right")
            }.accessibilityLabel(showsTaskList ? "收起任务系列" : "显示任务系列")
            AppButton(title: "添加事项", systemImage: "plus", tint: preferences.accentColor, action: onAddTask)
        }
        .padding(.horizontal, AppSpacing.page).padding(.vertical, AppSpacing.x3)
    }

    private func shift(_ direction: Int) {
        let component: Calendar.Component = mode == .day ? .day : mode == .week ? .weekOfYear : .month
        selectedDate = calendar.date(byAdding: component, value: direction, to: selectedDate) ?? selectedDate
    }

    private func refreshCalendar() {
        guard preferences.calendarIntegrationEnabled else {
            store.calendarEvents = []
            calendarState = "未连接系统日历，空闲估计仅含序内安排"
            return
        }
        guard CalendarIntegration.shared.hasReadAccess else {
            store.calendarEvents = []
            calendarState = "系统日历未授权，空闲估计仅含序内安排"
            return
        }
        let start = mode == .month ? monthGridStart : mode == .week ? weekStart : selectedDay
        let end = calendar.date(byAdding: .day, value: mode == .month ? monthGridCount : mode == .week ? 7 : 1, to: start) ?? start
        // Reading existing permission never triggers an authorization prompt.
        store.calendarEvents = CalendarIntegration.shared.events(from: start, to: end)
        calendarState = store.calendarEvents.isEmpty ? "系统日历：本周期无日程" : "系统日历：\(store.calendarEvents.count) 项日程"
    }

    private func beginArrange(_ task: TaskItem) {
        proposedStart = nil
        proposedHasTime = nil
        arrangingTask = task
    }

    private func availabilityText(on day: Date) -> String {
        let weekday = calendar.component(.weekday, from: day)
        guard workDaysMask & (1 << (weekday - 1)) != 0 else { return "非工作日" }
        let start = calendar.date(bySettingHour: workStartHour, minute: 0, second: 0, of: day) ?? day
        let end = calendar.date(bySettingHour: workEndHour, minute: 0, second: 0, of: day) ?? day
        var busy = CalendarPlanLogic.intervals(on: day, tasks: store.tasks, events: store.calendarEvents)
        if lunchBreakEnabled,
           let lunchStart = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
           let lunchEnd = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: day) {
            busy.append(.init(start: lunchStart, end: lunchEnd))
        }
        let slots = CalendarPlanLogic.freeSlots(in: .init(start: max(start, .now), end: end), busy: busy)
        let minutes = Int(slots.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) } / 60)
        let longest = Int((slots.map { $0.end.timeIntervalSince($0.start) }.max() ?? 0) / 60)
        if minutes <= 0 { return "无可用空档" }
        let totalText = minutes % 60 == 0 ? "\(minutes / 60)小时" : "\(minutes / 60)时\(minutes % 60)分"
        if mode != .day { return "可用 \(totalText)" }
        let longestText = longest % 60 == 0 ? "\(longest / 60)小时" : "\(longest / 60)时\(longest % 60)分"
        return "可用 \(totalText) · 最长 \(longestText)"
    }

    private var seriesList: some View {
        VStack(spacing: 0) {
            HStack {
                Text("任务系列").font(AppTypography.title)
                Spacer()
            }.padding(AppSpacing.x4)
            Picker("任务筛选", selection: $showsUnscheduledOnly) {
                Text("全部").tag(false)
                Text("待安排").tag(true)
            }.pickerStyle(.segmented).labelsHidden().padding(.horizontal, AppSpacing.x4)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: AppSpacing.x2) {
                    if groups.isEmpty {
                        AppEmptyState(title: "暂无任务系列", message: "添加任务后可在此安排时间。", systemImage: "calendar")
                    }
                    ForEach(groups) { group in seriesRow(group) }
                }.padding(AppSpacing.x3)
            }
        }
        .background(preferences.cardBackground)
    }

    private func seriesRow(_ group: TaskSeriesGroup) -> some View {
        let root = group.root
        let expanded = expandedIDs.contains(root.id)
        return VStack(alignment: .leading, spacing: AppSpacing.x1) {
            HStack(alignment: .top, spacing: AppSpacing.x2) {
                if group.isSeries {
                    Button { if expanded { expandedIDs.remove(root.id) } else { expandedIDs.insert(root.id) } } label: {
                        Image(systemName: expanded ? "chevron.down" : "chevron.right")
                            .frame(width: 36, height: 36)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain).accessibilityLabel(expanded ? "收起\(root.title)" : "展开\(root.title)")
                }
                Button { selectedSeriesID = selectedSeriesID == root.id ? nil : root.id } label: {
                    VStack(alignment: .leading, spacing: AppSpacing.x1) {
                        Text(root.title).font(AppTypography.headline).lineLimit(2)
                        HStack(spacing: AppSpacing.x2) {
                            if group.isSeries { Text("\(group.completedDirectChildren)/\(group.directChildrenCount) 已完成") }
                            else { Text(root.displayStatusTitle) }
                            if let due = root.dueDate { Text("截止 \(due.formatted(.dateTime.month().day()))") }
                        }.font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain)
                .accessibilityLabel("\(root.title)，\(group.completedDirectChildren)/\(group.directChildrenCount) 已完成")
            }
            if group.isSeries && expanded {
                ForEach(group.rows.filter { $0.depth > 0 }) { row in
                    let task = row.task
                    HStack(alignment: .top, spacing: AppSpacing.x2) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : task.timeBlock == nil ? "circle" : "clock")
                            .foregroundStyle(task.isCompleted ? AppColors.success : preferences.accentColor)
                        VStack(alignment: .leading, spacing: AppSpacing.x1) {
                            Text(task.title).font(AppTypography.body).lineLimit(2)
                            Text(planDescription(task)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.leading, CGFloat(min(row.depth, 4)) * AppSpacing.x3)
                    .padding(.vertical, AppSpacing.x1)
                    .background(calendar.isDate(task.scheduledFor, inSameDayAs: selectedDay) && !task.isUnscheduled ? preferences.accentColor.opacity(0.08) : Color.clear)
                    .contentShape(Rectangle())
                    .onTapGesture { if task.timeBlock != nil { selectedDate = task.timeBlock!.start }; onSelect(task) }
                    .contextMenu { taskMenu(task) }
                    .draggable(task.id.uuidString)
                }
            } else if !group.isSeries {
                HStack {
                    Text(planDescription(root)).font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    Spacer()
                    Button("安排") { beginArrange(root) }.disabled(root.isCompleted || root.planLocked)
                }
                .draggable(root.id.uuidString)
            }
        }
        .padding(AppSpacing.x3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(selectedSeriesID == root.id ? preferences.accentColor.opacity(0.12) : AppColors.surface,
                    in: RoundedRectangle(cornerRadius: AppRadius.control))
        .overlay(RoundedRectangle(cornerRadius: AppRadius.control).stroke(AppColors.border))
        .contextMenu {
            if group.isSeries {
                Button("查看详情") { onSelect(root) }
                if !root.isCancelled {
                    Button(root.isCompleted ? "取消完成" : "标记完成") { store.toggle(root) }
                }
                Button("移动整个系列") { beginSeriesMove(root, to: selectedDay) }
            } else { taskMenu(root) }
        }
        .draggable(root.id.uuidString)
    }

    private func beginSeriesMove(_ root: TaskItem, to day: Date) {
        proposedSeriesDay = day
        arrangingSeries = root
    }

    @ViewBuilder private func taskMenu(_ task: TaskItem) -> some View {
        Button("查看详情") { onSelect(task) }
        if !task.isCancelled {
            Button(task.isCompleted ? "取消完成" : "标记完成") { store.toggle(task) }
        }
        if task.needsAction && !task.planLocked && !store.tasks.contains(where: { $0.parentTaskID == task.id }) {
            Button("安排时间") { beginArrange(task) }
            if task.timeBlock != nil {
                Button("取消时间块") { clearBlock(task, keepDate: true) }
            }
            Button("移回待安排") { clearBlock(task, keepDate: false) }
        }
    }

    private func clearBlock(_ task: TaskItem, keepDate: Bool) {
        var updated = task
        updated.timeBlock = nil
        if !keepDate {
            updated.status = .unscheduled
            updated.scheduledFor = .now
        }
        if store.update(updated) {
            lastArrangement = .init(before: task, after: updated)
            lastSeriesArrangement = nil
        }
    }

    private func undoArrangement() {
        if let changes = lastSeriesArrangement {
            let reversed = changes.map { (before: $0.after, after: $0.before) }
            if store.applyCalendarSeriesMove(reversed) { lastSeriesArrangement = nil }
            return
        }
        guard let change = lastArrangement,
              let current = store.tasks.first(where: { $0.id == change.after.id }) else { return }
        guard current.timeBlock == change.after.timeBlock,
              current.scheduledFor == change.after.scheduledFor,
              current.effectiveStatus == change.after.effectiveStatus else {
            store.actionMessage = "事项已在其他位置修改，请重新检查安排。"
            lastArrangement = nil
            return
        }
        _ = store.update(change.before)
        lastArrangement = nil
    }

    private func planDescription(_ task: TaskItem) -> String {
        if task.isUnscheduled { return "待安排日期 · \(task.estimatedMinutes) 分钟" }
        if let block = task.timeBlock {
            return "\(block.start.formatted(.dateTime.month().day())) \(block.start.formatted(.dateTime.hour().minute()))–\(block.end.formatted(.dateTime.hour().minute()))"
        }
        return "\(task.scheduledFor.formatted(.dateTime.month().day())) · 待定时 · \(task.estimatedMinutes) 分钟"
    }

    private func scheduledTasks(on day: Date) -> [TaskItem] {
        executable.filter { task in
            !task.isUnscheduled && calendar.isDate(task.timeBlock?.start ?? task.scheduledFor, inSameDayAs: day)
                && (selectedSeriesID == nil || CalendarPlanLogic.root(of: task, in: store.tasks).id == selectedSeriesID)
        }
    }

    private var timeView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("").frame(width: 64)
                ForEach(days, id: \.self) { day in
                    Button { selectedDate = day } label: {
                        VStack(spacing: AppSpacing.x1) {
                            Text(day.formatted(.dateTime.weekday(.abbreviated))).font(AppTypography.caption)
                            Text(day.formatted(.dateTime.month().day())).font(AppTypography.headline)
                                .lineLimit(1).minimumScaleFactor(0.8)
                            if calendar.isDateInToday(day) { Text("今天").font(AppTypography.caption) }
                            Text(availabilityText(on: day)).font(AppTypography.caption)
                                .foregroundStyle(AppColors.textSecondary).lineLimit(1).minimumScaleFactor(0.8)
                        }.frame(maxWidth: .infinity)
                          .padding(.vertical, AppSpacing.x2)
                          .background(calendar.isDate(day, inSameDayAs: selectedDay) ? preferences.accentColor.opacity(0.1) : Color.clear)
                    }.buttonStyle(.plain)
                }
            }
            Divider()
            if mode == .week { seriesRangeStrip }
            HStack(alignment: .top, spacing: 0) {
                Text("当天待定时").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).frame(width: 64)
                ForEach(days, id: \.self) { day in
                    let waiting = scheduledTasks(on: day).filter { $0.timeBlock == nil && !$0.isCompleted }
                    VStack(alignment: .leading, spacing: AppSpacing.x1) {
                        ForEach(store.calendarEvents.filter { $0.isAllDay && $0.startDate < (calendar.date(byAdding: .day, value: 1, to: day) ?? day) && $0.endDate > day }) { event in
                            Label(event.title, systemImage: "calendar")
                                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).lineLimit(1)
                                .help("系统日历 · \(event.calendarTitle) · 只读")
                        }
                        ForEach(waiting.prefix(2)) { task in
                            Button { beginArrange(task) } label: {
                                Text(task.title).font(AppTypography.caption).lineLimit(1)
                            }.buttonStyle(.plain)
                        }
                        if waiting.count > 2 { Text("还有 \(waiting.count - 2) 项").font(AppTypography.caption) }
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
                     .padding(AppSpacing.x1)
                     .dropDestination(for: String.self) { values, _ in drop(values, on: day, hour: nil) }
                }
            }
            Divider()
            GeometryReader { geometry in
                let columnWidth = mode == .day ? max(420, geometry.size.width - 64) : max(72, (geometry.size.width - 64) / 7)
                ScrollView([.vertical, .horizontal]) {
                    HStack(alignment: .top, spacing: 0) {
                        VStack(alignment: .trailing, spacing: 0) {
                            ForEach(8..<21, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).font(AppTypography.caption)
                                    .foregroundStyle(AppColors.textSecondary)
                                    .frame(width: 56, height: 64, alignment: .topTrailing)
                            }
                        }.padding(.trailing, AppSpacing.x2)
                        ForEach(days, id: \.self) { day in
                            timeColumn(day)
                                .frame(width: columnWidth)
                        }
                    }
                    .frame(width: 64 + columnWidth * CGFloat(days.count))
                    .padding(.top, AppSpacing.x2)
                }
            }
        }
    }

    private var seriesRangeStrip: some View {
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let visible = seriesSpans.filter { $0.start <= weekEnd && $0.end >= weekStart }
        return HStack(alignment: .top, spacing: 0) {
            Text("系列范围").font(AppTypography.caption).foregroundStyle(AppColors.textSecondary).frame(width: 64)
            GeometryReader { geometry in
                let columnWidth = geometry.size.width / 7
                ZStack(alignment: .topLeading) {
                    ForEach(Array(visible.enumerated()), id: \.element.id) { index, span in
                        let first = max(weekStart, span.start)
                        let last = min(weekEnd, span.end)
                        let startIndex = calendar.dateComponents([.day], from: weekStart, to: first).day ?? 0
                        let endIndex = calendar.dateComponents([.day], from: weekStart, to: last).day ?? 0
                        Text("\(span.title) · \(span.progress)")
                            .font(AppTypography.caption).lineLimit(1)
                            .foregroundStyle(preferences.accentColor)
                            .padding(.horizontal, AppSpacing.x1)
                            .frame(width: CGFloat(endIndex - startIndex + 1) * columnWidth - AppSpacing.x1,
                                   height: 22, alignment: .leading)
                            .background(preferences.accentColor.opacity(0.12),
                                        in: RoundedRectangle(cornerRadius: AppRadius.control))
                            .offset(x: CGFloat(startIndex) * columnWidth, y: CGFloat(index) * 26)
                            .help("系列计划范围概览，不占用日历时段")
                    }
                }
            }.frame(height: CGFloat(max(1, visible.count)) * 26)
        }.padding(.vertical, AppSpacing.x2)
    }

    private func timeColumn(_ day: Date) -> some View {
        let tasks = scheduledTasks(on: day).filter { $0.timeBlock != nil }
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let events = store.calendarEvents.filter { !$0.isAllDay && $0.startDate < dayEnd && $0.endDate > day }
        let entries = tasks.compactMap { task -> CalendarPlanEntry? in
            guard let block = task.timeBlock else { return nil }
            return .init(id: task.id.uuidString, interval: .init(start: block.start, end: block.end))
        } + events.map { .init(id: "event:\($0.id)", interval: .init(start: $0.startDate, end: $0.endDate)) }
        let lanes = CalendarPlanLogic.lanes(for: entries)
        return GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    ForEach(8..<21, id: \.self) { hour in
                        Rectangle().fill(Color.clear).frame(height: 64)
                            .overlay(alignment: .top) { Divider() }
                            .contentShape(Rectangle())
                            .dropDestination(for: String.self) { values, _ in drop(values, on: day, hour: hour) }
                            .onTapGesture(count: 2) { selectedDate = day }
                    }
                }
                ForEach(tasks) { task in
                    if let block = task.timeBlock {
                        timeBlockView(task, block: block, day: day, width: geometry.size.width,
                                      lane: lanes[task.id.uuidString] ?? .init(index: 0, count: 1))
                    }
                }
                ForEach(events) { event in
                    eventBlockView(event, day: day, width: geometry.size.width,
                                   lane: lanes["event:\(event.id)"] ?? .init(index: 0, count: 1))
                }
            }
            .frame(width: geometry.size.width, height: 13 * 64, alignment: .topLeading)
            .overlay(alignment: .leading) { Rectangle().fill(AppColors.border).frame(width: 1) }
        }
        .frame(height: 13 * 64, alignment: .top)
        .frame(maxWidth: .infinity)
    }

    private func blockFrame(start: Date, end: Date, day: Date) -> (offset: CGFloat, height: CGFloat)? {
        let startHour = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day) ?? day
        let endHour = calendar.date(bySettingHour: 21, minute: 0, second: 0, of: day) ?? day
        guard end > startHour && start < endHour else { return nil }
        let clippedStart = max(start, startHour)
        let clippedEnd = min(end, endHour)
        return (CGFloat(clippedStart.timeIntervalSince(startHour) / 3600) * 64,
                max(28, CGFloat(clippedEnd.timeIntervalSince(clippedStart) / 3600) * 64))
    }

    @ViewBuilder private func timeBlockView(_ task: TaskItem, block: TaskTimeBlock, day: Date,
                                           width: CGFloat, lane: CalendarPlanLane) -> some View {
        if let frame = blockFrame(start: block.start, end: block.end, day: day) {
            let laneWidth = width / CGFloat(lane.count)
            let cardWidth = min(laneWidth - AppSpacing.x2, mode == .day ? 300 : laneWidth)
            Button { onSelect(task) } label: {
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    Text(task.title).font(AppTypography.caption.weight(.semibold)).lineLimit(2)
                    Text("\(block.start.formatted(.dateTime.hour().minute()))–\(block.end.formatted(.dateTime.hour().minute()))")
                        .font(AppTypography.caption).lineLimit(1)
                    if lane.count > 1 { Text("时间重叠").font(AppTypography.caption) }
                    if mode == .day {
                        Text(CalendarPlanLogic.root(of: task, in: store.tasks).title)
                            .font(AppTypography.caption).lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(AppSpacing.x1)
                .background(preferences.accentColor.opacity(task.isCompleted ? 0.08 : 0.18),
                            in: RoundedRectangle(cornerRadius: AppRadius.control))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.control).stroke(preferences.accentColor))
            }
            .buttonStyle(.plain)
            .contextMenu { taskMenu(task) }
            .draggable(task.id.uuidString)
            .frame(width: cardWidth, height: frame.height)
            .position(x: CGFloat(lane.index) * laneWidth + laneWidth / 2,
                      y: frame.offset + frame.height / 2)
        }
    }

    @ViewBuilder private func eventBlockView(_ event: CalendarEventItem, day: Date,
                                            width: CGFloat, lane: CalendarPlanLane) -> some View {
        if let frame = blockFrame(start: event.startDate, end: event.endDate, day: day) {
            let laneWidth = width / CGFloat(lane.count)
            let cardWidth = min(laneWidth - AppSpacing.x2, mode == .day ? 300 : laneWidth)
            VStack(alignment: .leading, spacing: AppSpacing.x1) {
                Text(event.title).font(AppTypography.caption.weight(.semibold)).lineLimit(2)
                Text(event.calendarTitle).font(AppTypography.caption).lineLimit(1)
                if lane.count > 1 { Text("时间重叠").font(AppTypography.caption) }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(AppSpacing.x1)
            .background(AppColors.textSecondary.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control))
            .overlay(RoundedRectangle(cornerRadius: AppRadius.control).stroke(AppColors.border))
            .frame(width: cardWidth, height: frame.height)
            .position(x: CGFloat(lane.index) * laneWidth + laneWidth / 2,
                      y: frame.offset + frame.height / 2)
            .help("系统日历 · \(event.calendarTitle) · 只读")
        }
    }

    private var monthView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(days.prefix(7), id: \.self) { day in
                    Text(day.formatted(.dateTime.weekday(.wide))).font(AppTypography.caption)
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(maxWidth: .infinity).padding(.vertical, AppSpacing.x2)
                }
            }
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                    ForEach(days, id: \.self) { day in monthCell(day) }
                }
            }
        }
    }

    private func monthCell(_ day: Date) -> some View {
        let tasks = scheduledTasks(on: day)
        let deadlines = store.tasks.filter { $0.dueDate.map { calendar.isDate($0, inSameDayAs: day) } == true && !$0.isCancelled }
        let ranges = seriesSpans.filter { day >= $0.start && day <= $0.end }
        return VStack(alignment: .leading, spacing: AppSpacing.x1) {
            Button { selectedDate = day } label: {
                HStack {
                    Text(day.formatted(.dateTime.day())).font(AppTypography.headline)
                    Spacer()
                    if calendar.isDateInToday(day) { Text("今天").font(AppTypography.caption) }
                }
            }.buttonStyle(.plain)
            ForEach(Array(ranges.prefix(1))) { group in
                Text("系列 · \(group.title) \(group.progress)")
                    .font(AppTypography.caption).lineLimit(1)
                    .foregroundStyle(preferences.accentColor)
                    .padding(.horizontal, AppSpacing.x1)
                    .background(preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: AppRadius.control))
                    .help("系列计划范围概览，不占用日历时段")
            }
            ForEach(tasks.prefix(3)) { task in
                Button { if task.timeBlock == nil { beginArrange(task) } else { onSelect(task) } } label: {
                    Text("\(task.timeBlock.map { $0.start.formatted(.dateTime.hour().minute()) } ?? "待定时") · \(task.title)")
                        .font(AppTypography.caption).lineLimit(1)
                        .foregroundStyle(task.isCompleted ? AppColors.textSecondary : preferences.accentColor)
                }.buttonStyle(.plain)
            }
            if tasks.count > 3 { Text("还有 \(tasks.count - 3) 项子任务").font(AppTypography.caption) }
            ForEach(deadlines.prefix(1)) { task in
                Label("\(task.title) 截止", systemImage: "flag.fill")
                    .font(AppTypography.caption).foregroundStyle(AppColors.warning).lineLimit(1)
            }
            Text(availabilityText(on: day)).font(AppTypography.caption)
                .foregroundStyle(AppColors.textSecondary).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(AppSpacing.x2)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(calendar.isDate(day, inSameDayAs: selectedDay) ? preferences.accentColor.opacity(0.1) : AppColors.surface)
        .overlay(Rectangle().stroke(AppColors.border, lineWidth: 0.5))
        .opacity(calendar.isDate(day, equalTo: monthStart, toGranularity: .month) ? 1 : 0.55)
        .onTapGesture(count: 2) { selectedDate = day; mode = .day }
        .dropDestination(for: String.self) { values, _ in drop(values, on: day, hour: nil) }
    }

    private func drop(_ values: [String], on day: Date, hour: Int?) -> Bool {
        guard let id = values.first.flatMap(UUID.init(uuidString:)),
              let task = store.tasks.first(where: { $0.id == id }) else { return false }
        if store.tasks.contains(where: { $0.parentTaskID == id }) {
            beginSeriesMove(task, to: day)
            return true
        }
        guard task.needsAction, !task.planLocked,
              executable.contains(where: { $0.id == id }) else { return false }
        selectedDate = day
        let carriedHour = task.timeBlock.map { calendar.component(.hour, from: $0.start) }
        let carriedMinute = task.timeBlock.map { calendar.component(.minute, from: $0.start) } ?? 0
        proposedStart = calendar.date(bySettingHour: hour ?? carriedHour ?? 9,
                                      minute: hour == nil ? carriedMinute : 0, second: 0, of: day) ?? day
        proposedHasTime = hour != nil ? true : task.timeBlock != nil
        arrangingTask = task
        return true
    }
}

private struct CalendarSeriesMoveDialog: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @AppDismiss private var dismiss
    let root: TaskItem
    let events: [CalendarEventItem]
    let onSaved: ([(before: TaskItem, after: TaskItem)]) -> Void
    @State private var targetDay: Date
    @State private var acceptsWarnings = false
    @State private var destinationEvents: [CalendarEventItem] = []

    init(root: TaskItem, initialDay: Date, events: [CalendarEventItem],
         onSaved: @escaping ([(before: TaskItem, after: TaskItem)]) -> Void) {
        self.root = root
        self.events = events
        self.onSaved = onSaved
        _targetDay = State(initialValue: initialDay)
    }

    private var preview: CalendarSeriesMovePreview {
        CalendarPlanLogic.seriesMove(rootID: root.id, to: targetDay, tasks: store.tasks,
                                     events: Array(Dictionary((events + destinationEvents).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first }).values))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            Text("移动系列 · \(root.title)").font(AppTypography.title)
            Text("以最早安排的子任务为起点，其他子任务保留相对日期和具体时刻；截止日期不变。")
                .font(AppTypography.callout).foregroundStyle(AppColors.textSecondary)
            DatePicker("系列新起点", selection: $targetDay, displayedComponents: .date)
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.x2) {
                    ForEach(preview.changes, id: \.before.id) { change in
                        VStack(alignment: .leading, spacing: AppSpacing.x1) {
                            Text(change.before.title).font(AppTypography.headline)
                            Text("\(description(change.before)) → \(description(change.after))")
                                .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                        }
                    }
                    ForEach(Array(preview.skipped.enumerated()), id: \.offset) { _, item in
                        Label("跳过 \(item.title)：\(item.reason)", systemImage: "minus.circle")
                            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    }
                    if preview.changes.isEmpty { Text("没有可移动的子任务").foregroundStyle(AppColors.textSecondary) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(maxHeight: 260)
            if !preview.warnings.isEmpty {
                VStack(alignment: .leading, spacing: AppSpacing.x1) {
                    ForEach(preview.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(AppTypography.caption).foregroundStyle(AppColors.warning)
                    }
                    Toggle("我已检查以上影响，仍然移动", isOn: $acceptsWarnings)
                }
            }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存系列安排") {
                    let changes = preview.changes
                    if store.applyCalendarSeriesMove(changes) {
                        onSaved(changes)
                        dismiss()
                    }
                }
                .disabled(preview.changes.isEmpty || (!preview.warnings.isEmpty && !acceptsWarnings))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.x6)
        .frame(width: 520)
        .onAppear { refreshDestinationEvents() }
        .onChange(of: targetDay) { _, _ in
            acceptsWarnings = false
            refreshDestinationEvents()
        }
    }

    private func refreshDestinationEvents() {
        guard preferences.calendarIntegrationEnabled, CalendarIntegration.shared.hasReadAccess else {
            destinationEvents = []
            return
        }
        let base = CalendarPlanLogic.seriesMove(rootID: root.id, to: targetDay, tasks: store.tasks, events: [])
        let blocks = base.changes.compactMap(\.after.timeBlock)
        guard let start = blocks.map(\.start).min(), let end = blocks.map(\.end).max() else {
            destinationEvents = []
            return
        }
        destinationEvents = CalendarIntegration.shared.events(from: start, to: end)
    }

    private func description(_ task: TaskItem) -> String {
        if let block = task.timeBlock {
            return "\(block.start.formatted(.dateTime.month().day().hour().minute()))–\(block.end.formatted(.dateTime.hour().minute()))"
        }
        return "\(task.scheduledFor.formatted(.dateTime.month().day())) · 待定时"
    }
}

private struct CalendarArrangeDialog: View {
    @EnvironmentObject private var store: TaskStore
    @AppDismiss private var dismiss
    let task: TaskItem
    let initialDate: Date
    let proposedStart: Date?
    let proposedHasTime: Bool?
    let events: [CalendarEventItem]
    let onSaved: (TaskItem, TaskItem) -> Void
    @State private var start: Date
    @State private var duration: Int
    @State private var hasTime: Bool
    @State private var allowConflict = false

    init(task: TaskItem, initialDate: Date, proposedStart: Date?, proposedHasTime: Bool?,
         events: [CalendarEventItem], onSaved: @escaping (TaskItem, TaskItem) -> Void) {
        self.task = task
        self.initialDate = initialDate
        self.proposedStart = proposedStart
        self.proposedHasTime = proposedHasTime
        self.events = events
        self.onSaved = onSaved
        let baseDate = task.isUnscheduled ? initialDate : task.scheduledFor
        let defaultStart = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate) ?? baseDate
        _start = State(initialValue: proposedStart ?? task.timeBlock?.start ?? defaultStart)
        _duration = State(initialValue: task.timeBlock.map { max(15, Int($0.end.timeIntervalSince($0.start) / 60)) } ?? max(15, task.estimatedMinutes))
        _hasTime = State(initialValue: proposedHasTime ?? (task.timeBlock != nil))
    }

    private var end: Date { start.addingTimeInterval(TimeInterval(duration * 60)) }
    private var conflicts: [String] {
        hasTime ? CalendarPlanLogic.conflicts(for: .init(start: start, end: end), excluding: task.id,
                                               tasks: store.tasks, events: events) : []
    }
    private var unmetDependencies: [String] {
        task.effectiveDependencyIDs.compactMap { id in
            guard let predecessor = store.tasks.first(where: { $0.id == id }), !predecessor.isCompleted else { return nil }
            return predecessor.title
        }
    }
    private var suggestedSlots: [CalendarPlanInterval] {
        guard hasTime else { return [] }
        let calendar = Calendar.current
        let defaults = UserDefaults.standard
        let workStart = defaults.object(forKey: "calendar.workStartHour") as? Int ?? 9
        let workEnd = defaults.object(forKey: "calendar.workEndHour") as? Int ?? 18
        let daysMask = defaults.object(forKey: "calendar.workDaysMask") as? Int ?? 127
        let lunch = defaults.bool(forKey: "calendar.lunchBreakEnabled")
        var result: [CalendarPlanInterval] = []
        let firstDay = calendar.startOfDay(for: max(start, .now))
        for offset in 0..<7 {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay),
                  daysMask & (1 << (calendar.component(.weekday, from: day) - 1)) != 0,
                  let workStartDate = calendar.date(bySettingHour: workStart, minute: 0, second: 0, of: day),
                  let workEndDate = calendar.date(bySettingHour: workEnd, minute: 0, second: 0, of: day) else { continue }
            var busy = CalendarPlanLogic.intervals(on: day, tasks: store.tasks.filter { $0.id != task.id }, events: events)
            if lunch, let from = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: day),
               let to = calendar.date(bySettingHour: 13, minute: 0, second: 0, of: day) {
                busy.append(.init(start: from, end: to))
            }
            let window = CalendarPlanInterval(start: max(workStartDate, .now), end: workEndDate)
            for slot in CalendarPlanLogic.freeSlots(in: window, busy: busy) {
                let rounded = Date(timeIntervalSince1970: ceil(slot.start.timeIntervalSince1970 / 900) * 900)
                let end = rounded.addingTimeInterval(TimeInterval(duration * 60))
                guard end <= slot.end else { continue }
                if let due = task.dueDate, end > due { continue }
                result.append(.init(start: rounded, end: end))
                if result.count == 3 { return result }
            }
        }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            Text("安排时间 · \(task.title)").font(AppTypography.title)
            if task.planLocked { Label("计划已锁定，请先在事项详情中解锁。", systemImage: "lock.fill") }
            Toggle("指定执行时间", isOn: $hasTime)
            DatePicker("计划日期与开始", selection: $start, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
            if hasTime {
                Stepper("预留 \(duration) 分钟", value: $duration, in: 15...480, step: 15)
                Text("结束 \(end.formatted(.dateTime.month().day().hour().minute())) · 预计工作量 \(task.estimatedMinutes) 分钟")
                    .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                if !suggestedSlots.isEmpty {
                    VStack(alignment: .leading, spacing: AppSpacing.x1) {
                        Text("可选空档").font(AppTypography.headline)
                        ForEach(suggestedSlots, id: \.start) { slot in
                            Button("\(slot.start.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute()))–\(slot.end.formatted(.dateTime.hour().minute()))") {
                                start = slot.start
                                allowConflict = false
                            }
                        }
                        Text("依据序内任务及已读取的系统日程计算")
                            .font(AppTypography.caption).foregroundStyle(AppColors.textSecondary)
                    }
                }
            }
            if !conflicts.isEmpty {
                Label("与 \(conflicts.joined(separator: "、")) 重叠", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppColors.warning)
                Toggle("仍然保留重叠安排", isOn: $allowConflict)
            }
            if !unmetDependencies.isEmpty {
                Label("前置事项未完成：\(unmetDependencies.joined(separator: "、"))", systemImage: "arrow.triangle.branch")
                    .foregroundStyle(AppColors.warning)
            }
            if let due = task.dueDate, end > due && hasTime {
                Label("安排晚于截止时间，截止保持 \(due.formatted(.dateTime.month().day().hour().minute()))", systemImage: "flag")
                    .foregroundStyle(AppColors.warning)
            }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存安排") { save() }
                    .disabled(task.planLocked || (!conflicts.isEmpty && !allowConflict))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.x6)
        .frame(width: 460)
    }

    private func save() {
        var updated = task
        updated.scheduledFor = start
        if task.isUnscheduled { updated.status = .pending }
        updated.timeBlock = hasTime ? TaskTimeBlock(id: task.timeBlock?.id ?? UUID(), start: start, end: end) : nil
        if store.update(updated) { onSaved(task, updated); dismiss() }
    }
}

private struct CalendarWorkHoursDialog: View {
    @AppDismiss private var dismiss
    @State private var startHour = UserDefaults.standard.object(forKey: "calendar.workStartHour") as? Int ?? 9
    @State private var endHour = UserDefaults.standard.object(forKey: "calendar.workEndHour") as? Int ?? 18
    @State private var daysMask = UserDefaults.standard.object(forKey: "calendar.workDaysMask") as? Int ?? 127
    @State private var lunchBreak = UserDefaults.standard.bool(forKey: "calendar.lunchBreakEnabled")
    private let names = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.section) {
            Text("可安排工作时段").font(AppTypography.title)
            Text("日历的可用时间和最长连续空档按这里计算。")
                .font(AppTypography.callout).foregroundStyle(AppColors.textSecondary)
            Stepper("开始 \(String(format: "%02d:00", startHour))", value: $startHour, in: 8...20)
            Stepper("结束 \(String(format: "%02d:00", endHour))", value: $endHour, in: 9...21)
            Toggle("12:00–13:00 午休", isOn: $lunchBreak)
            Text("每周可安排日期").font(AppTypography.headline)
            HStack(spacing: AppSpacing.x2) {
                ForEach(1...7, id: \.self) { day in
                    Toggle(names[day - 1], isOn: Binding(
                        get: { daysMask & (1 << (day - 1)) != 0 },
                        set: { enabled in
                            if enabled { daysMask |= 1 << (day - 1) }
                            else { daysMask &= ~(1 << (day - 1)) }
                        }
                    )).toggleStyle(.checkbox)
                }
            }
            if startHour >= endHour {
                Label("结束时间需晚于开始时间", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(AppColors.warning)
            }
            HStack {
                Button("取消") { dismiss() }
                Spacer()
                Button("保存") {
                    UserDefaults.standard.set(startHour, forKey: "calendar.workStartHour")
                    UserDefaults.standard.set(endHour, forKey: "calendar.workEndHour")
                    UserDefaults.standard.set(daysMask, forKey: "calendar.workDaysMask")
                    UserDefaults.standard.set(lunchBreak, forKey: "calendar.lunchBreakEnabled")
                    dismiss()
                }
                .disabled(startHour >= endHour || daysMask == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(AppSpacing.x6)
        .frame(width: 540)
    }
}
