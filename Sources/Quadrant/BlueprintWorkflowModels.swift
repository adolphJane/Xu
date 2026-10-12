#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import ImageIO

struct WorkflowImage: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var data: Data

    #if os(macOS)
    var nsImage: NSImage? { NSImage(data: data) }
    #else
    var uiImage: UIImage? { UIImage(data: data) }
    #endif

    static func imported(data: Data, name: String) throws -> WorkflowImage {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 1600
              ] as CFDictionary),
              let compressed = {
                  #if os(macOS)
                  NSBitmapImageRep(cgImage: thumbnail).representation(using: .jpeg, properties: [.compressionFactor: 0.82])
                  #else
                  UIImage(cgImage: thumbnail).jpegData(compressionQuality: 0.82)
                  #endif
              }() else {
            throw NSError(domain: "序图片", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取这张图片。"])
        }
        return WorkflowImage(name: name, data: compressed)
    }
}

enum WorkflowGraph {
    static func validationError(task: TaskItem, dependencies: [UUID], tasks: [TaskItem]) -> String? {
        guard task.blueprintID != nil else { return dependencies.isEmpty ? nil : "请先将任务归入蓝图。" }
        guard Set(dependencies).count == dependencies.count else { return "前置任务不能重复。" }
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for id in dependencies {
            guard let predecessor = byID[id], predecessor.blueprintID == task.blueprintID else {
                return "前置任务必须属于同一蓝图。"
            }
            if id == task.id { return "任务不能依赖自身。" }
        }
        var candidate = tasks.filter { $0.id != task.id }
        var updated = task
        updated.dependencyIDs = dependencies
        candidate.append(updated)
        for id in dependencies where DependencyRule.wouldCreateCycle(taskID: task.id, adding: id, tasks: candidate) {
            return "这条连线会形成循环依赖。"
        }
        if (task.isCompleted || task.isInProgress) && dependencies.contains(where: { byID[$0]?.isCompleted != true }) {
            return "进行中或已完成的任务不能新增尚未完成的前置任务。"
        }
        return nil
    }

    static func blockingReason(for task: TaskItem, tasks: [TaskItem], blueprints: [BlueprintItem]) -> String? {
        if task.isCancelled { return "任务已取消，请先恢复。" }
        if task.effectiveStatus == .blocked {
            let reason = task.blockReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return reason.isEmpty ? "任务已阻塞，请先解除阻塞。" : "任务已阻塞：\(reason)。请先解除阻塞。"
        }
        if let blueprintID = task.blueprintID,
           let blueprint = blueprints.first(where: { $0.id == blueprintID }),
           blueprint.status != .active {
            return "蓝图当前为“\(blueprint.status.title)”，请先设为执行中。"
        }
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let missing = task.effectiveDependencyIDs.filter { byID[$0]?.blueprintID != task.blueprintID }
        if !missing.isEmpty { return "存在失效的前置任务，请先修复连线。" }
        let cancelled = task.effectiveDependencyIDs.compactMap { byID[$0] }.filter(\.isCancelled)
        if !cancelled.isEmpty { return "前置任务已取消：\(cancelled.map(\.title).joined(separator: "、"))。请调整连线。" }
        let pending = task.effectiveDependencyIDs.compactMap { byID[$0] }.filter { !$0.isCompleted }
        if !pending.isEmpty { return "等待 \(pending.map(\.title).joined(separator: "、")) 完成。" }
        return nil
    }

    static func descendants(of taskID: UUID, tasks: [TaskItem]) -> [TaskItem] {
        var result: [TaskItem] = []
        var seen: Set<UUID> = [taskID]
        var frontier = [taskID]
        while let current = frontier.popLast() {
            for task in tasks where task.effectiveDependencyIDs.contains(current) && seen.insert(task.id).inserted {
                result.append(task)
                frontier.append(task.id)
            }
        }
        return result
    }

    static func automaticPositions(for tasks: [TaskItem]) -> [UUID: CGPoint] {
        let ids = Set(tasks.map(\.id))
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var levels: [UUID: Int] = [:]
        func level(_ id: UUID, visiting: Set<UUID> = []) -> Int {
            if let cached = levels[id] { return cached }
            guard let task = byID[id], !visiting.contains(id) else { return 0 }
            // Parent links express hierarchy for layout only; they never become execution dependencies.
            let dependencies = task.effectiveDependencyIDs.filter { ids.contains($0) }
            let hierarchyParent = task.parentTaskID.map { ids.contains($0) ? [$0] : [] } ?? []
            let layoutParents = Array(Set(dependencies + hierarchyParent))
            let result = layoutParents.isEmpty ? 0 : 1 + (layoutParents.map { level($0, visiting: visiting.union([id])) }.max() ?? 0)
            levels[id] = result
            return result
        }
        for task in tasks { _ = level(task.id) }
        var positions: [UUID: CGPoint] = [:]
        for (_, group) in Dictionary(grouping: tasks, by: { levels[$0.id] ?? 0 }) {
            let sorted = group.sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            for (row, task) in sorted.enumerated() {
                positions[task.id] = CGPoint(x: 72 + CGFloat(levels[task.id] ?? 0) * 340, y: 80 + CGFloat(row) * 315)
            }
        }
        return positions
    }
}

/// A read-only task hierarchy used by blueprint presentations.
enum TaskTreeProjection {
    /// Finds the topmost existing parent; broken links and cycles stay navigable.
    static func rootID(containing taskID: UUID, in tasks: [TaskItem]) -> UUID {
        let byID = Dictionary(tasks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var current = taskID
        var visited: Set<UUID> = [taskID]
        while let parentID = byID[current]?.parentTaskID,
              byID[parentID] != nil,
              visited.insert(parentID).inserted {
            current = parentID
        }
        return current
    }

    static func roots(in tasks: [TaskItem]) -> [TaskItem] {
        let parentIDs = Set(tasks.compactMap(\.parentTaskID))
        return tasks.filter { $0.parentTaskID == nil && $0.blueprintID == nil && parentIDs.contains($0.id) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    static func descendants(of rootID: UUID, in tasks: [TaskItem]) -> [TaskItem] {
        var result: [TaskItem] = []
        var seen: Set<UUID> = [rootID]
        var frontier = [rootID]
        while !frontier.isEmpty {
            let parentID = frontier.removeFirst()
            let children = tasks.filter { $0.parentTaskID == parentID }
                .sorted { ($0.createdAt, $0.id.uuidString) < ($1.createdAt, $1.id.uuidString) }
            for child in children where seen.insert(child.id).inserted {
                result.append(child)
                frontier.append(child.id)
            }
        }
        return result
    }
}
