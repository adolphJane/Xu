import XCTest
@testable import Quadrant

final class TodayTaskOutlineTests: XCTestCase {
    func testAncestorsAreContextAndOnlyScheduledTasksAreActionableRows() {
        let root = TaskItem(title: "父任务", quadrant: .schedule, status: .unscheduled)
        let child = TaskItem(title: "子任务", quadrant: .schedule, parentTaskID: root.id)
        let grandchild = TaskItem(title: "今天执行", quadrant: .doNow, parentTaskID: child.id)
        let rows = TodayTaskOutline.rows(tasks: [grandchild], allTasks: [root, child, grandchild])
        XCTAssertEqual(rows.map(\.id), [root.id, child.id, grandchild.id])
        XCTAssertEqual(rows.map(\.depth), [0, 1, 2])
        XCTAssertEqual(rows.filter { !$0.isContext }.map(\.id), [grandchild.id])
    }

    func testFocusLeafDoesNotRepeatAndCollapseDoesNotResurrectHiddenChildren() {
        let root = TaskItem(title: "父任务", quadrant: .schedule, status: .unscheduled)
        let focus = TaskItem(title: "重点", quadrant: .doNow, parentTaskID: root.id)
        let child = TaskItem(title: "其他行动", quadrant: .schedule, parentTaskID: root.id)
        let all = [root, focus, child]
        let rows = TodayTaskOutline.rows(tasks: [child], allTasks: all)
        XCTAssertEqual(Set(rows.map(\.id)), [root.id, child.id])
        let collapsed = TodayTaskOutline.rows(tasks: [child], allTasks: all, collapsed: [root.id])
        XCTAssertEqual(collapsed.map(\.id), [root.id])
        XCTAssertTrue(collapsed[0].hasChildren)
    }

    func testFocusAncestorRemainsContextForVisibleDescendant() {
        let focus = TaskItem(title: "重点主任务", quadrant: .doNow)
        let child = TaskItem(title: "下级行动", quadrant: .schedule, parentTaskID: focus.id)
        let rows = TodayTaskOutline.rows(tasks: [child], allTasks: [focus, child])
        XCTAssertTrue(rows[0].isContext)
        XCTAssertFalse(rows[1].isContext)
        XCTAssertEqual(rows[1].depth, 1)
    }

    func testLegacyBlueprintAndOrphanTasksAreNotLostOrGroupedIntoAnotherEntity() {
        let legacyID = UUID()
        let first = TaskItem(title: "旧蓝图任务", quadrant: .schedule, blueprintID: legacyID)
        let second = TaskItem(title: "独立事项", quadrant: .delegate)
        let orphan = TaskItem(title: "上级已删除", quadrant: .schedule, parentTaskID: UUID())
        let rows = TodayTaskOutline.rows(tasks: [first, second, orphan], allTasks: [first, second, orphan])
        XCTAssertEqual(Set(rows.map(\.id)), [first.id, second.id, orphan.id])
        XCTAssertTrue(rows.allSatisfy { !$0.isContext && $0.depth == 0 })
    }

    func testMalformedCyclesAreFiniteAndEveryVisibleTaskOccursOnce() {
        var first = TaskItem(title: "A", quadrant: .schedule)
        let second = TaskItem(title: "B", quadrant: .schedule, parentTaskID: first.id)
        let branch = TaskItem(title: "C", quadrant: .schedule, parentTaskID: first.id)
        first.parentTaskID = second.id
        let all = [first, second, branch]
        let rows = TodayTaskOutline.rows(tasks: all, allTasks: all)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(Set(rows.map(\.id)), Set(all.map(\.id)))
    }
}
