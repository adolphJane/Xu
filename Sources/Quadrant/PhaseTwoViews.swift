import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AppSurfaceModifier: ViewModifier {
    @EnvironmentObject private var preferences: AppPreferences

    func body(content: Content) -> some View {
        content
            .tint(preferences.accentColor)
            .font(.system(size: 13 * preferences.fontScale, design: preferences.fontStyle.design))
            .fontDesign(preferences.fontStyle.design)
            .controlSize(.large)
            .environment(\.defaultMinListRowHeight, 42 + preferences.density.spacing)
            .transaction { if preferences.reduceMotion { $0.animation = nil } }
            .background {
                ZStack {
                    preferences.pageBackground.ignoresSafeArea()
                    if preferences.showBackgroundImage {
                        if !preferences.backgroundImagePath.isEmpty, let image = NSImage(contentsOfFile: preferences.backgroundImagePath) {
                            Image(nsImage: image).resizable().scaledToFill().opacity(0.16).clipped()
                        } else {
                            Image(systemName: "point.3.filled.connected.trianglepath.dotted")
                                .resizable().scaledToFit().foregroundStyle(preferences.accentColor.opacity(0.06)).padding(90)
                        }
                    }
                }
            }
    }
}

extension View {
    func appSurface() -> some View { modifier(AppSurfaceModifier()) }
}

struct AnniversariesView: View {
    @EnvironmentObject private var store: TaskStore
    @State private var isAdding = false
    @State private var editing: AnniversaryItem?
    @State private var preparationCandidate: AnniversaryItem?

    private var sortedAnniversaries: [AnniversaryItem] {
        store.anniversaries.sorted {
            switch ($0.daysRemaining(), $1.daysRemaining()) {
            case let (left?, right?): left < right
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): $0.date > $1.date
            }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader(
                    eyebrow: "MILESTONES IN LIFE",
                    title: "纪念日",
                    description: "记住重要的人与日子，提前准备，但由你决定是否创建任务。",
                    action: { isAdding = true },
                    actionTitle: "新建纪念日"
                )

                let candidates = store.upcomingAnniversaries.filter { $0.shouldOfferPreparation() }
                if !candidates.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("待确认的准备事项", systemImage: "bell.badge")
                            .font(.headline)
                        ForEach(candidates) { anniversary in
                            HStack {
                                Text("“\(anniversary.displayName)”即将到来")
                                Spacer()
                                Button("预览准备任务") { preparationCandidate = anniversary }
                                    .buttonStyle(.borderedProminent)
                            }
                            .padding(12)
                            .background(.background.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(16)
                    .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
                }

                if store.anniversaries.isEmpty {
                    ContentUnavailableView("还没有纪念日", systemImage: "calendar.badge.plus", description: Text("创建生日、纪念日或项目节点，并设置提前提醒。"))
                        .frame(maxWidth: .infinity, minHeight: 360)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 270), spacing: 16)], spacing: 16) {
                        ForEach(sortedAnniversaries) { anniversary in
                            AnniversaryCard(item: anniversary) {
                                editing = anniversary
                            } onPrepare: {
                                preparationCandidate = anniversary
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: 1120, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(30)
        }
        .sheet(isPresented: $isAdding) { AnniversaryEditor() }
        .sheet(item: $editing) { AnniversaryEditor(item: $0) }
        .sheet(item: $preparationCandidate) { PreparationTaskPreview(anniversary: $0) }
    }
}

