import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CommandPaletteView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    let perform: (CommandPaletteAction) -> Void

    private var commands: [CommandPaletteAction] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? CommandPaletteAction.allCases : CommandPaletteAction.allCases.filter { $0.rawValue.localizedCaseInsensitiveContains(text) }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "command").foregroundStyle(.secondary)
                TextField("搜索命令", text: $query).textFieldStyle(.plain).font(.title3)
                Text("⌘⇧Space").font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(14).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(commands) { command in
                        Button {
                            dismiss(); perform(command)
                        } label: {
                            HStack {
                                Image(systemName: command.icon).frame(width: 26)
                                Text(command.rawValue)
                                Spacer(); Image(systemName: "return").foregroundStyle(.tertiary)
                            }.padding(11).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                    }
                }
            }
        }.padding(18).frame(width: 520, height: 460)
    }
}

struct AIBlueprintCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var goal = ""
    @State private var deadline = Calendar.current.date(byAdding: .month, value: 2, to: .now) ?? .now
    @State private var dailyMinutes = 90
    @State private var draft: AIBlueprintDraft?
    @State private var saveError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 生成完整蓝图").font(.title2.weight(.bold))
                    Text("AI 只生成草稿；检查并确认后才写入。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer(); Button("关闭") { dismiss() }
            }.padding(22)
            if draft == nil { inputView } else { previewView }
        }
        .frame(width: 760, height: draft == nil ? 500 : 760)
        .alert("保存失败", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("知道了") { saveError = nil }
        } message: { Text(saveError ?? "") }
    }

    private var inputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("描述你的目标").font(.headline)
            TextEditor(text: $goal).padding(8).frame(height: 150).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            HStack {
                DatePicker("目标完成日期", selection: $deadline, in: Date.now..., displayedComponents: .date)
                Spacer()
                Stepper("每日可用 \(dailyMinutes) 分钟", value: $dailyMinutes, in: 15...480, step: 15)
            }
            GroupBox("发送给 DeepSeek 的信息") {
                Text("目标描述、截止日期和每日可用时间。本功能不会发送已有任务、项目名称或备注。")
                    .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            if let error = store.aiTaskError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
            Spacer()
            HStack {
                Spacer()
                Button("生成蓝图草稿", systemImage: "sparkles") {
                    Task { draft = await store.parseAIBlueprint(goal: goal, deadline: deadline, dailyMinutes: dailyMinutes, endpoint: preferences.deepSeekEndpoint, model: preferences.deepSeekModel) }
                }.buttonStyle(.borderedProminent).disabled(goal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isAIParsing)
            }
        }.padding(22).overlay { if store.isAIParsing { ProgressView("正在拆解目标…").padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
    }

    private var previewView: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextField("蓝图名称", text: binding(\.name)).font(.title2.weight(.bold))
                    TextField("目标说明", text: binding(\.goal), axis: .vertical)
                    HStack {
                        DatePicker("开始", selection: binding(\.startDate), displayedComponents: .date)
                        DatePicker("截止", selection: binding(\.dueDate), displayedComponents: .date)
                    }
                    Label("创建后，同一阶段的任务可并行；下一阶段会等待上一阶段所有任务完成。你可以在工作流画布中调整连线。", systemImage: "arrow.triangle.branch")
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(draft?.stages ?? []) { stage in
                        VStack(alignment: .leading, spacing: 9) {
                            TextField("阶段名称", text: stageBinding(stage.id, \.name)).font(.headline)
                            TextField("里程碑", text: stageBinding(stage.id, \.milestone))
                            HStack {
                                DatePicker("开始", selection: stageBinding(stage.id, \.startDate), displayedComponents: .date)
                                DatePicker("结束", selection: stageBinding(stage.id, \.dueDate), displayedComponents: .date)
                            }.font(.caption)
                            ForEach(stage.tasks) { task in
                                HStack {
                                    Toggle("", isOn: taskBinding(stage.id, task.id, \.isIncluded)).labelsHidden()
                                    TextField("任务", text: taskBinding(stage.id, task.id, \.title))
                                    Stepper("\(taskValue(stage.id, task.id)?.estimatedMinutes ?? 0) 分", value: taskBinding(stage.id, task.id, \.estimatedMinutes), in: 5...480, step: 5)
                                        .frame(width: 120)
                                }
                            }
                        }.padding(14).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 13))
                    }
                }.padding(22)
            }
            Divider()
            HStack {
                Button("重新生成") { draft = nil }
                Spacer()
                Button("确认创建蓝图", systemImage: "checkmark") {
                    guard let draft else { return }
                    do { try store.commitAIBlueprint(draft); dismiss() }
                    catch { saveError = error.localizedDescription }
                }.buttonStyle(.borderedProminent)
            }.padding(20)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AIBlueprintDraft, Value>) -> Binding<Value> {
        Binding(get: { draft![keyPath: keyPath] }, set: { draft![keyPath: keyPath] = $0 })
    }
    private func stageBinding<Value>(_ stageID: UUID, _ keyPath: WritableKeyPath<AIStageDraft, Value>) -> Binding<Value> {
        Binding(get: { draft!.stages.first { $0.id == stageID }![keyPath: keyPath] }, set: { value in
            if let index = draft?.stages.firstIndex(where: { $0.id == stageID }) { draft!.stages[index][keyPath: keyPath] = value }
        })
    }
    private func taskBinding<Value>(_ stageID: UUID, _ taskID: UUID, _ keyPath: WritableKeyPath<AITaskDraft, Value>) -> Binding<Value> {
        Binding(get: { taskValue(stageID, taskID)![keyPath: keyPath] }, set: { value in
            guard let stageIndex = draft?.stages.firstIndex(where: { $0.id == stageID }),
                  let taskIndex = draft?.stages[stageIndex].tasks.firstIndex(where: { $0.id == taskID }) else { return }
            draft!.stages[stageIndex].tasks[taskIndex][keyPath: keyPath] = value
        })
    }
    private func taskValue(_ stageID: UUID, _ taskID: UUID) -> AITaskDraft? {
        draft?.stages.first { $0.id == stageID }?.tasks.first { $0.id == taskID }
    }
}

