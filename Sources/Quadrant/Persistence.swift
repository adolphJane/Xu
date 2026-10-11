import Foundation
import SwiftData

enum BlueprintStatus: String, CaseIterable, Codable, Identifiable {
    case draft
    case active
    case paused
    case completed
    case cancelled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .draft: "草稿"
        case .active: "执行中"
        case .paused: "已暂停"
        case .completed: "已完成"
        case .cancelled: "已取消"
        }
    }
}

struct BlueprintItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var goal: String = ""
    var startDate: Date = .now
    var dueDate: Date
    var status: BlueprintStatus = .active
    var colorHex: String = "4F65D9"
    var createdAt: Date = .now
    var originalDueDate: Date? = nil
    var archivedAt: Date? = nil
}

struct StageItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var blueprintID: UUID
    var name: String
    var order: Int
    var startDate: Date = .now
    var dueDate: Date
    var originalStartDate: Date? = nil
    var originalDueDate: Date? = nil
}

struct MilestoneItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var blueprintID: UUID
    var stageID: UUID
    var name: String
    var dueDate: Date
    var isCompleted = false
}

struct DailyReportItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var reportDate: Date = .now
    var minimumLength: Int
    var maximumLength: Int
    var supplement: String
    var content: String
    var createdAt: Date = .now
}

@Model
final class StoredTask {
    @Attribute(.unique) var id: UUID
    var title: String
    var notes: String
    var project: String?
    var category: String?
    var reportCategoryRaw: String?
    var quadrantRaw: String
    var scheduledFor: Date
    var dueDate: Date?
    var estimatedMinutes: Int
    var statusRaw: String
    var completedAt: Date?
    var createdAt: Date
    var blueprintID: UUID?
    var stageID: UUID?
    var milestoneID: UUID?
    var startedAt: Date?
    var originalScheduledFor: Date?
    var blockReason: String?
    var statusChangedAt: Date?
    var parentTaskID: UUID?
    var dependencyIDsRaw: String?
    var originalDueDate: Date?
    var isPlanLocked: Bool?
    var workflowX: Double?
    var workflowY: Double?
    var workflowImagesData: Data?

    init(_ item: TaskItem) {
        id = item.id
        title = item.title
        notes = item.notes
        project = item.project
        category = item.category
        reportCategoryRaw = item.reportCategory?.rawValue
        quadrantRaw = item.quadrant.rawValue
        scheduledFor = item.scheduledFor
        dueDate = item.dueDate
        estimatedMinutes = item.estimatedMinutes
        statusRaw = item.effectiveStatus.rawValue
        completedAt = item.completedAt
        createdAt = item.createdAt
        blueprintID = item.blueprintID
        stageID = item.stageID
        milestoneID = item.milestoneID
        startedAt = item.startedAt
        originalScheduledFor = item.originalScheduledFor
        blockReason = item.blockReason
        statusChangedAt = item.statusChangedAt
        parentTaskID = item.parentTaskID
        dependencyIDsRaw = Self.encodeIDs(item.effectiveDependencyIDs)
        originalDueDate = item.originalDueDate
        isPlanLocked = item.isPlanLocked
        workflowX = item.workflowX
        workflowY = item.workflowY
        workflowImagesData = try? JSONEncoder().encode(item.images)
    }

    func update(from item: TaskItem, preserveWorkflowImages: Bool = false) {
        title = item.title
        notes = item.notes
        project = item.project
        category = item.category
        reportCategoryRaw = item.reportCategory?.rawValue
        quadrantRaw = item.quadrant.rawValue
        scheduledFor = item.scheduledFor
        dueDate = item.dueDate
        estimatedMinutes = item.estimatedMinutes
        statusRaw = item.effectiveStatus.rawValue
        completedAt = item.completedAt
        createdAt = item.createdAt
        blueprintID = item.blueprintID
        stageID = item.stageID
        milestoneID = item.milestoneID
        startedAt = item.startedAt
        originalScheduledFor = item.originalScheduledFor
        blockReason = item.blockReason
        statusChangedAt = item.statusChangedAt
        parentTaskID = item.parentTaskID
        dependencyIDsRaw = Self.encodeIDs(item.effectiveDependencyIDs)
        originalDueDate = item.originalDueDate
        isPlanLocked = item.isPlanLocked
        workflowX = item.workflowX
        workflowY = item.workflowY
        if !preserveWorkflowImages {
            workflowImagesData = try? JSONEncoder().encode(item.images)
        }
    }

