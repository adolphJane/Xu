import AppKit
import Foundation

/// A curated, searchable set supported by the desktop category picker.
struct CategorySymbol: Identifiable, Sendable {
    let id: String
    let title: String
    let group: String
    let keywords: String

    static let groups = ["推荐", "全部", "工作", "生活", "学习", "健康", "兴趣", "出行", "财务"]
    static let all: [CategorySymbol] = [
        .init(id: "tag", title: "标签", group: "常用", keywords: "分类 标记 默认"),
        .init(id: "briefcase", title: "公文包", group: "工作", keywords: "工作 办公 work job"),
        .init(id: "house", title: "房屋", group: "生活", keywords: "生活 家庭 home"),
        .init(id: "book", title: "书本", group: "学习", keywords: "学习 阅读 书 read study"),
        .init(id: "heart", title: "爱心", group: "生活", keywords: "关爱 家庭 关系"),
        .init(id: "star", title: "星标", group: "常用", keywords: "收藏 重点 star"),
        .init(id: "folder", title: "文件夹", group: "常用", keywords: "文件 资料 归档"),
        .init(id: "leaf", title: "叶子", group: "生活", keywords: "健康 自然 环保"),
        .init(id: "airplane", title: "飞机", group: "出行", keywords: "旅行 出差 旅游 travel"),
        .init(id: "laptopcomputer", title: "电脑", group: "工作", keywords: "工作 编程 数码"),
        .init(id: "building.2", title: "办公楼", group: "工作", keywords: "公司 城市 办公"),
        .init(id: "chart.bar", title: "柱状图", group: "工作", keywords: "分析 数据 报告"),
        .init(id: "person.2", title: "协作", group: "工作", keywords: "团队 会议 人 合作"),
        .init(id: "lightbulb", title: "灯泡", group: "工作", keywords: "创意 灵感 idea"),
        .init(id: "hammer", title: "工具", group: "工作", keywords: "维修 构建 工具"),
        .init(id: "terminal", title: "终端", group: "工作", keywords: "代码 开发 编程 code"),
        .init(id: "graduationcap", title: "学士帽", group: "学习", keywords: "教育 课程 毕业"),
        .init(id: "pencil.and.ruler", title: "文具", group: "学习", keywords: "设计 绘画 文具"),
        .init(id: "books.vertical", title: "书架", group: "学习", keywords: "阅读 书 资料"),
        .init(id: "brain.head.profile", title: "思考", group: "学习", keywords: "大脑 知识 记忆"),
        .init(id: "globe", title: "地球", group: "学习", keywords: "语言 外语 世界"),
        .init(id: "pencil", title: "铅笔", group: "学习", keywords: "笔记 书写"),
        .init(id: "cup.and.saucer", title: "咖啡", group: "生活", keywords: "休闲 咖啡 休息"),
        .init(id: "cart", title: "购物车", group: "生活", keywords: "购物 采购 超市"),
        .init(id: "gift", title: "礼物", group: "生活", keywords: "礼物 生日 节日"),
        .init(id: "fork.knife", title: "餐具", group: "生活", keywords: "吃饭 美食 烹饪"),
        .init(id: "bed.double", title: "床", group: "生活", keywords: "睡眠 休息"),
        .init(id: "figure.walk", title: "步行", group: "健康", keywords: "运动 散步 健康"),
        .init(id: "bicycle", title: "自行车", group: "健康", keywords: "运动 骑行 自行车"),
        .init(id: "dumbbell", title: "哑铃", group: "健康", keywords: "健身 力量 运动"),
        .init(id: "cross.case", title: "医疗箱", group: "健康", keywords: "就医 体检 医疗"),
        .init(id: "pills", title: "药物", group: "健康", keywords: "药物 治疗 健康"),
        .init(id: "mountain.2", title: "山峰", group: "出行", keywords: "登山 户外 徒步"),
        .init(id: "camera", title: "相机", group: "兴趣", keywords: "摄影 拍照 记录"),
        .init(id: "music.note", title: "音符", group: "兴趣", keywords: "音乐 乐器"),
        .init(id: "film", title: "胶片", group: "兴趣", keywords: "电影 视频"),
        .init(id: "gamecontroller", title: "手柄", group: "兴趣", keywords: "游戏 娱乐"),
        .init(id: "paintbrush", title: "画笔", group: "兴趣", keywords: "绘画 艺术"),
        .init(id: "map", title: "地图", group: "出行", keywords: "路线 导航 旅行"),
        .init(id: "car", title: "汽车", group: "出行", keywords: "汽车 自驾"),
        .init(id: "tram", title: "电车", group: "出行", keywords: "通勤 地铁 交通"),
        .init(id: "ferry", title: "渡轮", group: "出行", keywords: "旅行 船 海"),
        .init(id: "suitcase", title: "行李箱", group: "出行", keywords: "旅行 行李"),
        .init(id: "wallet.pass", title: "钱包", group: "财务", keywords: "钱包 理财 预算"),
        .init(id: "creditcard", title: "银行卡", group: "财务", keywords: "支付 消费 银行"),
        .init(id: "banknote", title: "钞票", group: "财务", keywords: "现金 收入 财务"),
        .init(id: "chart.pie", title: "饼图", group: "财务", keywords: "财务 理财 预算"),
        .init(id: "target", title: "靶心", group: "常用", keywords: "目标 计划"),
        .init(id: "flag", title: "旗帜", group: "常用", keywords: "里程碑 目标"),
        .init(id: "bolt", title: "闪电", group: "常用", keywords: "效率 快速"),
        .init(id: "bell", title: "铃铛", group: "常用", keywords: "提醒 通知"),
        .init(id: "bookmark", title: "书签", group: "常用", keywords: "收藏 阅读"),
        .init(id: "link", title: "链接", group: "常用", keywords: "关联 链接"),
        .init(id: "calendar", title: "日历", group: "常用", keywords: "日期 日程"),
        .init(id: "sparkles", title: "星光", group: "兴趣", keywords: "灵感 创意"),
    ]