struct AnniversaryCard: View {
    @EnvironmentObject private var store: TaskStore
    let item: AnniversaryItem
    let onEdit: () -> Void
    let onPrepare: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let path = item.coverPath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable().scaledToFill().frame(height: 92).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 11))
            }
            HStack {
                Image(systemName: item.type.icon).foregroundStyle(.pink)
                Text(item.displayName).font(.headline)
                Spacer()
                Menu {
                    Button("编辑", systemImage: "pencil", action: onEdit)
                    if item.preparationEnabled && item.generatedTaskID == nil {
                        Button("生成准备任务", systemImage: "checklist", action: onPrepare)
                    }
                    Divider()
                    Button("删除", systemImage: "trash", role: .destructive) { store.deleteAnniversary(item) }
                } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
            }
            if let days = item.daysRemaining() {
                Text(days == 0 ? "就是今天" : "还有 \(days) 天")
                    .font(.title2.monospacedDigit().weight(.bold))
            } else {
                Text("已结束").font(.title3.weight(.semibold)).foregroundStyle(.secondary)
            }
            HStack {
                Text(item.calendar.rawValue)
                Text("·")
                Text(item.repeatRule.rawValue)
                Text("· 提前 \(item.reminderDays) 天")
            }
            .font(.caption).foregroundStyle(.secondary)
            if !item.contact.isEmpty && !item.privacyMode {
                Label(item.contact, systemImage: "person").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, minHeight: 155, alignment: .topLeading)
        .background(.background.opacity(0.88), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(.quaternary))
    }
}

