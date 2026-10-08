import Foundation
import SwiftUI
import UserNotifications

enum PlanViewMode: String, CaseIterable, Identifiable {
    case workflow = "工作流"
    case overview = "概览"
    case timeline = "时间轴"
    case week = "周计划"
    case month = "月计划"

    var id: String { rawValue }
}

enum AnniversaryCalendar: String, CaseIterable, Codable, Identifiable {
    case solar = "公历"
    case lunar = "农历"

    var id: String { rawValue }
}

enum AnniversaryRepeat: String, CaseIterable, Codable, Identifiable {
    case once = "仅一次"
    case yearly = "每年重复"

    var id: String { rawValue }
}

enum AnniversaryType: String, CaseIterable, Codable, Identifiable {
    case birthday = "生日"
    case relationship = "纪念日"
    case festival = "节日"
    case project = "项目节点"
    case custom = "其他"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .birthday: "birthday.cake"
        case .relationship: "heart"
        case .festival: "sparkles"
        case .project: "flag"
        case .custom: "calendar.badge.exclamationmark"
        }
    }
}

struct AnniversaryItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var date: Date
    var type: AnniversaryType = .custom
    var notes: String = ""
    var contact: String = ""
    var coverPath: String? = nil
    var calendar: AnniversaryCalendar = .solar
    var repeatRule: AnniversaryRepeat = .yearly
    var reminderDays: Int = 7
    var showOnHome = true
    var showInMenuBar = true
    var showNotification = true
    var privacyMode = false
    var blueprintID: UUID? = nil
    var preparationEnabled = false
    var preparationLeadDays = 7
    var preparationTaskTitle: String = ""
    var generatedTaskID: UUID? = nil
    var createdAt: Date = .now

    var displayName: String { privacyMode ? "重要日子" : name }

    func nextOccurrence(from reference: Date = .now, calendar systemCalendar: Calendar = .current) -> Date? {
        if repeatRule == .once { return date >= systemCalendar.startOfDay(for: reference) ? date : nil }
        if calendar == .solar {
            let source = systemCalendar.dateComponents([.month, .day], from: date)
            let currentYear = systemCalendar.component(.year, from: reference)
            for year in currentYear...(currentYear + 4) {
                let target = DateComponents(year: year, month: source.month, day: source.day)
                if let candidate = systemCalendar.date(from: target), candidate >= systemCalendar.startOfDay(for: reference) {
                    return candidate
                }
            }
            return nil
        }

        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = systemCalendar.timeZone
        let lunar = chinese.dateComponents([.month, .day, .isLeapMonth], from: date)
        let horizon = systemCalendar.date(byAdding: .year, value: 2, to: reference) ?? reference
        var cursor = systemCalendar.startOfDay(for: reference)
        while cursor <= horizon {
            let candidate = chinese.dateComponents([.month, .day, .isLeapMonth], from: cursor)
            if candidate.month == lunar.month,
               candidate.day == lunar.day,
               (candidate.isLeapMonth ?? false) == (lunar.isLeapMonth ?? false) {
                return cursor
            }
            cursor = systemCalendar.date(byAdding: .day, value: 1, to: cursor) ?? horizon.addingTimeInterval(1)
        }
        return nil
    }

    func daysRemaining(from reference: Date = .now, calendar: Calendar = .current) -> Int? {
        guard let next = nextOccurrence(from: reference, calendar: calendar) else { return nil }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: reference), to: calendar.startOfDay(for: next)).day
    }

    func shouldOfferPreparation(from reference: Date = .now) -> Bool {
        guard preparationEnabled, generatedTaskID == nil, let days = daysRemaining(from: reference) else { return false }
        return days >= 0 && days <= preparationLeadDays
    }
}

struct WeeklyReviewItem: Identifiable, Codable, Equatable {
    var id = UUID()
    var weekStart: Date
    var summary: String
    var nextWeekFocus: String
    var createdAt: Date = .now
}

enum ThemePreset: String, CaseIterable, Codable, Identifiable {
    case system = "跟随系统"
    case stone = "石墨"
    case paper = "纸张"
    case ocean = "深海"
    case forest = "森林"
    case ink = "墨色"

