import Foundation

/// A read-only grouping of the current task selection. The root supplies context;
/// only `matches` contribute to the result count.
struct TaskSeriesGroup: Identifiable {
    let root: TaskItem
    let matches: [TaskItem]
    let rows: [TaskSeriesRow]
    let isSeries: Bool
    let completedDirectChildren: Int
    let directChildrenCount: Int

    var id: UUID { root.id }
    var blockedCount: Int { matches.filter { $0.effectiveStatus == .blocked }.count }
}

struct TaskSeriesRow: Identifiable {
    let task: TaskItem
    let depth: Int
    let isContext: Bool

    var id: UUID { task.id }
}

enum TaskSeriesProjection {
    static func groups(matches: [TaskItem], allTasks: [TaskItem], quadrant: Quadrant? = nil) -> [TaskSeriesGroup] {
        let allByID = Dictionary(allTasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let matchIDs = Set(matches.map(\.id))
        var roots: [UUID] = []
        var matchesByRoot: [UUID: [TaskItem]] = [:]
        var childrenByParent: [UUID: [TaskItem]] = [:]
        var rank: [UUID: Int] = [:]
        for task in allTasks {
            if let parentID = task.parentTaskID, parentID != task.id {
                childrenByParent[parentID, default: []].append(task)
            }
        }

        func path(to id: UUID) -> [TaskItem] {
            var current: UUID? = id
            var seen = Set<UUID>()
            var result: [TaskItem] = []
            while let value = current, seen.insert(value).inserted, let task = allByID[value] {
                result.append(task)
                current = task.parentTaskID
            }
            return result.reversed()
        }

        for (index, task) in matches.enumerated() {
            let ancestors = path(to: task.id)
            for ancestor in ancestors { rank[ancestor.id] = min(rank[ancestor.id] ?? index, index) }
            let pathIDs = Set(ancestors.map(\.id))
            let isCycle = ancestors.first?.parentTaskID.map(pathIDs.contains) ?? false
            let rootID = isCycle
                ? (pathIDs.min { $0.uuidString < $1.uuidString } ?? task.id)
                : (ancestors.first?.id ?? task.id)
            if matchesByRoot[rootID] == nil { roots.append(rootID) }
            matchesByRoot[rootID, default: []].append(task)
        }

        return roots.compactMap { rootID in
            guard let root = allByID[rootID], let members = matchesByRoot[rootID] else { return nil }
            let directChildren = childrenByParent[rootID] ?? []
            let rows: [TaskSeriesRow]
            if quadrant != nil {
                // A context heading may be shown in several quadrants, but every
                // task row belongs to exactly its own quadrant.
                rows = members.map { TaskSeriesRow(task: $0, depth: 0, isContext: false) }
            } else {
                var included = matchIDs.intersection(Set(members.map(\.id)))
                for member in members {
                    included.formUnion(path(to: member.id).map(\.id))
                }
                var seen = Set<UUID>()
                var output: [TaskSeriesRow] = []
                func append(_ id: UUID, depth: Int) {
                    guard included.contains(id), seen.insert(id).inserted, let task = allByID[id] else { return }
                    output.append(TaskSeriesRow(task: task, depth: depth, isContext: !matchIDs.contains(id)))
                    let children = (childrenByParent[id] ?? []).filter { included.contains($0.id) }
                        .sorted { (rank[$0.id] ?? .max, $0.createdAt, $0.id.uuidString) <
                                  (rank[$1.id] ?? .max, $1.createdAt, $1.id.uuidString) }
                    for child in children {
                        append(child.id, depth: depth + 1)
                    }
                }
                append(rootID, depth: 0)
                // Legacy cycles or broken parent chains still show each result once.
                for member in members where !seen.contains(member.id) { append(member.id, depth: 0) }
                rows = output
            }
            return TaskSeriesGroup(root: root, matches: members, rows: rows,
                                   isSeries: !directChildren.isEmpty,
                                   completedDirectChildren: directChildren.filter(\.isCompleted).count,
                                   directChildrenCount: directChildren.count)
        }
    }
}
