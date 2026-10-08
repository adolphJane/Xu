import XCTest
import AppKit
@testable import Quadrant

@MainActor
final class BlueprintWorkflowTests: XCTestCase {
    func testSerialParallelAndJoinUnlockOnlyAfterAllPredecessorsFinish() {
        let store = TaskStore(inMemory: true)
        let blueprint = BlueprintItem(name: "发布", dueDate: .now)
        store.addBlueprint(blueprint)
        let design = TaskItem(title: "设计", quadrant: .schedule, blueprintID: blueprint.id)
        let code = TaskItem(title: "开发", quadrant: .schedule, blueprintID: blueprint.id, dependencyIDs: [design.id])
        let docs = TaskItem(title: "文档", quadrant: .schedule, blueprintID: blueprint.id, dependencyIDs: [design.id])
        let release = TaskItem(title: "发布", quadrant: .schedule, blueprintID: blueprint.id, dependencyIDs: [code.id, docs.id])
        [design, code, docs, release].forEach(store.add)

        store.markCompleted(code)
        XCTAssertFalse(store.tasks.first { $0.id == code.id }!.isCompleted)
        store.markCompleted(design)
        XCTAssertNil(store.executionBlockReason(for: code))
        XCTAssertNil(store.executionBlockReason(for: docs))

        store.markCompleted(code)
        store.markCompleted(release)
        XCTAssertFalse(store.tasks.first { $0.id == release.id }!.isCompleted)
        store.markCompleted(docs)
        store.markCompleted(release)
        XCTAssertTrue(store.tasks.first { $0.id == release.id }!.isCompleted)
    }

    func testInvalidConnectionsAndCancelledPredecessorStayBlocked() {
        let store = TaskStore(inMemory: true)
        let first = BlueprintItem(name: "A", dueDate: .now)
        let second = BlueprintItem(name: "B", dueDate: .now)
        store.addBlueprint(first)
        store.addBlueprint(second)
        let a = TaskItem(title: "A1", quadrant: .schedule, blueprintID: first.id)
        let b = TaskItem(title: "A2", quadrant: .schedule, blueprintID: first.id)
        let foreign = TaskItem(title: "B1", quadrant: .schedule, blueprintID: second.id)
        [a, b, foreign].forEach(store.add)

        XCTAssertFalse(store.connect(foreign, to: b))
        XCTAssertTrue(store.connect(a, to: b))
        XCTAssertFalse(store.connect(b, to: a))
        store.cancel(a)
        XCTAssertNotNil(store.executionBlockReason(for: b))
        store.markCompleted(b)
        XCTAssertFalse(store.tasks.first { $0.id == b.id }!.isCompleted)
    }

    func testRestoringPredecessorRequiresDownstreamRollback() {
        let store = TaskStore(inMemory: true)
        let blueprint = BlueprintItem(name: "流程", dueDate: .now)
        store.addBlueprint(blueprint)
        let first = TaskItem(title: "先", quadrant: .schedule, blueprintID: blueprint.id)
        let second = TaskItem(title: "后", quadrant: .schedule, blueprintID: blueprint.id, dependencyIDs: [first.id])
        store.add(first)
        store.add(second)
        store.markCompleted(first)
        store.start(second)
        store.restore(first)
        XCTAssertTrue(store.tasks.first { $0.id == first.id }!.isCompleted)
        store.cancel(first)
        XCTAssertTrue(store.tasks.first { $0.id == first.id }!.isCompleted)
        store.rollbackWorkflow(from: first)
        XCTAssertTrue(store.tasks.first { $0.id == first.id }!.isPending)
        XCTAssertTrue(store.tasks.first { $0.id == second.id }!.isPending)
        XCTAssertNotNil(store.executionBlockReason(for: second))
    }

    func testImageAndPositionPersistAndTravelWithSnapshot() throws {
        let persistence = try PersistenceController(inMemory: true)
        let image = WorkflowImage(name: "示意图", data: Data([1, 2, 3, 4]))
        let task = TaskItem(title: "绘制", quadrant: .schedule, workflowX: 144, workflowY: 288, workflowImages: [image])
        try persistence.saveTasks([task])
        let restored = try XCTUnwrap(persistence.loadTasks().first)
        XCTAssertEqual(restored.workflowX, 144)
        XCTAssertEqual(restored.workflowY, 288)
        XCTAssertEqual(restored.images, [image])

        let snapshot = WorkspaceSnapshot(tasks: [restored], blueprints: [], stages: [], milestones: [], reports: [], anniversaries: [], weeklyReviews: [])
        XCTAssertEqual(try SnapshotCodec.decode(SnapshotCodec.encode(snapshot)).tasks.first?.images, [image])
    }

