import AppKit
import XCTest
@testable import Quadrant

@MainActor
final class CategoryIconTests: XCTestCase {
    func testCatalogAvailabilityAndSearchAcrossGroups() {
        XCTAssertEqual(CategorySymbol.all.count, 55)
        XCTAssertEqual(Set(CategorySymbol.all.map(\.id)).count, 55)
        for item in CategorySymbol.all {
            XCTAssertNotNil(NSImage(systemSymbolName: item.id, accessibilityDescription: nil), item.id)
        }
        XCTAssertTrue(CategorySymbol.matching("书", group: "财务").contains { $0.id == "books.vertical" })
        XCTAssertEqual(CategorySymbol.matching("BRIEFCASE", group: "生活").map(\.id), ["briefcase"])
        XCTAssertTrue(CategorySymbol.matching("无匹配内容", group: "全部").isEmpty)
        XCTAssertTrue(CategorySymbol.matching("", group: "健康").allSatisfy { $0.group == "健康" })
    }

    func testLocalAppearanceRoundTripFallbackAndRecentHistory() throws {
        var appearance = CategoryAppearance()
        XCTAssertEqual(appearance.symbol(for: "旧类别"), "tag")
        XCTAssertEqual(appearance.symbol(for: nil), "tray")
        appearance.setSymbol("briefcase", for: " Work ")
        XCTAssertEqual(appearance.symbol(for: "work"), "briefcase")
        appearance.symbols["broken"] = "symbol.that.does.not.exist"
        XCTAssertEqual(appearance.symbol(for: "broken"), "tag")
        for item in CategorySymbol.all.prefix(12) { appearance.recordRecent(item.id) }
        appearance.recordRecent("book")
        XCTAssertEqual(appearance.recent.count, 9)
        XCTAssertEqual(appearance.recent.first, "book")
        XCTAssertEqual(Set(appearance.recent).count, appearance.recent.count)
        XCTAssertEqual(try JSONDecoder().decode(CategoryAppearance.self, from: JSONEncoder().encode(appearance)), appearance)
    }

    func testRenameAndDeletePreserveTaskStateAndMoveIcon() {
        let savedCategories = UserDefaults.standard.object(forKey: "quadrant.taskCategories.v1") as? [String]
        let savedAppearance = UserDefaults.standard.data(forKey: CategoryAppearance.defaultsKey)
        let store = TaskStore(inMemory: true)
        store.addCategory("Work")
        store.addCategory("生活")
        store.categoryAppearance.setSymbol("briefcase", for: "Work")
        store.add(TaskItem(title: "待办", category: "Work", quadrant: .schedule))
        store.add(TaskItem(title: "历史记录", category: "Work", quadrant: .schedule, status: .cancelled))
        let originalIDs = store.tasks.map(\.id)
        let originalStatus = store.tasks.map(\.effectiveStatus)

        XCTAssertFalse(store.renameCategory("Work", to: " 生活 "))
        XCTAssertEqual(store.categoryAppearance.symbol(for: "work"), "briefcase")
        XCTAssertTrue(store.renameCategory("Work", to: " WORK "))
        XCTAssertEqual(store.categoryAppearance.symbol(for: "WORK"), "briefcase")
        XCTAssertTrue(store.renameCategory("WORK", to: "工作规划"))
        XCTAssertEqual(store.categoryAppearance.symbol(for: "工作规划"), "briefcase")
        XCTAssertNil(store.categoryAppearance.symbols["work"])
        XCTAssertTrue(store.tasks.allSatisfy { $0.category == "工作规划" })
        store.deleteCategory("工作规划")
        XCTAssertTrue(store.tasks.allSatisfy { $0.category == nil })
        XCTAssertEqual(store.tasks.map(\.id), originalIDs)
        XCTAssertEqual(store.tasks.map(\.effectiveStatus), originalStatus)
        XCTAssertNil(store.categoryAppearance.symbols["工作规划"])
        XCTAssertEqual(store.categories, ["生活"])
        // In-memory previews and tests must not overwrite the user's category preferences.
        XCTAssertEqual(UserDefaults.standard.object(forKey: "quadrant.taskCategories.v1") as? [String], savedCategories)
        XCTAssertEqual(UserDefaults.standard.data(forKey: CategoryAppearance.defaultsKey), savedAppearance)
    }
}