    var id: String { rawValue }
    var backgroundHex: String {
        switch self {
        case .system: "F4F4F6"
        case .stone: "F5F6F3"
        case .paper: "F4ECDD"
        case .ocean: "0E2638"
        case .forest: "172B24"
        case .ink: "1D1D20"
        }
    }
    var cardHex: String {
        switch self {
        case .system: "FFFFFF"
        case .stone: "FFFFFF"
        case .paper: "FFF9ED"
        case .ocean: "17384E"
        case .forest: "234136"
        case .ink: "2A2A2E"
        }
    }
    var accentHex: String {
        switch self {
        case .system: "4F65D9"
        case .stone: "2A625D"
        case .paper: "9B6238"
        case .ocean: "4EB5D8"
        case .forest: "62B58B"
        case .ink: "B5A5E8"
        }
    }
    var preferredScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .stone, .paper: .light
        case .ocean, .forest, .ink: .dark
        }
    }
}

enum LayoutDensity: String, CaseIterable, Identifiable {
    case compact = "紧凑"
    case standard = "标准"
    case spacious = "宽松"

    var id: String { rawValue }
    var spacing: CGFloat {
        switch self { case .compact: 8; case .standard: 12; case .spacious: 18 }
    }
}

enum BlueprintTemplate: String, CaseIterable, Identifiable {
    case software = "软件开发"
    case study = "学习计划"
    case fitness = "健身计划"
    case travel = "旅行计划"

    var id: String { rawValue }
    var icon: String {
        switch self { case .software: "hammer"; case .study: "book"; case .fitness: "figure.run"; case .travel: "airplane" }
    }
    var goal: String {
        switch self {
        case .software: "从需求定义、开发验证到发布复盘，完成一个可交付的软件版本。"
        case .study: "建立目标明确、可检查成果的学习闭环。"
        case .fitness: "通过循序渐进的训练与复盘达成健康目标。"
        case .travel: "完成行程决策、预订准备和出行检查。"
        }
    }
    var stageNames: [String] {
        switch self {
        case .software: ["需求与设计", "开发与测试", "发布与复盘"]
        case .study: ["制定计划", "系统学习", "练习与验收"]
        case .fitness: ["体能评估", "基础训练", "强化与复测"]
        case .travel: ["目的地与预算", "预订与准备", "出行与回顾"]
        }
    }
}

struct BlueprintTransferPackage: Codable {
    var formatVersion = 1
    var blueprint: BlueprintItem
    var stages: [StageItem]
    var milestones: [MilestoneItem]
    var tasks: [TaskItem]
}

enum DependencyRule {
    static func wouldCreateCycle(taskID: UUID, adding dependencyID: UUID, tasks: [TaskItem]) -> Bool {
        guard taskID != dependencyID else { return true }
        let map = Dictionary(tasks.map { ($0.id, $0.effectiveDependencyIDs) }, uniquingKeysWith: { first, _ in first })
        var stack = [dependencyID]
        var visited = Set<UUID>()
        while let current = stack.popLast() {
            if current == taskID { return true }
            guard visited.insert(current).inserted else { continue }
            stack.append(contentsOf: map[current] ?? [])
        }
        return false
    }

    static func unmetDependencies(for task: TaskItem, tasks: [TaskItem]) -> [TaskItem] {
        task.effectiveDependencyIDs.compactMap { dependencyID in
            tasks.first { $0.id == dependencyID && !$0.isCompleted }
        }
    }
}

enum AnniversaryNotifications {
    static func configure(_ item: AnniversaryItem) async {
        let center = UNUserNotificationCenter.current()
        let identifier = "anniversary.\(item.id.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard item.showNotification,
              let occurrence = item.nextOccurrence(),
              let reminderDay = Calendar.current.date(byAdding: .day, value: -item.reminderDays, to: occurrence),
              let fireDate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: reminderDay),
              fireDate > .now,
              (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }

        let content = UNMutableNotificationContent()
        content.title = item.privacyMode ? "重要日子即将到来" : "\(item.name)即将到来"
        content.body = item.privacyMode ? "打开“序”查看倒计时和准备事项。" : "还有 \(item.reminderDays) 天，记得提前准备。"
        content.sound = .default
        let repeats = item.repeatRule == .yearly && item.calendar == .solar
        let units: Set<Calendar.Component> = repeats ? [.month, .day, .hour, .minute] : [.year, .month, .day, .hour, .minute]
        let components = Calendar.current.dateComponents(units, from: fireDate)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats))
        try? await center.add(request)
    }
}

extension Color {
    init(appHex: String) {
        let normalized = appHex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: normalized).scanHexInt64(&value)
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