struct AIReplanView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let blueprint: BlueprintItem
    @State private var dailyMinutes = 90
    @State private var proposal: AIReplanProposal?
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("AI 重新规划").font(.title2.weight(.bold)); Spacer(); Button("关闭") { dismiss() } }
            if proposal == nil {
                Text("分析延期、阻塞和剩余容量，生成可勾选的日期调整建议。已完成和已锁定任务不会发送、也不会修改。")
                    .foregroundStyle(.secondary)
                Stepper("每日可用 \(dailyMinutes) 分钟", value: $dailyMinutes, in: 15...480, step: 15)
                GroupBox("发送字段") {
                    VStack(alignment: .leading) {
                        Toggle("发送项目名称", isOn: $preferences.aiSendProject)
                        Toggle("发送任务备注", isOn: $preferences.aiSendNotes)
                        Text("始终发送：任务标题、日期、时长、状态、阻塞原因和目标截止日期。")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(4)
                }
                if let error = store.aiTaskError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.orange) }
                Spacer()
                HStack { Spacer(); Button("生成调整草案", systemImage: "sparkles") {
                    Task { proposal = await store.generateAIReplan(blueprint: blueprint, dailyMinutes: dailyMinutes, includeNotes: preferences.aiSendNotes, includeProject: preferences.aiSendProject, endpoint: preferences.deepSeekEndpoint, model: preferences.deepSeekModel) }
                }.buttonStyle(.borderedProminent).disabled(store.isAIParsing) }
            } else if let proposal {
                Text(proposal.summary).foregroundStyle(.secondary)
                List(proposal.changes) { change in
                    if let task = store.tasks.first(where: { $0.id == change.taskID && $0.blueprintID == blueprint.id && $0.needsAction && !$0.planLocked }) {
                        HStack {
                            Toggle("", isOn: proposalBinding(change.id)).labelsHidden()
                            VStack(alignment: .leading) {
                                Text(task.title).font(.headline)
                                Text("\(task.scheduledFor.formatted(date: .abbreviated, time: .omitted)) → \(change.newScheduledFor.formatted(date: .abbreviated, time: .omitted)) · \(change.reason)")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                HStack {
                    Button("重新分析") { self.proposal = nil }
                    Spacer(); Button("确认应用变更") {
                        do { try store.commitAIReplan(self.proposal!, blueprintID: blueprint.id); dismiss() }
                        catch { errorMessage = error.localizedDescription }
                    }.buttonStyle(.borderedProminent)
                }
            }
        }.padding(24).frame(width: 680, height: 620)
        .overlay { if store.isAIParsing { ProgressView("正在分析计划偏差…").padding(30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) } }
        .alert("无法应用", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("知道了") {} } message: { Text(errorMessage ?? "") }
    }

    private func proposalBinding(_ id: UUID) -> Binding<Bool> {
        Binding(get: { proposal?.changes.first { $0.id == id }?.isIncluded ?? false }, set: { value in
            if let index = proposal?.changes.firstIndex(where: { $0.id == id }) { proposal!.changes[index].isIncluded = value }
        })
    }
}

struct PlanChangeHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { Text("AI 变更记录").font(.title2.weight(.bold)); Spacer(); Button("关闭") { dismiss() } }
            Text("撤销会恢复该次操作前的计划快照。建议只撤销最近一次尚未撤销的 AI 操作。")
                .font(.caption).foregroundStyle(.secondary)
            List(store.planChanges) { item in
                HStack {
                    Image(systemName: item.kind == .aiBlueprint ? "point.3.connected.trianglepath.dotted" : "calendar.badge.clock")
                    VStack(alignment: .leading) {
                        Text(item.title)
                        Text(item.createdAt.formatted()).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(item.isUndone ? "已撤销" : "撤销") {
                        do { try store.undoPlanChange(item) } catch { errorMessage = error.localizedDescription }
                    }.disabled(item.isUndone)
                }
            }
        }.padding(24).frame(width: 650, height: 520)
        .alert("撤销失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("知道了") {} } message: { Text(errorMessage ?? "") }
    }
}

