import Foundation
import XCTest
@testable import Quadrant

final class ProcessedHistoryTests: XCTestCase {
    func testRangeStatusAndDescendingOrderUseCurrentProcessedState() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = date(2026, 10, 18, 18, 0, calendar: calendar)

        var completed = TaskItem(title: "今天完成", quadrant: .doNow)
        completed.status = .completed
        completed.completedAt = date(2026, 10, 18, 14, 32, calendar: calendar)

        var cancelled = TaskItem(title: "昨天取消", quadrant: .schedule)
        cancelled.status = .cancelled
        cancelled.statusChangedAt = date(2026, 10, 17, 11, 0, calendar: calendar)

        var postponed = TaskItem(title: "今天延期", quadrant: .delegate)
        postponed.status = .postponed
        postponed.statusChangedAt = date(2026, 10, 18, 10, 15, calendar: calendar)

        var older = TaskItem(title: "更早完成", quadrant: .eliminate)
        older.status = .completed
        older.completedAt = date(2026, 10, 10, 9, 0, calendar: calendar)

        var restored = TaskItem(title: "已经恢复", quadrant: .doNow)
        restored.status = .pending
        restored.statusChangedAt = date(2026, 10, 18, 15, 0, calendar: calendar)

        let tasks = [cancelled, restored, older, postponed, completed]
        XCTAssertEqual(ProcessedHistoryProjection.tasks(tasks, in: .today, now: now, calendar: calendar)
            .map(\.title), ["今天完成", "今天延期"])
        XCTAssertEqual(ProcessedHistoryProjection.tasks(tasks, in: .sevenDays, now: now, calendar: calendar)
            .map(\.title), ["今天完成", "今天延期", "昨天取消"])
        XCTAssertEqual(ProcessedHistoryProjection.tasks(tasks, in: .all, now: now, calendar: calendar)
            .map(\.title), ["今天完成", "今天延期", "昨天取消", "更早完成"])
        XCTAssertEqual(ProcessedHistoryProjection.tasks(tasks, in: .all, status: .cancelled,
                                                       now: now, calendar: calendar).map(\.title), ["昨天取消"])
    }

    func testMissingLegacyTimestampOnlyAppearsInAllRange() throws {
        var legacy = TaskItem(title: "旧数据", quadrant: .schedule)
        legacy.status = .cancelled
        let now = Date()
        XCTAssertNil(ProcessedHistoryProjection.processedAt(legacy))
        XCTAssertTrue(ProcessedHistoryProjection.tasks([legacy], in: .today, now: now).isEmpty)
        XCTAssertEqual(ProcessedHistoryProjection.tasks([legacy], in: .all, now: now).map(\.title), ["旧数据"])
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int,
                      calendar: Calendar) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day,
                                           hour: hour, minute: minute))!
    }
}
