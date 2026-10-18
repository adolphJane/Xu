import AppKit
import SwiftUI
import XCTest
@testable import Quadrant

/// Opt-in rasterization of the actual macOS page with isolated sample tasks.
@MainActor
final class TasksHubRenderingTests: XCTestCase {
    func testRenderReviewStates() throws {
        guard let directory = ProcessInfo.processInfo.environment["XU_TASKS_RENDER_DIR"] else {
            throw XCTSkip("Set XU_TASKS_RENDER_DIR to export the Tasks page.")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "准备新版首页发布", category: "产品开发", quadrant: .doNow,
                            dueDate: .now.addingTimeInterval(3 * 86400))
        store.add(root)
        let visual = TaskItem(title: "确认事项页面视觉方案", quadrant: .doNow,
                              dueDate: .now.addingTimeInterval(86400), status: .inProgress, parentTaskID: root.id)
        store.add(visual)
        let layout = TaskItem(title: "适配窄窗口布局与长中文标题", quadrant: .schedule, parentTaskID: root.id)
        store.add(layout)
        store.add(TaskItem(title: "检查更深一层的任务归属与长中文内容在大字号下的显示", quadrant: .doNow,
                           status: .blocked, blockReason: "等待布局适配", parentTaskID: visual.id))
        let second = TaskItem(title: "规划下个月的阅读", quadrant: .schedule, status: .unscheduled)
        store.add(second)
        XCTAssertTrue(store.addChild(title: "整理待读书单", to: second.id))
        store.add(TaskItem(title: "回复协作方的时间确认", quadrant: .delegate))
        store.add(TaskItem(title: "归档桌面截图", quadrant: .eliminate))

        try render(store, theme: .paper, width: 1050, name: "collapsed-paper", output: output)
        try render(store, theme: .ink, width: 1050, name: "collapsed-ink", output: output)
        try render(store, theme: .paper, width: 1050, name: "expanded-paper", output: output,
                   expanded: [root.id])
        try render(store, theme: .paper, width: 1050, name: "quadrants-paper", output: output,
                   presentation: .quadrants)
        try render(store, theme: .paper, width: 690, name: "narrow-paper", output: output)
        try render(store, theme: .ink, width: 690, name: "narrow-large-ink", output: output,
                   expanded: [root.id], fontScale: 1.25)
        try render(TaskStore(inMemory: true), theme: .paper, width: 1050, name: "empty-paper", output: output)

        let completedContextStore = TaskStore(inMemory: true)
        let completedParent = TaskItem(title: "已完成的父任务", quadrant: .schedule, status: .completed)
        completedContextStore.add(completedParent)
        completedContextStore.add(TaskItem(title: "仍待处理的子任务", quadrant: .schedule,
                                           parentTaskID: completedParent.id))
        try render(completedContextStore, theme: .paper, width: 1050,
                   name: "completed-parent-context", output: output,
                   expanded: [completedParent.id])

        let autoCompletedStore = TaskStore(inMemory: true)
        let autoParent = TaskItem(title: "自动完成的父任务", quadrant: .schedule)
        autoCompletedStore.add(autoParent)
        autoCompletedStore.add(TaskItem(title: "最后完成的子任务", quadrant: .schedule,
                                        parentTaskID: autoParent.id))
        if let child = autoCompletedStore.tasks.first(where: { $0.parentTaskID == autoParent.id }) {
            autoCompletedStore.markCompleted(child)
        }
        try render(autoCompletedStore, theme: .paper, width: 1050,
                   name: "auto-completed-parent", output: output, scope: .processed)
    }

    private func render(_ store: TaskStore, theme: ThemePreset, width: CGFloat,
                        name: String, output: URL, presentation: TasksPresentation = .list,
                        expanded: Set<UUID> = [], fontScale: Double = 1,
                        scope: TasksScope = .active) throws {
        let keys = ["automaticThemeRule", "themePreset", "customAccentHex", "customBackgroundHex",
                    "customCardHex", "reduceMotion", "fontScale", "fontStyle", "layoutDensity"]
        let defaults = UserDefaults.standard
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        let preferences = AppPreferences()
        preferences.automaticThemeRule = .manual
        preferences.themePreset = theme
        preferences.customAccentHex = ""
        preferences.customBackgroundHex = ""
        preferences.customCardHex = ""
        preferences.reduceMotion = true
        preferences.fontScale = fontScale
        preferences.fontStyle = .system
        preferences.density = .standard
        let content = TasksHubView(showsBlueprintLibrary: .constant(false), onSelect: { _ in }, onAddTask: {},
                                   initialPresentation: presentation, initiallyExpandedSeriesIDs: expanded,
                                   initialScope: scope)
            .appSurface()
            .environmentObject(store)
            .environmentObject(preferences)
            .preferredColorScheme(theme.preferredScheme ?? .light)
            .frame(width: width, height: 800)
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: content)
        let bounds = NSRect(x: 0, y: 0, width: width, height: 800)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        hosting.frame = bounds
        hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: bounds))
        hosting.cacheDisplay(in: bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }
}
