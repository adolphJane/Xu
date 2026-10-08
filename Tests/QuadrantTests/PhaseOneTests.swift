import XCTest
@testable import Quadrant

@MainActor
final class PhaseOneTests: XCTestCase {
    func testSwiftDataRoundTrip() throws {
        let persistence = try PersistenceController(inMemory: true)
        let task = TaskItem(
            title: "完成渠道适配测试",
            project: "渠道适配",
            reportCategory: .projectProgress,
            quadrant: .doNow,
            status: .inProgress,
            blueprintID: UUID(),
            blockReason: nil
        )

        try persistence.saveTasks([task])
        let loaded = try persistence.loadTasks()

        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, task.title)
        XCTAssertEqual(loaded.first?.project, "渠道适配")
        XCTAssertEqual(loaded.first?.effectiveStatus, .inProgress)
        XCTAssertEqual(loaded.first?.blueprintID, task.blueprintID)

        try persistence.saveTasks([])
        XCTAssertTrue(try persistence.loadTasks().isEmpty)
    }

    func testBlueprintAndReportRoundTrip() throws {
        let persistence = try PersistenceController(inMemory: true)
        let blueprint = BlueprintItem(name: "序 0.2", goal: "完成第一阶段", dueDate: .now)
        let stage = StageItem(blueprintID: blueprint.id, name: "开发", order: 0, dueDate: .now)
        let milestone = MilestoneItem(blueprintID: blueprint.id, stageID: stage.id, name: "内测", dueDate: .now)
        let report = DailyReportItem(minimumLength: 125, maximumLength: 180, supplement: "完成迁移", content: "测试日报内容")

        try persistence.saveBlueprints([blueprint])
        try persistence.saveStages([stage])
        try persistence.saveMilestones([milestone])
        try persistence.saveReports([report])

        XCTAssertEqual(try persistence.loadBlueprints().first?.name, "序 0.2")
        XCTAssertEqual(try persistence.loadStages().first?.blueprintID, blueprint.id)
        XCTAssertEqual(try persistence.loadMilestones().first?.stageID, stage.id)
        XCTAssertEqual(try persistence.loadReports().first?.minimumLength, 125)
    }

    func testReportGroupsSameProjectOncePerSection() {
        let tasks = [
            TaskItem(title: "适配登录", project: "渠道适配", reportCategory: .projectProgress, quadrant: .doNow),
            TaskItem(title: "验证支付", project: "渠道适配", reportCategory: .projectProgress, quadrant: .schedule)
        ]

        let prompt = DailyReportPrompt.make(
            tasks: tasks,
            completed: [],
            supplement: "",
            minimumLength: 125,
            maximumLength: 180
        )
        let groupedSection = prompt.components(separatedBy: "2. 会议/方案/讨论的原始任务数据：").first ?? prompt
        XCTAssertEqual(groupedSection.components(separatedBy: "- 【渠道适配】").count - 1, 1)
        XCTAssertTrue(groupedSection.contains("适配登录"))
        XCTAssertTrue(groupedSection.contains("验证支付"))
    }

    func testReportMinimumLengthFallback() {
        let result = DailyReportPrompt.enforceMinimumLength(
            "内容过短",
            fallback: "1. 项目/测试/开发进度\n2. 会议/方案/讨论\n3. 明日重点事项规划",
            minimumLength: 125
        )
        XCTAssertGreaterThanOrEqual(result.count, 125)
        XCTAssertTrue(result.contains("1. 项目/测试/开发进度"))
        XCTAssertTrue(result.contains("3. 明日重点事项规划"))
    }
}
