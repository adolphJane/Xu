import AppKit
import SwiftUI
import XCTest
@testable import Quadrant

@MainActor
final class CategoriesRenderingTests: XCTestCase {
    func testRenderReviewStates() throws {
        guard let path = ProcessInfo.processInfo.environment["XU_CATEGORIES_RENDER_DIR"] else {
            throw XCTSkip("Set XU_CATEGORIES_RENDER_DIR to review the actual category views.")
        }
        let output = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let store = TaskStore(inMemory: true)
        for name in ["工作", "生活", "学习", "旅行", "需要持续跟进的长期学习与个人成长计划"] { store.addCategory(name) }
        store.categoryAppearance.setSymbol("briefcase", for: "工作")
        store.categoryAppearance.setSymbol("house", for: "生活")
        store.categoryAppearance.setSymbol("book", for: "学习")
        store.categoryAppearance.setSymbol("airplane", for: "旅行")
        store.add(TaskItem(title: "确认分类页面的视觉与交互方案", category: "工作", quadrant: .doNow))
        store.add(TaskItem(title: "整理产品评审资料", category: "工作", quadrant: .schedule))
        store.add(TaskItem(title: "与团队同步下周的版本计划", category: "工作", quadrant: .schedule,
                           status: .blocked, blockReason: "等待评审结论"))
        store.add(TaskItem(title: "补充项目交接说明", category: "工作", quadrant: .eliminate, status: .unscheduled))
        store.add(TaskItem(title: "归档上个版本的设计资料", category: "工作", quadrant: .schedule, status: .completed))
        store.add(TaskItem(title: "旧版组件清单核对", category: "工作", quadrant: .schedule, status: .cancelled))

        let defaults = UserDefaults.standard
        let keys = ["automaticThemeRule", "themePreset", "customAccentHex", "customBackgroundHex", "customCardHex", "fontScale", "fontStyle", "layoutDensity", "reduceMotion"]
        let previous = keys.map { defaults.object(forKey: $0) }
        defer {
            for (key, value) in zip(keys, previous) {
                if let value { defaults.set(value, forKey: key) } else { defaults.removeObject(forKey: key) }
            }
        }
        let preferences = AppPreferences()
        preferences.automaticThemeRule = .manual
        preferences.customAccentHex = ""; preferences.customBackgroundHex = ""; preferences.customCardHex = ""
        preferences.reduceMotion = true; preferences.fontStyle = .system; preferences.density = .standard
        for theme in [ThemePreset.paper, .ink] {
            preferences.themePreset = theme
            preferences.fontScale = 1
            try render(TaskCategoriesView(initialSelection: .named("工作"), onSelect: { _ in }),
                       store: store, preferences: preferences, width: 1100, height: 800,
                       name: "categories-\(theme.rawValue)", output: output)
            try render(CategoryIconPicker(selection: "briefcase", categoryName: "工作", recent: ["briefcase", "book"]) { _ in },
                       store: store, preferences: preferences, width: 600, height: 560,
                       name: "icons-\(theme.rawValue)", output: output)
        }
        preferences.themePreset = .paper
        try render(CategoryEditor(name: "工作", symbol: "briefcase"), store: store, preferences: preferences,
                   width: 540, height: 400, name: "editor", output: output)
        try render(TaskCategoriesView(initialSelection: .named("旅行"), onSelect: { _ in }),
                   store: store, preferences: preferences, width: 1100, height: 800, name: "empty-category", output: output)
        try render(TaskCategoriesView(initialSelection: .named("工作"), initialScope: .processed, onSelect: { _ in }),
                   store: store, preferences: preferences, width: 1100, height: 800, name: "processed", output: output)
        try render(TaskCategoriesView(onSelect: { _ in }), store: TaskStore(inMemory: true), preferences: preferences,
                   width: 1100, height: 800, name: "first-use", output: output)
        preferences.fontScale = 1.35
        try render(TaskCategoriesView(initialSelection: .named("需要持续跟进的长期学习与个人成长计划"), onSelect: { _ in }),
                   store: store, preferences: preferences, width: 660, height: 800, name: "narrow-large", output: output)
        try render(CategoryIconPicker(selection: "book", categoryName: "需要持续跟进的长期学习与个人成长计划", recent: []) { _ in },
                   store: store, preferences: preferences, width: 600, height: 660, name: "icons-large", output: output)
    }

    private func render<V: View>(_ view: V, store: TaskStore, preferences: AppPreferences,
                                 width: CGFloat, height: CGFloat, name: String, output: URL) throws {
        _ = NSApplication.shared
        let content = view.environmentObject(store).environmentObject(preferences)
            .preferredColorScheme(preferences.colorScheme ?? .light)
            .frame(width: width, height: height).background(preferences.pageBackground)
        let hosting = NSHostingView(rootView: content)
        let bounds = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: bounds, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -10000, y: -10000))
        window.contentView = hosting; window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        hosting.frame = bounds; hosting.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.15))
        hosting.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: bounds))
        hosting.cacheDisplay(in: bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        try data.write(to: output.appendingPathComponent("\(name).png"))
    }
}
