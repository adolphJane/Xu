import Foundation
import SwiftUI

struct WorkspaceSnapshot: Codable, Equatable {
    var formatVersion = 1
    var generatedAt = Date.now
    var tasks: [TaskItem]
    var blueprints: [BlueprintItem]
    var stages: [StageItem]
    var milestones: [MilestoneItem]
    var reports: [DailyReportItem]
    var anniversaries: [AnniversaryItem]
    var weeklyReviews: [WeeklyReviewItem]
    var categories: [String]? = nil

    var isValid: Bool {
        formatVersion == 1
            && Set(tasks.map(\.id)).count == tasks.count
            && Set(blueprints.map(\.id)).count == blueprints.count
            && Set(stages.map(\.id)).count == stages.count
            && Set(milestones.map(\.id)).count == milestones.count
            && Set(reports.map(\.id)).count == reports.count
            && Set(anniversaries.map(\.id)).count == anniversaries.count
            && Set(weeklyReviews.map(\.id)).count == weeklyReviews.count
    }
}

enum ReportTaskGrouping {
    static func usingBlueprintNames(_ tasks: [TaskItem], blueprints: [BlueprintItem]) -> [TaskItem] {
        let names = Dictionary(uniqueKeysWithValues: blueprints.map { ($0.id, $0.name) })
        return tasks.map { task in
            var copy = task
            if let blueprintID = task.blueprintID, let name = names[blueprintID] { copy.project = name }
            return copy
        }
    }
}

enum PlanChangeKind: String, Codable {
    case aiBlueprint
    case aiReplan
    case restore
}

struct PlanChangeItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var kind: PlanChangeKind
    var title: String
    var beforeData: Data
    var afterData: Data
    var createdAt = Date.now
    var isUndone = false
}

struct AIBlueprintDraft: Codable, Equatable {
    var name: String
    var goal: String
    var startDate: Date
    var dueDate: Date
    var colorHex: String = "4F65D9"
    var stages: [AIStageDraft]
}

struct AIStageDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var startDate: Date
    var dueDate: Date
    var milestone: String
    var tasks: [AITaskDraft]
}

struct AITaskDraft: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var scheduledFor: Date
    var dueDate: Date?
    var estimatedMinutes: Int
    var quadrant: Quadrant
    var notes: String = ""
    var isIncluded = true
}

struct AIReplanProposal: Codable, Equatable {
    var summary: String
    var changes: [AIReplanChange]
}

struct AIReplanChange: Identifiable, Codable, Equatable {
    var id = UUID()
    var taskID: UUID
    var newScheduledFor: Date
    var newDueDate: Date?
    var reason: String
    var isIncluded = true
}

extension AIBlueprintDraft {
    private enum CodingKeys: String, CodingKey { case name, goal, startDate, dueDate, colorHex, stages }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        name = try values.decode(String.self, forKey: .name)
        goal = try values.decode(String.self, forKey: .goal)
        startDate = try values.decode(Date.self, forKey: .startDate)
        dueDate = try values.decode(Date.self, forKey: .dueDate)
        colorHex = try values.decodeIfPresent(String.self, forKey: .colorHex) ?? "4F65D9"
        stages = try values.decode([AIStageDraft].self, forKey: .stages)
    }
}

extension AIStageDraft {
    private enum CodingKeys: String, CodingKey { case name, startDate, dueDate, milestone, tasks }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        name = try values.decode(String.self, forKey: .name)
        startDate = try values.decode(Date.self, forKey: .startDate)
        dueDate = try values.decode(Date.self, forKey: .dueDate)
        milestone = try values.decodeIfPresent(String.self, forKey: .milestone) ?? "完成阶段验收"
        tasks = try values.decode([AITaskDraft].self, forKey: .tasks)
    }
}

extension AITaskDraft {
    private enum CodingKeys: String, CodingKey { case title, scheduledFor, dueDate, estimatedMinutes, quadrant, notes }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        title = try values.decode(String.self, forKey: .title)
        scheduledFor = try values.decode(Date.self, forKey: .scheduledFor)
        dueDate = try values.decodeIfPresent(Date.self, forKey: .dueDate)
        estimatedMinutes = min(max(try values.decodeIfPresent(Int.self, forKey: .estimatedMinutes) ?? 30, 5), 480)
        quadrant = try values.decodeIfPresent(Quadrant.self, forKey: .quadrant) ?? .schedule
        notes = try values.decodeIfPresent(String.self, forKey: .notes) ?? ""
        isIncluded = true
    }
}