struct SyncConflictView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    let conflict: SyncConflict
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("检测到同步冲突", systemImage: "arrow.triangle.branch").font(.title2.weight(.bold)).foregroundStyle(.orange)
            Text(conflict.message)
            Text("云端修订 \(conflict.remote.revision)，来自 \(conflict.remote.deviceID)，更新时间 \(conflict.remote.generatedAt.formatted())。")
                .font(.caption).foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 6) {
                    Text("合并会保留两边独有的数据；同 ID 项目以本机版本为准。")
                    Text("选择任一覆盖方案前，应用不会修改数据。")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
            }
            HStack {
                Button("使用云端") { resolve(.useRemote) }
                Button("保留本机") { resolve(.keepLocal) }
                Spacer(); Button("安全合并") { resolve(.merge) }.buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 540, height: 300)
        .alert("同步失败", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) { Button("知道了") {} } message: { Text(errorMessage ?? "") }
    }
    private func resolve(_ resolution: SyncResolution) {
        do { try store.resolveSyncConflict(conflict, resolution: resolution, folderPath: preferences.syncFolderPath); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }
}

struct DataIntegrationSettingsView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @State private var pendingRestore: WorkspaceSnapshot?
    @State private var message: String?
    @State private var isConflictPresented = false

    var body: some View {
        Form {
            Section("iCloud Drive / 文件夹同步") {
                Toggle("启用文件夹同步", isOn: $preferences.syncEnabled)
                HStack {
                    Text(preferences.syncFolderPath.isEmpty ? "未选择文件夹" : preferences.syncFolderPath).lineLimit(1).foregroundStyle(.secondary)
                    Spacer(); Button("选择文件夹") { chooseSyncFolder() }
                }
                Button("立即同步", systemImage: "arrow.triangle.2.circlepath") { syncNow() }
                    .disabled(!preferences.syncEnabled || preferences.syncFolderPath.isEmpty)
                Text("选择 iCloud Drive 中的文件夹即可跨 Mac 同步。冲突发生时必须人工选择，不会静默覆盖。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("系统日历") {
                Toggle("允许读取和可选写入系统日历", isOn: $preferences.calendarIntegrationEnabled)
                Button("请求授权并读取未来 30 天") {
                    Task {
                        do {
                            guard try await CalendarIntegration.shared.requestAccess() else { throw NSError(domain: "日历", code: 1, userInfo: [NSLocalizedDescriptionKey: "未获得日历授权。"]) }
                            store.calendarEvents = CalendarIntegration.shared.events()
                            message = "已读取 \(store.calendarEvents.count) 条日程。"
                        } catch { message = error.localizedDescription }
                    }
                }.disabled(!preferences.calendarIntegrationEnabled)
                Text("只有开启并单独授权后才会读取；写入操作仍需在具体任务菜单中主动执行。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("本地备份") {
                HStack {
                    ForEach(BackupFormat.allCases) { format in
                        Button("导出 \(format.fileExtension.uppercased())") { export(format) }
                    }
                    Button("恢复 JSON", role: .destructive) { chooseRestore() }
                }
                Text("JSON 包含全部业务数据；Markdown 适合阅读；CSV 适合表格处理。恢复前会校验并再次确认。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("自动更新") {
                Toggle("启动时自动检查", isOn: $preferences.autoCheckUpdates)
                TextField("更新清单 URL", text: $preferences.updateManifestURL)
                Button(preferences.isCheckingUpdate ? "正在检查…" : "检查更新") { Task { await preferences.checkForUpdates() } }
                    .disabled(preferences.isCheckingUpdate)
                if let status = preferences.updateStatus { Text(status).foregroundStyle(.secondary) }
                if let update = preferences.availableUpdate, let url = URL(string: update.downloadURL) {
                    Link("下载版本 \(update.version)", destination: url)
                    Text(update.notes).font(.caption)
                }
            }
            Section("系统入口") {
                LabeledContent("全局命令面板", value: "⌘⇧Space")
                Text("菜单栏可打开紧凑桌面小组件；当前执行计时和纪念日倒计时会同步显示。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
        .sheet(isPresented: $isConflictPresented) { if let conflict = store.syncConflict { SyncConflictView(conflict: conflict) } }
        .confirmationDialog("用备份替换当前数据？", isPresented: Binding(get: { pendingRestore != nil }, set: { if !$0 { pendingRestore = nil } })) {
            Button("确认恢复", role: .destructive) {
                guard let snapshot = pendingRestore else { return }
                do { try store.restoreWorkspace(snapshot); message = "备份恢复完成。" }
                catch { message = error.localizedDescription }
                pendingRestore = nil
            }
            Button("取消", role: .cancel) { pendingRestore = nil }
        } message: { Text("现有任务、蓝图、日报和纪念日将被备份内容替换。") }
        .alert("数据与集成", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("知道了") { message = nil } } message: { Text(message ?? "") }
    }

    private func chooseSyncFolder() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true
        panel.prompt = "选择同步文件夹"
        if panel.runModal() == .OK { preferences.syncFolderPath = panel.url?.path ?? "" }
    }
    private func syncNow() {
        do {
            try store.performFolderSync(folderPath: preferences.syncFolderPath)
            if store.syncConflict != nil { isConflictPresented = true } else { message = store.syncMessage }
        } catch { message = error.localizedDescription }
    }
    private func export(_ format: BackupFormat) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: format.fileExtension) ?? .data]
        panel.nameFieldStringValue = "序-备份-\(Date.now.formatted(.iso8601.year().month().day())).\(format.fileExtension)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try store.backupData(format: format).write(to: url, options: .atomic); message = "备份已导出。" }
        catch { message = error.localizedDescription }
    }
    private func chooseRestore() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { pendingRestore = try SnapshotCodec.decode(Data(contentsOf: url)) }
        catch { message = "备份校验失败：\(error.localizedDescription)" }
    }
}