    var item: TaskItem {
        TaskItem(
            id: id,
            title: title,
            notes: notes,
            project: project,
            category: category,
            reportCategory: reportCategoryRaw.flatMap(ReportCategory.init(rawValue:)),
            quadrant: Quadrant(rawValue: quadrantRaw) ?? .schedule,
            scheduledFor: scheduledFor,
            dueDate: dueDate,
            estimatedMinutes: estimatedMinutes,
            isComplete: statusRaw == TaskStatus.completed.rawValue,
            status: TaskStatus(rawValue: statusRaw) ?? .pending,
            completedAt: completedAt,
            createdAt: createdAt,
            blueprintID: blueprintID,
            stageID: stageID,
            milestoneID: milestoneID,
            startedAt: startedAt,
            originalScheduledFor: originalScheduledFor,
            blockReason: blockReason,
            statusChangedAt: statusChangedAt,
            parentTaskID: parentTaskID,
            dependencyIDs: Self.decodeIDs(dependencyIDsRaw),
            originalDueDate: originalDueDate,
            isPlanLocked: isPlanLocked,
            workflowX: workflowX,
            workflowY: workflowY,
            workflowImages: workflowImagesData.flatMap { try? JSONDecoder().decode([WorkflowImage].self, from: $0) }
        )
    }

    private static func encodeIDs(_ ids: [UUID]) -> String? {
        ids.isEmpty ? nil : ids.map(\.uuidString).joined(separator: ",")
    }

    private static func decodeIDs(_ value: String?) -> [UUID]? {
        guard let value, !value.isEmpty else { return nil }
        return value.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
    }
}

@Model
final class StoredBlueprint {
    @Attribute(.unique) var id: UUID
    var name: String
    var goal: String
    var startDate: Date
    var dueDate: Date
    var statusRaw: String
    var colorHex: String
    var createdAt: Date
    var originalDueDate: Date?
    var archivedAt: Date?

    init(_ item: BlueprintItem) {
        id = item.id
        name = item.name
        goal = item.goal
        startDate = item.startDate
        dueDate = item.dueDate
        statusRaw = item.status.rawValue
        colorHex = item.colorHex
        createdAt = item.createdAt
        originalDueDate = item.originalDueDate
        archivedAt = item.archivedAt
    }

    func update(from item: BlueprintItem) {
        name = item.name
        goal = item.goal
        startDate = item.startDate
        dueDate = item.dueDate
        statusRaw = item.status.rawValue
        colorHex = item.colorHex
        originalDueDate = item.originalDueDate
        archivedAt = item.archivedAt
    }

    var item: BlueprintItem {
        BlueprintItem(id: id, name: name, goal: goal, startDate: startDate, dueDate: dueDate, status: BlueprintStatus(rawValue: statusRaw) ?? .active, colorHex: colorHex, createdAt: createdAt, originalDueDate: originalDueDate, archivedAt: archivedAt)
    }
}

@Model
final class StoredStage {
    @Attribute(.unique) var id: UUID
    var blueprintID: UUID
    var name: String
    var order: Int
    var startDate: Date
    var dueDate: Date
    var originalStartDate: Date?
    var originalDueDate: Date?

    init(_ item: StageItem) {
        id = item.id
        blueprintID = item.blueprintID
        name = item.name
        order = item.order
        startDate = item.startDate
        dueDate = item.dueDate
        originalStartDate = item.originalStartDate
        originalDueDate = item.originalDueDate
    }

    func update(from item: StageItem) {
        name = item.name
        order = item.order
        startDate = item.startDate
        dueDate = item.dueDate
        originalStartDate = item.originalStartDate
        originalDueDate = item.originalDueDate
    }

