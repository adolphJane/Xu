#if os(macOS)
import AppKit
#else
import UIKit
#endif
import Foundation
import Security
import SwiftUI
import UserNotifications

#if os(macOS)
@main
struct QuadrantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = TaskStore()
    @StateObject private var preferences = AppPreferences()

    var body: some Scene {
        WindowGroup("序", id: "main") {
            ContentView()
                .environmentObject(store)
                .environmentObject(preferences)
                .preferredColorScheme(preferences.colorScheme)
                .tint(preferences.accentColor)
                .frame(minWidth: 980, minHeight: 680)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("添加事项") {
                    NotificationCenter.default.post(name: .showTaskComposer, object: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }

        WindowGroup("序小组件", id: "widget") {
            CompactWidgetView()
                .environmentObject(store)
                .environmentObject(preferences)
                .preferredColorScheme(preferences.colorScheme)
        }
        .defaultSize(width: 330, height: 300)
        .windowResizability(.contentSize)

        MenuBarExtra {
            MenuBarView()
                .environmentObject(store)
                .environmentObject(preferences)
                .preferredColorScheme(preferences.colorScheme)
                .tint(preferences.accentColor)
        } label: {
            MenuBarStatusLabel()
                .environmentObject(store)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(preferences)
                .preferredColorScheme(preferences.colorScheme)
                .tint(preferences.accentColor)
        }
    }
}
#endif

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system = "跟随系统"
    case light = "浅色"
    case dark = "深色"

    var id: String { rawValue }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

@MainActor
final class AppPreferences: ObservableObject {
    @Published var appearance: AppearanceMode { didSet { save(appearance.rawValue, key: "appearance") } }
    @Published var defaultQuadrant: Quadrant { didSet { save(defaultQuadrant.rawValue, key: "defaultQuadrant") } }
    @Published var defaultDuration: Int { didSet { save(defaultDuration, key: "defaultDuration") } }
    @Published var dailyReviewEnabled: Bool { didSet { save(dailyReviewEnabled, key: "dailyReviewEnabled") } }
    @Published var dailyReviewTime: Date { didSet { save(dailyReviewTime.timeIntervalSinceReferenceDate, key: "dailyReviewTime") } }
    @Published var deepSeekModel: String { didSet { save(deepSeekModel, key: "deepSeekModel") } }
    @Published var deepSeekVisionModel: String { didSet { save(deepSeekVisionModel, key: "deepSeekVisionModel") } }
    @Published var deepSeekEndpoint: String { didSet { save(deepSeekEndpoint, key: "deepSeekEndpoint") } }
    @Published var themePreset: ThemePreset { didSet { save(themePreset.rawValue, key: "themePreset") } }
    @Published var customAccentHex: String { didSet { save(customAccentHex, key: "customAccentHex") } }
    @Published var customBackgroundHex: String { didSet { save(customBackgroundHex, key: "customBackgroundHex") } }
    @Published var customCardHex: String { didSet { save(customCardHex, key: "customCardHex") } }
    @Published var doNowColorHex: String { didSet { save(doNowColorHex, key: "doNowColorHex") } }
    @Published var scheduleColorHex: String { didSet { save(scheduleColorHex, key: "scheduleColorHex") } }
    @Published var delegateColorHex: String { didSet { save(delegateColorHex, key: "delegateColorHex") } }
    @Published var eliminateColorHex: String { didSet { save(eliminateColorHex, key: "eliminateColorHex") } }
    @Published var density: LayoutDensity { didSet { save(density.rawValue, key: "layoutDensity") } }
    @Published var fontScale: Double { didSet { save(fontScale, key: "fontScale") } }
    @Published var cornerRadius: Double { didSet { save(cornerRadius, key: "cornerRadius") } }
    @Published var shadowStrength: Double { didSet { save(shadowStrength, key: "shadowStrength") } }
    @Published var showBackgroundImage: Bool { didSet { save(showBackgroundImage, key: "showBackgroundImage") } }
    @Published var fontStyle: AppFontStyle { didSet { save(fontStyle.rawValue, key: "fontStyle") } }
    @Published var iconStyle: AppIconStyle { didSet { save(iconStyle.rawValue, key: "iconStyle") } }
    @Published var backgroundImagePath: String { didSet { save(backgroundImagePath, key: "backgroundImagePath") } }
    @Published var automaticThemeRule: AutomaticThemeRule { didSet { save(automaticThemeRule.rawValue, key: "automaticThemeRule") } }
    @Published var focusThemeActive: Bool { didSet { save(focusThemeActive, key: "focusThemeActive") } }
    @Published var highContrast: Bool { didSet { save(highContrast, key: "highContrast") } }
    @Published var reduceMotion: Bool { didSet { save(reduceMotion, key: "reduceMotion") } }
    @Published var savedThemes: [PersonalTheme] { didSet { saveThemes() } }
    @Published var aiSendNotes: Bool { didSet { save(aiSendNotes, key: "aiSendNotes") } }
    @Published var aiSendProject: Bool { didSet { save(aiSendProject, key: "aiSendProject") } }
    @Published var syncEnabled: Bool { didSet { save(syncEnabled, key: "syncEnabled") } }
    @Published var syncFolderPath: String { didSet { save(syncFolderPath, key: "syncFolderPath") } }
    @Published var calendarIntegrationEnabled: Bool { didSet { save(calendarIntegrationEnabled, key: "calendarIntegrationEnabled") } }
    @Published var autoCheckUpdates: Bool { didSet { save(autoCheckUpdates, key: "autoCheckUpdates") } }
    @Published var availableUpdate: UpdateManifest?
    @Published var isCheckingUpdate = false
    @Published var isInstallingUpdate = false
    @Published var shouldPresentUpdatePrompt = false
    @Published var updateStatus: String?

    var resolvedPreset: ThemePreset {
        switch automaticThemeRule {
        case .manual: themePreset
        case .system: .system
        case .time:
            (Calendar.current.component(.hour, from: .now) >= 18 || Calendar.current.component(.hour, from: .now) < 7) ? .ink : .paper
        case .focus: focusThemeActive ? .ocean : themePreset
        }
    }
    var colorScheme: ColorScheme? {
        automaticThemeRule == .system ? nil : (resolvedPreset.preferredScheme ?? appearance.colorScheme)
    }
    var accentColor: Color {
        if highContrast { return colorScheme == .dark ? .yellow : .blue }
        return Color(appHex: customAccentHex.isEmpty ? resolvedPreset.accentHex : customAccentHex)
    }
    var pageBackground: Color {
        if highContrast { return colorScheme == .dark ? .black : .white }
        if resolvedPreset == .system && customBackgroundHex.isEmpty {
            #if os(macOS)
            return Color(nsColor: .windowBackgroundColor)
            #else
            return Color(uiColor: .systemBackground)
            #endif
        }
        return Color(appHex: customBackgroundHex.isEmpty ? resolvedPreset.backgroundHex : customBackgroundHex)
    }
    var cardBackground: Color {
        if highContrast { return colorScheme == .dark ? Color(appHex: "101010") : .white }
        if resolvedPreset == .system && customCardHex.isEmpty {
            #if os(macOS)
            return Color(nsColor: .controlBackgroundColor)
            #else
            return Color(uiColor: .secondarySystemBackground)
            #endif
        }
        return Color(appHex: customCardHex.isEmpty ? resolvedPreset.cardHex : customCardHex)
    }
    var contrastIsReadable: Bool {
        if resolvedPreset == .system && customBackgroundHex.isEmpty { return true }
        let background = Self.rgb(customBackgroundHex.isEmpty ? resolvedPreset.backgroundHex : customBackgroundHex)
        let foreground = colorScheme == .dark ? (1.0, 1.0, 1.0) : (0.08, 0.08, 0.08)
        let l1 = Self.luminance(background), l2 = Self.luminance(foreground)
        return (max(l1, l2) + 0.05) / (min(l1, l2) + 0.05) >= 4.5
    }
    private let defaults = UserDefaults.standard

    init() {
        appearance = AppearanceMode(rawValue: defaults.string(forKey: "appearance") ?? "") ?? .system
        defaultQuadrant = Quadrant(rawValue: defaults.string(forKey: "defaultQuadrant") ?? "") ?? .schedule
        let duration = defaults.integer(forKey: "defaultDuration")
        defaultDuration = duration == 0 ? 30 : duration
        dailyReviewEnabled = defaults.bool(forKey: "dailyReviewEnabled")
        let savedTime = defaults.double(forKey: "dailyReviewTime")
        dailyReviewTime = savedTime == 0 ? Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: .now) ?? .now : Date(timeIntervalSinceReferenceDate: savedTime)
        deepSeekModel = defaults.string(forKey: "deepSeekModel") ?? "deepseek-chat"
        deepSeekVisionModel = defaults.string(forKey: "deepSeekVisionModel") ?? "deepseek-flash"
        deepSeekEndpoint = defaults.string(forKey: "deepSeekEndpoint") ?? "https://api.deepseek.com/chat/completions"
        themePreset = ThemePreset(rawValue: defaults.string(forKey: "themePreset") ?? "") ?? .stone
        customAccentHex = defaults.string(forKey: "customAccentHex") ?? ""
        customBackgroundHex = defaults.string(forKey: "customBackgroundHex") ?? ""
        customCardHex = defaults.string(forKey: "customCardHex") ?? ""
        doNowColorHex = defaults.string(forKey: "doNowColorHex") ?? "D84A4A"
        scheduleColorHex = defaults.string(forKey: "scheduleColorHex") ?? "4F65D9"
        delegateColorHex = defaults.string(forKey: "delegateColorHex") ?? "D9823B"
        eliminateColorHex = defaults.string(forKey: "eliminateColorHex") ?? "77777C"
        density = LayoutDensity(rawValue: defaults.string(forKey: "layoutDensity") ?? "") ?? .standard
        let savedScale = defaults.double(forKey: "fontScale")
        fontScale = savedScale == 0 ? 1 : savedScale
        let savedRadius = defaults.double(forKey: "cornerRadius")
        cornerRadius = savedRadius == 0 ? 14 : savedRadius
        shadowStrength = defaults.double(forKey: "shadowStrength")
        showBackgroundImage = defaults.bool(forKey: "showBackgroundImage")
        fontStyle = AppFontStyle(rawValue: defaults.string(forKey: "fontStyle") ?? "") ?? .system
        iconStyle = AppIconStyle(rawValue: defaults.string(forKey: "iconStyle") ?? "") ?? .colorful
        backgroundImagePath = defaults.string(forKey: "backgroundImagePath") ?? ""
        automaticThemeRule = AutomaticThemeRule(rawValue: defaults.string(forKey: "automaticThemeRule") ?? "") ?? .manual
        focusThemeActive = defaults.bool(forKey: "focusThemeActive")
        highContrast = defaults.bool(forKey: "highContrast")
        reduceMotion = defaults.bool(forKey: "reduceMotion")
        if let data = defaults.data(forKey: "savedThemes"), let decoded = try? JSONDecoder().decode([PersonalTheme].self, from: data) { savedThemes = decoded }
        else { savedThemes = [] }
        aiSendNotes = defaults.object(forKey: "aiSendNotes") as? Bool ?? true
        aiSendProject = defaults.object(forKey: "aiSendProject") as? Bool ?? true
        syncEnabled = defaults.bool(forKey: "syncEnabled")
        syncFolderPath = defaults.string(forKey: "syncFolderPath") ?? ""
        calendarIntegrationEnabled = defaults.bool(forKey: "calendarIntegrationEnabled")
        autoCheckUpdates = defaults.bool(forKey: "autoCheckUpdates")
        availableUpdate = nil
    }

    private func save(_ value: Any, key: String) { defaults.set(value, forKey: key) }

    func resetTheme() {
        themePreset = .stone
        customAccentHex = ""
        customBackgroundHex = ""
        customCardHex = ""
        doNowColorHex = "D84A4A"
        scheduleColorHex = "4F65D9"
        delegateColorHex = "D9823B"
        eliminateColorHex = "77777C"
        density = .standard
        fontScale = 1
        cornerRadius = 14
        shadowStrength = 0
        showBackgroundImage = false
        fontStyle = .system
        iconStyle = .colorful
        backgroundImagePath = ""
        automaticThemeRule = .manual
        focusThemeActive = false
        highContrast = false
        reduceMotion = false
    }

    func savePersonalTheme(named name: String) {
        savedThemes.append(PersonalTheme(
            name: name, preset: themePreset, accentHex: customAccentHex,
            backgroundHex: customBackgroundHex, cardHex: customCardHex,
            fontStyle: fontStyle, iconStyle: iconStyle,
            backgroundImagePath: backgroundImagePath.isEmpty ? nil : backgroundImagePath,
            highContrast: highContrast, reduceMotion: reduceMotion
        ))
    }

    func apply(_ theme: PersonalTheme) {
        themePreset = theme.preset; customAccentHex = theme.accentHex
        customBackgroundHex = theme.backgroundHex; customCardHex = theme.cardHex
        fontStyle = theme.fontStyle; iconStyle = theme.iconStyle
        backgroundImagePath = theme.backgroundImagePath ?? ""
        highContrast = theme.highContrast; reduceMotion = theme.reduceMotion
    }

    func deleteTheme(_ theme: PersonalTheme) { savedThemes.removeAll { $0.id == theme.id } }

    private func saveThemes() {
        if let data = try? JSONEncoder().encode(savedThemes) { defaults.set(data, forKey: "savedThemes") }
    }

    func color(for quadrant: Quadrant) -> Color {
        switch quadrant {
        case .doNow: Color(appHex: doNowColorHex)
        case .schedule: Color(appHex: scheduleColorHex)
        case .delegate: Color(appHex: delegateColorHex)
        case .eliminate: Color(appHex: eliminateColorHex)
        }
    }

    private static func rgb(_ hex: String) -> (Double, Double, Double) {
        var value: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&value)
        return (Double((value >> 16) & 255) / 255, Double((value >> 8) & 255) / 255, Double(value & 255) / 255)
    }

    private static func luminance(_ rgb: (Double, Double, Double)) -> Double {
        func component(_ value: Double) -> Double { value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4) }
        return 0.2126 * component(rgb.0) + 0.7152 * component(rgb.1) + 0.0722 * component(rgb.2)
    }
}