struct AnniversaryEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    private let original: AnniversaryItem?
    @State private var name: String
    @State private var date: Date
    @State private var type: AnniversaryType
    @State private var notes: String
    @State private var contact: String
    @State private var coverPath: String?
    @State private var calendar: AnniversaryCalendar
    @State private var repeatRule: AnniversaryRepeat
    @State private var reminderDays: Int
    @State private var showOnHome: Bool
    @State private var showInMenuBar: Bool
    @State private var showNotification: Bool
    @State private var privacyMode: Bool
    @State private var blueprintID: UUID?
    @State private var preparationEnabled: Bool
    @State private var preparationLeadDays: Int
    @State private var preparationTaskTitle: String

    init(item: AnniversaryItem? = nil) {
        original = item
        _name = State(initialValue: item?.name ?? "")
        _date = State(initialValue: item?.date ?? .now)
        _type = State(initialValue: item?.type ?? .custom)
        _notes = State(initialValue: item?.notes ?? "")
        _contact = State(initialValue: item?.contact ?? "")
        _coverPath = State(initialValue: item?.coverPath)
        _calendar = State(initialValue: item?.calendar ?? .solar)
        _repeatRule = State(initialValue: item?.repeatRule ?? .yearly)
        _reminderDays = State(initialValue: item?.reminderDays ?? 7)
        _showOnHome = State(initialValue: item?.showOnHome ?? true)
        _showInMenuBar = State(initialValue: item?.showInMenuBar ?? true)
        _showNotification = State(initialValue: item?.showNotification ?? true)
        _privacyMode = State(initialValue: item?.privacyMode ?? false)
        _blueprintID = State(initialValue: item?.blueprintID)
        _preparationEnabled = State(initialValue: item?.preparationEnabled ?? false)
        _preparationLeadDays = State(initialValue: item?.preparationLeadDays ?? 7)
        _preparationTaskTitle = State(initialValue: item?.preparationTaskTitle ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            Text(original == nil ? "新建纪念日" : "编辑纪念日")
                .font(.title2.weight(.bold)).frame(maxWidth: .infinity, alignment: .leading).padding(22)
            Form {
                Section("基本信息") {
                    TextField("名称", text: $name)
                    Picker("类型", selection: $type) { ForEach(AnniversaryType.allCases) { Text($0.rawValue).tag($0) } }
                    DatePicker("日期", selection: $date, displayedComponents: .date)
                    Picker("历法", selection: $calendar) { ForEach(AnniversaryCalendar.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("重复", selection: $repeatRule) { ForEach(AnniversaryRepeat.allCases) { Text($0.rawValue).tag($0) } }
                    TextField("联系人（可选）", text: $contact)
                    TextField("备注（可选）", text: $notes, axis: .vertical)
                    HStack {
                        Text(coverPath == nil ? "未设置封面" : "已选择封面")
                        Spacer()
                        Button("选择图片") { chooseCover() }
                        if coverPath != nil { Button("移除") { coverPath = nil } }
                    }
                }
                Section("提醒与展示") {
                    Stepper("提前提醒：\(reminderDays) 天", value: $reminderDays, in: 0...365)
                    Toggle("显示在首页", isOn: $showOnHome)
                    Toggle("显示在菜单栏", isOn: $showInMenuBar)
                    Toggle("通过系统通知提醒", isOn: $showNotification)
                    Toggle("隐私模式（隐藏名称）", isOn: $privacyMode)
                }
                Section("联动") {
                    Picker("关联蓝图", selection: $blueprintID) {
                        Text("不关联").tag(nil as UUID?)
                        ForEach(store.blueprints.filter { $0.archivedAt == nil }) { Text($0.name).tag($0.id as UUID?) }
                    }
                    Toggle("到期前建议生成准备任务", isOn: $preparationEnabled)
                    if preparationEnabled {
                        Stepper("提前 \(preparationLeadDays) 天开始准备", value: $preparationLeadDays, in: 1...365)
                        TextField("准备任务名称（可选）", text: $preparationTaskTitle)
                        Text("应用只会展示预览，确认后才创建任务。").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer(); Button("取消") { dismiss() }
                Button("保存") { save() }.buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.padding(20)
        }
        .frame(width: 570, height: 700)
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK { coverPath = panel.url?.path }
    }

    private func save() {
        let item = AnniversaryItem(
            id: original?.id ?? UUID(), name: name.trimmingCharacters(in: .whitespacesAndNewlines), date: date,
            type: type, notes: notes, contact: contact, coverPath: coverPath, calendar: calendar,
            repeatRule: repeatRule, reminderDays: reminderDays, showOnHome: showOnHome,
            showInMenuBar: showInMenuBar, showNotification: showNotification, privacyMode: privacyMode,
            blueprintID: blueprintID, preparationEnabled: preparationEnabled,
            preparationLeadDays: preparationLeadDays, preparationTaskTitle: preparationTaskTitle,
            generatedTaskID: original?.generatedTaskID, createdAt: original?.createdAt ?? .now
        )
        if original == nil { store.addAnniversary(item) } else { store.updateAnniversary(item) }
        dismiss()
    }
}

struct PreparationTaskPreview: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    let anniversary: AnniversaryItem

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("确认准备任务").font(.title2.weight(.bold))
            Text("纪念日不会直接修改计划。确认后才会创建下面的待办事项。")
                .foregroundStyle(.secondary)
            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Label(anniversary.preparationTaskTitle.isEmpty ? "准备\(anniversary.name)" : anniversary.preparationTaskTitle, systemImage: "checklist")
                        .font(.headline)
                    if let date = anniversary.nextOccurrence() {
                        Text("截止：\(date.formatted(date: .long, time: .omitted))")
                    }
                    Text("计划提前 \(anniversary.preparationLeadDays) 天开始")
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
            HStack {
                Spacer(); Button("暂不创建") { dismiss() }
                Button("确认创建", systemImage: "checkmark") { store.createPreparationTask(for: anniversary); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24).frame(width: 480, height: 280)
    }
}

struct BlueprintTimelineView: View {
    @EnvironmentObject private var store: TaskStore
    let blueprint: BlueprintItem
    private let dayWidth: CGFloat = 24

    var body: some View {
        let calendar = Calendar.current
        let totalDays = max(1, calendar.dateComponents([.day], from: blueprint.startDate, to: blueprint.dueDate).day ?? 1)
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 0) {
                    ForEach(0...totalDays, id: \.self) { day in
                        if day % 7 == 0 {
                            Text(calendar.date(byAdding: .day, value: day, to: blueprint.startDate) ?? blueprint.startDate, format: .dateTime.month().day())
                                .font(.caption2).frame(width: dayWidth * 7, alignment: .leading)
                        }
                    }
                }
                ForEach(store.stages(for: blueprint.id)) { stage in
                    timelineRow(name: stage.name, start: stage.startDate, end: stage.dueDate, color: Color(appHex: blueprint.colorHex), baseline: stage.originalStartDate.map { ($0, stage.originalDueDate ?? stage.dueDate) })
                }
                ForEach(store.tasks(for: blueprint.id).filter(\.needsAction).sorted { $0.scheduledFor < $1.scheduledFor }) { task in
                    timelineRow(name: task.title, start: task.scheduledFor, end: task.dueDate ?? task.scheduledFor, color: task.quadrant.tint, baseline: task.originalScheduledFor.map { ($0, task.originalDueDate ?? task.dueDate ?? $0) })
                }
            }
            .frame(width: max(CGFloat(totalDays + 1) * dayWidth, 760), alignment: .leading)
            .padding(.vertical, 8)
        }
        .padding(16)
        .background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
    }

    private func timelineRow(name: String, start: Date, end: Date, color: Color, baseline: (Date, Date)?) -> some View {
        let calendar = Calendar.current
        let offset = max(0, calendar.dateComponents([.day], from: blueprint.startDate, to: start).day ?? 0)
        let duration = max(1, calendar.dateComponents([.day], from: start, to: end).day ?? 1)
        return VStack(alignment: .leading, spacing: 3) {
            Text(name).font(.caption).lineLimit(1)
            ZStack(alignment: .leading) {
                if let baseline {
                    let baselineOffset = max(0, calendar.dateComponents([.day], from: blueprint.startDate, to: baseline.0).day ?? 0)
                    let baselineDuration = max(1, calendar.dateComponents([.day], from: baseline.0, to: baseline.1).day ?? 1)
                    Capsule().stroke(color.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [4]))
                        .frame(width: CGFloat(baselineDuration) * dayWidth, height: 12)
                        .offset(x: CGFloat(baselineOffset) * dayWidth)
                }
                Capsule().fill(color).frame(width: CGFloat(duration) * dayWidth, height: 10).offset(x: CGFloat(offset) * dayWidth)
            }.frame(height: 14)
        }
    }
}