extension AIReplanChange {
    private enum CodingKeys: String, CodingKey { case taskID, newScheduledFor, newDueDate, reason }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        taskID = try values.decode(UUID.self, forKey: .taskID)
        newScheduledFor = try values.decode(Date.self, forKey: .newScheduledFor)
        newDueDate = try values.decodeIfPresent(Date.self, forKey: .newDueDate)
        reason = try values.decodeIfPresent(String.self, forKey: .reason) ?? "容量与依赖调整"
        isIncluded = true
    }
}

enum AIReplanRule {
    static func applying(_ proposal: AIReplanProposal, to source: [TaskItem], blueprintID: UUID? = nil) -> [TaskItem] {
        var result = source
        let allowedIDs = Set(source.filter { task in
            task.needsAction && !task.isUnscheduled && !task.planLocked
                && (blueprintID == nil || task.blueprintID == blueprintID)
        }.map(\.id))
        let changedIDs = Set(proposal.changes.filter { $0.isIncluded && allowedIDs.contains($0.taskID) }.map(\.taskID))
        for change in proposal.changes where change.isIncluded {
            guard allowedIDs.contains(change.taskID), let index = result.firstIndex(where: { $0.id == change.taskID }) else { continue }
            result[index].originalScheduledFor = result[index].originalScheduledFor ?? result[index].scheduledFor
            result[index].originalDueDate = result[index].originalDueDate ?? result[index].dueDate
            result[index].scheduledFor = change.newScheduledFor
            result[index].dueDate = change.newDueDate
        }
        for _ in 0..<result.count {
            var adjusted = false
            for index in result.indices where changedIDs.contains(result[index].id) {
                let dependencyDates = result[index].effectiveDependencyIDs.compactMap { dependencyID in
                    result.first(where: { $0.id == dependencyID }).map { $0.dueDate ?? $0.scheduledFor }
                }
                if let latest = dependencyDates.max(), result[index].scheduledFor < latest {
                    result[index].scheduledFor = latest
                    adjusted = true
                }
                if let due = result[index].dueDate, due < result[index].scheduledFor {
                    result[index].dueDate = result[index].scheduledFor.addingTimeInterval(TimeInterval(result[index].estimatedMinutes * 60))
                }
            }
            if !adjusted { break }
        }
        return result
    }
}

enum SnapshotMerge {
    static func merge(local: WorkspaceSnapshot, remote: WorkspaceSnapshot) -> WorkspaceSnapshot {
        func union<T: Identifiable>(_ local: [T], _ remote: [T]) -> [T] where T.ID == UUID {
            var result = Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0) })
            for item in local { result[item.id] = item }
            return Array(result.values)
        }
        return WorkspaceSnapshot(
            tasks: union(local.tasks, remote.tasks), blueprints: union(local.blueprints, remote.blueprints),
            stages: union(local.stages, remote.stages), milestones: union(local.milestones, remote.milestones),
            reports: union(local.reports, remote.reports), anniversaries: union(local.anniversaries, remote.anniversaries),
            weeklyReviews: union(local.weeklyReviews, remote.weeklyReviews),
            categories: Array(Set((local.categories ?? []) + (remote.categories ?? []))).sorted()
        )
    }
}

struct SyncEnvelope: Codable {
    var formatVersion = 1
    var revision: Int
    var deviceID: String
    var generatedAt = Date.now
    var snapshot: WorkspaceSnapshot
    var checksum: String
}

struct SyncConflict: Identifiable {
    var id = UUID()
    var remote: SyncEnvelope
    var local: WorkspaceSnapshot
    var message: String
}

enum SyncResolution {
    case merge
    case keepLocal
    case useRemote
}

enum BackupFormat: String, CaseIterable, Identifiable {
    case json = "JSON 完整备份"
    case markdown = "Markdown 阅读版"
    case csv = "CSV 任务表"

    var id: String { rawValue }
    var fileExtension: String {
        switch self { case .json: "json"; case .markdown: "md"; case .csv: "csv" }
    }
}

enum AppFontStyle: String, CaseIterable, Codable, Identifiable {
    case system = "系统"
    case rounded = "圆体"
    case serif = "衬线"
    case monospaced = "等宽"

    var id: String { rawValue }
    var design: Font.Design {
        switch self { case .system: .default; case .rounded: .rounded; case .serif: .serif; case .monospaced: .monospaced }
    }
}

enum AppIconStyle: String, CaseIterable, Codable, Identifiable {
    case colorful = "彩色"
    case monochrome = "单色"
    case minimal = "极简"