enum DailyReviewNotification {
    private static let identifier = "quadrant.daily-review"

    static func configure(enabled: Bool, time: Date) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard enabled else { return }
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        let values = Calendar.current.dateComponents([.hour, .minute], from: time)
        let content = UNMutableNotificationContent()
        content.title = "该为今天做个收尾了"
        content.body = "查看完成情况，生成今天的日报。"
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: values, repeats: true)
        )
        try? await center.add(request)
    }
}

enum Quadrant: String, CaseIterable, Codable, Identifiable {
    case doNow
    case schedule
    case delegate
    case eliminate

    var id: String { rawValue }

    var title: String {
        switch self {
        case .doNow: "重要且紧急"
        case .schedule: "重要不紧急"
        case .delegate: "不重要但紧急"
        case .eliminate: "不重要不紧急"
        }
    }

    var subtitle: String {
        switch self {
        case .doNow: "立即处理"
        case .schedule: "安排时间"
        case .delegate: "快速处理"
        case .eliminate: "暂缓或删除"
        }
    }

    var tint: Color {
        switch self {
        case .doNow: .red
        case .schedule: .blue
        case .delegate: .orange
        case .eliminate: .gray
        }
    }
}

enum ReportCategory: String, CaseIterable, Codable, Identifiable {
    case projectProgress
    case collaboration

    var id: String { rawValue }
    var title: String {
        switch self {
        case .projectProgress: "项目/测试/开发进度"
        case .collaboration: "会议/方案/讨论"
        }
    }
}

enum TaskStatus: String, CaseIterable, Codable {
    case unscheduled
    case pending
    case inProgress
    case completed
    case cancelled
    case postponed
    case blocked

    var title: String {
        switch self {
        case .unscheduled: "待安排"
        case .pending: "待完成"
        case .inProgress: "进行中"
        case .completed: "已完成"
        case .cancelled: "已取消"
        case .postponed: "已延期"
        case .blocked: "已阻塞"
        }
    }
}

struct TaskTimeBlock: Identifiable, Codable, Equatable {
    var id = UUID()
    var start: Date
    var end: Date
    var timeZoneID: String = TimeZone.current.identifier
}

struct TaskItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var title: String
    var notes: String = ""
    var project: String? = nil
    var category: String? = nil
    var reportCategory: ReportCategory? = nil
    var quadrant: Quadrant
    var scheduledFor: Date = .now
    var dueDate: Date?
    var estimatedMinutes: Int = 30
    var isComplete = false
    var status: TaskStatus? = nil
    var completedAt: Date?
    var autoCompletedAt: Date? = nil
    var createdAt: Date = .now
    var blueprintID: UUID? = nil
    var stageID: UUID? = nil
    var milestoneID: UUID? = nil
    var startedAt: Date? = nil
    var originalScheduledFor: Date? = nil
    var blockReason: String? = nil
    var statusChangedAt: Date? = nil
    var parentTaskID: UUID? = nil
    var dependencyIDs: [UUID]? = nil
    var originalDueDate: Date? = nil
    var isPlanLocked: Bool? = nil
    var workflowX: Double? = nil
    var workflowY: Double? = nil
    var workflowImages: [WorkflowImage]? = nil
    /// Explicit execution time. Older date-only plans decode with no block.
    var timeBlock: TaskTimeBlock? = nil

    var effectiveReportCategory: ReportCategory { reportCategory ?? .projectProgress }
    var effectiveStatus: TaskStatus { status ?? (isComplete ? .completed : .pending) }
    var displayStatusTitle: String { isCompleted && autoCompletedAt != nil ? "自动完成" : effectiveStatus.title }
    var isPending: Bool { effectiveStatus == .pending }
    var needsAction: Bool { !isCompleted && !isCancelled }
    var isInProgress: Bool { effectiveStatus == .inProgress }
    var isCompleted: Bool { effectiveStatus == .completed }
    var isCancelled: Bool { effectiveStatus == .cancelled }
    var isUnscheduled: Bool { effectiveStatus == .unscheduled }
    var projectName: String {
        let value = project?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未归类项目" : value
    }
    var categoryName: String {
        let value = category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return value.isEmpty ? "未分类" : value
    }
    var effectiveDependencyIDs: [UUID] { dependencyIDs ?? [] }
    var planLocked: Bool { isPlanLocked ?? false }
    var images: [WorkflowImage] { workflowImages ?? [] }
}

struct ParsedTask {
    let task: TaskItem
    let subtasks: [String]
}

@MainActor
final class TaskStore: ObservableObject {
    @Published var tasks: [TaskItem] = [] {
        didSet {
            if !isApplyingSingleTaskMutation { persistTasks() }
        }
    }
    @Published var categories: [String] = [] {
        didSet {
            if storesCategoryPreferences { UserDefaults.standard.set(categories, forKey: "quadrant.taskCategories.v1") }
        }
    }
    #if os(macOS)
    @Published var categoryAppearance = CategoryAppearance() {
        didSet {
            if storesCategoryPreferences, let data = try? JSONEncoder().encode(categoryAppearance) {
                UserDefaults.standard.set(data, forKey: CategoryAppearance.defaultsKey)
            }
        }
    }
    #endif
    @Published var blueprints: [BlueprintItem] = [] { didSet { persist { try persistence?.saveBlueprints(blueprints) } } }
    @Published var stages: [StageItem] = [] { didSet { persist { try persistence?.saveStages(stages) } } }
    @Published var milestones: [MilestoneItem] = [] { didSet { persist { try persistence?.saveMilestones(milestones) } } }
    @Published var reports: [DailyReportItem] = [] { didSet { persist { try persistence?.saveReports(reports) } } }
    @Published var anniversaries: [AnniversaryItem] = [] { didSet { persist { try persistence?.saveAnniversaries(anniversaries) } } }
    @Published var weeklyReviews: [WeeklyReviewItem] = [] { didSet { persist { try persistence?.saveWeeklyReviews(weeklyReviews) } } }
    @Published var planChanges: [PlanChangeItem] = [] { didSet { persist { try persistence?.savePlanChanges(planChanges) } } }
    @Published var calendarEvents: [CalendarEventItem] = []
    @Published var syncConflict: SyncConflict?
    @Published var syncMessage: String?
    @Published var apiKey: String = "" {
        didSet { KeychainStore.save(apiKey, account: "deepseek-api-key") }
    }
    @Published var isReportLoading = false
    @Published var reportError: String?
    @Published var reportLengthWarning: String?
    @Published var isAIParsing = false
    @Published var aiTaskError: String?
    @Published var actionMessage: String?

    private let storageKey = "quadrant.tasks.v1"
    private var persistence: PersistenceController?
    private var isApplyingSingleTaskMutation = false
    private var storesCategoryPreferences = true