struct BlueprintScheduleView: View {
    @EnvironmentObject private var store: TaskStore
    let blueprint: BlueprintItem
    let days: Int

    var body: some View {
        let start = Calendar.current.startOfDay(for: .now)
        let end = Calendar.current.date(byAdding: .day, value: days, to: start) ?? start
        let tasks = store.tasks(for: blueprint.id).filter { !$0.isUnscheduled && $0.scheduledFor >= start && $0.scheduledFor < end }
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(days == 7 ? "未来七天" : "未来三十天").font(.headline)
                Spacer(); Text("\(tasks.count) 项").foregroundStyle(.secondary)
            }
            if tasks.isEmpty {
                ContentUnavailableView("当前周期没有任务", systemImage: "calendar", description: Text("可编辑任务日期或使用重新规划。"))
                    .frame(maxWidth: .infinity, minHeight: 180)
            } else {
                ForEach(Dictionary(grouping: tasks, by: { Calendar.current.startOfDay(for: $0.scheduledFor) }).keys.sorted(), id: \.self) { date in
                    VStack(alignment: .leading, spacing: 7) {
                        Text(date, format: .dateTime.month().day().weekday()).font(.subheadline.weight(.semibold))
                        ForEach(tasks.filter { Calendar.current.isDate($0.scheduledFor, inSameDayAs: date) }) { task in
                            HStack {
                                Circle().fill(task.quadrant.tint).frame(width: 7, height: 7)
                                Text(task.title)
                                Spacer()
                                Text(task.effectiveStatus.title).font(.caption).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }
                    }
                    Divider()
                }
            }
        }
        .padding(16).background(.background.opacity(0.78), in: RoundedRectangle(cornerRadius: 14))
    }
}

struct ReschedulePreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    let blueprintID: UUID
    @State private var days = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("批量重新规划").font(.title2.weight(.bold))
            Text("只调整已安排、未完成且未锁定的任务，并保留原计划日期。")
                .foregroundStyle(.secondary)
            Stepper("整体顺延 \(days) 天", value: $days, in: 1...90)
            List(store.reschedulePreview(blueprintID: blueprintID, days: days)) { task in
                HStack {
                    Text(task.title).lineLimit(1)
                    Spacer()
                    Text("\(task.originalScheduledFor ?? task.scheduledFor, format: .dateTime.month().day()) → \(task.scheduledFor, format: .dateTime.month().day())")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            HStack {
                Spacer(); Button("取消") { dismiss() }
                Button("确认重新规划") { store.applyReschedule(blueprintID: blueprintID, days: days); dismiss() }
                    .buttonStyle(.borderedProminent)
            }
        }.padding(24).frame(width: 620, height: 520)
    }
}