struct CompactWidgetView: View {
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.openWindow) private var openWindow

    private var current: TaskItem? {
        store.todayTasks.first(where: \.isInProgress) ?? store.todayTasks.filter(\.needsAction).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("序").font(.title2.weight(.bold)); Spacer(); Button { openWindow(id: "main") } label: { Image(systemName: "arrow.up.right.square") } }
            if let current {
                VStack(alignment: .leading, spacing: 7) {
                    Text(current.isInProgress ? "正在执行" : "下一项").font(.caption).foregroundStyle(.secondary)
                    Text(current.title).font(.headline).lineLimit(2)
                    if current.isInProgress, let start = current.startedAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(duration(from: start, to: context.date)).font(.title.monospacedDigit().weight(.semibold)).foregroundStyle(preferences.accentColor)
                        }
                    }
                    HStack {
                        if !current.isInProgress { Button("开始") { store.start(current) } }
                        Button("完成") { store.markCompleted(current) }.buttonStyle(.borderedProminent)
                    }
                }.padding(14).background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: preferences.cornerRadius))
            } else { ContentUnavailableView("今日已清空", systemImage: "checkmark.circle") }
            if let anniversary = store.upcomingAnniversaries.first(where: { $0.showOnHome }), let days = anniversary.daysRemaining() {
                HStack { Image(systemName: anniversary.type.icon).foregroundStyle(.pink); Text(anniversary.displayName); Spacer(); Text(days == 0 ? "今天" : "\(days) 天") }
                    .font(.caption)
            }
        }.padding(18).frame(width: 330, height: 300).appSurface()
    }
    private func duration(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, seconds % 3600 / 60, seconds % 60)
    }
}
