import XCTest
@testable import Quadrant

final class BusinessLogicTests: XCTestCase {
    func testTodayIncludesOverdueAndCompletedTodayButExcludesInbox() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!
        let overdue = TaskItem(title: "逾期待办", quadrant: .doNow, scheduledFor: yesterday)
        let inbox = TaskItem(title: "待安排", quadrant: .schedule, scheduledFor: today, status: .unscheduled)
        let completed = TaskItem(title: "今日提前完成", quadrant: .schedule, scheduledFor: tomorrow, isComplete: true, status: .completed, completedAt: today)

        XCTAssertTrue(TaskPlacement.isInToday(overdue, date: today, calendar: calendar))
        XCTAssertFalse(TaskPlacement.isInToday(inbox, date: today, calendar: calendar))
        XCTAssertTrue(TaskPlacement.isInToday(completed, date: today, calendar: calendar))
    }

    func testAIReplanCannotModifyAnotherBlueprintOrCancelledTask() {
        let first = BlueprintItem(name: "渠道适配", dueDate: .now)
        let second = BlueprintItem(name: "体验优化", dueDate: .now)
        let movable = TaskItem(title: "联调", quadrant: .schedule, blueprintID: first.id)
        let foreign = TaskItem(title: "视觉优化", quadrant: .schedule, blueprintID: second.id)
        let cancelled = TaskItem(title: "已取消", quadrant: .schedule, status: .cancelled, blueprintID: first.id)
        let nextWeek = Date.now.addingTimeInterval(7 * 86_400)
        let proposal = AIReplanProposal(summary: "调整计划", changes: [movable, foreign, cancelled].map {
            AIReplanChange(taskID: $0.id, newScheduledFor: nextWeek, newDueDate: nil, reason: "测试")
        })

        let result = AIReplanRule.applying(proposal, to: [movable, foreign, cancelled], blueprintID: first.id)
        XCTAssertEqual(result[0].scheduledFor, nextWeek)
        XCTAssertEqual(result[1], foreign)
        XCTAssertEqual(result[2], cancelled)
    }

    func testReportUsesBlueprintNameForLinkedTasksWithoutChangingSource() {
        let blueprint = BlueprintItem(name: "渠道适配", dueDate: .now)
        let linked = TaskItem(title: "登录联调", project: "旧项目名", quadrant: .doNow, blueprintID: blueprint.id)
        let normalized = ReportTaskGrouping.usingBlueprintNames([linked], blueprints: [blueprint])

        XCTAssertEqual(normalized.first?.projectName, "渠道适配")
        XCTAssertEqual(linked.projectName, "旧项目名")
    }

    func testBackupRejectsDuplicateStageIdentifiers() {
        let blueprint = BlueprintItem(name: "项目", dueDate: .now)
        let stage = StageItem(blueprintID: blueprint.id, name: "开发", order: 0, dueDate: .now)
        let snapshot = WorkspaceSnapshot(tasks: [], blueprints: [blueprint], stages: [stage, stage], milestones: [], reports: [], anniversaries: [], weeklyReviews: [])

        XCTAssertFalse(snapshot.isValid)
    }
}
