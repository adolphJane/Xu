import AppKit
import SwiftUI
import XCTest
@testable import Quadrant

@MainActor
final class ProcessedHistoryRenderingTests: XCTestCase {
    func testRenderReviewStates() throws {
        guard let directory = ProcessInfo.processInfo.environment["XU_PROCESSED_RENDER_DIR"] else {
            throw XCTSkip("Set XU_PROCESSED_RENDER_DIR to export the Processed page.")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let populated = TaskStore(inMemory: true)
        let root = TaskItem(title: "新版首页发布", category: "工作", quadrant: .doNow)
        var selected = TaskItem(title: "检查发布清单", notes: "检查发布前配置与素材", category: "工作",
                                quadrant: .doNow, dueDate: .now.addingTimeInterval(3 * 86400),
                                parentTaskID: root.id)
        selected.status = .postponed
        selected.statusChangedAt = .now.addingTimeInterval(-3600)
        var firstChild = TaskItem(title: "核对发布配置", quadrant: .doNow, parentTaskID: selected.id)
        firstChild.status = .completed
        firstChild.completedAt = .now.addingTimeInterval(-7200)
        var secondChild = TaskItem(title: "检查素材", quadrant: .doNow, parentTaskID: selected.id)
        secondChild.status = .completed
        secondChild.completedAt = .now.addingTimeInterval(-6000)
        let thirdChild = TaskItem(title: "最终验收", quadrant: .doNow, parentTaskID: selected.id)
        var cancelled = TaskItem(title: "旧版发布检查", category: "工作", quadrant: .schedule)
        cancelled.status = .cancelled
        cancelled.statusChangedAt = .now.addingTimeInterval(-9000)
        populated.tasks = [root, selected, firstChild, secondChild, thirdChild, cancelled]

        try render(populated, theme: .paper, width: 1160, name: "populated-paper", output: output)
        try render(populated, theme: .ink, width: 1160, name: "populated-ink", output: output)
        try render(populated, theme: .paper, width: 720, name: "narrow-paper", output: output,
                   fontScale: 1.25)
        try render(TaskStore(inMemory: true), theme: .paper, width: 1160, name: "empty-paper", output: output)
    }

    private func render(_ store: TaskStore, theme: ThemePreset, width: CGFloat,
                        name: String, output: URL, fontScale: Double = 1) throws {
        let preferences = AppPreferences()
        preferences.automaticThemeRule = .manual
        preferences.themePreset = theme
        preferences.fontScale = fontScale
        preferences.fontStyle = .system
        preferences.density = .standard
        preferences.reduceMotion = true
        let content = CompletedView(onSelect: { _ in })
            .appSurface()
            .environmentObject(store)
            .environmentObject(preferences)
            .preferredColorScheme(theme.preferredScheme ?? .light)
            .frame(width: width, height: 760)
        _ = NSApplication.shared
        let hosting = NSHostingView(rootView: content)
        let bounds = NSRect(x: 0, y: 0, width: width, height: 760)
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
