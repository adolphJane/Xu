import AppKit
import CryptoKit
@preconcurrency import EventKit
import Foundation

enum SnapshotCodec {
    static func encode(_ snapshot: WorkspaceSnapshot, pretty: Bool = false) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(snapshot)
    }

    static func decode(_ data: Data) throws -> WorkspaceSnapshot {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(WorkspaceSnapshot.self, from: data)
        guard snapshot.isValid else {
            throw NSError(domain: "序数据", code: 1, userInfo: [NSLocalizedDescriptionKey: "数据文件结构无效，未修改现有数据。"])
        }
        return snapshot
    }

    static func checksum(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func checksum(_ snapshot: WorkspaceSnapshot) throws -> String {
        var stable = snapshot
        stable.generatedAt = Date(timeIntervalSince1970: 0)
        return checksum(try encode(stable))
    }
}

@MainActor
extension TaskStore {
    func workspaceSnapshot() -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            tasks: tasks, blueprints: blueprints, stages: stages, milestones: milestones,
            reports: reports, anniversaries: anniversaries, weeklyReviews: weeklyReviews
        )
    }

    func restoreWorkspace(_ snapshot: WorkspaceSnapshot) throws {
        guard snapshot.isValid else {
            throw NSError(domain: "序数据", code: 2, userInfo: [NSLocalizedDescriptionKey: "备份校验失败，现有数据保持不变。"])
        }
        tasks = snapshot.tasks
        blueprints = snapshot.blueprints
        stages = snapshot.stages
        milestones = snapshot.milestones
        reports = snapshot.reports.sorted { $0.reportDate > $1.reportDate }
        anniversaries = snapshot.anniversaries
        weeklyReviews = snapshot.weeklyReviews.sorted { $0.weekStart > $1.weekStart }
    }

    func backupData(format: BackupFormat) throws -> Data {
        let snapshot = workspaceSnapshot()
        switch format {
        case .json:
            return try SnapshotCodec.encode(snapshot, pretty: true)
        case .markdown:
            var output = "# 序 · 数据备份\n\n生成时间：\(snapshot.generatedAt.formatted())\n\n"
            output += "## 蓝图\n\n"
            for blueprint in blueprints {
                output += "- **\(blueprint.name)**：\(blueprint.goal)（进度 \(Int(blueprintProgress(blueprint.id) * 100))%）\n"
            }
            output += "\n## 任务\n\n"
            for task in tasks.sorted(by: { $0.scheduledFor < $1.scheduledFor }) {
                output += "- [\(task.isCompleted ? "x" : " ")] \(task.title) · \(task.projectName) · \(task.effectiveStatus.title) · \(task.scheduledFor.formatted(date: .numeric, time: .omitted))\n"
            }
            output += "\n## 纪念日\n\n"
            for item in anniversaries { output += "- \(item.name) · \(item.date.formatted(date: .long, time: .omitted))\n" }
            output += "\n## 日报\n\n"
            for report in reports { output += "### \(report.reportDate.formatted(date: .long, time: .omitted))\n\n\(report.content)\n\n" }
            return Data(output.utf8)
        case .csv:
            func quote(_ value: String) -> String { "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\"" }
            var rows = ["id,title,project,status,quadrant,scheduledFor,dueDate,estimatedMinutes,notes"]
            let iso = ISO8601DateFormatter()
            rows += tasks.map { task in
                [task.id.uuidString, task.title, task.projectName, task.effectiveStatus.title, task.quadrant.title,
                 iso.string(from: task.scheduledFor), task.dueDate.map(iso.string) ?? "", String(task.estimatedMinutes), task.notes]
                    .map(quote).joined(separator: ",")
            }
            return Data(rows.joined(separator: "\n").utf8)
        }
    }

    func performFolderSync(folderPath: String) throws {
        let folder = URL(fileURLWithPath: folderPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw NSError(domain: "序同步", code: 1, userInfo: [NSLocalizedDescriptionKey: "同步文件夹不可用，请重新选择。"])
        }
        let url = folder.appendingPathComponent("序-workspace-sync.json")
        let local = workspaceSnapshot()
        let localChecksum = try SnapshotCodec.checksum(local)
        let defaults = UserDefaults.standard
        let lastRemote = defaults.string(forKey: "sync.lastRemoteChecksum") ?? ""
        let lastLocal = defaults.string(forKey: "sync.lastLocalChecksum") ?? ""

        guard FileManager.default.fileExists(atPath: url.path) else {
            try writeSyncEnvelope(snapshot: local, revision: 1, to: url)
            defaults.set(localChecksum, forKey: "sync.lastLocalChecksum")
            syncMessage = "已创建同步文件。"
            return
        }

        let remoteData = try Data(contentsOf: url)
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let remote = try decoder.decode(SyncEnvelope.self, from: remoteData)
        let verified = try SnapshotCodec.checksum(remote.snapshot)
        guard remote.formatVersion == 1, remote.snapshot.isValid, verified == remote.checksum else {
            throw NSError(domain: "序同步", code: 2, userInfo: [NSLocalizedDescriptionKey: "云端同步文件校验失败，未修改本地数据。"])
        }
        let remoteChanged = !lastRemote.isEmpty && remote.checksum != lastRemote
        let localChanged = !lastLocal.isEmpty && localChecksum != lastLocal
        if lastRemote.isEmpty || (remoteChanged && localChanged) {
            syncConflict = SyncConflict(remote: remote, local: local, message: "本机与同步文件都有变化，请选择合并方式。")
            return
        }
        if remoteChanged {
            try restoreWorkspace(remote.snapshot)
            rememberSync(remoteChecksum: remote.checksum)
            syncMessage = "已接收其他设备的更新。"
        } else if localChanged {
            try writeSyncEnvelope(snapshot: local, revision: remote.revision + 1, to: url)
            syncMessage = "本机更新已同步。"
        } else {
            syncMessage = "数据已经是最新状态。"
        }
    }

    func resolveSyncConflict(_ conflict: SyncConflict, resolution: SyncResolution, folderPath: String) throws {
        let url = URL(fileURLWithPath: folderPath, isDirectory: true).appendingPathComponent("序-workspace-sync.json")
        let result: WorkspaceSnapshot
        switch resolution {
        case .keepLocal: result = conflict.local
        case .useRemote: result = conflict.remote.snapshot
        case .merge: result = SnapshotMerge.merge(local: conflict.local, remote: conflict.remote.snapshot)
        }
        try restoreWorkspace(result)
        try writeSyncEnvelope(snapshot: result, revision: conflict.remote.revision + 1, to: url)
        syncConflict = nil
        syncMessage = resolution == .merge ? "冲突已合并。" : "已按选择解决同步冲突。"
    }

    private func writeSyncEnvelope(snapshot: WorkspaceSnapshot, revision: Int, to url: URL) throws {
        let envelope = SyncEnvelope(
            revision: revision,
            deviceID: Host.current().localizedName ?? "Mac",
            snapshot: snapshot,
            checksum: try SnapshotCodec.checksum(snapshot)
        )
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(envelope).write(to: url, options: .atomic)
        rememberSync(remoteChecksum: envelope.checksum)
    }

    private func rememberSync(remoteChecksum: String) {
        let localChecksum = (try? SnapshotCodec.checksum(workspaceSnapshot())) ?? ""
        UserDefaults.standard.set(remoteChecksum, forKey: "sync.lastRemoteChecksum")
        UserDefaults.standard.set(localChecksum, forKey: "sync.lastLocalChecksum")
    }

    func parseAIBlueprint(goal: String, deadline: Date, dailyMinutes: Int, endpoint: String, model: String) async -> AIBlueprintDraft? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiTaskError = "请先在设置中填写 DeepSeek API Key。"; return nil
        }
        isAIParsing = true; aiTaskError = nil
        defer { isAIParsing = false }
        let iso = ISO8601DateFormatter()
        let prompt = """
        你是严谨的项目规划助手。根据目标生成可执行蓝图，只返回 JSON，不要 Markdown。
        当前日期：\(iso.string(from: .now))；截止日期：\(iso.string(from: deadline))；每日可用 \(dailyMinutes) 分钟。
        JSON：{"name":"", "goal":"", "startDate":"ISO8601", "dueDate":"ISO8601", "colorHex":"4F65D9", "stages":[{"name":"", "startDate":"ISO8601", "dueDate":"ISO8601", "milestone":"", "tasks":[{"title":"", "scheduledFor":"ISO8601", "dueDate":"ISO8601或null", "estimatedMinutes":30, "quadrant":"doNow|schedule|delegate|eliminate", "notes":""}]}]}
        要求 2～6 个阶段、每阶段 1～8 个任务，任务总时长遵守每日容量，不编造外部事实。
        用户目标：\(goal)
        """
        do {
            let content = try await DeepSeekService.generateReport(apiKey: apiKey, endpoint: endpoint, model: model, prompt: prompt)
            return try decodeJSONObject(AIBlueprintDraft.self, content: content)
        } catch {
            aiTaskError = "AI 蓝图生成失败：\(error.localizedDescription)"; return nil
        }
    }

    func commitAIBlueprint(_ draft: AIBlueprintDraft) throws {
        guard !draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !draft.stages.isEmpty,
              draft.dueDate >= draft.startDate,
              draft.stages.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.dueDate >= $0.startDate }) else {
            throw NSError(domain: "序 AI", code: 2, userInfo: [NSLocalizedDescriptionKey: "蓝图名称、阶段或日期无效，请修改草稿后重试。"])
        }
        let before = workspaceSnapshot()
        let blueprint = BlueprintItem(name: draft.name, goal: draft.goal, startDate: draft.startDate, dueDate: draft.dueDate, colorHex: draft.colorHex)
        addBlueprint(blueprint)
        var previousStageTaskIDs: [UUID] = []
        for (order, stageDraft) in draft.stages.enumerated() {
            let stage = StageItem(blueprintID: blueprint.id, name: stageDraft.name, order: order, startDate: stageDraft.startDate, dueDate: stageDraft.dueDate)
            addStage(stage)
            addMilestone(MilestoneItem(blueprintID: blueprint.id, stageID: stage.id, name: stageDraft.milestone, dueDate: stageDraft.dueDate))
            var currentStageTaskIDs: [UUID] = []
            for taskDraft in stageDraft.tasks where taskDraft.isIncluded {
                let task = TaskItem(title: taskDraft.title, notes: taskDraft.notes, project: blueprint.name, reportCategory: .projectProgress, quadrant: taskDraft.quadrant, scheduledFor: taskDraft.scheduledFor, dueDate: taskDraft.dueDate, estimatedMinutes: taskDraft.estimatedMinutes, status: .pending, blueprintID: blueprint.id, stageID: stage.id, dependencyIDs: previousStageTaskIDs.isEmpty ? nil : previousStageTaskIDs)
                add(task)
                currentStageTaskIDs.append(task.id)
            }
            if !currentStageTaskIDs.isEmpty { previousStageTaskIDs = currentStageTaskIDs }
        }
        try recordPlanChange(kind: .aiBlueprint, title: "AI 创建蓝图：\(blueprint.name)", before: before, after: workspaceSnapshot())
    }

    func generateAIReplan(blueprint: BlueprintItem, dailyMinutes: Int, includeNotes: Bool, includeProject: Bool, endpoint: String, model: String) async -> AIReplanProposal? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { aiTaskError = "请先配置 DeepSeek API Key。"; return nil }
        let editable = tasks(for: blueprint.id).filter { $0.needsAction && !$0.isUnscheduled && !$0.planLocked }
        guard !editable.isEmpty else { aiTaskError = "没有可重新规划的未完成任务。"; return nil }
        isAIParsing = true; aiTaskError = nil
        defer { isAIParsing = false }
        let iso = ISO8601DateFormatter()
        let rows = editable.map { task in
            "id=\(task.id.uuidString), title=\(task.title), project=\(includeProject ? task.projectName : "已隐藏"), date=\(iso.string(from: task.scheduledFor)), due=\(task.dueDate.map(iso.string) ?? "null"), minutes=\(task.estimatedMinutes), status=\(task.effectiveStatus.title), blocker=\(task.blockReason ?? "无"), notes=\(includeNotes ? task.notes : "已隐藏")"
        }.joined(separator: "\n")
        let prompt = """
        只返回 JSON：{"summary":"", "changes":[{"taskID":"UUID", "newScheduledFor":"ISO8601", "newDueDate":"ISO8601或null", "reason":""}]}。
        根据延期、阻塞原因和每日 \(dailyMinutes) 分钟容量重新安排下列任务，保持依赖顺序，不修改标题，不遗漏 UUID。截止目标：\(iso.string(from: blueprint.dueDate))。
        \(rows)
        """
        do {
            let content = try await DeepSeekService.generateReport(apiKey: apiKey, endpoint: endpoint, model: model, prompt: prompt)
            return try decodeJSONObject(AIReplanProposal.self, content: content)
        } catch {
            aiTaskError = "AI 重新规划失败：\(error.localizedDescription)"; return nil
        }
    }

    func commitAIReplan(_ proposal: AIReplanProposal, blueprintID: UUID) throws {
        let before = workspaceSnapshot()
        let updated = AIReplanRule.applying(proposal, to: tasks, blueprintID: blueprintID)
        let changed = zip(tasks, updated).filter { $0 != $1 }.count
        tasks = updated
        guard changed > 0 else { throw NSError(domain: "序 AI", code: 3, userInfo: [NSLocalizedDescriptionKey: "没有可应用的计划变更。"]) }
        try recordPlanChange(kind: .aiReplan, title: "AI 重新规划 \(changed) 项任务", before: before, after: workspaceSnapshot())
    }

    func undoPlanChange(_ item: PlanChangeItem) throws {
        guard !item.isUndone else { return }
        let after = try SnapshotCodec.decode(item.afterData)
        guard try SnapshotCodec.checksum(workspaceSnapshot()) == SnapshotCodec.checksum(after) else {
            throw NSError(domain: "序计划", code: 4, userInfo: [NSLocalizedDescriptionKey: "此后已有新的数据变更，无法安全撤销这次 AI 调整。请先导出备份，再手动调整相关任务。"])
        }
        let before = try SnapshotCodec.decode(item.beforeData)
        try restoreWorkspace(before)
        if let index = planChanges.firstIndex(where: { $0.id == item.id }) { planChanges[index].isUndone = true }
    }

    private func recordPlanChange(kind: PlanChangeKind, title: String, before: WorkspaceSnapshot, after: WorkspaceSnapshot) throws {
        planChanges.insert(PlanChangeItem(kind: kind, title: title, beforeData: try SnapshotCodec.encode(before), afterData: try SnapshotCodec.encode(after)), at: 0)
    }

    private func decodeJSONObject<T: Decodable>(_ type: T.Type, content: String) throws -> T {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") else {
            throw NSError(domain: "序 AI", code: 1, userInfo: [NSLocalizedDescriptionKey: "AI 未返回有效 JSON。"])
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let iso = ISO8601DateFormatter()
            if let date = iso.date(from: value) { return date }
            let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX"); day.dateFormat = "yyyy-MM-dd"
            if let date = day.date(from: value) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析日期：\(value)")
        }
        return try decoder.decode(type, from: Data(content[start...end].utf8))
    }
}