    var item: StageItem { StageItem(id: id, blueprintID: blueprintID, name: name, order: order, startDate: startDate, dueDate: dueDate, originalStartDate: originalStartDate, originalDueDate: originalDueDate) }
}

@Model
final class StoredAnniversary {
    @Attribute(.unique) var id: UUID
    var name: String
    var date: Date
    var typeRaw: String
    var notes: String
    var contact: String
    var coverPath: String?
    var calendarRaw: String
    var repeatRaw: String
    var reminderDays: Int
    var showOnHome: Bool
    var showInMenuBar: Bool
    var showNotification: Bool
    var privacyMode: Bool
    var blueprintID: UUID?
    var preparationEnabled: Bool
    var preparationLeadDays: Int
    var preparationTaskTitle: String
    var generatedTaskID: UUID?
    var createdAt: Date

    init(_ item: AnniversaryItem) {
        id = item.id; name = item.name; date = item.date; typeRaw = item.type.rawValue
        notes = item.notes; contact = item.contact; coverPath = item.coverPath
        calendarRaw = item.calendar.rawValue; repeatRaw = item.repeatRule.rawValue
        reminderDays = item.reminderDays; showOnHome = item.showOnHome
        showInMenuBar = item.showInMenuBar; showNotification = item.showNotification
        privacyMode = item.privacyMode; blueprintID = item.blueprintID
        preparationEnabled = item.preparationEnabled; preparationLeadDays = item.preparationLeadDays
        preparationTaskTitle = item.preparationTaskTitle; generatedTaskID = item.generatedTaskID
        createdAt = item.createdAt
    }

    func update(from item: AnniversaryItem) {
        name = item.name; date = item.date; typeRaw = item.type.rawValue
        notes = item.notes; contact = item.contact; coverPath = item.coverPath
        calendarRaw = item.calendar.rawValue; repeatRaw = item.repeatRule.rawValue
        reminderDays = item.reminderDays; showOnHome = item.showOnHome
        showInMenuBar = item.showInMenuBar; showNotification = item.showNotification
        privacyMode = item.privacyMode; blueprintID = item.blueprintID
        preparationEnabled = item.preparationEnabled; preparationLeadDays = item.preparationLeadDays
        preparationTaskTitle = item.preparationTaskTitle; generatedTaskID = item.generatedTaskID
    }

    var item: AnniversaryItem {
        AnniversaryItem(
            id: id, name: name, date: date,
            type: AnniversaryType(rawValue: typeRaw) ?? .custom,
            notes: notes, contact: contact, coverPath: coverPath,
            calendar: AnniversaryCalendar(rawValue: calendarRaw) ?? .solar,
            repeatRule: AnniversaryRepeat(rawValue: repeatRaw) ?? .yearly,
            reminderDays: reminderDays, showOnHome: showOnHome,
            showInMenuBar: showInMenuBar, showNotification: showNotification,
            privacyMode: privacyMode, blueprintID: blueprintID,
            preparationEnabled: preparationEnabled, preparationLeadDays: preparationLeadDays,
            preparationTaskTitle: preparationTaskTitle, generatedTaskID: generatedTaskID,
            createdAt: createdAt
        )
    }
}

@Model
final class StoredWeeklyReview {
    @Attribute(.unique) var id: UUID
    var weekStart: Date
    var summary: String
    var nextWeekFocus: String
    var createdAt: Date

    init(_ item: WeeklyReviewItem) {
        id = item.id; weekStart = item.weekStart; summary = item.summary
        nextWeekFocus = item.nextWeekFocus; createdAt = item.createdAt
    }

    func update(from item: WeeklyReviewItem) {
        weekStart = item.weekStart; summary = item.summary; nextWeekFocus = item.nextWeekFocus
    }

    var item: WeeklyReviewItem {
        WeeklyReviewItem(id: id, weekStart: weekStart, summary: summary, nextWeekFocus: nextWeekFocus, createdAt: createdAt)
    }
}

@Model
final class StoredPlanChange {
    @Attribute(.unique) var id: UUID
    var kindRaw: String
    var title: String
    var beforeData: Data
    var afterData: Data
    var createdAt: Date
    var isUndone: Bool

