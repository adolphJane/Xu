import XCTest
@testable import Quadrant

@MainActor
final class TaskTreeProjectionTests: XCTestCase {
    func testTaskTreeIsSharedAcrossBlueprintListAndQuadrant() {
        let store = TaskStore(inMemory: true)
        let parent = TaskItem(title: "发布首页", quadrant: .schedule)
        let first = TaskItem(title: "设计检查", quadrant: .schedule, parentTaskID: parent.id)
        let second = TaskItem(title: "回归测试", quadrant: .delegate, parentTaskID: parent.id)

        XCTAssertTrue(store.addTaskTree(parent: parent, children: [first, second]))
        XCTAssertEqual(TaskTreeProjection.roots(in: store.tasks).map(\.id), [parent.id])
        XCTAssertEqual(TaskTreeProjection.descendants(of: parent.id, in: store.tasks).map(\.id), [first.id, second.id])
        XCTAssertTrue(store.tasks(in: .delegate).contains { $0.id == second.id })
        XCTAssertTrue(store.tasks(in: .schedule).contains { $0.id == first.id })
        XCTAssertNil(store.executionBlockReason(for: second), "A parent link must not become an execution dependency")

        store.markCompleted(second)
        XCTAssertTrue(store.tasks.first { $0.id == second.id }?.isCompleted == true)
        XCTAssertFalse(store.tasks.first { $0.id == parent.id }?.isCompleted == true)
    }

    func testInvalidTreeIsRejectedWithoutPartialInsert() {
        let store = TaskStore(inMemory: true)
        let parent = TaskItem(title: "主任务", quadrant: .schedule)
        let child = TaskItem(title: "错误关联", quadrant: .schedule, parentTaskID: UUID())
        XCTAssertFalse(store.addTaskTree(parent: parent, children: [child]))
        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testExistingBlueprintDoesNotGetDuplicateDerivedCard() {
        let store = TaskStore(inMemory: true)
        let blueprint = BlueprintItem(name: "现有蓝图", dueDate: .now)
        store.addBlueprint(blueprint)
        let parent = TaskItem(title: "主任务", quadrant: .schedule, blueprintID: blueprint.id)
        let child = TaskItem(title: "子任务", quadrant: .schedule, blueprintID: blueprint.id, parentTaskID: parent.id)
        XCTAssertTrue(store.addTaskTree(parent: parent, children: [child]))
        XCTAssertTrue(TaskTreeProjection.roots(in: store.tasks).isEmpty)
        let positions = WorkflowGraph.automaticPositions(for: store.tasks(for: blueprint.id))
        XCTAssertGreaterThan(positions[child.id]!.x, positions[parent.id]!.x)
        XCTAssertNil(store.executionBlockReason(for: child))
    }

    func testAnyTaskCanFindItsBlueprintRoot() {
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        let child = TaskItem(title: "子任务", quadrant: .schedule, parentTaskID: root.id)
        let leaf = TaskItem(title: "细项", quadrant: .doNow, parentTaskID: child.id)
        let tasks = [leaf, child, root]

        XCTAssertEqual(TaskTreeProjection.rootID(containing: leaf.id, in: tasks), root.id)
        XCTAssertEqual(TaskTreeProjection.rootID(containing: child.id, in: tasks), root.id)
        XCTAssertEqual(TaskTreeProjection.rootID(containing: root.id, in: tasks), root.id)
        XCTAssertEqual(TaskTreeProjection.rootID(containing: leaf.id, in: [leaf]), leaf.id)
    }
}