    private func persistTasks() {
        if let persistence {
            persist { try persistence.saveTasks(tasks) }
        } else if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func persistTask(_ task: TaskItem) {
        if let persistence {
            persist { try persistence.saveTask(task) }
        } else if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    private func persist(_ action: () throws -> Void) {
        do { try action() }
        catch { actionMessage = "本地数据保存失败：\(error.localizedDescription)。请检查磁盘空间并导出备份。" }
    }

    init(inMemory: Bool = false) {
        storesCategoryPreferences = !inMemory
        categories = inMemory ? [] : UserDefaults.standard.stringArray(forKey: "quadrant.taskCategories.v1") ?? []
        #if os(macOS)
        if !inMemory, let data = UserDefaults.standard.data(forKey: CategoryAppearance.defaultsKey),
           let saved = try? JSONDecoder().decode(CategoryAppearance.self, from: data) {
            categoryAppearance = saved
        }
        #endif
        do {
            let persistence = try PersistenceController(inMemory: inMemory)
            let storedTasks = try persistence.loadTasks()
            let storedBlueprints = try persistence.loadBlueprints()
            let storedStages = try persistence.loadStages()
            let storedMilestones = try persistence.loadMilestones()
            let storedReports = try persistence.loadReports()
            let storedAnniversaries = try persistence.loadAnniversaries()
            let storedReviews = try persistence.loadWeeklyReviews()
            let storedPlanChanges = try persistence.loadPlanChanges()
            if !storedTasks.isEmpty {
                tasks = storedTasks
            } else if !inMemory,
                      !UserDefaults.standard.bool(forKey: "quadrant.swiftdata.migration.v1"),
                      let data = UserDefaults.standard.data(forKey: storageKey),
                      let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
                tasks = decoded
                try persistence.saveTasks(decoded)
            }
            if !inMemory { UserDefaults.standard.set(true, forKey: "quadrant.swiftdata.migration.v1") }
            blueprints = storedBlueprints
            stages = storedStages
            milestones = storedMilestones
            reports = storedReports.sorted { $0.reportDate > $1.reportDate }
            anniversaries = storedAnniversaries
            weeklyReviews = storedReviews.sorted { $0.weekStart > $1.weekStart }
            planChanges = storedPlanChanges.sorted { $0.createdAt > $1.createdAt }
            self.persistence = persistence
        } catch {
            if !inMemory, let data = UserDefaults.standard.data(forKey: storageKey),
               let decoded = try? JSONDecoder().decode([TaskItem].self, from: data) {
                tasks = decoded
            }
            reportError = "本地数据库暂不可用，已切换到兼容模式：\(error.localizedDescription)"
        }
        apiKey = KeychainStore.load(account: "deepseek-api-key") ?? ""
        categories = Self.normalizedCategories(categories + tasks.compactMap(\.category))
        reconcileCompletedParents()
        for anniversary in anniversaries {
            Task { await AnniversaryNotifications.configure(anniversary) }
        }
    }

    var todayTasks: [TaskItem] {
        tasks.filter { TaskPlacement.isInToday($0) }
    }

    var completedToday: [TaskItem] {
        tasks.filter { $0.isCompleted && $0.completedAt.map(Calendar.current.isDateInToday) == true }
    }

    var processedToday: [TaskItem] {
        tasks.filter { task in
            if task.isCompleted { return task.completedAt.map(Calendar.current.isDateInToday) == true }
            return task.statusChangedAt.map(Calendar.current.isDateInToday) == true && [.cancelled, .postponed].contains(task.effectiveStatus)
        }
    }

    var cancelledTodayCount: Int {
        tasks.filter { $0.isCancelled && $0.statusChangedAt.map(Calendar.current.isDateInToday) == true }.count
    }

    var postponedTodayCount: Int {
        tasks.filter { $0.effectiveStatus == .postponed && $0.statusChangedAt.map(Calendar.current.isDateInToday) == true }.count
    }

    var completionText: String { "\(completedToday.count)/\(todayTasks.filter { !$0.isCancelled }.count)" }

    private static func normalizedCategories(_ names: [String]) -> [String] {
        var seen = Set<String>()
        return names.compactMap { name in
            let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, seen.insert(value.localizedLowercase).inserted else { return nil }
            return value
        }
    }

    func addCategory(_ name: String) {
        let updated = Self.normalizedCategories(categories + [name])
        if updated != categories { categories = updated }
    }

    private func resolvedCategory(_ name: String?) -> String? {
        let value = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !value.isEmpty else { return nil }
        return categories.first { $0.localizedCaseInsensitiveCompare(value) == .orderedSame } ?? value
    }

    func renameCategory(_ oldName: String, to newName: String) -> Bool {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, categories.contains(oldName),
              !categories.contains(where: { $0 != oldName && $0.localizedCaseInsensitiveCompare(name) == .orderedSame }) else { return false }
        categories = categories.map { $0 == oldName ? name : $0 }
        #if os(macOS)
        categoryAppearance.rename(oldName, to: name)
        #endif
        tasks = tasks.map { task in
            var updated = task
            if updated.category == oldName { updated.category = name }
            return updated
        }
        return true
    }

    func deleteCategory(_ name: String) {
        categories.removeAll { $0 == name }
        #if os(macOS)
        categoryAppearance.remove(name)
        #endif
        tasks = tasks.map { task in
            var updated = task
            if updated.category == name { updated.category = nil }
            return updated
        }
    }

    func tasks(in quadrant: Quadrant, includeCompleted: Bool = false) -> [TaskItem] {
        tasks.filter { $0.quadrant == quadrant && (includeCompleted || $0.needsAction) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    func add(_ task: TaskItem) {
        var task = task
        task.category = resolvedCategory(task.category)
        guard TaskTreeProjection.canAssignParent(task.parentTaskID, to: task.id, in: tasks),
              !tasks.contains(where: { $0.id == task.id }) else {
            actionMessage = "任务归属无效，请重新选择父任务。"
            return
        }
        if let parentID = task.parentTaskID,
           tasks.first(where: { $0.id == parentID })?.blueprintID != task.blueprintID {
            actionMessage = "子任务与父任务必须属于同一蓝图。"
            return
        }
        if let error = WorkflowGraph.validationError(task: task, dependencies: task.effectiveDependencyIDs, tasks: tasks) {
            actionMessage = error
            return
        }
        if task.isCompleted, let reason = WorkflowGraph.blockingReason(for: task, tasks: tasks, blueprints: blueprints) {
            actionMessage = reason
            return
        }
        var updated = tasks
        updated.insert(task, at: 0)
        if let parentID = task.parentTaskID, !task.isCompleted {
            let completedAncestors = TaskTreeProjection.path(to: parentID, in: updated).filter(\.isCompleted)
            for ancestor in completedAncestors where !activeWorkflowDescendants(of: ancestor.id).isEmpty {
                actionMessage = "请先回退“\(ancestor.title)”的后续任务，再添加子任务。"
                return
            }
            let changedAt = Date()
            for ancestor in completedAncestors {
                guard let index = updated.firstIndex(where: { $0.id == ancestor.id }) else { continue }
                updated[index].status = .pending
                updated[index].isComplete = false
                updated[index].completedAt = nil
                updated[index].autoCompletedAt = nil
                updated[index].statusChangedAt = changedAt
            }
        }
        tasks = updated
        if let category = task.category { addCategory(category) }
    }

    /// Adds a child to any existing task while preserving its planning context.
    @discardableResult
    func addChild(title: String, to parentID: UUID, notes: String = "") -> Bool {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, let parent = tasks.first(where: { $0.id == parentID }) else {
            actionMessage = "父任务不存在或子任务名称为空。"
            return false
        }
        let child = TaskItem(
            title: name, notes: notes, project: parent.project, category: parent.category,
            reportCategory: parent.reportCategory, quadrant: parent.quadrant,
            scheduledFor: parent.scheduledFor, dueDate: parent.dueDate,
            estimatedMinutes: parent.estimatedMinutes,
            status: parent.isUnscheduled ? .unscheduled : .pending,
            blueprintID: parent.blueprintID, stageID: parent.stageID,
            milestoneID: parent.milestoneID, parentTaskID: parent.id
        )
        let previousCount = tasks.count
        add(child)
        return tasks.count == previousCount + 1
    }

    /// Saves one task tree as a single collection update, after validating every task.
    @discardableResult
    func addTaskTree(parent: TaskItem, children: [TaskItem]) -> Bool {
        let incoming = [parent] + children
        let incomingIDs = incoming.map(\.id)
        guard Set(incomingIDs).count == incoming.count,
              incomingIDs.allSatisfy({ id in !tasks.contains(where: { $0.id == id }) }),
              children.allSatisfy({ $0.parentTaskID == parent.id && $0.blueprintID == parent.blueprintID }) else {
            actionMessage = "任务结构无效，请重试。"
            return false
        }
        let resolved = incoming.map { original in
            var task = original
            task.category = resolvedCategory(task.category)
            return task
        }
        let combined = tasks + resolved
        for task in resolved {
            if let error = WorkflowGraph.validationError(task: task, dependencies: task.effectiveDependencyIDs, tasks: combined) {
                actionMessage = error
                return false
            }
            if task.isCompleted, let reason = WorkflowGraph.blockingReason(for: task, tasks: combined, blueprints: blueprints) {
                actionMessage = reason
                return false
            }
        }
        tasks.insert(contentsOf: resolved, at: 0)
        for category in Set(resolved.compactMap(\.category)) { addCategory(category) }
        return true
    }

    @discardableResult
    func update(_ task: TaskItem) -> Bool {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return false }
        let previous = tasks[index]
        let previousBlueprintID = previous.blueprintID
        var updated = task
        updated.category = resolvedCategory(updated.category)
        if updated.isUnscheduled || updated.isCancelled {
            updated.timeBlock = nil
        } else if updated.timeBlock == previous.timeBlock,
                  !Calendar.current.isDate(updated.scheduledFor, inSameDayAs: previous.scheduledFor) {
            // A date edit in the existing task editor makes the precise time unconfirmed.
            updated.timeBlock = nil
        }
        if !updated.isCompleted { updated.autoCompletedAt = nil }
        guard !updated.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              TaskTreeProjection.canAssignParent(updated.parentTaskID, to: updated.id, in: tasks) else {
            actionMessage = "任务名称或父任务归属无效。"
            return false
        }
        if let parentID = updated.parentTaskID,
           tasks.first(where: { $0.id == parentID })?.blueprintID != updated.blueprintID {
            actionMessage = "子任务与父任务必须属于同一蓝图。"
            return false
        }
        if let error = TaskTreeProjection.validationError(in: tasks.filter { $0.id != updated.id } + [updated]) {
            actionMessage = error
            return false
        }
        let movingTree = previousBlueprintID != updated.blueprintID
            ? [previous] + TaskTreeProjection.descendants(of: updated.id, in: tasks)
            : []
        if updated.workflowX == nil { updated.workflowX = previous.workflowX }
        if updated.workflowY == nil { updated.workflowY = previous.workflowY }
        if updated.workflowImages == nil { updated.workflowImages = previous.workflowImages }
        if previous.isCompleted && !updated.isCompleted && !activeWorkflowDescendants(of: previous.id).isEmpty {
            actionMessage = "请先回退已开始的后续任务，再修改前置任务的完成状态。"
            return false
        }
        if previousBlueprintID != task.blueprintID {
            let movingIDs = Set(movingTree.map(\.id))
            guard task.blueprintID == nil || blueprints.contains(where: { $0.id == task.blueprintID }) else {
                actionMessage = "目标蓝图不存在。"
                return false
            }
            let outsideEdges = tasks.filter { !movingIDs.contains($0.id) && !$0.effectiveDependencyIDs.filter(movingIDs.contains).isEmpty }
            if !outsideEdges.isEmpty || (task.blueprintID == nil && movingTree.contains(where: { !$0.effectiveDependencyIDs.isEmpty })) {
                actionMessage = "请先移除任务树与其他任务之间的前置连线，再移动或解除蓝图。"
                return false
            }
            var moved = movingTree.map { item -> TaskItem in
                var value = item
                value.blueprintID = task.blueprintID
                if value.id == task.id {
                    value = updated
                    value.blueprintID = task.blueprintID
                    if value.stageID.flatMap({ stageID in stages(for: task.blueprintID ?? UUID()).contains(where: { $0.id == stageID }) }) != true { value.stageID = nil }
                    if value.milestoneID.flatMap({ milestoneID in milestones.contains(where: { $0.id == milestoneID && $0.blueprintID == task.blueprintID }) }) != true { value.milestoneID = nil }
                } else {
                    value.stageID = nil
                    value.milestoneID = nil
                }
                return value
            }
            for item in moved {
                if let error = WorkflowGraph.validationError(task: item, dependencies: item.effectiveDependencyIDs, tasks: tasks.filter { !movingIDs.contains($0.id) } + moved) {
                    actionMessage = error
                    return false
                }
            }
            tasks.removeAll { movingIDs.contains($0.id) }
            tasks.insert(contentsOf: moved, at: 0)
            if let category = updated.category { addCategory(category) }
            return true
        }
        if let error = WorkflowGraph.validationError(task: updated, dependencies: updated.effectiveDependencyIDs, tasks: tasks) {
            actionMessage = error
            return false
        }
        tasks[index] = updated
        if let category = updated.category { addCategory(category) }
        if previousBlueprintID != updated.blueprintID { removeCrossBlueprintDependents(of: updated) }
        return true
    }

    /// Commits a calendar series move in one task collection update after checking stale previews.
    @discardableResult
    func applyCalendarSeriesMove(_ changes: [(before: TaskItem, after: TaskItem)]) -> Bool {
        guard !changes.isEmpty, Set(changes.map { $0.before.id }).count == changes.count else { return false }
        var candidate = tasks
        for change in changes {
            guard let index = candidate.firstIndex(where: { $0.id == change.before.id }),
                  candidate[index] == change.before,
                  change.after.id == change.before.id,
                  !change.before.isCompleted, !change.before.isCancelled,
                  !change.before.planLocked, change.before.startedAt == nil,
                  change.after.dueDate == change.before.dueDate,
                  change.after.effectiveStatus == change.before.effectiveStatus else {
                actionMessage = "系列安排已变化，请重新预览后再保存。"
                return false
            }
            candidate[index] = change.after
        }
        do {
            if let persistence {
                do { try persistence.saveTasks(candidate) }
                catch {
                    persistence.rollbackChanges()
                    throw error
                }
            } else {
                let data = try JSONEncoder().encode(candidate)
                UserDefaults.standard.set(data, forKey: storageKey)
            }
        } catch {
            actionMessage = "系列安排保存失败：\(error.localizedDescription)"
            return false
        }
        isApplyingSingleTaskMutation = true
        tasks = candidate
        isApplyingSingleTaskMutation = false
        return true
    }

    func toggle(_ task: TaskItem) {
        if task.isCompleted { restore(task) } else { markCompleted(task) }
    }

    func markCompleted(_ task: TaskItem) {
        guard let current = tasks.first(where: { $0.id == task.id }) else { return }
        if current.isCancelled {
            actionMessage = "请先恢复已取消的任务。"
            return
        }

        // Validate the full hierarchy against a working copy, so a blocked child
        // cannot leave its parent and siblings partially completed.
        var updated = tasks
        let descendants = TaskTreeProjection.descendants(of: current.id, in: tasks)
        var remaining = ([current] + descendants).filter { !$0.isCompleted && !$0.isCancelled }.map(\.id)
        let completedAt = Date()
        while !remaining.isEmpty {
            var progressed = false
            for id in remaining {
                guard let index = updated.firstIndex(where: { $0.id == id }),
                      WorkflowGraph.blockingReason(for: updated[index], tasks: updated, blueprints: blueprints) == nil else { continue }
                updated[index].status = .completed
                updated[index].isComplete = true
                updated[index].completedAt = completedAt
                updated[index].autoCompletedAt = id == current.id ? nil : completedAt
                updated[index].statusChangedAt = completedAt
                updated[index].blockReason = nil
                remaining.removeAll { $0 == id }
                progressed = true
            }
            if !progressed {
                guard let blocked = updated.first(where: { remaining.contains($0.id) && $0.effectiveStatus == .blocked })
                    ?? updated.first(where: { remaining.contains($0.id) }) else { return }
                let reason = WorkflowGraph.blockingReason(for: blocked, tasks: updated, blueprints: blueprints)
                    ?? "请检查任务的前置条件。"
                actionMessage = "无法完成“\(blocked.title)”：\(reason)"
                return
            }
        }
        autoCompleteAncestors(of: current.id, in: &updated, at: completedAt)
        if updated != tasks { tasks = updated }
    }

    private func autoCompleteAncestors(of taskID: UUID, in updated: inout [TaskItem], at date: Date) {
        let ancestors = TaskTreeProjection.path(to: taskID, in: updated).dropLast().reversed()
        for ancestor in ancestors {
            let children = TaskTreeProjection.directChildren(of: ancestor.id, in: updated)
            guard !children.isEmpty, children.allSatisfy(\.isCompleted) else { break }
            guard let index = updated.firstIndex(where: { $0.id == ancestor.id }) else { break }
            if updated[index].isCompleted { continue }
            if let reason = WorkflowGraph.blockingReason(for: updated[index], tasks: updated, blueprints: blueprints) {
                actionMessage = "子任务已完成，但“\(ancestor.title)”无法自动完成：\(reason)"
                break
            }
            Self.completeAutomatically(&updated[index], at: date)
        }
    }

    /// Reconciles older task data that already has every child completed.
    func reconcileCompletedParents() {
        var updated = tasks
        let completedAt = Date()
        var changed = false
        repeat {
            changed = false
            for index in updated.indices where !updated[index].isCompleted {
                let children = TaskTreeProjection.directChildren(of: updated[index].id, in: updated)
                guard !children.isEmpty, children.allSatisfy(\.isCompleted),
                      WorkflowGraph.blockingReason(for: updated[index], tasks: updated, blueprints: blueprints) == nil else { continue }
                Self.completeAutomatically(&updated[index], at: completedAt)
                changed = true
            }
        } while changed
        if updated != tasks { tasks = updated }
    }

    private static func completeAutomatically(_ task: inout TaskItem, at date: Date) {
        task.status = .completed
        task.isComplete = true
        task.completedAt = date
        task.autoCompletedAt = date
        task.statusChangedAt = date
        task.blockReason = nil
    }

    func start(_ task: TaskItem) {
        guard let current = tasks.first(where: { $0.id == task.id }), !current.isCompleted else { return }
        if let reason = executionBlockReason(for: task) {
            actionMessage = reason
            return
        }
        mutate(task) {
            $0.status = .inProgress
            if task.isUnscheduled { $0.scheduledFor = .now }
            $0.startedAt = $0.startedAt ?? .now
            $0.statusChangedAt = .now
        }
    }

    func cancel(_ task: TaskItem) {
        setStatus(task, to: .cancelled)
    }

    func restore(_ task: TaskItem) {
        guard let current = tasks.first(where: { $0.id == task.id }) else { return }
        if current.isCompleted {
            let batchChildren = TaskTreeProjection.descendants(of: current.id, in: tasks).filter {
                guard let completedAt = current.completedAt, current.autoCompletedAt == nil else { return false }
                return $0.isCompleted && $0.autoCompletedAt == completedAt
            }
            let completedAncestors = TaskTreeProjection.path(to: current.id, in: tasks).dropLast().filter(\.isCompleted)
            let affected = Set(batchChildren.map(\.id)).union(completedAncestors.map(\.id)).union([current.id])
            let active = affected.flatMap { WorkflowGraph.descendants(of: $0, tasks: tasks) }
                .filter { !affected.contains($0.id) && ($0.isInProgress || $0.isCompleted) }
            if !active.isEmpty {
                actionMessage = "请先回退后续任务：\(active.map(\.title).joined(separator: "、"))。"
                return
            }
            if affected.count > 1 {
                var updated = tasks
                let changedAt = Date()
                for index in updated.indices where affected.contains(updated[index].id) {
                    updated[index].status = .pending
                    updated[index].isComplete = false
                    updated[index].completedAt = nil
                    updated[index].autoCompletedAt = nil
                    updated[index].statusChangedAt = changedAt
                    updated[index].blockReason = nil
                }
                tasks = updated
                return
            }
        }
        setStatus(task, to: .pending)
    }

    func rollbackWorkflow(from task: TaskItem) {
        guard let current = tasks.first(where: { $0.id == task.id }), current.isCompleted else { return }
        var affected: Set<UUID> = [task.id]
        var previousCount = 0
        while previousCount != affected.count {
            previousCount = affected.count
            for id in Array(affected) {
                affected.formUnion(WorkflowGraph.descendants(of: id, tasks: tasks)
                    .filter { $0.isInProgress || $0.isCompleted }.map(\.id))
                affected.formUnion(TaskTreeProjection.path(to: id, in: tasks).dropLast()
                    .filter(\.isCompleted).map(\.id))
            }
        }
        var updated = tasks
        for index in updated.indices where affected.contains(updated[index].id) {
            updated[index].status = .pending
            updated[index].isComplete = false
            updated[index].completedAt = nil
            updated[index].autoCompletedAt = nil
            updated[index].startedAt = nil
            updated[index].blockReason = nil
            updated[index].statusChangedAt = .now
        }
        tasks = updated
    }

    func postpone(_ task: TaskItem, to date: Date? = nil) {
        guard let current = tasks.first(where: { $0.id == task.id }), !current.isCompleted, !current.isCancelled else { return }
        guard !current.planLocked else {
            actionMessage = "此事项已固定安排。请先在事项详情中关闭“固定安排”，再修改日期。"
            return
        }
        mutate(task) {
            $0.originalScheduledFor = $0.originalScheduledFor ?? $0.scheduledFor
            let calendar = Calendar.current
            let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now)) ?? .now
            let hour = calendar.component(.hour, from: $0.scheduledFor)
            let minute = calendar.component(.minute, from: $0.scheduledFor)
            $0.scheduledFor = date ?? calendar.date(bySettingHour: hour, minute: minute, second: 0, of: tomorrow) ?? tomorrow
            $0.status = .postponed
            $0.completedAt = nil
            $0.statusChangedAt = .now
        }
    }