    init(_ item: PlanChangeItem) {
        id = item.id; kindRaw = item.kind.rawValue; title = item.title
        beforeData = item.beforeData; afterData = item.afterData
        createdAt = item.createdAt; isUndone = item.isUndone
    }

    func update(from item: PlanChangeItem) {
        kindRaw = item.kind.rawValue; title = item.title
        beforeData = item.beforeData; afterData = item.afterData; isUndone = item.isUndone
    }

    var item: PlanChangeItem {
        PlanChangeItem(id: id, kind: PlanChangeKind(rawValue: kindRaw) ?? .aiReplan, title: title, beforeData: beforeData, afterData: afterData, createdAt: createdAt, isUndone: isUndone)
    }
}

@Model
final class StoredMilestone {
    @Attribute(.unique) var id: UUID
    var blueprintID: UUID
    var stageID: UUID
    var name: String
    var dueDate: Date
    var isCompleted: Bool

    init(_ item: MilestoneItem) {
        id = item.id
        blueprintID = item.blueprintID
        stageID = item.stageID
        name = item.name
        dueDate = item.dueDate
        isCompleted = item.isCompleted
    }

    func update(from item: MilestoneItem) {
        name = item.name
        dueDate = item.dueDate
        isCompleted = item.isCompleted
    }

    var item: MilestoneItem { MilestoneItem(id: id, blueprintID: blueprintID, stageID: stageID, name: name, dueDate: dueDate, isCompleted: isCompleted) }
}

@Model
final class StoredDailyReport {
    @Attribute(.unique) var id: UUID
    var reportDate: Date
    var minimumLength: Int
    var maximumLength: Int
    var supplement: String
    var content: String
    var createdAt: Date

    init(_ item: DailyReportItem) {
        id = item.id
        reportDate = item.reportDate
        minimumLength = item.minimumLength
        maximumLength = item.maximumLength
        supplement = item.supplement
        content = item.content
        createdAt = item.createdAt
    }

    func update(from item: DailyReportItem) {
        reportDate = item.reportDate
        minimumLength = item.minimumLength
        maximumLength = item.maximumLength
        supplement = item.supplement
        content = item.content
    }

    var item: DailyReportItem {
        DailyReportItem(id: id, reportDate: reportDate, minimumLength: minimumLength, maximumLength: maximumLength, supplement: supplement, content: content, createdAt: createdAt)
    }
}

@MainActor
final class PersistenceController {
    private let container: ModelContainer
    private let context: ModelContext