final class CalendarIntegration: @unchecked Sendable {
    static let shared = CalendarIntegration()
    private let store = EKEventStore()

    func requestAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    func events(days: Int = 30) -> [CalendarEventItem] {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).map {
            CalendarEventItem(id: $0.eventIdentifier ?? UUID().uuidString, title: $0.title ?? "无标题日程", startDate: $0.startDate, endDate: $0.endDate, calendarTitle: $0.calendar.title, isAllDay: $0.isAllDay)
        }.sorted { $0.startDate < $1.startDate }
    }

    func write(task: TaskItem) throws {
        let event = EKEvent(eventStore: store)
        event.title = task.title
        event.notes = task.notes
        event.startDate = task.scheduledFor
        event.endDate = task.dueDate ?? task.scheduledFor.addingTimeInterval(TimeInterval(task.estimatedMinutes * 60))
        event.calendar = store.defaultCalendarForNewEvents
        try store.save(event, span: .thisEvent, commit: true)
    }
}

extension AppPreferences {
    func checkForUpdates(currentVersion: String = "0.4.0") async {
        guard let url = URL(string: updateManifestURL), !updateManifestURL.isEmpty else {
            updateStatus = "请先填写更新清单地址。"; return
        }
        isCheckingUpdate = true; defer { isCheckingUpdate = false }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let manifest = try JSONDecoder().decode(UpdateManifest.self, from: data)
            if manifest.version.compare(currentVersion, options: .numeric) == .orderedDescending {
                availableUpdate = manifest; updateStatus = "发现新版本 \(manifest.version)。"
            } else { availableUpdate = nil; updateStatus = "当前已是最新版本。" }
        } catch { updateStatus = "检查更新失败：\(error.localizedDescription)" }
    }
}