    func block(_ task: TaskItem, reason: String) {
        guard let current = tasks.first(where: { $0.id == task.id }), !current.isCompleted, !current.isCancelled else { return }
        mutate(task) {
            $0.status = .blocked
            $0.blockReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
            $0.statusChangedAt = .now
        }
    }

    private func setStatus(_ task: TaskItem, to status: TaskStatus) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        if tasks[index].isCompleted && status != .completed && !activeWorkflowDescendants(of: task.id).isEmpty {
            actionMessage = "请先回退已开始的后续任务，再更改此任务状态。"
            return
        }
        if status == .completed && tasks[index].isCancelled {
            actionMessage = "请先恢复已取消的任务。"
            return
        }
        if status == .completed, let reason = executionBlockReason(for: tasks[index]) {
            actionMessage = reason
            return
        }
        let completedAncestors = status == .completed ? [] :
            TaskTreeProjection.path(to: task.id, in: tasks).dropLast().filter(\.isCompleted)
        for ancestor in completedAncestors where !activeWorkflowDescendants(of: ancestor.id).isEmpty {
            actionMessage = "请先回退“\(ancestor.title)”的后续任务，再更改此任务状态。"
            return
        }
        var updated = tasks
        let changedAt = Date()
        updated[index].status = status
        updated[index].isComplete = status == .completed
        updated[index].completedAt = status == .completed ? changedAt : nil
        updated[index].autoCompletedAt = nil
        updated[index].statusChangedAt = changedAt
        if status != .blocked { updated[index].blockReason = nil }
        for ancestor in completedAncestors {
            guard let ancestorIndex = updated.firstIndex(where: { $0.id == ancestor.id }) else { continue }
            updated[ancestorIndex].status = .pending
            updated[ancestorIndex].isComplete = false
            updated[ancestorIndex].completedAt = nil
            updated[ancestorIndex].autoCompletedAt = nil
            updated[ancestorIndex].statusChangedAt = changedAt
        }
        tasks = updated
    }

    private func activeWorkflowDescendants(of taskID: UUID) -> [TaskItem] {
        WorkflowGraph.descendants(of: taskID, tasks: tasks).filter { $0.isInProgress || $0.isCompleted }
    }

    private func mutate(_ task: TaskItem, change: (inout TaskItem) -> Void) {
        guard let index = tasks.firstIndex(where: { $0.id == task.id }) else { return }
        isApplyingSingleTaskMutation = true
        change(&tasks[index])
        isApplyingSingleTaskMutation = false
        persistTask(tasks[index])
    }

    func delete(_ task: TaskItem) {
        let removedIDs = Set([task.id] + TaskTreeProjection.descendants(of: task.id, in: tasks).map(\.id))
        let successors = tasks.filter { !removedIDs.contains($0.id) && !$0.effectiveDependencyIDs.filter(removedIDs.contains).isEmpty }
        if !successors.isEmpty {
            actionMessage = "请先移除“\(successors.map(\.title).joined(separator: "、"))”的前置连线，再删除任务。"
            return
        }
        var updated = tasks.filter { !removedIDs.contains($0.id) }
        for index in updated.indices {
            updated[index].dependencyIDs?.removeAll { removedIDs.contains($0) }
            if updated[index].dependencyIDs?.isEmpty == true { updated[index].dependencyIDs = nil }
            if updated[index].parentTaskID.map(removedIDs.contains) == true { updated[index].parentTaskID = nil }
        }
        tasks = updated
        for index in anniversaries.indices where anniversaries[index].generatedTaskID.map(removedIDs.contains) == true {
            anniversaries[index].generatedTaskID = nil
        }
    }

    @discardableResult
    func removeWorkflowNode(_ task: TaskItem, reconnect: Bool) -> Bool {
        guard let current = tasks.first(where: { $0.id == task.id }) else { return false }
        let removedIDs = Set([current.id] + TaskTreeProjection.descendants(of: current.id, in: tasks).map(\.id))
        var updated = tasks.filter { !removedIDs.contains($0.id) }
        for index in updated.indices {
            if updated[index].parentTaskID.map(removedIDs.contains) == true { updated[index].parentTaskID = nil }
            guard !updated[index].effectiveDependencyIDs.filter(removedIDs.contains).isEmpty else { continue }
            var dependencies = updated[index].effectiveDependencyIDs.filter { !removedIDs.contains($0) }
            if reconnect {
                let predecessors = Set(removedIDs.flatMap { id in tasks.first(where: { $0.id == id })?.effectiveDependencyIDs ?? [] })
                for predecessorID in predecessors where !removedIDs.contains(predecessorID) && !dependencies.contains(predecessorID) {
                    dependencies.append(predecessorID)
                }
            }
            updated[index].dependencyIDs = dependencies.isEmpty ? nil : dependencies
        }
        for successor in updated where tasks.contains(where: { $0.id == successor.id && !$0.effectiveDependencyIDs.filter(removedIDs.contains).isEmpty }) {
            if let error = WorkflowGraph.validationError(task: successor, dependencies: successor.effectiveDependencyIDs, tasks: updated) {
                actionMessage = error
                return false
            }
        }
        tasks = updated
        for index in anniversaries.indices where anniversaries[index].generatedTaskID.map(removedIDs.contains) == true {
            anniversaries[index].generatedTaskID = nil
        }
        return true
    }

    func scheduleToday(_ task: TaskItem) {
        guard let current = tasks.first(where: { $0.id == task.id }) else { return }
        guard !current.planLocked else {
            actionMessage = "此事项已固定安排。请先在事项详情中关闭“固定安排”，再修改日期。"
            return
        }
        mutate(task) {
            $0.scheduledFor = .now
            if $0.isUnscheduled { $0.status = .pending }
            $0.statusChangedAt = .now
        }
    }

    func move(_ task: TaskItem, to quadrant: Quadrant) {
        var updated = task
        updated.quadrant = quadrant
        update(updated)
    }

    func assign(_ task: TaskItem, to blueprint: BlueprintItem?, showMessage: Bool = true) {
        if task.blueprintID != blueprint?.id,
           tasks.contains(where: { $0.effectiveDependencyIDs.contains(task.id) }) {
            actionMessage = "请先移除后续任务的前置连线，再更改蓝图。"
            return
        }
        mutate(task) { updated in
            if updated.blueprintID != blueprint?.id { updated.dependencyIDs = nil }
            updated.blueprintID = blueprint?.id
            updated.stageID = nil
            updated.milestoneID = nil
            if let blueprint, updated.projectName == "未归类项目" {
                updated.project = blueprint.name
            }
        }
        if let updated = tasks.first(where: { $0.id == task.id }) { removeCrossBlueprintDependents(of: updated) }
        if showMessage {
            actionMessage = blueprint.map { "已将“\(task.title)”归入“\($0.name)”。" } ?? "已解除“\(task.title)”的蓝图关联。"
        }
    }

    private func removeCrossBlueprintDependents(of task: TaskItem) {
        for index in tasks.indices where tasks[index].id != task.id && tasks[index].blueprintID != task.blueprintID {
            tasks[index].dependencyIDs?.removeAll { $0 == task.id }
            if tasks[index].dependencyIDs?.isEmpty == true { tasks[index].dependencyIDs = nil }
        }
    }

    func addBlueprint(_ blueprint: BlueprintItem) { blueprints.insert(blueprint, at: 0) }

    func updateBlueprint(_ blueprint: BlueprintItem) {
        guard let index = blueprints.firstIndex(where: { $0.id == blueprint.id }) else { return }
        blueprints[index] = blueprint
    }

    func addStage(_ stage: StageItem) { stages.append(stage) }
    func addMilestone(_ milestone: MilestoneItem) { milestones.append(milestone) }

    func unmetDependencies(for task: TaskItem) -> [TaskItem] {
        DependencyRule.unmetDependencies(for: task, tasks: tasks)
    }

    func executionBlockReason(for task: TaskItem) -> String? {
        let current = tasks.first { $0.id == task.id } ?? task
        return WorkflowGraph.blockingReason(for: current, tasks: tasks, blueprints: blueprints)
    }

    @discardableResult
    func setDependencies(for task: TaskItem, dependencyIDs: [UUID]) -> Bool {
        if let error = WorkflowGraph.validationError(task: task, dependencies: dependencyIDs, tasks: tasks) {
            actionMessage = error
            return false
        }
        mutate(task) { $0.dependencyIDs = dependencyIDs.isEmpty ? nil : dependencyIDs }
        return true
    }

    @discardableResult
    func connect(_ predecessor: TaskItem, to successor: TaskItem) -> Bool {
        let current = tasks.first { $0.id == successor.id } ?? successor
        let dependencies = current.effectiveDependencyIDs + [predecessor.id]
        return setDependencies(for: current, dependencyIDs: dependencies)
    }

    func disconnect(_ predecessorID: UUID, from successor: TaskItem) {
        let current = tasks.first { $0.id == successor.id } ?? successor
        _ = setDependencies(for: current, dependencyIDs: current.effectiveDependencyIDs.filter { $0 != predecessorID })
    }

    func setWorkflowPosition(for taskID: UUID, x: Double, y: Double) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var updated = tasks
        updated[index].workflowX = max(0, x)
        updated[index].workflowY = max(0, y)
        tasks = updated
    }

    func setWorkflowPositions(_ positions: [UUID: CGPoint]) {
        var updated = tasks
        for index in updated.indices {
            guard let point = positions[updated[index].id] else { continue }
            updated[index].workflowX = Double(max(0, point.x))
            updated[index].workflowY = Double(max(0, point.y))
        }
        tasks = updated
    }

    func setWorkflowImages(for taskID: UUID, images: [WorkflowImage]) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].workflowImages = images
    }

    func setWorkflowContent(for taskID: UUID, title: String, notes: String, stageID: UUID?) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let cleaned = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return }
        var updated = tasks
        updated[index].title = cleaned
        updated[index].notes = notes
        updated[index].stageID = stageID
        tasks = updated
    }

    func setBlueprintStatus(_ blueprint: BlueprintItem, status: BlueprintStatus) {
        guard let index = blueprints.firstIndex(where: { $0.id == blueprint.id }) else { return }
        blueprints[index].status = status
    }

    func moveStage(_ stage: StageItem, direction: Int) {
        var scoped = stages(for: stage.blueprintID)
        guard let current = scoped.firstIndex(where: { $0.id == stage.id }) else { return }
        let destination = current + direction
        guard scoped.indices.contains(destination) else { return }
        scoped.swapAt(current, destination)
        for (order, item) in scoped.enumerated() {
            if let index = stages.firstIndex(where: { $0.id == item.id }) { stages[index].order = order }
        }
    }

    func deleteBlueprint(_ blueprint: BlueprintItem) {
        let stageIDs = Set(stages.filter { $0.blueprintID == blueprint.id }.map(\.id))
        blueprints.removeAll { $0.id == blueprint.id }
        stages.removeAll { $0.blueprintID == blueprint.id }
        milestones.removeAll { $0.blueprintID == blueprint.id || stageIDs.contains($0.stageID) }
        for index in tasks.indices where tasks[index].blueprintID == blueprint.id {
            tasks[index].blueprintID = nil
            tasks[index].stageID = nil
            tasks[index].milestoneID = nil
        }
        for index in anniversaries.indices where anniversaries[index].blueprintID == blueprint.id {
            anniversaries[index].blueprintID = nil
        }
    }

    func archiveBlueprint(_ blueprint: BlueprintItem) {
        guard let index = blueprints.firstIndex(where: { $0.id == blueprint.id }) else { return }
        blueprints[index].archivedAt = blueprints[index].archivedAt == nil ? .now : nil
    }

    @discardableResult
    func duplicateBlueprint(_ blueprint: BlueprintItem) -> BlueprintItem {
        let newID = UUID()
        var copy = blueprint
        copy.id = newID
        copy.name += " 副本"
        copy.createdAt = .now
        copy.archivedAt = nil
        copy.status = .active
        copy.originalDueDate = nil
        blueprints.insert(copy, at: 0)
        var stageMap: [UUID: UUID] = [:]
        for stage in stages(for: blueprint.id) {
            let stageID = UUID()
            stageMap[stage.id] = stageID
            var cloned = stage
            cloned.id = stageID
            cloned.blueprintID = newID
            cloned.originalStartDate = nil
            cloned.originalDueDate = nil
            stages.append(cloned)
        }
        var milestoneMap: [UUID: UUID] = [:]
        for milestone in milestones.filter({ $0.blueprintID == blueprint.id }) {
            guard let stageID = stageMap[milestone.stageID] else { continue }
            let milestoneID = UUID()
            milestoneMap[milestone.id] = milestoneID
            var cloned = milestone
            cloned.id = milestoneID
            cloned.blueprintID = newID
            cloned.stageID = stageID
            cloned.isCompleted = false
            milestones.append(cloned)
        }
        let originals = tasks(for: blueprint.id)
        let taskMap = Dictionary(uniqueKeysWithValues: originals.map { ($0.id, UUID()) })
        for task in originals {
            var cloned = task
            cloned.id = taskMap[task.id] ?? UUID()
            cloned.blueprintID = newID
            cloned.stageID = task.stageID.flatMap { stageMap[$0] }
            cloned.milestoneID = task.milestoneID.flatMap { milestoneMap[$0] }
            cloned.parentTaskID = task.parentTaskID.flatMap { taskMap[$0] }
            let dependencies = task.effectiveDependencyIDs.compactMap { taskMap[$0] }
            cloned.dependencyIDs = dependencies.isEmpty ? nil : dependencies
            cloned.status = .pending
            cloned.isComplete = false
            cloned.completedAt = nil
            cloned.startedAt = nil
            cloned.blockReason = nil
            cloned.statusChangedAt = nil
            cloned.originalScheduledFor = nil
            cloned.originalDueDate = nil
            cloned.createdAt = .now
            tasks.append(cloned)
        }
        return copy
    }

    @discardableResult
    func createBlueprint(from template: BlueprintTemplate, startDate: Date = .now) -> BlueprintItem {
        let calendar = Calendar.current
        let dueDate = calendar.date(byAdding: .day, value: template.stageNames.count * 14, to: startDate) ?? startDate
        let blueprint = BlueprintItem(name: template.rawValue, goal: template.goal, startDate: startDate, dueDate: dueDate)
        addBlueprint(blueprint)
        for (index, name) in template.stageNames.enumerated() {
            let stageStart = calendar.date(byAdding: .day, value: index * 14, to: startDate) ?? startDate
            let stageDue = calendar.date(byAdding: .day, value: (index + 1) * 14, to: startDate) ?? dueDate
            let stage = StageItem(blueprintID: blueprint.id, name: name, order: index, startDate: stageStart, dueDate: stageDue)
            addStage(stage)
            addMilestone(MilestoneItem(blueprintID: blueprint.id, stageID: stage.id, name: "完成\(name)", dueDate: stageDue))
        }
        return blueprint
    }

    func exportPackage(for blueprint: BlueprintItem) throws -> Data {
        let package = BlueprintTransferPackage(
            blueprint: blueprint,
            stages: stages(for: blueprint.id),
            milestones: milestones.filter { $0.blueprintID == blueprint.id },
            tasks: tasks(for: blueprint.id)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(package)
    }

    @discardableResult
    func importBlueprint(from data: Data) throws -> BlueprintItem {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let package = try decoder.decode(BlueprintTransferPackage.self, from: data)
        guard package.formatVersion == 1 else {
            throw NSError(domain: "序蓝图", code: 1, userInfo: [NSLocalizedDescriptionKey: "不支持的蓝图文件版本。"])
        }
        let importedIDs = Set(package.tasks.map(\.id))
        guard importedIDs.count == package.tasks.count,
              package.tasks.allSatisfy({ $0.blueprintID == package.blueprint.id
                  && $0.effectiveDependencyIDs.allSatisfy(importedIDs.contains) }),
              TaskTreeProjection.validationError(in: package.tasks) == nil else {
            throw NSError(domain: "序蓝图", code: 3, userInfo: [NSLocalizedDescriptionKey: "导入文件的任务或前置连线无效，未写入任何数据。"])
        }
        for task in package.tasks {
            for dependencyID in task.effectiveDependencyIDs where DependencyRule.wouldCreateCycle(taskID: task.id, adding: dependencyID, tasks: package.tasks) {
                throw NSError(domain: "序蓝图", code: 2, userInfo: [NSLocalizedDescriptionKey: "导入文件包含循环任务依赖，未写入任何数据。"])
            }
        }
        let oldBlueprintID = package.blueprint.id
        var blueprint = package.blueprint
        blueprint.id = UUID(); blueprint.name += "（导入）"; blueprint.createdAt = .now; blueprint.archivedAt = nil
        var stageMap: [UUID: UUID] = [:]
        var milestoneMap: [UUID: UUID] = [:]
        var taskMap: [UUID: UUID] = [:]
        addBlueprint(blueprint)
        for old in package.stages where old.blueprintID == oldBlueprintID {
            var item = old; item.id = UUID(); item.blueprintID = blueprint.id
            stageMap[old.id] = item.id; stages.append(item)
        }
        for old in package.milestones where old.blueprintID == oldBlueprintID {
            guard let stageID = stageMap[old.stageID] else { continue }
            var item = old; item.id = UUID(); item.blueprintID = blueprint.id; item.stageID = stageID
            milestoneMap[old.id] = item.id; milestones.append(item)
        }
        for old in package.tasks { taskMap[old.id] = UUID() }
        for old in package.tasks {
            var item = old; item.id = taskMap[old.id] ?? UUID(); item.blueprintID = blueprint.id
            item.stageID = old.stageID.flatMap { stageMap[$0] }
            item.milestoneID = old.milestoneID.flatMap { milestoneMap[$0] }
            item.parentTaskID = old.parentTaskID.flatMap { taskMap[$0] }
            let dependencies = old.effectiveDependencyIDs.compactMap { taskMap[$0] }
            item.dependencyIDs = dependencies.isEmpty ? nil : dependencies
            tasks.append(item)
        }
        return blueprint
    }

    func reschedulePreview(blueprintID: UUID, days: Int) -> [TaskItem] {
        tasks(for: blueprintID).filter { $0.needsAction && !$0.planLocked && !$0.isUnscheduled }.map { task in
            var copy = task
            copy.originalScheduledFor = copy.originalScheduledFor ?? copy.scheduledFor
            copy.originalDueDate = copy.originalDueDate ?? copy.dueDate
            copy.scheduledFor = Calendar.current.date(byAdding: .day, value: days, to: copy.scheduledFor) ?? copy.scheduledFor
            if let due = copy.dueDate { copy.dueDate = Calendar.current.date(byAdding: .day, value: days, to: due) ?? due }
            return copy
        }
    }

    func applyReschedule(blueprintID: UUID, days: Int) {
        let updates = reschedulePreview(blueprintID: blueprintID, days: days)
        for update in updates { self.update(update) }
        let stageUpdates = stages(for: blueprintID).map { stage -> StageItem in
            var copy = stage
            copy.originalStartDate = copy.originalStartDate ?? copy.startDate
            copy.originalDueDate = copy.originalDueDate ?? copy.dueDate
            copy.startDate = Calendar.current.date(byAdding: .day, value: days, to: copy.startDate) ?? copy.startDate
            copy.dueDate = Calendar.current.date(byAdding: .day, value: days, to: copy.dueDate) ?? copy.dueDate
            return copy
        }
        for update in stageUpdates {
            if let index = stages.firstIndex(where: { $0.id == update.id }) { stages[index] = update }
        }
        if let index = blueprints.firstIndex(where: { $0.id == blueprintID }) {
            blueprints[index].originalDueDate = blueprints[index].originalDueDate ?? blueprints[index].dueDate
            blueprints[index].dueDate = Calendar.current.date(byAdding: .day, value: days, to: blueprints[index].dueDate) ?? blueprints[index].dueDate
        }
    }

    func delayedDays(for task: TaskItem) -> Int {
        guard let original = task.originalScheduledFor else { return 0 }
        return max(0, Calendar.current.dateComponents([.day], from: original, to: task.scheduledFor).day ?? 0)
    }

    func riskCount(for blueprintID: UUID) -> Int {
        tasks(for: blueprintID).filter { task in
            task.effectiveStatus == .blocked || (task.needsAction && (task.dueDate ?? .distantFuture) < .now)
        }.count
    }

    func addAnniversary(_ item: AnniversaryItem) {
        anniversaries.append(item)
        Task { await AnniversaryNotifications.configure(item) }
    }

    func updateAnniversary(_ item: AnniversaryItem) {
        guard let index = anniversaries.firstIndex(where: { $0.id == item.id }) else { return }
        anniversaries[index] = item
        Task { await AnniversaryNotifications.configure(item) }
    }

    func deleteAnniversary(_ item: AnniversaryItem) {
        anniversaries.removeAll { $0.id == item.id }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["anniversary.\(item.id.uuidString)"])
    }

    var upcomingAnniversaries: [AnniversaryItem] {
        anniversaries.compactMap { item -> (AnniversaryItem, Int)? in
            guard let days = item.daysRemaining() else { return nil }
            return (item, days)
        }.sorted { $0.1 < $1.1 }.map(\.0)
    }

    func createPreparationTask(for anniversary: AnniversaryItem) {
        guard anniversary.generatedTaskID == nil, let occurrence = anniversary.nextOccurrence() else { return }
        let taskDate = Calendar.current.date(byAdding: .day, value: -anniversary.preparationLeadDays, to: occurrence) ?? .now
        let title = anniversary.preparationTaskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let task = TaskItem(
            title: title.isEmpty ? "准备\(anniversary.name)" : title,
            project: anniversary.blueprintID.flatMap { id in blueprints.first { $0.id == id }?.name } ?? "纪念日准备",
            reportCategory: .projectProgress,
            quadrant: .schedule,
            scheduledFor: max(taskDate, .now),
            dueDate: occurrence,
            estimatedMinutes: 30,
            status: .pending,
            blueprintID: anniversary.blueprintID
        )
        add(task)
        if let index = anniversaries.firstIndex(where: { $0.id == anniversary.id }) {
            anniversaries[index].generatedTaskID = task.id
        }
    }

    func saveWeeklyReview(summary: String, nextWeekFocus: String, weekStart: Date) {
        weeklyReviews.insert(WeeklyReviewItem(weekStart: weekStart, summary: summary, nextWeekFocus: nextWeekFocus), at: 0)
    }

    func saveReview(period: ReviewPeriod, interval: DateInterval, summary: String, nextFocus: String) {
        weeklyReviews.insert(WeeklyReviewItem(weekStart: interval.start, summary: summary,
                                              nextWeekFocus: nextFocus, period: period), at: 0)
    }

    func toggleMilestone(_ milestone: MilestoneItem) {
        guard let index = milestones.firstIndex(where: { $0.id == milestone.id }) else { return }
        milestones[index].isCompleted.toggle()
    }

    func stages(for blueprintID: UUID) -> [StageItem] {
        stages.filter { $0.blueprintID == blueprintID }.sorted { $0.order < $1.order }
    }

    func milestones(for stageID: UUID) -> [MilestoneItem] {
        milestones.filter { $0.stageID == stageID }.sorted { $0.dueDate < $1.dueDate }
    }

    func tasks(for blueprintID: UUID) -> [TaskItem] {
        tasks.filter { $0.blueprintID == blueprintID }
    }

    func blueprintProgress(_ blueprintID: UUID) -> Double {
        let scoped = tasks(for: blueprintID).filter { !$0.isCancelled }
        guard !scoped.isEmpty else { return 0 }
        return Double(scoped.filter(\.isCompleted).count) / Double(scoped.count)
    }

    func blueprintPlannedProgress(_ blueprintID: UUID, at date: Date = .now) -> Double {
        guard let blueprint = blueprints.first(where: { $0.id == blueprintID }) else { return 0 }
        let total = blueprint.dueDate.timeIntervalSince(blueprint.startDate)
        guard total > 0 else { return date >= blueprint.dueDate ? 1 : 0 }
        return min(1, max(0, date.timeIntervalSince(blueprint.startDate) / total))
    }

    @discardableResult
    func saveReport(content: String, supplement: String, minimumLength: Int, maximumLength: Int,
                    updating reportID: UUID? = nil) -> UUID {
        if let reportID, let index = reports.firstIndex(where: { $0.id == reportID }) {
            reports[index].content = content
            reports[index].supplement = supplement
            reports[index].minimumLength = minimumLength
            reports[index].maximumLength = maximumLength
            return reportID
        }
        let item = DailyReportItem(minimumLength: minimumLength, maximumLength: maximumLength,
                                   supplement: supplement, content: content)
        reports.insert(item, at: 0)
        return item.id
    }

    func parseTask(
        sentence: String,
        endpoint: String,
        model: String,
        defaultQuadrant: Quadrant,
        defaultDuration: Int,
        imageData: Data? = nil,
        visionModel: String? = nil
    ) async -> ParsedTask? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            aiTaskError = "请先在设置中填写 DeepSeek API Key。"
            return nil
        }
        isAIParsing = true
        aiTaskError = nil
        defer { isAIParsing = false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let prompt = """
        你是任务解析器。当前时间为 \(formatter.string(from: .now))，时区为 \(TimeZone.current.identifier)。
        \(imageData == nil ? "将用户的描述解析为任务。" : "根据用户提供的图片识别真实内容，整理成一个主任务和若干不同的、具体可执行的子任务。只依据图片及补充说明，不猜测看不清的文字、日期或项目；忽略与任务无关的内容。若图片没有明确行动项，可合理拆分可见目标。")
        只返回 JSON，不要 Markdown。缺失信息使用 null，不要编造项目。
        JSON 字段：title(String), project(String|null), quadrant(String|null，限 doNow/schedule/delegate/eliminate), reportCategory(String|null，限 projectProgress/collaboration), scheduledFor(String|null，ISO8601), dueDate(String|null，ISO8601), estimatedMinutes(Int|null), notes(String|null), subtasks([String]|null，最多8项；图片输入至少1项，子任务不得重复主任务或彼此重复)。
        用户补充说明：\(sentence.isEmpty ? "无" : sentence)
        """
        do {
            let content: String
            if let imageData {
                content = try await DeepSeekService.generateWithImage(
                    apiKey: apiKey, endpoint: endpoint, model: visionModel ?? "deepseek-flash",
                    prompt: prompt, jpegData: imageData
                )
            } else {
                content = try await DeepSeekService.generateReport(apiKey: apiKey, endpoint: endpoint, model: model, prompt: prompt)
            }
            let payload = try AITaskPayload.decode(from: content)
            let task = payload.makeTask(defaultQuadrant: defaultQuadrant, defaultDuration: defaultDuration)
            guard !task.title.isEmpty else {
                throw NSError(domain: "AI task", code: 3, userInfo: [NSLocalizedDescriptionKey: "图片中未识别出可用的主任务，请补充说明后重试。"])
            }
            let children = Array((payload.subtasks ?? [])
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty && $0.localizedCaseInsensitiveCompare(task.title) != .orderedSame }
                .uniquedTaskTitles()
                .prefix(8))
            guard imageData == nil || !children.isEmpty else {
                throw NSError(domain: "AI task", code: 4, userInfo: [NSLocalizedDescriptionKey: "图片中未识别出可用的子任务，请补充说明后重试。"])
            }
            return ParsedTask(
                task: task,
                subtasks: children
            )
        } catch {
            aiTaskError = "AI 解析失败：\(error.localizedDescription)"
            return nil
        }
    }

    func generateReport(endpoint: String, model: String, supplement: String, minimumLength: Int, maximumLength: Int) async -> String? {
        let source = ReportSourceBuilder.candidates(today: todayTasks, completed: completedToday, processed: processedToday)
        return await generateReport(
            endpoint: endpoint, model: model,
            request: ReportRequest(tasks: source, template: .classic, supplement: supplement,
                                   minimumLength: minimumLength, maximumLength: maximumLength,
                                   sendNotes: true, sendProject: true)
        )
    }

    func generateReport(endpoint: String, model: String, request: ReportRequest) async -> String? {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            reportError = "请先在设置中填写 DeepSeek API Key。"
            return nil
        }
        isReportLoading = true
        reportError = nil
        reportLengthWarning = nil
        defer { isReportLoading = false }

        let reportTasks = ReportSourceBuilder.preparedTasks(for: request, blueprints: blueprints)
        let completed = reportTasks.filter(\.isCompleted)
        let prompt = DailyReportPrompt.make(tasks: reportTasks, completed: completed,
                                            supplement: request.supplement,
                                            minimumLength: request.minimumLength,
                                            maximumLength: request.maximumLength,
                                            template: request.template)
        do {
            var result = try await DeepSeekService.generateReport(apiKey: apiKey, endpoint: endpoint, model: model, prompt: prompt)
            if result.count < request.minimumLength || result.count > request.maximumLength {
                let direction = result.count < request.minimumLength ? "补充" : "压缩"
                let revisionPrompt = """
                请将下面日报\(direction)到 \(request.minimumLength)～\(request.maximumLength) 字，保留“\(request.template.rawValue)”模板的章节和分组，不得编造事实。只返回修改后的日报。\n\n\(result)
                """
                result = try await DeepSeekService.generateReport(apiKey: apiKey, endpoint: endpoint, model: model, prompt: revisionPrompt)
            }
            let finalResult = DailyReportPrompt.enforceMinimumLength(
                result,
                fallback: DailyReportPrompt.fallback(tasks: reportTasks, completed: completed,
                                                     supplement: request.supplement, template: request.template),
                minimumLength: request.minimumLength
            )
            if finalResult.count > request.maximumLength {
                reportLengthWarning = "生成内容为 \(finalResult.count) 字，超过设定上限 \(request.maximumLength) 字，请编辑或重新生成。"
            }
            return finalResult
        } catch {
            reportError = error.localizedDescription
            return nil
        }
    }

}