struct BlueprintTemplatePicker: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("从模板创建蓝图").font(.title2.weight(.bold))
            Text("模板会创建三个可编辑阶段和对应里程碑。").foregroundStyle(.secondary)
            ForEach(BlueprintTemplate.allCases) { template in
                Button {
                    store.createBlueprint(from: template); dismiss()
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: template.icon).font(.title2).frame(width: 34)
                        VStack(alignment: .leading) {
                            Text(template.rawValue).font(.headline)
                            Text(template.stageNames.joined(separator: " → ")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(); Image(systemName: "chevron.right")
                    }.padding(12)
                }.buttonStyle(.plain)
            }
            HStack { Spacer(); Button("关闭") { dismiss() } }
        }.padding(24).frame(width: 520, height: 420)
    }
}

struct WeeklyReviewEditor: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var store: TaskStore
    @State private var summary = ""
    @State private var nextWeekFocus = ""

    private var weekStart: Date {
        Calendar.current.dateInterval(of: .weekOfYear, for: .now)?.start ?? .now
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("本周复盘").font(.title2.weight(.bold))
            Text("本周完成 \(store.tasks.filter { $0.isCompleted && $0.completedAt.map { $0 >= weekStart } == true }.count) 项，阻塞 \(store.tasks.filter { $0.effectiveStatus == .blocked }.count) 项。")
                .foregroundStyle(.secondary)
            Text("本周总结").font(.headline)
            TextEditor(text: $summary).padding(6).frame(height: 130).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            Text("下周重点").font(.headline)
            TextEditor(text: $nextWeekFocus).padding(6).frame(height: 110).overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary))
            HStack {
                Spacer(); Button("取消") { dismiss() }
                Button("保存周复盘") { store.saveWeeklyReview(summary: summary, nextWeekFocus: nextWeekFocus, weekStart: weekStart); dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(summary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 620, height: 560)
    }
}

struct ThemeSettingsView: View {
    @EnvironmentObject private var preferences: AppPreferences
    @State private var themeName = "我的主题"
    @State private var message: String?