    var id: String { rawValue }
}

enum AutomaticThemeRule: String, CaseIterable, Codable, Identifiable {
    case manual = "手动"
    case system = "跟随系统外观"
    case time = "按时间切换"
    case focus = "专注模式"

    var id: String { rawValue }
}

struct PersonalTheme: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var preset: ThemePreset
    var accentHex: String
    var backgroundHex: String
    var cardHex: String
    var fontStyle: AppFontStyle
    var iconStyle: AppIconStyle
    var backgroundImagePath: String?
    var highContrast: Bool
    var reduceMotion: Bool
    var createdAt = Date.now
}

struct CalendarEventItem: Identifiable, Equatable {
    var id: String
    var title: String
    var startDate: Date
    var endDate: Date
    var calendarTitle: String
    var isAllDay: Bool
}

struct UpdateManifest: Codable, Equatable {
    var version: String
    var downloadURL: String
    var notes: String
    var sha256: String?
}

enum CommandPaletteAction: String, CaseIterable, Identifiable {
    case addTask = "新增待办事项"
    case addCompleted = "记录已完成事项"
    case aiTask = "AI 一句话生成任务"
    case aiBlueprint = "AI 生成完整蓝图"
    case dailyReport = "生成今日日报"
    case openToday = "打开今日"
    case openBlueprints = "打开蓝图"
    case openAnniversaries = "打开纪念日"
    case openWidget = "打开桌面小组件"
    case toggleFocusTheme = "切换专注主题"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .addTask: "plus.circle"
        case .addCompleted: "checkmark.circle"
        case .aiTask, .aiBlueprint: "sparkles"
        case .dailyReport: "doc.text"
        case .openToday: "sun.max"
        case .openBlueprints: "point.3.connected.trianglepath.dotted"
        case .openAnniversaries: "heart.circle"
        case .openWidget: "rectangle.inset.filled"
        case .toggleFocusTheme: "moon.stars"
        }
    }
}

struct TodayBlueprintTaskGroup: Identifiable, Equatable {
    var id: UUID { blueprint.id }
    let blueprint: BlueprintItem
    let tasks: [TaskItem]
}

enum TaskPlacement {
    static func isInToday(_ task: TaskItem, date: Date = .now, calendar: Calendar = .current) -> Bool {
        if task.isUnscheduled { return false }
        if calendar.isDate(task.scheduledFor, inSameDayAs: date) { return true }
        if task.isCompleted, let completedAt = task.completedAt,
           calendar.isDate(completedAt, inSameDayAs: date) { return true }
        return task.needsAction && task.scheduledFor < calendar.startOfDay(for: date)
    }
}

enum TodayBlueprintOrganizer {
    static func groups(
        tasks: [TaskItem],
        blueprints: [BlueprintItem],
        date: Date = .now,
        calendar: Calendar = .current
    ) -> [TodayBlueprintTaskGroup] {
        let todayTasks = tasks.filter { TaskPlacement.isInToday($0, date: date, calendar: calendar) }
        return blueprints.compactMap { blueprint in
            let scoped = sortedTasks(todayTasks.filter { $0.blueprintID == blueprint.id })
            return scoped.isEmpty ? nil : TodayBlueprintTaskGroup(blueprint: blueprint, tasks: scoped)
        }
    }

    static func unassignedTasks(
        tasks: [TaskItem],
        blueprints: [BlueprintItem],
        date: Date = .now,
        calendar: Calendar = .current
    ) -> [TaskItem] {
        let blueprintIDs = Set(blueprints.map(\.id))
        return sortedTasks(tasks.filter { task in
            guard TaskPlacement.isInToday(task, date: date, calendar: calendar) else { return false }
            return task.blueprintID.map { !blueprintIDs.contains($0) } ?? true
        })
    }

    static func sortedTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        tasks.sorted { lhs, rhs in
            if lhs.needsAction != rhs.needsAction { return lhs.needsAction }
            if lhs.isInProgress != rhs.isInProgress { return lhs.isInProgress }
            if (lhs.quadrant == .doNow) != (rhs.quadrant == .doNow) { return lhs.quadrant == .doNow }
            if (lhs.dueDate ?? .distantFuture) != (rhs.dueDate ?? .distantFuture) {
                return (lhs.dueDate ?? .distantFuture) < (rhs.dueDate ?? .distantFuture)
            }
            return lhs.createdAt < rhs.createdAt
        }
    }
}

extension Notification.Name {
    static let showCommandPalette = Notification.Name("sequence.showCommandPalette")
}
