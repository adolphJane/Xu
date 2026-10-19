import AppKit
import SwiftUI
import XCTest
@testable import Quadrant

@MainActor
final class CalendarPlanRenderingTests: XCTestCase {
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    func testRenderReviewStates() throws {
        guard let directory = ProcessInfo.processInfo.environment["XU_CALENDAR_RENDER_DIR"] else {
            throw XCTSkip("Set XU_CALENDAR_RENDER_DIR to export the calendar plan.")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = TaskStore(inMemory: true)
        var release = TaskItem(title: "新版发布准备", quadrant: .schedule, dueDate: date(23, 18))
        release.scheduledFor = date(19, 0)
        var requirements = TaskItem(title: "需求确认", quadrant: .schedule, scheduledFor: date(16, 0), parentTaskID: release.id)
        requirements.status = .completed
        requirements.timeBlock = .init(start: date(16, 9), end: date(16, 9, 45))
        var design = TaskItem(title: "界面设计", quadrant: .schedule, scheduledFor: date(19, 0), parentTaskID: release.id)
        design.timeBlock = .init(start: date(19, 15), end: date(19, 16))
        var verify = TaskItem(title: "联调验证", quadrant: .schedule, scheduledFor: date(21, 0), parentTaskID: release.id)
        verify.timeBlock = .init(start: date(21, 10), end: date(21, 11, 30))
        let checklist = TaskItem(title: "发布检查", quadrant: .schedule, scheduledFor: date(23, 0), parentTaskID: release.id)
        let learning = TaskItem(title: "个人学习", quadrant: .schedule, scheduledFor: date(20, 0))
        var reading = TaskItem(title: "阅读章节", quadrant: .schedule, scheduledFor: date(20, 0), parentTaskID: learning.id)
        reading.timeBlock = .init(start: date(20, 16), end: date(20, 16, 30))
        var notes = TaskItem(title: "整理笔记", quadrant: .schedule, parentTaskID: learning.id)
        notes.status = .unscheduled
        store.tasks = [release, requirements, design, verify, checklist, learning, reading, notes]
        for mode in CalendarPlanMode.allCases {
            try render(store, mode: mode, name: mode.rawValue, output: output)
        }
    }

    private func render(_ store: TaskStore, mode: CalendarPlanMode, name: String, output: URL) throws {
        let preferences = AppPreferences()
        preferences.automaticThemeRule = .manual
        preferences.themePreset = .paper
        preferences.reduceMotion = true
        let originalCalendarEnabled = preferences.calendarIntegrationEnabled
        preferences.calendarIntegrationEnabled = false
        defer { preferences.calendarIntegrationEnabled = originalCalendarEnabled }
        let content = PlanView(initialMode: mode, initialDate: date(19, 0), onSelect: { _ in }, onAddTask: {})
            .environmentObject(store)
            .environmentObject(preferences)
            .preferredColorScheme(.light)
            .frame(width: 1320, height: 800)
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: content)
        let bounds = NSRect(x: 0, y: 0, width: 1320, height: 800)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        hosting.frame = bounds
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: bounds))
        hosting.cacheDisplay(in: bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("calendar-\(name).png"))
    }
}
