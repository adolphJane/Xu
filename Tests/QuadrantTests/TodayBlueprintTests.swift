import XCTest
@testable import Quadrant

final class TodayBlueprintTests: XCTestCase {
    func testTodayTasksAreGroupedUnderTheirBlueprint() {
        let calendar = Calendar(identifier: .gregorian)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: date)!
        let first = BlueprintItem(name: "渠道适配", dueDate: tomorrow)
        let second = BlueprintItem(name: "体验优化", dueDate: tomorrow)
        let grouped = TaskItem(title: "完成渠道联调", quadrant: .doNow, scheduledFor: date, blueprintID: first.id)
        let another = TaskItem(title: "优化首页布局", quadrant: .schedule, scheduledFor: date, blueprintID: second.id)
        let future = TaskItem(title: "明日事项", quadrant: .schedule, scheduledFor: tomorrow, blueprintID: first.id)

        let groups = TodayBlueprintOrganizer.groups(
            tasks: [future, another, grouped],
            blueprints: [first, second],
            date: date,
            calendar: calendar
        )

        XCTAssertEqual(groups.map(\.blueprint.name), ["渠道适配", "体验优化"])
        XCTAssertEqual(groups[0].tasks.map(\.title), ["完成渠道联调"])
        XCTAssertEqual(groups[1].tasks.map(\.title), ["优化首页布局"])
    }

    func testOrphanedAndUnlinkedTasksRemainVisible() {
        let calendar = Calendar(identifier: .gregorian)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let blueprint = BlueprintItem(name: "有效蓝图", dueDate: date)
        let unlinked = TaskItem(title: "临时事项", quadrant: .schedule, scheduledFor: date)
        let orphaned = TaskItem(title: "原蓝图已删除", quadrant: .doNow, scheduledFor: date, blueprintID: UUID())
        let linked = TaskItem(title: "已有归属", quadrant: .schedule, scheduledFor: date, blueprintID: blueprint.id)

        let tasks = TodayBlueprintOrganizer.unassignedTasks(
            tasks: [unlinked, linked, orphaned],
            blueprints: [blueprint],
            date: date,
            calendar: calendar
        )

        XCTAssertEqual(Set(tasks.map(\.title)), Set(["临时事项", "原蓝图已删除"]))
    }

    func testActionableTasksAreSortedAheadOfProcessedTasks() {
        let pending = TaskItem(title: "待执行", quadrant: .schedule, status: .pending)
        let completed = TaskItem(title: "已完成", quadrant: .doNow, isComplete: true, status: .completed)

        XCTAssertEqual(TodayBlueprintOrganizer.sortedTasks([completed, pending]).map(\.title), ["待执行", "已完成"])
    }
}
