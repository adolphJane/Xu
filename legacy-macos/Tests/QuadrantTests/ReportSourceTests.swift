import XCTest
@testable import Quadrant

final class ReportSourceTests: XCTestCase {
    func testCandidatesDeduplicateAndPrivacyAppliesToPrompt() {
        let task = TaskItem(title: "联调接口", notes: "PRIVATE_NOTE", project: "PRIVATE_PROJECT",
                            category: "工作", quadrant: .schedule)
        let another = TaskItem(title: "整理回归", category: "工作", quadrant: .schedule)
        let candidates = ReportSourceBuilder.candidates(today: [task], completed: [task],
                                                         processed: [another, task])
        XCTAssertEqual(candidates.map(\.id), [task.id, another.id])

        let request = ReportRequest(tasks: candidates, template: .byCategory, supplement: "",
                                    minimumLength: 125, maximumLength: 180,
                                    sendNotes: false, sendProject: false)
        let prepared = ReportSourceBuilder.preparedTasks(for: request, blueprints: [])
        let prompt = DailyReportPrompt.make(tasks: prepared, completed: [], supplement: "",
                                            minimumLength: 125, maximumLength: 180,
                                            template: .byCategory)
        XCTAssertFalse(prompt.contains("PRIVATE_NOTE"))
        XCTAssertFalse(prompt.contains("PRIVATE_PROJECT"))
        XCTAssertTrue(prompt.contains("工作"))
        XCTAssertTrue(prompt.contains("联调接口"))
    }

    func testSnapshotVersionTwoReadsLegacyVersionOne() throws {
        var snapshot = WorkspaceSnapshot(tasks: [], blueprints: [], stages: [], milestones: [],
                                         reports: [], anniversaries: [], weeklyReviews: [])
        XCTAssertEqual(snapshot.formatVersion, 2)
        snapshot.formatVersion = 1
        let data = try SnapshotCodec.encode(snapshot)
        XCTAssertTrue(try SnapshotCodec.decode(data).isValid)
    }
}
