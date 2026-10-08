import SwiftUI

struct AITaskCreatorView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences

    @State private var sentence = ""
    @State private var hasDraft = false
    @State private var title = ""
    @State private var project = ""
    @State private var quadrant: Quadrant = .schedule
    @State private var reportCategory: ReportCategory = .projectProgress
    @State private var scheduledFor = Date.now
    @State private var hasDeadline = false
    @State private var dueDate = Date.now
    @State private var estimatedMinutes = 30
    @State private var notes = ""
    @State private var subtasks: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("AI 一句话生成任务").font(.title2.weight(.bold))
                    Text("描述要做什么、时间、项目和优先级，AI 会先生成可编辑草稿。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("关闭") { dismiss() }
            }
            .padding(22)

            if hasDraft {
                draftForm
            } else {
                inputView
            }
        }
        .frame(width: 570, height: hasDraft ? 640 : 410)
    }

    private var inputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            TextEditor(text: $sentence)
                .font(.title3)
                .padding(10)
                .frame(height: 150)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
            Text("例如：明天下午完成渠道适配登录页测试，预计一小时，重要且紧急。")
                .font(.caption).foregroundStyle(.secondary)
            if let error = store.aiTaskError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            HStack {
                if store.aiTaskError != nil {
                    Button("按原句创建普通待办") { useSentenceAsDraft() }
                }
                Spacer()
                Button("解析任务", systemImage: "sparkles") {
                    Task { await parse() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(sentence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isAIParsing)
            }
        }
        .padding(22)
        .overlay {
            if store.isAIParsing {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.82)
                    ProgressView("正在理解任务…")
                }
            }
        }
    }

    private var draftForm: some View {
        VStack(spacing: 0) {
            Form {
                Section("AI 草稿 · 保存前可修改") {
                    TextField("任务名称", text: $title)
                    TextField("所属项目", text: $project)
                    TextField("备注", text: $notes, axis: .vertical)
                    Picker("四象限", selection: $quadrant) {
                        ForEach(Quadrant.allCases) { Text($0.title).tag($0) }
                    }
                    Picker("日报分类", selection: $reportCategory) {
                        ForEach(ReportCategory.allCases) { Text($0.title).tag($0) }
                    }
                    DatePicker("安排时间", selection: $scheduledFor)
                    Toggle("设置截止时间", isOn: $hasDeadline)
                    if hasDeadline { DatePicker("截止时间", selection: $dueDate) }
                    Stepper("预计时长：\(estimatedMinutes) 分钟", value: $estimatedMinutes, in: 5...480, step: 5)
                    if !subtasks.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("建议子任务").font(.subheadline.weight(.semibold))
                            ForEach(subtasks, id: \.self) { Text("• \($0)").font(.subheadline) }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Button("重新描述") { hasDraft = false }
                Spacer()
                Button("创建任务", systemImage: "checkmark") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(20)
        }
    }

    private func parse() async {
        guard let parsed = await store.parseTask(
            sentence: sentence,
            endpoint: preferences.deepSeekEndpoint,
            model: preferences.deepSeekModel,
            defaultQuadrant: preferences.defaultQuadrant,
            defaultDuration: preferences.defaultDuration
        ) else { return }
        subtasks = parsed.subtasks
        apply(parsed.task)
    }

    private func useSentenceAsDraft() {
        apply(TaskItem(
            title: sentence.trimmingCharacters(in: .whitespacesAndNewlines),
            reportCategory: .projectProgress,
            quadrant: preferences.defaultQuadrant,
            estimatedMinutes: preferences.defaultDuration,
            status: .pending
        ))
    }

    private func apply(_ task: TaskItem) {
        title = task.title
        project = task.project ?? ""
        notes = task.notes
        quadrant = task.quadrant
        reportCategory = task.effectiveReportCategory
        scheduledFor = task.scheduledFor
        hasDeadline = task.dueDate != nil
        dueDate = task.dueDate ?? task.scheduledFor
        estimatedMinutes = task.estimatedMinutes
        hasDraft = true
    }

    private func save() {
        let normalizedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchedBlueprint = store.blueprints.first { $0.name.localizedCaseInsensitiveCompare(normalizedProject) == .orderedSame }
        let parentID = UUID()
        let parent = TaskItem(
            id: parentID,
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes,
            project: normalizedProject.isEmpty ? nil : normalizedProject,
            reportCategory: reportCategory,
            quadrant: quadrant,
            scheduledFor: scheduledFor,
            dueDate: hasDeadline ? dueDate : nil,
            estimatedMinutes: estimatedMinutes,
            status: .pending,
            blueprintID: matchedBlueprint?.id
        )
        store.add(parent)
        for subtask in subtasks {
            store.add(TaskItem(
                title: subtask,
                project: parent.project,
                reportCategory: parent.reportCategory,
                quadrant: parent.quadrant,
                scheduledFor: parent.scheduledFor,
                dueDate: parent.dueDate,
                estimatedMinutes: max(5, parent.estimatedMinutes / max(subtasks.count, 1)),
                status: .pending,
                blueprintID: parent.blueprintID,
                parentTaskID: parentID
            ))
        }
        dismiss()
    }
}