    var body: some View {
        HStack(spacing: 18) {
            Form {
                Section("预置皮肤") {
                    Picker("皮肤", selection: $preferences.themePreset) {
                        ForEach(ThemePreset.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("自定义强调色（HEX，可选）", text: $preferences.customAccentHex)
                    TextField("自定义页面色（HEX，可选）", text: $preferences.customBackgroundHex)
                    TextField("自定义卡片色（HEX，可选）", text: $preferences.customCardHex)
                }
                Section("自动切换") {
                    Picker("切换规则", selection: $preferences.automaticThemeRule) {
                        ForEach(AutomaticThemeRule.allCases) { Text($0.rawValue).tag($0) }
                    }
                    if preferences.automaticThemeRule == .focus {
                        Toggle("专注主题当前启用", isOn: $preferences.focusThemeActive)
                        Text("可通过命令面板快速切换专注主题。").font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("四象限颜色") {
                    TextField("重要且紧急", text: $preferences.doNowColorHex)
                    TextField("重要不紧急", text: $preferences.scheduleColorHex)
                    TextField("不重要但紧急", text: $preferences.delegateColorHex)
                    TextField("不重要不紧急", text: $preferences.eliminateColorHex)
                }
                Section("排版与质感") {
                    Picker("字体", selection: $preferences.fontStyle) { ForEach(AppFontStyle.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("图标风格", selection: $preferences.iconStyle) { ForEach(AppIconStyle.allCases) { Text($0.rawValue).tag($0) } }
                    Picker("界面密度", selection: $preferences.density) {
                        ForEach(LayoutDensity.allCases) { Text($0.rawValue).tag($0) }
                    }
                    Slider(value: $preferences.fontScale, in: 0.85...1.25, step: 0.05) { Text("字体大小") }
                    Text("字体缩放 \(Int(preferences.fontScale * 100))%")
                    Slider(value: $preferences.cornerRadius, in: 4...24, step: 1) { Text("圆角") }
                    Slider(value: $preferences.shadowStrength, in: 0...0.3, step: 0.05) { Text("阴影") }
                    Toggle("显示背景纹理", isOn: $preferences.showBackgroundImage)
                    if preferences.showBackgroundImage {
                        HStack {
                            Text(preferences.backgroundImagePath.isEmpty ? "使用内置纹理" : "已选择背景素材").foregroundStyle(.secondary)
                            Spacer(); Button("选择图片") { chooseBackground() }
                            if !preferences.backgroundImagePath.isEmpty { Button("移除") { preferences.backgroundImagePath = "" } }
                        }
                    }
                    Toggle("高对比度", isOn: $preferences.highContrast)
                    Toggle("减少动态效果", isOn: $preferences.reduceMotion)
                }
                Section("个人主题") {
                    HStack {
                        TextField("主题名称", text: $themeName)
                        Button("保存当前主题") { preferences.savePersonalTheme(named: themeName) }
                    }
                    ForEach(preferences.savedThemes) { theme in
                        HStack {
                            Button(theme.name) { preferences.apply(theme) }
                            Spacer()
                            Button { export(theme) } label: { Image(systemName: "square.and.arrow.up") }
                            Button(role: .destructive) { preferences.deleteTheme(theme) } label: { Image(systemName: "trash") }
                        }
                    }
                    Button("导入主题", systemImage: "square.and.arrow.down") { importTheme() }
                }
                Section {
                    Label(preferences.contrastIsReadable ? "当前文字与背景对比度可读" : "当前组合对比度不足，请更换皮肤", systemImage: preferences.contrastIsReadable ? "checkmark.circle" : "exclamationmark.triangle")
                        .foregroundStyle(preferences.contrastIsReadable ? .green : .orange)
                    Button("恢复默认外观") { preferences.resetTheme() }
                }
            }
            .formStyle(.grouped)
            VStack(alignment: .leading, spacing: preferences.density.spacing) {
                Text("实时预览").font(.title2.weight(.bold))
                Text("今天，做好最重要的事").foregroundStyle(.secondary)
                HStack {
                    Circle().fill(preferences.accentColor).frame(width: 10, height: 10)
                    Text("完成第三阶段智能规划").font(.headline)
                    Spacer(); Text("进行中").foregroundStyle(preferences.accentColor)
                }
                .padding(16)
                .background(preferences.cardBackground, in: RoundedRectangle(cornerRadius: preferences.cornerRadius))
                .shadow(color: .black.opacity(preferences.shadowStrength), radius: 8)
                ProgressView(value: 0.68).tint(preferences.accentColor)
                Spacer()
            }
            .padding(22)
            .frame(width: 300)
            .background(preferences.pageBackground, in: RoundedRectangle(cornerRadius: 18))
        }
        .alert("主题", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) { Button("知道了") { message = nil } } message: { Text(message ?? "") }
    }

    private func chooseBackground() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.image]
        if panel.runModal() == .OK { preferences.backgroundImagePath = panel.url?.path ?? "" }
    }

    private func export(_ theme: PersonalTheme) {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "\(theme.name).xu-theme.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(theme).write(to: url, options: .atomic); message = "主题已导出。"
        } catch { message = "主题导出失败：\(error.localizedDescription)" }
    }

    private func importTheme() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            let theme = try decoder.decode(PersonalTheme.self, from: Data(contentsOf: url))
            preferences.savedThemes.append(theme)
            preferences.apply(theme)
            message = "主题已校验、导入并应用。"
        } catch { message = "主题文件无效，当前主题未改变：\(error.localizedDescription)" }
    }
}
