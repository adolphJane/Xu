import XCTest
@testable import Quadrant

final class CalendarPlanLogicTests: XCTestCase {
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testDateOnlyLegacyTaskDoesNotOccupyTimeAndParentIsNotCounted() throws {
        let parent = TaskItem(title: "系列", quadrant: .schedule, scheduledFor: date(19, 9))
        let child = TaskItem(title: "子任务", quadrant: .schedule, scheduledFor: date(19, 10), parentTaskID: parent.id)
        let decoded = try JSONDecoder().decode(TaskItem.self, from: JSONEncoder().encode(child))
        XCTAssertNil(decoded.timeBlock)
        XCTAssertEqual(CalendarPlanLogic.executableTasks([parent, decoded]).map(\.id), [child.id])
        XCTAssertTrue(CalendarPlanLogic.intervals(on: date(19, 0), tasks: [parent, decoded], events: []).isEmpty)
    }

    func testHalfOpenConflictAndUnionOfOverlappingBusyTimes() {
        var first = TaskItem(title: "设计", quadrant: .schedule)
        first.timeBlock = .init(start: date(19, 14), end: date(19, 15))
        let event = CalendarEventItem(id: "meeting", title: "会议", startDate: date(19, 14, 30),
                                      endDate: date(19, 15, 30), calendarTitle: "工作", isAllDay: false)
        let busy = CalendarPlanLogic.intervals(on: date(19, 0), tasks: [first], events: [event])
        let slots = CalendarPlanLogic.freeSlots(in: .init(start: date(19, 14), end: date(19, 16)), busy: busy)
        XCTAssertEqual(slots, [.init(start: date(19, 15, 30), end: date(19, 16))])
        XCTAssertTrue(CalendarPlanLogic.conflicts(for: .init(start: date(19, 15, 30), end: date(19, 16)),
                                                  excluding: nil, tasks: [first], events: [event]).isEmpty)
        XCTAssertEqual(CalendarPlanLogic.conflicts(for: .init(start: date(19, 14, 45), end: date(19, 15)),
                                                   excluding: nil, tasks: [first], events: [event]).count, 2)
    }

    func testOverlappingEntriesUseSeparateLanesAndReuseLaneAfterEnd() {
        let entries = [
            CalendarPlanEntry(id: "first", interval: .init(start: date(19, 14), end: date(19, 15))),
            CalendarPlanEntry(id: "second", interval: .init(start: date(19, 14, 30), end: date(19, 15, 30))),
            CalendarPlanEntry(id: "third", interval: .init(start: date(19, 15), end: date(19, 16)))
        ]
        let lanes = CalendarPlanLogic.lanes(for: entries)
        XCTAssertEqual(lanes["first"], .init(index: 0, count: 2))
        XCTAssertEqual(lanes["second"], .init(index: 1, count: 2))
        XCTAssertEqual(lanes["third"], .init(index: 0, count: 2))
    }

    func testSeriesMoveKeepsRelativeDaysAndDeadlineWhileSkippingLockedChildren() {
        let parent = TaskItem(title: "系列", quadrant: .schedule)
        var first = TaskItem(title: "第一步", quadrant: .schedule, scheduledFor: date(19, 9), parentTaskID: parent.id)
        first.timeBlock = .init(start: date(19, 9), end: date(19, 10))
        first.dueDate = date(20, 18)
        var second = TaskItem(title: "第二步", quadrant: .schedule, scheduledFor: date(21, 14), parentTaskID: parent.id)
        second.timeBlock = .init(start: date(21, 14), end: date(21, 15))
        var locked = TaskItem(title: "锁定步骤", quadrant: .schedule, scheduledFor: date(19, 16), parentTaskID: parent.id)
        locked.isPlanLocked = true
        let preview = CalendarPlanLogic.seriesMove(rootID: parent.id, to: date(22, 0),
                                                   tasks: [parent, first, second, locked], events: [])
        XCTAssertEqual(preview.changes.count, 2)
        XCTAssertEqual(preview.changes.first?.after.timeBlock?.start, date(22, 9))
        XCTAssertEqual(preview.changes.last?.after.timeBlock?.start, date(24, 14))
        XCTAssertEqual(preview.changes.first?.after.dueDate, first.dueDate)
        XCTAssertTrue(preview.skipped.contains { $0.title == "锁定步骤" && $0.reason == "计划已锁定" })
        XCTAssertTrue(preview.warnings.contains { $0.contains("晚于截止时间") })
    }

    func testSeriesMoveExplainsWhenAllChildrenAreCompleted() {
        let parent = TaskItem(title: "系列", quadrant: .schedule)
        var child = TaskItem(title: "已做完", quadrant: .schedule, scheduledFor: date(19, 9), parentTaskID: parent.id)
        child.status = .completed
        let preview = CalendarPlanLogic.seriesMove(rootID: parent.id, to: date(22, 0), tasks: [parent, child], events: [])
        XCTAssertTrue(preview.changes.isEmpty)
        XCTAssertTrue(preview.skipped.contains { $0.title == "已做完" && $0.reason == "已完成" })
    }

    @MainActor func testSeriesMoveRejectsStalePreviewWithoutPartialChange() {
        let store = TaskStore(inMemory: true)
        let parent = TaskItem(title: "系列", quadrant: .schedule)
        let first = TaskItem(title: "第一步", quadrant: .schedule, scheduledFor: date(19, 9), parentTaskID: parent.id)
        let second = TaskItem(title: "第二步", quadrant: .schedule, scheduledFor: date(20, 9), parentTaskID: parent.id)
        store.tasks = [parent, first, second]
        let preview = CalendarPlanLogic.seriesMove(rootID: parent.id, to: date(22, 0), tasks: store.tasks, events: [])
        var edited = store.tasks[2]
        edited.title = "别人已编辑"
        XCTAssertTrue(store.update(edited))
        XCTAssertFalse(store.applyCalendarSeriesMove(preview.changes))
        XCTAssertEqual(store.tasks.first(where: { $0.id == first.id })?.scheduledFor, first.scheduledFor)
        XCTAssertEqual(store.tasks.first(where: { $0.id == second.id })?.title, "别人已编辑")
    }

    @MainActor func testTimeBlockPersistsThroughSwiftData() throws {
        let persistence = try PersistenceController(inMemory: true)
        let store = TaskStore(inMemory: true)
        var task = TaskItem(title: "安排", quadrant: .schedule, scheduledFor: date(19, 0))
        task.timeBlock = .init(start: date(19, 15), end: date(19, 16))
        try persistence.saveTask(task)
        XCTAssertEqual(try persistence.loadTasks().first?.timeBlock, task.timeBlock)
        store.add(task)
        XCTAssertEqual(store.tasks.first?.timeBlock, task.timeBlock)
        let backup = try SnapshotCodec.encode(store.workspaceSnapshot())
        XCTAssertEqual(try SnapshotCodec.decode(backup).tasks.first?.timeBlock, task.timeBlock)
        var sameDayEdit = store.tasks[0]
        sameDayEdit.title = "安排更新"
        XCTAssertTrue(store.update(sameDayEdit))
        XCTAssertEqual(store.tasks[0].timeBlock, task.timeBlock)
        var changed = store.tasks[0]
        changed.scheduledFor = date(20, 0)
        XCTAssertTrue(store.update(changed))
        XCTAssertNil(store.tasks[0].timeBlock)
    }
}