enum ReportTemplatePreset: String, CaseIterable, Identifiable {
    case classic = "工作进展"
    case byCategory = "按分类汇总"
    case personal = "个人回顾"

    var id: String { rawValue }
    var groupingTitle: String { self == .byCategory ? "分类" : "项目" }
}

struct ReportRequest {
    let tasks: [TaskItem]
    let template: ReportTemplatePreset
    let supplement: String
    let minimumLength: Int
    let maximumLength: Int
    let sendNotes: Bool
    let sendProject: Bool
}

enum ReportSourceBuilder {
    static func candidates(today: [TaskItem], completed: [TaskItem], processed: [TaskItem]) -> [TaskItem] {
        var seen = Set<UUID>()
        return (today + completed + processed).filter { seen.insert($0.id).inserted }
    }

    static func preparedTasks(for request: ReportRequest, blueprints: [BlueprintItem]) -> [TaskItem] {
        let named = request.sendProject
            ? ReportTaskGrouping.usingBlueprintNames(request.tasks, blueprints: blueprints)
            : request.tasks
        return named.map { task in
            var copy = task
            if !request.sendNotes { copy.notes = ""; copy.blockReason = nil }
            if !request.sendProject { copy.project = nil }
            return copy
        }
    }
}

enum DailyReportPrompt {
    static func make(tasks: [TaskItem], completed: [TaskItem], supplement: String, minimumLength: Int, maximumLength: Int,
                     template: ReportTemplatePreset = .classic) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        let projectProgress = groupedItems(tasks.filter { $0.effectiveReportCategory == .projectProgress }, template: template)
        let collaboration = groupedItems(tasks.filter { $0.effectiveReportCategory == .collaboration }, template: template)
        let tomorrowFocus = groupedItems(tasks.filter { $0.needsAction }, template: template)
        let supplementText = supplement.trimmingCharacters(in: .whitespacesAndNewlines)
        if template != .classic {
            let all = groupedItems(tasks, template: template)
            let section = template == .byCategory ? "今日分类进展" : "今日行动与感受"
            return """
            根据以下真实事项和补充信息，使用“\(template.rawValue)”模板生成 \(minimumLength)～\(maximumLength) 字的中文 Markdown 日报。不得编造完成、安排或结论。
            只使用三个一级标题：1. \(section)；2. 需要关注；3. 后续重点。\(template == .byCategory ? "第一部分按分类汇总，未分类单列。" : "第一部分以个人回顾口吻描述实际行动。")第三部分的未完成事项只是建议，不得写成已安排到明天。
            日期：\(formatter.string(from: .now))
            今日事项：\(all.isEmpty ? "无" : all)
            未完成事项：\(tomorrowFocus.isEmpty ? "无" : tomorrowFocus)
            补充：\(supplementText.isEmpty ? "无" : supplementText)
            """
        }
        return """
        请基于以下任务数据，用务实、清晰的中文生成一份 Markdown 日报。不要编造不存在的事实。

        输出规则必须严格遵守：
        1. 全文控制在 \(minimumLength)～\(maximumLength) 个中文字符。
        2. 只能使用以下三个一级编号，按顺序输出：
           1. 项目/测试/开发进度
           2. 会议/方案/讨论
           3. 明日重点事项规划
        3. 每个一级编号下使用 "- 【项目名称】" 作为项目标题，并用缩进项目符号列出事项、完成状态、进度或结论。
        4. 同一项目的全部事项必须放在同一个 "【项目名称】" 标题下。例如所有“渠道适配”事项必须统一归入 "【渠道适配】"。
        5. 第 3 部分按重要性列出未完成事项，说明建议推进方向；如没有未完成事项，给出基于已完成工作的下一步计划。
        6. 将“日报补充”自然融入对应章节。禁止添加其他一级标题、寒暄或总结段。

        日期：\(formatter.string(from: .now))

        1. 项目/测试/开发进度的原始任务数据：
        \(projectProgress.isEmpty ? "无" : projectProgress)

        2. 会议/方案/讨论的原始任务数据：
        \(collaboration.isEmpty ? "无" : collaboration)

        3. 明日重点事项规划的待办数据：
        \(tomorrowFocus.isEmpty ? "无" : tomorrowFocus)

        日报补充：
        \(supplementText.isEmpty ? "无" : supplementText)
        """
    }

    static func fallback(tasks: [TaskItem], completed: [TaskItem], supplement: String,
                         template: ReportTemplatePreset = .classic) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年MM月dd日"
        let progress = groupedItems(tasks.filter { $0.effectiveReportCategory == .projectProgress }, template: template)
        let collaboration = groupedItems(tasks.filter { $0.effectiveReportCategory == .collaboration }, template: template)
        let focus = groupedItems(tasks.filter { $0.needsAction }, template: template)
        let context = supplement.trimmingCharacters(in: .whitespacesAndNewlines)
        if template != .classic {
            let section = template == .byCategory ? "今日分类进展" : "今日行动与感受"
            return """
            \(formatter.string(from: .now)) 日报
            1. \(section)
            \(groupedItems(tasks, template: template).isEmpty ? "- 今日暂无事项记录。" : groupedItems(tasks, template: template))
            2. 需要关注
            - \(context.isEmpty ? "根据实际工作补充风险和结论。" : context)
            3. 后续重点
            \(focus.isEmpty ? "- 下一步待确认。" : focus)
            """
        }
        return """
        \(formatter.string(from: .now)) 日报

        1. 项目/测试/开发进度
        \(progress.isEmpty ? "- 【未归类项目】\n  - 今日暂无项目、测试或开发事项记录，后续应补充实际推进内容与完成状态。" : progress)

        2. 会议/方案/讨论
        \(collaboration.isEmpty ? "- 【未归类项目】\n  - 今日暂无会议、方案或讨论事项记录；如有关键结论，可通过日报补充完善。" : collaboration)

        3. 明日重点事项规划
        \(focus.isEmpty ? "- 【重点规划】\n  - 基于今日已完成事项，明日应优先复核关键成果、补齐遗留信息，并安排下一阶段的核心任务。" : focus)

        \(context.isEmpty ? "- 【补充说明】\n  - 以上内容依据当天已记录的事项与完成状态整理，后续可根据实际推进情况持续补充和修订。" : "- 【补充说明】\n  - \(context)")
        """
    }

    static func enforceMinimumLength(_ report: String, fallback: String, minimumLength: Int) -> String {
        let trimmed = report.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.count >= minimumLength ? trimmed : fallback
        guard base.count < minimumLength else { return base }
        let neutralDetail = "\n- 【记录说明】\n  - 日报内容依据已登记事项、项目分类和补充信息整理而成；请在下一次复盘时更新实际进度、会议结论和下一步安排，以确保计划持续可执行。"
        var output = base
        while output.count < minimumLength { output += neutralDetail }
        return output
    }

    private static func groupedItems(_ tasks: [TaskItem], template: ReportTemplatePreset) -> String {
        let key: (TaskItem) -> String = template == .byCategory ? { $0.categoryName } : { $0.projectName }
        let groups = Dictionary(grouping: tasks, by: key)
        return groups
            .keys.sorted()
            .map { project in
                let entries = groups[project] ?? []
                let lines = entries.map { task in
                    let status = task.effectiveStatus.title
                    let note = task.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    let blocker = task.blockReason?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let detail = [note, blocker.isEmpty ? "" : "阻塞原因：\(blocker)"].filter { !$0.isEmpty }.joined(separator: "；")
                    return "  - \(status)：\(task.title)（\(task.quadrant.title)，预计\(task.estimatedMinutes)分钟）\(detail.isEmpty ? "" : "；\(detail)")"
                }.joined(separator: "\n")
                return "- 【\(project)】\n\(lines)"
            }
            .joined(separator: "\n")
    }
}