    init(inMemory: Bool = false) throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(
            for: StoredTask.self,
            StoredBlueprint.self,
            StoredStage.self,
            StoredMilestone.self,
            StoredDailyReport.self,
            StoredAnniversary.self,
            StoredWeeklyReview.self,
            StoredPlanChange.self,
            configurations: configuration
        )
        context = container.mainContext
    }

    func loadTasks() throws -> [TaskItem] {
        try context.fetch(FetchDescriptor<StoredTask>()).map(\.item)
    }

    func loadBlueprints() throws -> [BlueprintItem] {
        try context.fetch(FetchDescriptor<StoredBlueprint>()).map(\.item)
    }

    func loadStages() throws -> [StageItem] {
        try context.fetch(FetchDescriptor<StoredStage>()).map(\.item)
    }

    func loadMilestones() throws -> [MilestoneItem] {
        try context.fetch(FetchDescriptor<StoredMilestone>()).map(\.item)
    }

    func loadReports() throws -> [DailyReportItem] {
        try context.fetch(FetchDescriptor<StoredDailyReport>()).map(\.item)
    }

    func loadAnniversaries() throws -> [AnniversaryItem] {
        try context.fetch(FetchDescriptor<StoredAnniversary>()).map(\.item)
    }

    func loadWeeklyReviews() throws -> [WeeklyReviewItem] {
        try context.fetch(FetchDescriptor<StoredWeeklyReview>()).map(\.item)
    }

    func loadPlanChanges() throws -> [PlanChangeItem] {
        try context.fetch(FetchDescriptor<StoredPlanChange>()).map(\.item)
    }

    func saveTasks(_ items: [TaskItem]) throws { try sync(items, records: context.fetch(FetchDescriptor<StoredTask>()), id: \.id, make: StoredTask.init, update: { $0.update(from: $1) }) }
    func saveTask(_ item: TaskItem) throws {
        let taskID = item.id
        let descriptor = FetchDescriptor<StoredTask>(predicate: #Predicate { $0.id == taskID })
        if let record = try context.fetch(descriptor).first {
            record.update(from: item, preserveWorkflowImages: true)
        } else {
            context.insert(StoredTask(item))
        }
        try context.save()
    }
    func saveBlueprints(_ items: [BlueprintItem]) throws { try sync(items, records: context.fetch(FetchDescriptor<StoredBlueprint>()), id: \.id, make: StoredBlueprint.init, update: { $0.update(from: $1) }) }
    func saveStages(_ items: [StageItem]) throws { try sync(items, records: context.fetch(FetchDescriptor<StoredStage>()), id: \.id, make: StoredStage.init, update: { $0.update(from: $1) }) }
    func saveMilestones(_ items: [MilestoneItem]) throws { try sync(items, records: context.fetch(FetchDescriptor<StoredMilestone>()), id: \.id, make: StoredMilestone.init, update: { $0.update(from: $1) }) }
    func saveReports(_ items: [DailyReportItem]) throws { try sync(items, records: context.fetch(FetchDescriptor<StoredDailyReport>()), id: \.id, make: StoredDailyReport.init, update: { $0.update(from: $1) }) }
    func saveAnniversaries(_ items: [AnniversaryItem]) throws { try sync(items, records: context.fetch(FetchDescriptor<StoredAnniversary>()), id: \.id, make: StoredAnniversary.init, update: { $0.update(from: $1) }) }
    func saveWeeklyReviews(_ items: [WeeklyReviewItem]) throws { try sync(items, records: context.fetch(FetchDescriptor<StoredWeeklyReview>()), id: \.id, make: StoredWeeklyReview.init, update: { $0.update(from: $1) }) }
    func savePlanChanges(_ items: [PlanChangeItem]) throws { try sync(items, records: context.fetch(FetchDescriptor<StoredPlanChange>()), id: \.id, make: StoredPlanChange.init, update: { $0.update(from: $1) }) }

    private func sync<Item, Record: PersistentModel>(
        _ items: [Item],
        records: [Record],
        id itemID: KeyPath<Item, UUID>,
        make: (Item) -> Record,
        update: (Record, Item) -> Void
    ) throws {
        let itemIDs = Set(items.map { $0[keyPath: itemID] })
        var recordsByID: [UUID: Record] = [:]
        for record in records {
            if let identifiable = record as? any UUIDIdentifiedRecord {
                recordsByID[identifiable.uuid] = record
            }
        }
        for item in items {
            if let record = recordsByID[item[keyPath: itemID]] { update(record, item) }
            else { context.insert(make(item)) }
        }
        for record in records {
            if let identifiable = record as? any UUIDIdentifiedRecord, !itemIDs.contains(identifiable.uuid) {
                context.delete(record)
            }
        }
        try context.save()
    }
}

private protocol UUIDIdentifiedRecord {
    var uuid: UUID { get }
}

extension StoredTask: UUIDIdentifiedRecord { var uuid: UUID { id } }
extension StoredBlueprint: UUIDIdentifiedRecord { var uuid: UUID { id } }
extension StoredStage: UUIDIdentifiedRecord { var uuid: UUID { id } }
extension StoredMilestone: UUIDIdentifiedRecord { var uuid: UUID { id } }
extension StoredDailyReport: UUIDIdentifiedRecord { var uuid: UUID { id } }
extension StoredAnniversary: UUIDIdentifiedRecord { var uuid: UUID { id } }
extension StoredWeeklyReview: UUIDIdentifiedRecord { var uuid: UUID { id } }
extension StoredPlanChange: UUIDIdentifiedRecord { var uuid: UUID { id } }
