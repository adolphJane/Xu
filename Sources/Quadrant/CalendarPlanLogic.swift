import Foundation

struct CalendarPlanInterval: Equatable {
    let start: Date
    let end: Date

    func overlaps(_ other: Self) -> Bool { start < other.end && other.start < end }
}

struct CalendarPlanEntry {
    let id: String
    let interval: CalendarPlanInterval
}

struct CalendarPlanLane: Equatable {
    let index: Int
    let count: Int
}

struct CalendarSeriesMovePreview {
    let changes: [(before: TaskItem, after: TaskItem)]
    let skipped: [(title: String, reason: String)]
    let warnings: [String]
}

enum CalendarPlanLogic {
    static func seriesMove(rootID: UUID, to targetDay: Date, tasks: [TaskItem],
                           events: [CalendarEventItem], calendar: Calendar = .current) -> CalendarSeriesMovePreview {
        guard tasks.contains(where: { $0.id == rootID }) else {
            return .init(changes: [], skipped: [], warnings: [])
        }
        let members = tasks.filter { $0.id == rootID || root(of: $0, in: tasks).id == rootID }
        let parentIDs = Set(members.compactMap(\.parentTaskID))
        let leaves = members.filter { !parentIDs.contains($0.id) }
        let anchored = leaves.filter { !$0.isUnscheduled && !$0.isCompleted && !$0.isCancelled && !$0.planLocked && $0.startedAt == nil }
        func skipReason(_ task: TaskItem) -> String? {
            if parentIDs.contains(task.id) { return "系列汇总，不占用时间" }
            if task.isCompleted { return "已完成" }
            if task.isCancelled { return "已取消" }
            if task.planLocked { return "计划已锁定" }
            if task.startedAt != nil { return "已开始" }
            if task.isUnscheduled { return "尚未安排日期" }
            return nil
        }
        guard let earliest = anchored.map({ calendar.startOfDay(for: $0.timeBlock?.start ?? $0.scheduledFor) }).min() else {
            return .init(changes: [], skipped: members.map { ($0.title, skipReason($0) ?? "无可移动安排") }, warnings: [])
        }
        let offset = calendar.dateComponents([.day], from: earliest, to: calendar.startOfDay(for: targetDay)).day ?? 0
        var changes: [(before: TaskItem, after: TaskItem)] = []
        var skipped: [(title: String, reason: String)] = []
        for task in members {
            if let reason = skipReason(task) { skipped.append((task.title, reason)); continue }
            guard let nextDate = calendar.date(byAdding: .day, value: offset, to: task.scheduledFor) else { continue }
            var next = task
            next.scheduledFor = nextDate
            if let block = task.timeBlock,
               let start = calendar.date(byAdding: .day, value: offset, to: block.start),
               let end = calendar.date(byAdding: .day, value: offset, to: block.end) {
                next.timeBlock = .init(id: block.id, start: start, end: end, timeZoneID: block.timeZoneID)
            }
            if next != task { changes.append((task, next)) }
        }
        let movedIDs = Set(changes.map { $0.before.id })
        let otherTasks = tasks.filter { !movedIDs.contains($0.id) }
        var warnings: [String] = []
        for change in changes {
            if let block = change.after.timeBlock {
                let peers = changes.filter { $0.after.id != change.after.id }.map(\.after)
                let overlaps = conflicts(for: .init(start: block.start, end: block.end), excluding: nil,
                                         tasks: otherTasks + peers, events: events)
                if !overlaps.isEmpty { warnings.append("\(change.after.title)：与 \(overlaps.joined(separator: "、")) 重叠") }
                if let due = change.after.dueDate, block.end > due { warnings.append("\(change.after.title)：晚于截止时间") }
            } else if let due = change.after.dueDate, calendar.startOfDay(for: change.after.scheduledFor) > calendar.startOfDay(for: due) {
                warnings.append("\(change.after.title)：计划日期晚于截止日期")
            }
            let unmet = change.after.effectiveDependencyIDs.compactMap { id in
                tasks.first(where: { $0.id == id && !$0.isCompleted })?.title
            }
            if !unmet.isEmpty { warnings.append("\(change.after.title)：前置事项未完成（\(unmet.joined(separator: "、"))）") }
        }
        return .init(changes: changes, skipped: skipped, warnings: warnings)
    }

