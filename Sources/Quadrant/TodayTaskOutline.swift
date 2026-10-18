import Foundation

/// A read-only outline of today's rows. Ancestors provide context without becoming today tasks.
struct TodayTaskOutlineRow: Identifiable {
    var id: UUID { task.id }
    let task: TaskItem
    let depth: Int
    let isContext: Bool
    let hasChildren: Bool
    let isLastSibling: Bool
    let ancestorContinuations: [Bool]
}

enum TodayTaskOutline {
    static func rows(tasks: [TaskItem], allTasks: [TaskItem], collapsed: Set<UUID> = []) -> [TodayTaskOutlineRow] {
        let byID = Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let ordered = TodayBlueprintOrganizer.sortedTasks(tasks)
        let visibleIDs = Set(ordered.map(\.id))
        var included = visibleIDs
        var rank: [UUID: Int] = [:]
        for (index, task) in ordered.enumerated() {
            for ancestor in TaskTreeProjection.path(to: task.id, in: allTasks) {
                included.insert(ancestor.id)
                rank[ancestor.id] = min(rank[ancestor.id] ?? index, index)
            }
        }
        func sorted(_ ids: [UUID]) -> [UUID] {
            ids.sorted { (rank[$0] ?? .max, $0.uuidString) < (rank[$1] ?? .max, $1.uuidString) }
        }
        var children: [UUID: [UUID]] = [:]
        var roots: [UUID] = []
        for id in included {
            if let parent = byID[id]?.parentTaskID, parent != id, included.contains(parent) {
                children[parent, default: []].append(id)
            } else { roots.append(id) }
        }
        for id in Array(children.keys) { children[id] = sorted(children[id] ?? []) }
        roots = sorted(roots)

        // Malformed legacy cycles have no natural root. Keep each component visible and finite.
        var covered = Set<UUID>()
        func cover(_ root: UUID) {
            var pending = [root]
            while let id = pending.popLast() {
                guard covered.insert(id).inserted else { continue }
                pending.append(contentsOf: children[id] ?? [])
            }
        }
        for root in roots { cover(root) }
        for id in sorted(Array(included)) where !covered.contains(id) {
            roots.append(id)
            cover(id)
        }

        typealias Entry = (id: UUID, depth: Int, last: Bool, continuations: [Bool])
        var pending: [Entry] = roots.enumerated().map { ($0.element, 0, $0.offset == roots.count - 1, []) }.reversed()
        var seen = Set<UUID>()
        var result: [TodayTaskOutlineRow] = []
        while let entry = pending.popLast() {
            guard seen.insert(entry.id).inserted, let task = byID[entry.id] else { continue }
            let childIDs = (children[entry.id] ?? []).filter { !seen.contains($0) }
            result.append(TodayTaskOutlineRow(task: task, depth: entry.depth,
                isContext: !visibleIDs.contains(entry.id), hasChildren: !childIDs.isEmpty,
                isLastSibling: entry.last, ancestorContinuations: entry.continuations))
            guard !collapsed.contains(entry.id) else { continue }
            let guides = entry.continuations + (entry.depth > 0 ? [!entry.last] : [])
            for (index, childID) in childIDs.enumerated().reversed() {
                pending.append((childID, entry.depth + 1, index == childIDs.count - 1, guides))
            }
        }
        return result
    }
}
