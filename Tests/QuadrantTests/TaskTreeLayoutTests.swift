import XCTest
@testable import Quadrant

final class TaskTreeLayoutTests: XCTestCase {
    func testParentIsCentredAcrossVisibleSubtree() {
        let root = UUID(), branch = UUID(), first = UUID(), second = UUID(), other = UUID()
        let nodes: [TaskTreeLayout.Node] = [
            .init(id: root, parentID: nil), .init(id: branch, parentID: root),
            .init(id: first, parentID: branch), .init(id: second, parentID: branch),
            .init(id: other, parentID: root)
        ]
        let layout = TaskTreeLayout.arrange(nodes, rootID: root)
        XCTAssertEqual(layout.positions.count, 5)
        XCTAssertEqual(layout.positions[branch]!.y,
                       (layout.positions[first]!.y + layout.positions[second]!.y) / 2)
        XCTAssertEqual(layout.positions[root]!.y,
                       (layout.positions[branch]!.y + layout.positions[other]!.y) / 2)
        XCTAssertLessThan(layout.positions[root]!.x, layout.positions[branch]!.x)
        XCTAssertLessThan(layout.positions[branch]!.x, layout.positions[first]!.x)
    }

    func testCollapsedBranchHidesDescendantsButKeepsSibling() {
        let root = UUID(), branch = UUID(), hidden = UUID(), sibling = UUID()
        let nodes: [TaskTreeLayout.Node] = [
            .init(id: root, parentID: nil), .init(id: branch, parentID: root),
            .init(id: hidden, parentID: branch), .init(id: sibling, parentID: root)
        ]
        let layout = TaskTreeLayout.arrange(nodes, rootID: root, collapsed: [branch])
        XCTAssertEqual(layout.visibleIDs, [root, branch, sibling])
        XCTAssertNil(layout.positions[hidden])
    }

    func testSingleNodeAndWideTreeHaveContentBounds() {
        let root = UUID()
        let single = TaskTreeLayout.arrange([.init(id: root, parentID: nil)], rootID: root)
        XCTAssertEqual(single.positions.count, 1)
        XCTAssertGreaterThan(single.width, TaskTreeLayout.cardWidth)
        XCTAssertGreaterThan(single.height, TaskTreeLayout.cardHeight)

        let children = (0..<12).map { _ in UUID() }
        let wide = TaskTreeLayout.arrange([.init(id: root, parentID: nil)] +
            children.map { .init(id: $0, parentID: root) }, rootID: root)
        XCTAssertEqual(wide.positions.count, 13)
        XCTAssertGreaterThan(wide.height, single.height)
        XCTAssertEqual(wide.positions[root]!.y,
                       (wide.positions[children.first!]!.y + wide.positions[children.last!]!.y) / 2)
    }
}
