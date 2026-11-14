import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum TaskComposerMode: String, CaseIterable, Identifiable {
    case task = "待办"
    case completed = "已完成"
    case ai = "AI 生成"

    var id: Self { self }

    var icon: String {
        switch self {
        case .task: "plus.circle"
        case .completed: "checkmark.circle"
        case .ai: "sparkles"
        }
    }
}

private enum TaskPlanChoice: String, CaseIterable, Identifiable {
    case today = "今天"
    case tomorrow = "明天"
    case custom = "选日期"
    case inbox = "暂不安排"

    var id: Self { self }
}

private struct SubtaskDraft: Identifiable {
    let id = UUID()
    var title: String
}

/// One creation surface for tasks, completed work, and editable AI drafts.
struct TaskComposerView: View {
    @AppDismiss private var dismiss
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @FocusState private var titleFocused: Bool
    @FocusState private var sentenceFocused: Bool
    @FocusState private var subtaskFocused: Bool

    @State private var mode: TaskComposerMode
    @State private var title = ""
    @State private var sentence = ""
    @State private var selectedImageData: Data?
    @State private var selectedImageName: String?
    @State private var imageImportError: String?
    @State private var isChoosingImage = false
    @State private var hasAIDraft = false
    @State private var subtasks: [SubtaskDraft] = []
    @State private var subtaskInput = ""
    @State private var isAddingSubtask = false
    @State private var showDiscardConfirmation = false
    @State private var navigationTaskID: UUID?
    @State private var navigationBlueprintID: UUID?
    @State private var shouldNavigateAfterClose = false
    @State private var blueprintID: UUID?
    @State private var stageID: UUID?
    @State private var milestoneID: UUID?
    @State private var dependencyIDs: Set<UUID> = []
    @State private var project = ""
    @State private var category = ""
    @State private var notes = ""
    @State private var quadrant: Quadrant = .schedule
    @State private var reportCategory: ReportCategory = .projectProgress
    @State private var planChoice: TaskPlanChoice = .today
    @State private var customDate = Date.now
    @State private var displayedPlanMonth: Date?
    @State private var completedAt = Date.now
    @State private var estimatedMinutes = 30
    @State private var hasDeadline = false
    @State private var dueDate = Date.now
    @State private var isPlanLocked = false
    @State private var showDetails = false
    @State private var keepOpen = false
    @State private var feedback: String?
    @State private var appliedDefaults = false
    @Environment(\.appDialogPresentation) private var dialogPresentation
    private var isClosing: Bool { dialogPresentation?.isClosing ?? false }
    private let opensBlueprintOnSave: Bool
    private let isPresentationActive: Bool

    init(mode: TaskComposerMode = .task, blueprintID: UUID? = nil, category: String? = nil,
         opensBlueprintOnSave: Bool = true,
         startsInInbox: Bool = false,
         isPresentationActive: Bool = true) {
        _mode = State(initialValue: mode)
        _blueprintID = State(initialValue: blueprintID)
        _category = State(initialValue: category ?? "")
        _planChoice = State(initialValue: startsInInbox ? .inbox : .today)
        self.opensBlueprintOnSave = opensBlueprintOnSave
        self.isPresentationActive = isPresentationActive
    }