enum DeepSeekService {
    private struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        struct Message: Encodable { let role: String; let content: String }
    }
    private struct ResponseBody: Decodable {
        let choices: [Choice]
        struct Choice: Decodable { let message: Message }
        struct Message: Decodable { let content: String }
    }

    private struct ImageRequestBody: Encodable {
        let model: String
        let messages: [ImageMessage]
        struct ImageMessage: Encodable {
            let role: String
            let content: [ContentPart]
        }
        struct ContentPart: Encodable {
            let type: String
            let text: String?
            let image_url: ImageURL?
        }
        struct ImageURL: Encodable { let url: String }
    }

    static func generateReport(apiKey: String, endpoint: String, model: String, prompt: String) async throws -> String {
        guard let url = URL(string: endpoint), let scheme = url.scheme, ["https", "http"].contains(scheme) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(RequestBody(model: model, messages: [.init(role: "user", content: prompt)]))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "DeepSeek", code: 1, userInfo: [NSLocalizedDescriptionKey: "日报生成失败，请检查 API Key 和网络连接。"])
        }
        guard let content = try JSONDecoder().decode(ResponseBody.self, from: data).choices.first?.message.content else {
            throw NSError(domain: "DeepSeek", code: 2, userInfo: [NSLocalizedDescriptionKey: "DeepSeek 未返回日报内容。"])
        }
        return content
    }

    static func generateWithImage(apiKey: String, endpoint: String, model: String, prompt: String, jpegData: Data) async throws -> String {
        guard let url = URL(string: endpoint), url.scheme == "https" else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try imageRequestBody(model: model, prompt: prompt, jpegData: jpegData)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw NSError(domain: "DeepSeek", code: 3, userInfo: [NSLocalizedDescriptionKey: "图片识别请求失败，请检查图片模型、API Key 和网络连接。"])
        }
        guard let content = try JSONDecoder().decode(ResponseBody.self, from: data).choices.first?.message.content else {
            throw NSError(domain: "DeepSeek", code: 4, userInfo: [NSLocalizedDescriptionKey: "图片模型未返回任务内容。"])
        }
        return content
    }

    static func imageRequestBody(model: String, prompt: String, jpegData: Data) throws -> Data {
        let imageURL = "data:image/jpeg;base64,\(jpegData.base64EncodedString())"
        let body = ImageRequestBody(model: model, messages: [
            .init(role: "user", content: [
                .init(type: "text", text: prompt, image_url: nil),
                .init(type: "image_url", text: nil, image_url: .init(url: imageURL))
            ])
        ])
        return try JSONEncoder().encode(body)
    }
}

