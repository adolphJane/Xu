import XCTest
@testable import Quadrant

final class TaskSeriesProjectionTests: XCTestCase {
    func testFilteredChildKeepsItsSeriesAndParentIsOnlyContext() {
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        let child = TaskItem(title: "命中的子任务", quadrant: .doNow, parentTaskID: root.id)
        let sibling = TaskItem(title: "未命中的子任务", quadrant: .schedule, parentTaskID: root.id)

        let groups = TaskSeriesProjection.groups(matches: [child], allTasks: [root, child, sibling])

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].id, root.id)
        XCTAssertEqual(groups[0].matches.map(\.id), [child.id])
        XCTAssertEqual(groups[0].rows.map(\.id), [root.id, child.id])
        XCTAssertEqual(groups[0].rows.map(\.isContext), [true, false])
        XCTAssertEqual(groups[0].directChildrenCount, 2)
    }

    func testQuadrantsShowEachMatchingTaskOnceUnderItsSeries() {
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        let first = TaskItem(title: "紧急子任务", quadrant: .doNow, parentTaskID: root.id)
        let second = TaskItem(title: "规划子任务", quadrant: .schedule, parentTaskID: root.id)
        let all = [root, first, second]

        let urgent = TaskSeriesProjection.groups(matches: [first], allTasks: all, quadrant: .doNow)
        let planned = TaskSeriesProjection.groups(matches: [root, second], allTasks: all, quadrant: .schedule)

        XCTAssertEqual(urgent.map(\.id), [root.id])
        XCTAssertEqual(urgent.flatMap(\.rows).map(\.id), [first.id])
        XCTAssertEqual(planned.flatMap(\.rows).map(\.id), [root.id, second.id])
        XCTAssertEqual(Set((urgent + planned).flatMap(\.rows).map(\.id)).count, all.count)
    }

    func testMissingParentAndCycleRemainFinite() {
        let missingID = UUID()
        let orphan = TaskItem(title: "旧数据子任务", quadrant: .delegate, parentTaskID: missingID)
        let firstID = UUID(), secondID = UUID()
        let first = TaskItem(id: firstID, title: "甲", quadrant: .schedule, parentTaskID: secondID)
        let second = TaskItem(id: secondID, title: "乙", quadrant: .schedule, parentTaskID: firstID)

        let groups = TaskSeriesProjection.groups(matches: [orphan, first, second], allTasks: [orphan, first, second])

        XCTAssertEqual(Set(groups.flatMap(\.matches).map(\.id)), Set([orphan.id, firstID, secondID]))
        XCTAssertLessThanOrEqual(groups.flatMap(\.rows).count, 3)
    }
}