    private var motion: Animation? {
        preferences.reduceMotion || systemReduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)
    }

    private var reduceMotion: Bool { preferences.reduceMotion || systemReduceMotion }

    private var isAIInput: Bool { mode == .ai && !hasAIDraft }
    private var composerHeight: CGFloat {
        if isAIInput { return selectedImageData == nil ? 450 : 590 }
        if showDetails || planChoice == .custom || !subtasks.isEmpty || isAddingSubtask { return 690 }
        return 575
    }
    private var cleanTitle: String { title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanSentence: String { sentence.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var cleanSubtasks: [String] {
        (subtasks.map(\.title) + [subtaskInput]).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }
    private var activeBlueprints: [BlueprintItem] { store.blueprints.filter { $0.archivedAt == nil } }

    var body: some View {
        VStack(spacing: 0) {
            header
            modeSelector
                .padding(.horizontal, 25)
                .padding(.bottom, 13)
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 19) {
                        if isAIInput { aiInput } else { taskFields }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 25)
                    .padding(.vertical, 15)
                }
                .onChange(of: planChoice) { _, choice in
                    if choice == .custom {
                        withAnimation(motion) { scrollProxy.scrollTo("plan-calendar", anchor: .top) }
                    }
                }
            }
            footer
        }
        .frame(width: 630, height: composerHeight)
        .animation(motion, value: composerHeight)
        .tint(preferences.accentColor)
        .onAppDialogCancel { if !showDiscardConfirmation { cancel() } }
        .task(id: isPresentationActive) {
            guard isPresentationActive else { return }
            if !appliedDefaults {
                quadrant = preferences.defaultQuadrant
                estimatedMinutes = preferences.defaultDuration
                if let blueprintID {
                    project = store.blueprints.first(where: { $0.id == blueprintID })?.name ?? ""
                }
                appliedDefaults = true
                if mode == .ai { store.aiTaskError = nil }
            }
            focusInput()
        }
        .onChange(of: blueprintID) { oldValue, newValue in
            stageID = nil
            milestoneID = nil
            dependencyIDs = []
            let oldName = store.blueprints.first(where: { $0.id == oldValue })?.name ?? ""
            if project.isEmpty || project == oldName {
                project = store.blueprints.first(where: { $0.id == newValue })?.name ?? ""
            }
        }
        .onChange(of: stageID) { _, _ in milestoneID = nil }
        .onExitCommand {
            if isAddingSubtask && subtaskInput.isEmpty {
                isAddingSubtask = false
                titleFocused = true
            } else {
                cancel()
            }
        }
        .onDisappear {
            guard shouldNavigateAfterClose, let navigationTaskID else { return }
            NotificationCenter.default.post(
                name: opensBlueprintOnSave ? .showTaskBlueprint : .focusBlueprintTask,
                object: navigationTaskID,
                userInfo: navigationBlueprintID.map { ["blueprintID": $0] }
            )
        }
        .fileImporter(isPresented: $isChoosingImage, allowedContentTypes: [.image]) { result in
            importImage(result)
        }
        .confirmationDialog("放弃未保存的任务？", isPresented: $showDiscardConfirmation) {
            Button("放弃", role: .destructive) {
                if keepOpen { navigationTaskID = nil }
                close()
            }
            Button("继续编辑", role: .cancel) { }
        } message: { Text("主任务和子任务的输入内容将丢失。") }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(preferences.accentColor)
                .frame(width: 40, height: 40)
                .background(preferences.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("添加事项")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("快速记录，再决定如何安排。")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button { cancel() } label: {
                Image(systemName: "xmark")
                    .font(AppTypography.desktop(.callout, scale: preferences.fontScale,
                                                weight: .semibold, design: preferences.fontStyle.design))
                    .frame(width: 27, height: 27)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)
            .help("关闭")
            .accessibilityLabel("关闭添加事项")
        }
        .padding(.horizontal, 25)
        .padding(.top, 23)
        .padding(.bottom, 20)
    }

    private var modeSelector: some View {
        HStack(spacing: 5) {
            ForEach(TaskComposerMode.allCases) { option in
                Button {
                    withAnimation(motion) {
                        mode = option
                        feedback = nil
                    }
                    if option == .ai { store.aiTaskError = nil }
                    focusInput()
                } label: {
                    Label(option.rawValue, systemImage: option.icon)
                        .font(AppTypography.desktop(.callout, scale: preferences.fontScale,
                                                    weight: mode == option ? .semibold : .medium,
                                                    design: preferences.fontStyle.design))
                        .frame(maxWidth: .infinity)
                        .frame(height: 35)
                        .foregroundStyle(mode == option ? preferences.accentColor : .secondary)
                        .background(mode == option ? preferences.accentColor.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(mode == option ? preferences.accentColor.opacity(0.23) : .clear))
                        .contentShape(RoundedRectangle(cornerRadius: 9))
                }
                .buttonStyle(WorkbenchPressStyle(reduceMotion: preferences.reduceMotion || systemReduceMotion))
                .accessibilityAddTraits(mode == option ? [.isSelected] : [])
            }
        }
        .padding(5)
        .background(preferences.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 13))
    }

    private var aiInput: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("描述任务或导入图片")
                .font(.headline)
            TextField("补充说明（可选，例如：按图片列出本周要完成的事项）", text: $sentence, axis: .vertical)
                .lineLimit(3...5)
                .font(.system(size: 16))
                .textFieldStyle(.plain)
                .focused($sentenceFocused)
                .padding(16)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(preferences.accentColor.opacity(0.25)))
                .onSubmit { if hasAIInput { Task { await parseAI() } } }
            HStack(spacing: AppSpacing.x3) {
                AppButton(title: selectedImageData == nil ? "选择图片" : "更换图片",
                          systemImage: "photo.on.rectangle", kind: .secondary,
                          tint: preferences.accentColor) { isChoosingImage = true }
                    .disabled(store.isAIParsing)
                if let selectedImageData, let image = NSImage(data: selectedImageData) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .accessibilityLabel("待识别图片预览")
                    Text(selectedImageName ?? "已选择图片")
                        .font(AppTypography.caption)
                        .lineLimit(2)
                    Button("移除图片", systemImage: "xmark.circle") {
                        self.selectedImageData = nil
                        selectedImageName = nil
                        imageImportError = nil
                    }
                    .labelStyle(.iconOnly)
                    .frame(width: 36, height: 36)
                    .accessibilityLabel("移除图片")
                    .disabled(store.isAIParsing)
                }
            }
            Text("图片和补充说明会发送到设置中的 AI 接口。AI 会生成可编辑的主任务与子任务，确认后才保存。")
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)
            if let imageImportError {
                Label(imageImportError, systemImage: "exclamationmark.triangle")
                    .font(AppTypography.caption)
                    .foregroundStyle(AppColors.danger)
            }
            if let feedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(preferences.accentColor)
            }
            if let error = store.aiTaskError {
                Label(error, systemImage: "exclamationmark.triangle")
                    .font(AppTypography.caption)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
                if !cleanSentence.isEmpty {
                    Button("直接作为普通待办", systemImage: "arrow.right") {
                        title = cleanSentence
                        hasAIDraft = false
                        mode = .task
                        focusInput()
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .overlay {
            if store.isAIParsing {
                ProgressView("正在生成草稿…")
                    .padding(24)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
            }
        }
    }

    private var taskFields: some View {
        VStack(alignment: .leading, spacing: 17) {
            VStack(alignment: .leading, spacing: 8) {
                Text(mode == .completed ? "完成了什么？" : "要做什么？")
                    .font(AppTypography.desktop(.callout, scale: preferences.fontScale,
                                                weight: .semibold, design: preferences.fontStyle.design))
                    .foregroundStyle(.secondary)
                TextField(mode == .completed ? "例如：完成支付链路回归" : "例如：完成渠道适配登录联调", text: $title)
                    .font(.system(size: 19, weight: .medium))
                    .textFieldStyle(.plain)
                    .focused($titleFocused)
                    .submitLabel(.done)
                    .onSubmit { if !cleanTitle.isEmpty { save() } }
                    .padding(.horizontal, 16)
                    .frame(height: 57)
                    .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(preferences.accentColor.opacity(0.25)))
            }
            TaskCategoryField(category: $category)
                .padding(.horizontal, 15)
                .frame(height: 50)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 12))

            if mode == .completed {
                HStack {
                    Label("完成时间", systemImage: "checkmark.circle")
                        .font(AppTypography.callout)
                    Spacer()
                    DatePicker("完成时间", selection: $completedAt, displayedComponents: [.date, .hourAndMinute])
                        .labelsHidden()
                }
                .padding(.horizontal, 15)
                .frame(height: 50)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: 12))
            } else {
                VStack(alignment: .leading, spacing: 9) {
                    Text("安排到")
                        .font(AppTypography.desktop(.callout, scale: preferences.fontScale,
                                                    weight: .semibold, design: preferences.fontStyle.design))
                        .foregroundStyle(.secondary)
                    HStack(spacing: AppSpacing.x2) {
                        ForEach([TaskPlanChoice.today, .tomorrow, .custom]) { choice in
                            Button {
                                planChoice = choice
                            } label: {
                                Text(choice.rawValue)
                                    .font(AppTypography.desktop(.body, scale: preferences.fontScale,
                                                              weight: planChoice == choice ? .semibold : .regular,
                                                              design: preferences.fontStyle.design))
                                    .foregroundStyle(planChoice == choice ? preferences.accentColor : AppColors.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 36)
                                    .background(planChoice == choice ? preferences.accentColor.opacity(0.14) : preferences.cardBackground,
                                                in: RoundedRectangle(cornerRadius: AppRadius.small))
                                    .contentShape(RoundedRectangle(cornerRadius: AppRadius.small))
                            }
                            .buttonStyle(.plain)
                            .accessibilityAddTraits(planChoice == choice ? .isSelected : [])
                        }
                    }
                    Button {
                        planChoice = .inbox
                    } label: {
                        Label("暂不安排 · 放入收集箱", systemImage: planChoice == .inbox ? "checkmark.circle.fill" : "tray")
                            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(planChoice == .inbox ? preferences.accentColor : AppColors.textSecondary)
                    if planChoice == .custom {
                        planCalendar
                    }
                }
            }

            TaskNotesField(text: $notes)

            subtaskFields

            VStack(spacing: 0) {
                Button {
                    showDetails.toggle()
                } label: {
                    HStack(spacing: AppSpacing.x2) {
                        Image(systemName: "chevron.right")
                            .rotationEffect(.degrees(showDetails ? 90 : 0))
                        Label("更多设置", systemImage: "slider.horizontal.3")
                            .font(AppTypography.callout.weight(.medium))
                        Spacer(minLength: 0)
                    }
                    .padding(AppSpacing.x4)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("更多设置")
                .accessibilityValue(showDetails ? "已展开" : "已收起")

                if showDetails {
                    advancedFields
                        .padding(.horizontal, AppSpacing.x4)
                        .padding(.bottom, AppSpacing.x4)
                }
            }
            .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))

            if let feedback {
                Label(feedback, systemImage: "checkmark.circle.fill")
                    .font(AppTypography.caption)
                    .foregroundStyle(preferences.accentColor)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private var planCalendar: some View {
        let calendar = Calendar.current
        let monthStart = calendar.dateInterval(of: .month, for: displayedPlanMonth ?? customDate)?.start
            ?? calendar.startOfDay(for: customDate)

        return VStack(alignment: .leading, spacing: AppSpacing.x3) {
            planCalendarTitle
            planCalendarNavigation(monthStart: monthStart)
            planCalendarGrid(monthStart: monthStart)
        }
        .padding(AppSpacing.x4)
        .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
        .id("plan-calendar")
    }

    private var planCalendarTitle: some View {
        HStack(spacing: AppSpacing.x2) {
            Label("计划日期", systemImage: "calendar")
                .font(AppTypography.desktop(.body, scale: preferences.fontScale,
                                            weight: .semibold, design: preferences.fontStyle.design))
            Spacer(minLength: AppSpacing.x2)
            Text(customDate.formatted(date: .long, time: .omitted))
                .font(AppTypography.desktop(.callout, scale: preferences.fontScale,
                                            design: preferences.fontStyle.design))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func planCalendarNavigation(monthStart: Date) -> some View {
        HStack(spacing: AppSpacing.x2) {
            Text(monthStart.formatted(.dateTime.year().month(.wide)))
                .font(AppTypography.desktop(.body, scale: preferences.fontScale,
                                            weight: .semibold, design: preferences.fontStyle.design))
            Spacer(minLength: 0)
            Button("回到本月") { displayedPlanMonth = .now }
                .buttonStyle(.plain)
                .font(AppTypography.desktop(.callout, scale: preferences.fontScale,
                                            design: preferences.fontStyle.design))
                .foregroundStyle(preferences.accentColor)
            Button {
                displayedPlanMonth = Calendar.current.date(byAdding: .month, value: -1, to: monthStart)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("上个月")
            Button {
                displayedPlanMonth = Calendar.current.date(byAdding: .month, value: 1, to: monthStart)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 36, height: 36)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("下个月")
        }
    }

    private func planCalendarGrid(monthStart: Date) -> some View {
        let calendar = Calendar.current
        let leadingDays = (calendar.component(.weekday, from: monthStart) - calendar.firstWeekday + 7) % 7
        let dayCount = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 30
        let columns = Array(repeating: GridItem(.flexible(), spacing: AppSpacing.x1), count: 7)

        return LazyVGrid(columns: columns, spacing: AppSpacing.x1) {
            ForEach(0..<7) { index in
                planCalendarWeekday(index, calendar: calendar)
            }
            ForEach(0..<(leadingDays + dayCount), id: \.self) { index in
                if index < leadingDays {
                    Color.clear.frame(height: 40)
                } else if let date = calendar.date(byAdding: .day, value: index - leadingDays, to: monthStart) {
                    planCalendarDay(date)
                }
            }
        }
    }

    private func planCalendarWeekday(_ index: Int, calendar: Calendar) -> some View {
        let weekday = (calendar.firstWeekday - 1 + index) % 7
        return Text(calendar.veryShortStandaloneWeekdaySymbols[weekday])
            .font(AppTypography.desktop(.caption1, scale: preferences.fontScale,
                                        design: preferences.fontStyle.design))
            .foregroundStyle(AppColors.textSecondary)
            .frame(maxWidth: .infinity, minHeight: 28)
            .accessibilityHidden(true)
    }

    private func planCalendarDay(_ date: Date) -> some View {
        let calendar = Calendar.current
        let isSelected = calendar.isDate(date, inSameDayAs: customDate)
        let isToday = calendar.isDateInToday(date)

        return Button {
            let time = calendar.dateComponents([.hour, .minute, .second], from: customDate)
            customDate = calendar.date(bySettingHour: time.hour ?? 0,
                                       minute: time.minute ?? 0,
                                       second: time.second ?? 0, of: date) ?? date
            displayedPlanMonth = nil
        } label: {
            Text("\(calendar.component(.day, from: date))")
                .font(AppTypography.desktop(.body, scale: preferences.fontScale,
                                            weight: isSelected ? .semibold : .regular,
                                            design: preferences.fontStyle.design))
                .foregroundStyle(isSelected ? preferences.accentColor : AppColors.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 40)
                .background(isSelected ? preferences.accentColor.opacity(0.14) : Color.clear,
                            in: RoundedRectangle(cornerRadius: AppRadius.small))
                .overlay(RoundedRectangle(cornerRadius: AppRadius.small)
                    .strokeBorder(isToday ? preferences.accentColor.opacity(0.6) : .clear))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
        .accessibilityLabel((isToday ? "今天，" : "") + date.formatted(date: .long, time: .omitted))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var subtaskFields: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x2) {
            HStack {
                Label("子任务", systemImage: "arrow.turn.down.right")
                    .font(AppTypography.callout.weight(.semibold))
                Spacer()
                Text("回车连续添加")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach($subtasks) { $draft in
                HStack(spacing: AppSpacing.x2) {
                    Image(systemName: "circle.dotted")
                        .foregroundStyle(preferences.accentColor)
                    TextField("子任务名称", text: $draft.title)
                        .textFieldStyle(.plain)
                        .accessibilityLabel("编辑子任务")
                    Button {
                        subtasks.removeAll { $0.id == draft.id }
                    } label: { Image(systemName: "xmark.circle.fill") }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("移除子任务")
                }
                .padding(.horizontal, AppSpacing.x3)
                .frame(minHeight: 38)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
            }
            if isAddingSubtask {
                HStack(spacing: AppSpacing.x2) {
                    Image(systemName: "plus.circle.fill").foregroundStyle(preferences.accentColor)
                    TextField("输入子任务，按回车继续", text: $subtaskInput)
                        .textFieldStyle(.plain)
                        .focused($subtaskFocused)
                        .onSubmit { appendSubtask() }
                        .accessibilityLabel("新子任务")
                }
                .padding(.horizontal, AppSpacing.x3)
                .frame(minHeight: 40)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: AppRadius.control))
            } else {
                Button("添加子任务", systemImage: "plus") {
                    isAddingSubtask = true
                    DispatchQueue.main.async { subtaskFocused = true }
                }
                .buttonStyle(.plain)
                .foregroundStyle(preferences.accentColor)
                .frame(minHeight: 36)
            }
            if !cleanSubtasks.isEmpty {
                Text("将创建 1 项主任务 + \(cleanSubtasks.count) 项子任务，保存后可选择查看蓝图。")
                    .font(AppTypography.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(AppSpacing.x4)
        .background(preferences.accentColor.opacity(0.055), in: RoundedRectangle(cornerRadius: AppRadius.control))
    }

    private var advancedFields: some View {
        VStack(alignment: .leading, spacing: 13) {
            Picker("所属项目", selection: $blueprintID) {
                Text("无项目").tag(nil as UUID?)
                ForEach(activeBlueprints) { blueprint in
                    Text(blueprint.name).tag(blueprint.id as UUID?)
                }
            }
            if !project.isEmpty && blueprintID == nil {
                Text("历史项目名称：\(project)。可在上方选择已有项目。")
                    .font(AppTypography.desktop(.footnote, scale: preferences.fontScale,
                                                design: preferences.fontStyle.design))
                    .foregroundStyle(AppColors.textSecondary)
            }
            if let blueprintID, !store.stages(for: blueprintID).isEmpty {
                Picker("所属阶段", selection: $stageID) {
                    Text("不指定").tag(nil as UUID?)
                    ForEach(store.stages(for: blueprintID)) { stage in
                        Text(stage.name).tag(stage.id as UUID?)
                    }
                }
            }
            if let stageID, !store.milestones(for: stageID).isEmpty {
                Picker("关联里程碑", selection: $milestoneID) {
                    Text("不指定").tag(nil as UUID?)
                    ForEach(store.milestones(for: stageID)) { milestone in
                        Text(milestone.name).tag(milestone.id as UUID?)
                    }
                }
            }
            if let blueprintID, mode != .completed {
                let candidates = store.tasks(for: blueprintID).filter { !$0.isCompleted && !$0.isCancelled }
                if !candidates.isEmpty {
                    DisclosureGroup("前置依赖") {
                        ForEach(candidates) { candidate in
                            Toggle(candidate.title, isOn: Binding(
                                get: { dependencyIDs.contains(candidate.id) },
                                set: { selected in
                                    if selected { dependencyIDs.insert(candidate.id) }
                                    else { dependencyIDs.remove(candidate.id) }
                                }
                            ))
                        }
                    }
                }
            }
            Picker("四象限", selection: $quadrant) {
                ForEach(Quadrant.allCases) { Text($0.title).tag($0) }
            }
            Picker("日报分类", selection: $reportCategory) {
                ForEach(ReportCategory.allCases) { Text($0.title).tag($0) }
            }
            Stepper("预计时长：\(estimatedMinutes) 分钟", value: $estimatedMinutes, in: 5...480, step: 5)
            if mode != .completed {
                Toggle("设置截止时间", isOn: $hasDeadline)
                if hasDeadline {
                    DatePicker("截止时间", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                }
                if planChoice != .inbox {
                    Toggle("固定安排", isOn: $isPlanLocked)
                        .help("批量调整与 AI 重新规划会跳过此事项；手动改期需先关闭固定安排。")
                }
            }
        }
        .font(AppTypography.desktop(.body, scale: preferences.fontScale,
                                    design: preferences.fontStyle.design))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            if keepOpen, navigationTaskID != nil {
                Button("查看蓝图", systemImage: "point.3.connected.trianglepath.dotted") {
                    shouldNavigateAfterClose = true
                    close()
                }
                    .buttonStyle(.link)
            }
            if !isAIInput {
                Toggle("连续添加", isOn: $keepOpen)
                    .toggleStyle(.checkbox)
                    .font(AppTypography.caption)
            }
            Spacer()
            Button("取消") { cancel() }
            Button(primaryTitle, systemImage: primaryIcon) {
                if isAIInput { Task { await parseAI() } }
                else { save() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.return, modifiers: [.command])
            .disabled(isAIInput ? !hasAIInput || store.isAIParsing : cleanTitle.isEmpty)
            if !isAIInput && mode == .task && !cleanSubtasks.isEmpty && !keepOpen {
                Button("添加并打开蓝图") { save(openBlueprint: true) }
                    .disabled(cleanTitle.isEmpty)
            }
        }
        .padding(.horizontal, 25)
        .padding(.vertical, 17)
        .background(preferences.cardBackground.opacity(0.82))
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 1) }
    }

    private var primaryTitle: String {
        if isAIInput { return "生成草稿" }
        if mode == .completed { return "记录完成" }
        return "添加任务"
    }

    private var primaryIcon: String {
        if isAIInput { return "sparkles" }
        return mode == .completed ? "checkmark" : "plus"
    }

    private var hasAIInput: Bool { !cleanSentence.isEmpty || selectedImageData != nil }

    private func focusInput() {
        DispatchQueue.main.async {
            guard isPresentationActive, !isClosing else { return }
            if isAIInput { sentenceFocused = true }
            else { titleFocused = true }
        }
    }

    private func parseAI() async {
        guard hasAIInput else { return }
        guard let parsed = await store.parseTask(
            sentence: cleanSentence,
            endpoint: preferences.deepSeekEndpoint,
            model: preferences.deepSeekModel,
            defaultQuadrant: preferences.defaultQuadrant,
            defaultDuration: preferences.defaultDuration,
            imageData: selectedImageData,
            visionModel: preferences.deepSeekVisionModel
        ) else { return }
        withAnimation(motion) {
            title = parsed.task.title
            notes = parsed.task.notes
            quadrant = parsed.task.quadrant
            reportCategory = parsed.task.effectiveReportCategory
            estimatedMinutes = parsed.task.estimatedMinutes
            project = parsed.task.project ?? ""
            customDate = parsed.task.scheduledFor
            displayedPlanMonth = nil
            planChoice = Calendar.current.isDateInToday(customDate) ? .today : Calendar.current.isDateInTomorrow(customDate) ? .tomorrow : .custom
            hasDeadline = parsed.task.dueDate != nil
            dueDate = parsed.task.dueDate ?? customDate
            subtasks = parsed.subtasks.map { SubtaskDraft(title: $0) }
            subtaskInput = ""
            isAddingSubtask = !subtasks.isEmpty
            hasAIDraft = true
            showDetails = true
        }
        focusInput()
    }

    private func save(openBlueprint: Bool = false) {
        guard !isClosing, !cleanTitle.isEmpty else { return }
        let normalizedProject = project.trimmingCharacters(in: .whitespacesAndNewlines)
        let isCompleted = mode == .completed
        let scheduledFor: Date
        switch planChoice {
        case .today: scheduledFor = .now
        case .tomorrow: scheduledFor = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
        case .custom: scheduledFor = customDate
        case .inbox: scheduledFor = .now
        }
        let actualDate = isCompleted ? completedAt : scheduledFor
        let status: TaskStatus = isCompleted ? .completed : planChoice == .inbox ? .unscheduled : .pending
        let parentID = UUID()
        let parent = TaskItem(
            id: parentID,
            title: cleanTitle,
            notes: notes,
            project: normalizedProject.isEmpty ? nil : normalizedProject,
            category: category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : category.trimmingCharacters(in: .whitespacesAndNewlines),
            reportCategory: reportCategory,
            quadrant: quadrant,
            scheduledFor: actualDate,
            dueDate: isCompleted || !hasDeadline ? nil : dueDate,
            estimatedMinutes: estimatedMinutes,
            isComplete: isCompleted,
            status: status,
            completedAt: isCompleted ? completedAt : nil,
            blueprintID: blueprintID,
            stageID: stageID,
            milestoneID: milestoneID,
            statusChangedAt: isCompleted ? completedAt : nil,
            dependencyIDs: isCompleted || dependencyIDs.isEmpty ? nil : Array(dependencyIDs),
            isPlanLocked: !isCompleted && planChoice != .inbox && isPlanLocked
        )
        let childTitles = cleanSubtasks
        let children = childTitles.map { subtask in
                TaskItem(
                    title: subtask,
                    project: parent.project,
                    category: parent.category,
                    reportCategory: parent.reportCategory,
                    quadrant: parent.quadrant,
                    scheduledFor: parent.scheduledFor,
                    dueDate: parent.dueDate,
                    estimatedMinutes: max(5, parent.estimatedMinutes / max(childTitles.count, 1)),
                    isComplete: parent.isCompleted,
                    status: parent.status,
                    completedAt: parent.completedAt,
                    blueprintID: parent.blueprintID,
                    stageID: parent.stageID,
                    statusChangedAt: parent.statusChangedAt,
                    parentTaskID: parentID
                )
        }
        guard store.addTaskTree(parent: parent, children: children) else { return }
        if !children.isEmpty {
            navigationTaskID = parentID
            navigationBlueprintID = blueprintID
            shouldNavigateAfterClose = openBlueprint
        } else {
            navigationTaskID = nil
            navigationBlueprintID = nil
            shouldNavigateAfterClose = false
        }
        if keepOpen {
            withAnimation(motion) {
                title = ""
                notes = ""
                sentence = ""
                selectedImageData = nil
                selectedImageName = nil
                subtasks = []
                subtaskInput = ""
                isAddingSubtask = false
                hasAIDraft = false
                completedAt = .now
                feedback = "已创建 1 项主任务和 \(children.count) 项子任务，继续输入下一项"
            }
            focusInput()
        } else {
            close()
        }
    }

    private func appendSubtask() {
        let value = subtaskInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        subtasks.append(SubtaskDraft(title: value))
        subtaskInput = ""
        subtaskFocused = true
    }

    private func cancel() {
        guard !isClosing else { return }
        if cleanTitle.isEmpty && cleanSubtasks.isEmpty && cleanSentence.isEmpty && selectedImageData == nil && notes.isEmpty {
            shouldNavigateAfterClose = false
            close()
        } else {
            showDiscardConfirmation = true
        }
    }

    private func close() {
        guard !isClosing else { return }
        titleFocused = false
        sentenceFocused = false
        subtaskFocused = false
        dismiss()
    }

    private func importImage(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let sourceData = try Data(contentsOf: url)
            guard let source = CGImageSourceCreateWithData(sourceData as CFData, nil),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2048
                  ] as CFDictionary),
                  let jpeg = NSBitmapImageRep(cgImage: thumbnail).representation(using: .jpeg, properties: [.compressionFactor: 0.8]),
                  jpeg.count <= 8_000_000 else {
                throw NSError(domain: "图片导入", code: 1, userInfo: [NSLocalizedDescriptionKey: "无法读取这张图片，请选择常见格式的图片重试。"])
            }
            selectedImageData = jpeg
            selectedImageName = url.lastPathComponent
            imageImportError = nil
            store.aiTaskError = nil
        } catch {
            imageImportError = "图片导入失败：\(error.localizedDescription)"
        }
    }
}
