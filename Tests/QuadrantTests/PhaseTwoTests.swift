import XCTest
@testable import Quadrant

@MainActor
final class PhaseTwoTests: XCTestCase {
    func testDependencyCycleIsRejected() {
        let firstID = UUID()
        let secondID = UUID()
        let first = TaskItem(id: firstID, title: "第一项", quadrant: .schedule, dependencyIDs: [secondID])
        let second = TaskItem(id: secondID, title: "第二项", quadrant: .schedule)

        XCTAssertTrue(DependencyRule.wouldCreateCycle(taskID: secondID, adding: firstID, tasks: [first, second]))
        XCTAssertTrue(DependencyRule.wouldCreateCycle(taskID: firstID, adding: firstID, tasks: [first, second]))
    }

    func testDependenciesUnlockOnlyAfterCompletion() {
        let prerequisite = TaskItem(title: "完成设计", quadrant: .doNow, status: .pending)
        let task = TaskItem(title: "开始开发", quadrant: .schedule, dependencyIDs: [prerequisite.id])

        XCTAssertEqual(DependencyRule.unmetDependencies(for: task, tasks: [prerequisite, task]).map(\.id), [prerequisite.id])

        var completed = prerequisite
        completed.status = .completed
        completed.isComplete = true
        XCTAssertTrue(DependencyRule.unmetDependencies(for: task, tasks: [completed, task]).isEmpty)
    }

    func testPhaseTwoPersistenceRoundTrip() throws {
        let persistence = try PersistenceController(inMemory: true)
        let dependencyID = UUID()
        let task = TaskItem(title: "依赖任务", quadrant: .schedule, dependencyIDs: [dependencyID], originalDueDate: .now)
        let anniversary = AnniversaryItem(name: "产品发布", date: .now, type: .project, reminderDays: 3, privacyMode: true, preparationEnabled: true)
        let review = WeeklyReviewItem(weekStart: .now, summary: "完成核心功能", nextWeekFocus: "稳定性测试")

        try persistence.saveTasks([task])
        try persistence.saveAnniversaries([anniversary])
        try persistence.saveWeeklyReviews([review])

        XCTAssertEqual(try persistence.loadTasks().first?.effectiveDependencyIDs, [dependencyID])
        XCTAssertEqual(try persistence.loadAnniversaries().first?.displayName, "重要日子")
        XCTAssertEqual(try persistence.loadWeeklyReviews().first?.nextWeekFocus, "稳定性测试")
    }

    func testReviewPeriodsUseCalendarBoundariesAndPersist() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31)))
        let month = try XCTUnwrap(ReviewPeriod.month.interval(containing: reference, calendar: calendar))
        let year = try XCTUnwrap(ReviewPeriod.year.interval(containing: reference, calendar: calendar))
        XCTAssertEqual(calendar.component(.month, from: month.start), 12)
        XCTAssertEqual(calendar.component(.year, from: month.end), 2027)
        XCTAssertEqual(calendar.component(.year, from: year.end), 2027)

        let persistence = try PersistenceController(inMemory: true)
        let review = WeeklyReviewItem(weekStart: month.start, summary: "完成月度工作",
                                      nextWeekFocus: "下月计划", period: .month)
        try persistence.saveWeeklyReviews([review])
        let loaded = try XCTUnwrap(persistence.loadWeeklyReviews().first)
        XCTAssertEqual(loaded.id, review.id)
        XCTAssertEqual(loaded.effectivePeriod, .month)

        let legacy = WeeklyReviewItem(weekStart: reference, summary: "旧周总结", nextWeekFocus: "下周")
        let decoded = try JSONDecoder().decode(WeeklyReviewItem.self, from: JSONEncoder().encode(legacy))
        XCTAssertEqual(decoded.effectivePeriod, .week)
    }

    func testYearlySolarAnniversaryFindsNextOccurrence() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let source = try XCTUnwrap(calendar.date(from: DateComponents(year: 2020, month: 10, day: 1)))
        let reference = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13)))
        let item = AnniversaryItem(name: "纪念日", date: source, calendar: .solar, repeatRule: .yearly)

        let next = try XCTUnwrap(item.nextOccurrence(from: reference, calendar: calendar))
        XCTAssertEqual(calendar.dateComponents([.year, .month, .day], from: next), DateComponents(year: 2026, month: 10, day: 1))
        XCTAssertEqual(item.daysRemaining(from: reference, calendar: calendar), 18)
    }

    func testBlueprintTransferPackageRoundTrip() throws {
        let blueprint = BlueprintItem(name: "软件开发", dueDate: .now)
        let stage = StageItem(blueprintID: blueprint.id, name: "开发", order: 0, dueDate: .now)
        let package = BlueprintTransferPackage(blueprint: blueprint, stages: [stage], milestones: [], tasks: [])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(package)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let restored = try decoder.decode(BlueprintTransferPackage.self, from: data)

        XCTAssertEqual(restored.formatVersion, 1)
        XCTAssertEqual(restored.blueprint.name, "软件开发")
        XCTAssertEqual(restored.stages.first?.blueprintID, blueprint.id)
    }
}
