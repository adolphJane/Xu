import Foundation

/// Pure, subtree-centred layout for the task hierarchy canvas.
enum TaskTreeLayout {
    struct Node {
        let id: UUID
        let parentID: UUID?
    }

    struct Point: Equatable {
        let x: Double
        let y: Double
    }

    struct Result {
        let positions: [UUID: Point]
        let visibleIDs: Set<UUID>
        let width: Double
        let height: Double
    }

    static let cardWidth = 226.0
    static let cardHeight = 88.0
    private static let horizontalStep = 278.0
    private static let verticalStep = 108.0
    private static let inset = 32.0

    static func arrange(_ nodes: [Node], rootID: UUID, collapsed: Set<UUID> = []) -> Result {
        let children = Dictionary(grouping: nodes, by: \.parentID)
        var positions: [UUID: Point] = [:]
        var visited: Set<UUID> = []
        var nextLeaf = 0

        @discardableResult
        func place(_ id: UUID, depth: Int) -> Double? {
            guard visited.insert(id).inserted else { return nil }
            let childYs = collapsed.contains(id) ? [] : (children[id] ?? []).compactMap {
                place($0.id, depth: depth + 1)
            }
            let y: Double
            if let first = childYs.first, let last = childYs.last {
                y = (first + last) / 2
            } else {
                y = inset + Double(nextLeaf) * verticalStep
                nextLeaf += 1
            }
            positions[id] = Point(x: inset + Double(depth) * horizontalStep, y: y)
            return y
        }

        _ = place(rootID, depth: 0)
        let width = (positions.values.map(\.x).max() ?? inset) + cardWidth + inset
        let height = (positions.values.map(\.y).max() ?? inset) + cardHeight + inset
        return Result(positions: positions, visibleIDs: visited, width: width, height: height)
    }
}
