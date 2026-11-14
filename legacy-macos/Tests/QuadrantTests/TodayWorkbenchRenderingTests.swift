import AppKit
import SwiftUI
import XCTest
@testable import Quadrant

/// Opt-in rendering of real SwiftUI views for visual review, using isolated in-memory tasks.
@MainActor
final class TodayWorkbenchRenderingTests: XCTestCase {
    func testRenderReviewStates() throws {
        guard let directory = ProcessInfo.processInfo.environment["XU_TODAY_RENDER_DIR"] else {
            throw XCTSkip("Set XU_TODAY_RENDER_DIR to export the Today page for visual review.")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        let empty = TaskStore(inMemory: true)
        empty.anniversaries = TodayWorkbenchPreviewData.populated().anniversaries
        try render(empty, name: "empty-paper", theme: .paper, output: output)
        try render(TodayWorkbenchPreviewData.populated(), name: "populated-paper", theme: .paper, output: output)
        try render(TodayWorkbenchPreviewData.populated(), name: "populated-ink", theme: .ink, output: output)

        let processed = TodayWorkbenchPreviewData.populated()
        processed.tasks = processed.tasks.map { task in
            guard TaskPlacement.isInToday(task), task.needsAction else { return task }
            var changed = task
            changed.status = .completed
            changed.completedAt = .now
            return changed
        }
        try render(processed, name: "all-processed", theme: .paper, output: output)

        let long = TodayWorkbenchPreviewData.populated()
        long.tasks[1].title = "核对多层级子任务在窄窗口、长中文标题和放大字号情况下的显示与点击区域"
        long.tasks[2].dependencyIDs = [long.tasks[3].id]
        try render(long, name: "narrow-large-text", theme: .paper, width: 730, scale: 1.25, output: output)
        try render(empty, name: "empty-ink", theme: .ink, output: output)
        let onlyFocus = TaskStore(inMemory: true)
        onlyFocus.tasks = [TaskItem(title: "推进今天最重要的一件事", quadrant: .doNow)]
        try render(onlyFocus, name: "only-focus", theme: .paper, output: output)
    }

    private func render(_ store: TaskStore, name: String, theme: ThemePreset,
                        width: CGFloat = 1050, scale: Double = 1, output: URL) throws {
        let preferences = AppPreferences()
        preferences.automaticThemeRule = .manual
        preferences.themePreset = theme
        preferences.customAccentHex = ""
        preferences.customBackgroundHex = ""
        preferences.customCardHex = ""
        preferences.fontScale = scale
        preferences.density = .standard
        preferences.fontStyle = .system
        preferences.highContrast = false
        preferences.reduceMotion = true
        let content = TodayWorkbenchView(onSelect: { _ in }, onReport: {}, onAddTask: {})
            .appSurface()
            .environmentObject(store)
            .environmentObject(preferences)
            .preferredColorScheme(theme.preferredScheme ?? .light)
            .frame(width: width, height: 760)
        // GeometryReader / ScrollView need a hosted AppKit layout pass before rasterization.
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
        var colors = Set<Int>()
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 12) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 12) {
                if let rgb = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) {
                    colors.insert((Int(rgb.redComponent * 255) << 16) |
                                  (Int(rgb.greenComponent * 255) << 8) | Int(rgb.blueComponent * 255))
                }
            }
        }
        XCTAssertGreaterThan(colors.count, 16, "The exported \(name) must contain rendered content, not a blank surface.")
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try png.write(to: output.appendingPathComponent("\(name).png"))
    }
}