    func testImportedPictureCanBeDecodedAfterCompression() throws {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        ))
        bitmap.setColor(.red, atX: 0, y: 0)
        let source = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let imported = try WorkflowImage.imported(data: source, name: "测试.png")
        XCTAssertEqual(imported.name, "测试.png")
        XCTAssertNotNil(imported.nsImage)
    }

    func testDeletingMiddleNodeCanReconnectItsNeighbors() {
        let store = TaskStore(inMemory: true)
        let blueprint = BlueprintItem(name: "发布", dueDate: .now)
        store.addBlueprint(blueprint)
        let first = TaskItem(title: "准备", quadrant: .schedule, blueprintID: blueprint.id)
        let middle = TaskItem(title: "开发", quadrant: .schedule, blueprintID: blueprint.id, dependencyIDs: [first.id])
        let last = TaskItem(title: "验收", quadrant: .schedule, blueprintID: blueprint.id, dependencyIDs: [middle.id])
        [first, middle, last].forEach(store.add)

        XCTAssertTrue(store.removeWorkflowNode(middle, reconnect: true))
        XCTAssertNil(store.tasks.first { $0.id == middle.id })
        XCTAssertEqual(store.tasks.first { $0.id == last.id }?.effectiveDependencyIDs, [first.id])
    }

    func testBlueprintExportImportKeepsImagesAndRemapsConnections() throws {
        let store = TaskStore(inMemory: true)
        let blueprint = BlueprintItem(name: "视觉项目", dueDate: .now)
        store.addBlueprint(blueprint)
        let image = WorkflowImage(name: "参考图", data: Data([9, 8, 7]))
        let first = TaskItem(title: "准备", quadrant: .schedule, blueprintID: blueprint.id,
                             workflowX: 72, workflowY: 80, workflowImages: [image])
        let second = TaskItem(title: "执行", quadrant: .schedule, blueprintID: blueprint.id,
                              dependencyIDs: [first.id])
        store.add(first)
        store.add(second)

        let imported = try store.importBlueprint(from: store.exportPackage(for: blueprint))
        let copy = store.tasks(for: imported.id)
        let copiedFirst = try XCTUnwrap(copy.first { $0.title == "准备" })
        let copiedSecond = try XCTUnwrap(copy.first { $0.title == "执行" })
        XCTAssertNotEqual(copiedFirst.id, first.id)
        XCTAssertEqual(copiedFirst.images, [image])
        XCTAssertEqual(copiedFirst.workflowX, 72)
        XCTAssertEqual(copiedSecond.effectiveDependencyIDs, [copiedFirst.id])
    }

    func testImportRejectsBrokenGraphWithoutChangingWorkspace() throws {
        let store = TaskStore(inMemory: true)
        let blueprint = BlueprintItem(name: "损坏蓝图", dueDate: .now)
        let node = TaskItem(title: "节点", quadrant: .schedule, blueprintID: blueprint.id,
                            dependencyIDs: [UUID()])
        let package = BlueprintTransferPackage(blueprint: blueprint, stages: [], milestones: [], tasks: [node])
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(package)

        XCTAssertThrowsError(try store.importBlueprint(from: data))
        XCTAssertTrue(store.blueprints.isEmpty)
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testAIBlueprintLinksStagesButKeepsTasksWithinStageParallel() throws {
        let store = TaskStore(inMemory: true)
        let start = Date.now
        let finish = start.addingTimeInterval(86_400)
        let firstTasks = ["调研", "设计"].map {
            AITaskDraft(title: $0, scheduledFor: start, estimatedMinutes: 30, quadrant: .schedule)
        }
        let finalTask = AITaskDraft(title: "发布", scheduledFor: finish, estimatedMinutes: 30, quadrant: .schedule)
        let draft = AIBlueprintDraft(
            name: "新产品", goal: "发布", startDate: start, dueDate: finish,
            stages: [
                AIStageDraft(name: "准备", startDate: start, dueDate: finish, milestone: "准备完成", tasks: firstTasks),
                AIStageDraft(name: "交付", startDate: start, dueDate: finish, milestone: "发布完成", tasks: [finalTask])
            ]
        )
        try store.commitAIBlueprint(draft)
        let tasks = store.tasks(for: try XCTUnwrap(store.blueprints.first).id)
        let earlier = tasks.filter { $0.title == "调研" || $0.title == "设计" }
        let release = try XCTUnwrap(tasks.first { $0.title == "发布" })
        XCTAssertTrue(earlier.allSatisfy { $0.effectiveDependencyIDs.isEmpty })
        XCTAssertEqual(Set(release.effectiveDependencyIDs), Set(earlier.map(\.id)))
    }
}