    static func matching(_ query: String, group: String) -> [CategorySymbol] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            return all.filter { "\($0.title) \($0.id) \($0.keywords)".localizedCaseInsensitiveContains(query) }
        }
        if group == "推荐" {
            let names = ["tag", "briefcase", "house", "book", "heart", "leaf", "airplane", "star", "folder",
                         "target", "calendar", "lightbulb", "cup.and.saucer", "dumbbell", "camera",
                         "wallet.pass", "music.note", "gift"]
            return names.compactMap { name in all.first { $0.id == name } }
        }
        return all.filter { group == "全部" || $0.group == group }
    }

    static func validated(_ name: String) -> String {
        guard all.contains(where: { $0.id == name }),
              NSImage(systemSymbolName: name, accessibilityDescription: nil) != nil else { return "tag" }
        return name
    }
}

/// Local presentation preferences. Task, backup and folder-sync schemas stay unchanged.
struct CategoryAppearance: Codable, Equatable {
    var symbols: [String: String] = [:]
    var recent: [String] = []
    static let defaultsKey = "quadrant.categoryAppearance.v1"

    static func key(_ category: String) -> String {
        category.trimmingCharacters(in: .whitespacesAndNewlines).localizedLowercase
    }

    func symbol(for category: String?) -> String {
        guard let category, !Self.key(category).isEmpty else { return "tray" }
        return CategorySymbol.validated(symbols[Self.key(category)] ?? "tag")
    }

    mutating func setSymbol(_ symbol: String, for category: String) {
        guard !Self.key(category).isEmpty else { return }
        let symbol = CategorySymbol.validated(symbol)
        symbols[Self.key(category)] = symbol
    }

    mutating func recordRecent(_ symbol: String) {
        let symbol = CategorySymbol.validated(symbol)
        recent = [symbol] + recent.filter { $0 != symbol }.prefix(8)
    }

    mutating func rename(_ oldName: String, to newName: String) {
        let value = symbols.removeValue(forKey: Self.key(oldName))
        if let value { symbols[Self.key(newName)] = value }
    }

    mutating func remove(_ name: String) { symbols.removeValue(forKey: Self.key(name)) }
}