private extension Array where Element == String {
    func uniquedTaskTitles() -> [String] {
        var seen = Set<String>()
        return filter { seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted }
    }
}

private struct AITaskPayload: Decodable {
    let title: String
    let project: String?
    let quadrant: String?
    let reportCategory: String?
    let scheduledFor: String?
    let dueDate: String?
    let estimatedMinutes: Int?
    let notes: String?
    let subtasks: [String]?

    static func decode(from content: String) throws -> Self {
        guard let start = content.firstIndex(of: "{"), let end = content.lastIndex(of: "}") else {
            throw NSError(domain: "AI task", code: 1, userInfo: [NSLocalizedDescriptionKey: "未返回有效的任务 JSON。"])
        }
        let json = String(content[start...end])
        return try JSONDecoder().decode(Self.self, from: Data(json.utf8))
    }

    func makeTask(defaultQuadrant: Quadrant, defaultDuration: Int) -> TaskItem {
        TaskItem(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes ?? "",
            project: project,
            reportCategory: reportCategory.flatMap(ReportCategory.init(rawValue:)) ?? .projectProgress,
            quadrant: quadrant.flatMap(Quadrant.init(rawValue:)) ?? defaultQuadrant,
            scheduledFor: Self.parseDate(scheduledFor) ?? .now,
            dueDate: Self.parseDate(dueDate),
            estimatedMinutes: min(max(estimatedMinutes ?? defaultDuration, 5), 480),
            status: .pending
        )
    }

    private static func parseDate(_ text: String?) -> Date? {
        guard let text else { return nil }
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: text) { return date }
        let simple = DateFormatter()
        simple.locale = Locale(identifier: "zh_CN")
        simple.dateFormat = "yyyy-MM-dd HH:mm"
        return simple.date(from: text)
    }
}

enum KeychainStore {
    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: account]
        SecItemDelete(query as CFDictionary)
        let item: [String: Any] = query.merging([kSecValueData as String: data]) { $1 }
        SecItemAdd(item as CFDictionary, nil)
    }

    static func load(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