    static func lanes(for entries: [CalendarPlanEntry]) -> [String: CalendarPlanLane] {
        let sorted = entries.sorted {
            if $0.interval.start != $1.interval.start { return $0.interval.start < $1.interval.start }
            return $0.id < $1.id
        }
        var result: [String: CalendarPlanLane] = [:]
        var component: [CalendarPlanEntry] = []
        var componentEnd = Date.distantPast

        func finish(_ entries: [CalendarPlanEntry]) {
            var active: [(end: Date, lane: Int)] = []
            var assigned: [(id: String, lane: Int)] = []
            var width = 1
            for entry in entries {
                active.removeAll { $0.end <= entry.interval.start }
                let occupied = Set(active.map(\.lane))
                var lane = 0
                while occupied.contains(lane) { lane += 1 }
                active.append((entry.interval.end, lane))
                assigned.append((entry.id, lane))
                width = max(width, lane + 1)
            }
            for item in assigned { result[item.id] = .init(index: item.lane, count: width) }
        }

        for entry in sorted {
            if !component.isEmpty && entry.interval.start >= componentEnd {
                finish(component)
                component = []
                componentEnd = .distantPast
            }
            component.append(entry)
            componentEnd = max(componentEnd, entry.interval.end)
        }
        if !component.isEmpty { finish(component) }
        return result
    }

    static func executableTasks(_ tasks: [TaskItem]) -> [TaskItem] {
        let parents = Set(tasks.compactMap(\.parentTaskID))
        return tasks.filter { !parents.contains($0.id) && !$0.isCancelled }
    }

    static func root(of task: TaskItem, in tasks: [TaskItem]) -> TaskItem {
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var current = task
        var seen: Set<UUID> = [current.id]
        while let parentID = current.parentTaskID, seen.insert(parentID).inserted,
              let parent = byID[parentID] { current = parent }
        return current
    }

    static func intervals(on date: Date, tasks: [TaskItem], events: [CalendarEventItem]) -> [CalendarPlanInterval] {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        let taskIntervals = executableTasks(tasks).filter { !$0.isCompleted }.compactMap { task -> CalendarPlanInterval? in
            guard let block = task.timeBlock, block.end > block.start else { return nil }
            return CalendarPlanInterval(start: block.start, end: block.end)
        }
        let eventIntervals = events.filter(\.isBusy).map { CalendarPlanInterval(start: $0.startDate, end: $0.endDate) }
        return (taskIntervals + eventIntervals).compactMap { interval in
            let start = max(dayStart, interval.start)
            let end = min(dayEnd, interval.end)
            return start < end ? CalendarPlanInterval(start: start, end: end) : nil
        }
    }

    static func freeSlots(in window: CalendarPlanInterval, busy: [CalendarPlanInterval]) -> [CalendarPlanInterval] {
        guard window.end > window.start else { return [] }
        let clipped = busy.compactMap { interval -> CalendarPlanInterval? in
            let start = max(window.start, interval.start)
            let end = min(window.end, interval.end)
            return start < end ? CalendarPlanInterval(start: start, end: end) : nil
        }.sorted { $0.start < $1.start }
        var cursor = window.start
        var slots: [CalendarPlanInterval] = []
        for interval in clipped {
            if interval.start > cursor { slots.append(.init(start: cursor, end: interval.start)) }
            cursor = max(cursor, interval.end)
        }
        if cursor < window.end { slots.append(.init(start: cursor, end: window.end)) }
        return slots
    }

    static func conflicts(for interval: CalendarPlanInterval, excluding taskID: UUID?, tasks: [TaskItem], events: [CalendarEventItem]) -> [String] {
        let taskNames = executableTasks(tasks).filter { $0.id != taskID && !$0.isCompleted }.compactMap { task -> String? in
            guard let block = task.timeBlock,
                  interval.overlaps(.init(start: block.start, end: block.end)) else { return nil }
            return task.title
        }
        let eventNames = events.filter { $0.isBusy && interval.overlaps(.init(start: $0.startDate, end: $0.endDate)) }.map(\.title)
        return taskNames + eventNames
    }
}
