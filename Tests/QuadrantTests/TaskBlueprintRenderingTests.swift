import AppKit
import SwiftUI
import XCTest
@testable import Quadrant

@MainActor
final class TaskBlueprintRenderingTests: XCTestCase {
    func testRenderReviewStates() throws {
        guard let directory = ProcessInfo.processInfo.environment["XU_BLUEPRINT_RENDER_DIR"] else {
            throw XCTSkip("Set XU_BLUEPRINT_RENDER_DIR to export the task view.")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "准备新版首页发布", quadrant: .doNow)
        let first = TaskItem(title: "检查交互和辅助功能", quadrant: .doNow, parentTaskID: root.id)
        let second = TaskItem(title: "协调排期", quadrant: .schedule, parentTaskID: root.id)
        let deep = TaskItem(title: "确认较长的中文标题在不同窗口宽度下依然可以清楚阅读", quadrant: .delegate,
                            parentTaskID: first.id)
        let last = TaskItem(title: "整理旧素材", quadrant: .eliminate, parentTaskID: root.id)
        store.tasks = [root, first, second, deep, last]
        try render(store, rootID: root.id, mode: .blueprint, width: 960, name: "graph-paper", output: output)
        try render(store, rootID: root.id, mode: .blueprint, width: 680, name: "graph-narrow", output: output,
                   fontScale: 1.25)
        try render(store, rootID: root.id, mode: .list, width: 960, name: "list-paper", output: output)
        try render(store, rootID: root.id, mode: .quadrants, width: 960, name: "quadrants-paper", output: output)
        try render(store, rootID: root.id, mode: .quadrants, width: 680, name: "quadrants-narrow", output: output,
                   fontScale: 1.25)
        try render(store, rootID: root.id, mode: .blueprint, width: 960, name: "graph-ink", output: output,
                   theme: .ink)
    }

    private func render(_ store: TaskStore, rootID: UUID, mode: TaskBlueprintMode, width: CGFloat,
                        name: String, output: URL, fontScale: Double = 1,
                        theme: ThemePreset = .paper) throws {
        let preferences = AppPreferences()
        preferences.automaticThemeRule = .manual
        preferences.themePreset = theme
        preferences.fontScale = fontScale
        preferences.reduceMotion = true
        let view = TaskBlueprintView(rootTaskID: rootID, initialMode: mode)
            .environmentObject(store)
            .environmentObject(preferences)
            .preferredColorScheme(theme.preferredScheme ?? .light)
            .frame(width: width, height: 720)
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: view)
        let bounds = NSRect(x: 0, y: 0, width: width, height: 720)
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
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }
}
