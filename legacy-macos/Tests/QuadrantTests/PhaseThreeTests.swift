import XCTest
@testable import Quadrant

@MainActor
final class PhaseThreeTests: XCTestCase {
    func testAIBlueprintDecodesWithoutInternalIDs() throws {
        let json = """
        {
          "name":"发布序 1.0",
          "goal":"完成稳定版本",
          "startDate":"2026-09-13T00:00:00Z",
          "dueDate":"2026-10-30T00:00:00Z",
          "stages":[{
            "name":"开发",
            "startDate":"2026-09-13T00:00:00Z",
            "dueDate":"2026-10-01T00:00:00Z",
            "milestone":"功能冻结",
            "tasks":[{
              "title":"完成同步模块",
              "scheduledFor":"2026-09-14T00:00:00Z",
              "dueDate":null,
              "estimatedMinutes":90,
              "quadrant":"doNow"
            }]
          }]
        }
        """
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let draft = try decoder.decode(AIBlueprintDraft.self, from: Data(json.utf8))

        XCTAssertEqual(draft.stages.count, 1)
        XCTAssertEqual(draft.stages[0].tasks[0].title, "完成同步模块")
        XCTAssertTrue(draft.stages[0].tasks[0].isIncluded)
        XCTAssertEqual(draft.colorHex, "4F65D9")
    }

    func testAIReplanNeverChangesCompletedOrLockedTasks() {
        let active = TaskItem(title: "可调整", quadrant: .schedule, scheduledFor: .now)
        let completed = TaskItem(title: "已完成", quadrant: .schedule, scheduledFor: .now, isComplete: true, status: .completed)
        let locked = TaskItem(title: "已锁定", quadrant: .schedule, scheduledFor: .now, isPlanLocked: true)
        let target = Calendar.current.date(byAdding: .day, value: 3, to: .now)!
        let proposal = AIReplanProposal(summary: "调整容量", changes: [
            AIReplanChange(taskID: active.id, newScheduledFor: target, reason: "容量"),
            AIReplanChange(taskID: completed.id, newScheduledFor: target, reason: "容量"),
            AIReplanChange(taskID: locked.id, newScheduledFor: target, reason: "容量")
        ])

        let result = AIReplanRule.applying(proposal, to: [active, completed, locked])
        XCTAssertEqual(result[0].scheduledFor, target)
        XCTAssertEqual(result[1].scheduledFor, completed.scheduledFor)
        XCTAssertEqual(result[2].scheduledFor, locked.scheduledFor)
        XCTAssertNotNil(result[0].originalScheduledFor)
    }

    func testAIReplanKeepsDependencyOrder() {
        let prerequisiteDate = Calendar.current.date(byAdding: .day, value: 5, to: .now)!
        let requestedDate = Calendar.current.date(byAdding: .day, value: 1, to: .now)!
        let prerequisite = TaskItem(title: "前置任务", quadrant: .schedule, scheduledFor: prerequisiteDate)
        let dependent = TaskItem(title: "后续任务", quadrant: .schedule, scheduledFor: .now, dependencyIDs: [prerequisite.id])
        let proposal = AIReplanProposal(summary: "依赖调整", changes: [
            AIReplanChange(taskID: dependent.id, newScheduledFor: requestedDate, reason: "AI 建议")
        ])

        let result = AIReplanRule.applying(proposal, to: [prerequisite, dependent])
        XCTAssertGreaterThanOrEqual(result[1].scheduledFor, prerequisiteDate)
    }

    func testSnapshotChecksumIgnoresGenerationTime() throws {
        let task = TaskItem(title: "备份测试", quadrant: .schedule)
        var first = emptySnapshot(tasks: [task])
        var second = first
        first.generatedAt = Date(timeIntervalSince1970: 1)
        second.generatedAt = Date(timeIntervalSince1970: 999)

        XCTAssertEqual(try SnapshotCodec.checksum(first), try SnapshotCodec.checksum(second))
        XCTAssertEqual(try SnapshotCodec.decode(SnapshotCodec.encode(first)).tasks.first?.title, "备份测试")
    }

    func testSnapshotMergeKeepsUniqueItemsAndPrefersLocalCollision() {
        let sharedID = UUID()
        let localTask = TaskItem(id: sharedID, title: "本机版本", quadrant: .doNow)
        let remoteCollision = TaskItem(id: sharedID, title: "云端版本", quadrant: .schedule)
        let remoteOnly = TaskItem(title: "云端独有", quadrant: .schedule)

        let merged = SnapshotMerge.merge(local: emptySnapshot(tasks: [localTask]), remote: emptySnapshot(tasks: [remoteCollision, remoteOnly]))
        XCTAssertEqual(merged.tasks.count, 2)
        XCTAssertEqual(merged.tasks.first { $0.id == sharedID }?.title, "本机版本")
        XCTAssertTrue(merged.tasks.contains { $0.id == remoteOnly.id })
    }

    func testPlanChangeAndLockedTaskPersistence() throws {
        let persistence = try PersistenceController(inMemory: true)
        let task = TaskItem(title: "锁定计划", quadrant: .schedule, isPlanLocked: true)
        let snapshot = emptySnapshot(tasks: [task])
        let data = try SnapshotCodec.encode(snapshot)
        let change = PlanChangeItem(kind: .aiReplan, title: "AI 调整", beforeData: data, afterData: data)

        try persistence.saveTasks([task])
        try persistence.savePlanChanges([change])

        XCTAssertTrue(try persistence.loadTasks().first?.planLocked == true)
        XCTAssertEqual(try persistence.loadPlanChanges().first?.title, "AI 调整")
    }

    func testPersonalThemeRoundTrip() throws {
        let theme = PersonalTheme(name: "专注", preset: .ocean, accentHex: "00AACC", backgroundHex: "001122", cardHex: "112233", fontStyle: .rounded, iconStyle: .minimal, highContrast: true, reduceMotion: true)
        let data = try JSONEncoder().encode(theme)
        XCTAssertEqual(try JSONDecoder().decode(PersonalTheme.self, from: data), theme)
    }

    private func emptySnapshot(tasks: [TaskItem] = []) -> WorkspaceSnapshot {
        WorkspaceSnapshot(tasks: tasks, blueprints: [], stages: [], milestones: [], reports: [], anniversaries: [], weeklyReviews: [])
    }
}
