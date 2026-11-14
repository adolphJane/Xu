import XCTest
@testable import Quadrant

@MainActor
final class TaskTreeProjectionTests: XCTestCase {
    func testExistingChildCanReceiveAnotherLevelAndKeepItsContext() throws {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "发布版本", project: "序", category: "工作", quadrant: .doNow, status: .unscheduled)
        store.add(root)
        XCTAssertTrue(store.addChild(title: "准备说明", to: root.id))
        let child = try XCTUnwrap(TaskTreeProjection.directChildren(of: root.id, in: store.tasks).first)
        XCTAssertTrue(store.addChild(title: "核对截图", to: child.id))
        let grandchild = try XCTUnwrap(TaskTreeProjection.directChildren(of: child.id, in: store.tasks).first)

        XCTAssertEqual(grandchild.parentTaskID, child.id)
        XCTAssertEqual(grandchild.project, root.project)
        XCTAssertEqual(grandchild.category, root.category)
        XCTAssertEqual(grandchild.quadrant, root.quadrant)
        XCTAssertEqual(grandchild.effectiveStatus, .unscheduled)
        XCTAssertEqual(TaskTreeProjection.path(to: grandchild.id, in: store.tasks).map(\.id), [root.id, child.id, grandchild.id])
        XCTAssertEqual(TaskTreeProjection.descendants(of: root.id, in: store.tasks).count, 2)
    }

    func testReparentRejectsCyclesAndKeepsOriginalTree() throws {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        store.add(root)
        XCTAssertTrue(store.addChild(title: "子任务", to: root.id))
        let child = try XCTUnwrap(TaskTreeProjection.directChildren(of: root.id, in: store.tasks).first)
        var changedRoot = root
        changedRoot.parentTaskID = child.id
        XCTAssertFalse(store.update(changedRoot))
        XCTAssertNil(store.tasks.first(where: { $0.id == root.id })?.parentTaskID)
        XCTAssertFalse(store.addChild(title: " ", to: child.id))
        XCTAssertEqual(store.tasks.count, 2)
    }

    func testEditingAndMovingChildKeepsItsIdentityAndDescendants() throws {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        store.add(root)
        XCTAssertTrue(store.addChild(title: "第一阶段", to: root.id))
        XCTAssertTrue(store.addChild(title: "第二阶段", to: root.id))
        let siblings = TaskTreeProjection.directChildren(of: root.id, in: store.tasks)
        let first = try XCTUnwrap(siblings.first)
        let second = try XCTUnwrap(siblings.last)
        XCTAssertTrue(store.addChild(title: "核对资料", to: first.id))
        let grandchild = try XCTUnwrap(TaskTreeProjection.directChildren(of: first.id, in: store.tasks).first)

        var edited = first
        edited.title = "准备阶段"
        edited.notes = "补充细节"
        edited.parentTaskID = second.id
        XCTAssertTrue(store.update(edited))

        let saved = try XCTUnwrap(store.tasks.first { $0.id == first.id })
        XCTAssertEqual(saved.title, "准备阶段")
        XCTAssertEqual(saved.notes, "补充细节")
        XCTAssertEqual(saved.parentTaskID, second.id)
        XCTAssertEqual(saved.createdAt, first.createdAt)
        XCTAssertEqual(store.tasks.first { $0.id == grandchild.id }?.parentTaskID, first.id)
        XCTAssertEqual(TaskTreeProjection.path(to: grandchild.id, in: store.tasks).map(\.id), [root.id, second.id, first.id, grandchild.id])
    }

    func testDeletingMiddleTaskRemovesItsDescendants() throws {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        store.add(root)
        XCTAssertTrue(store.addChild(title: "阶段", to: root.id))
        let middle = try XCTUnwrap(TaskTreeProjection.directChildren(of: root.id, in: store.tasks).first)
        XCTAssertTrue(store.addChild(title: "执行", to: middle.id))
        let child = try XCTUnwrap(TaskTreeProjection.directChildren(of: middle.id, in: store.tasks).first)
        XCTAssertTrue(store.addChild(title: "校验", to: child.id))
        let grandchild = try XCTUnwrap(TaskTreeProjection.directChildren(of: child.id, in: store.tasks).first)

        store.delete(middle)
        XCTAssertFalse(store.tasks.contains { [middle.id, child.id, grandchild.id].contains($0.id) })
        XCTAssertTrue(store.tasks.contains { $0.id == root.id })
        XCTAssertTrue(TaskTreeProjection.descendants(of: root.id, in: store.tasks).isEmpty)
    }

    func testDeletingParentRemovesAllDescendants() throws {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        store.add(root)
        XCTAssertTrue(store.addChild(title: "阶段", to: root.id))
        let child = try XCTUnwrap(TaskTreeProjection.directChildren(of: root.id, in: store.tasks).first)
        XCTAssertTrue(store.addChild(title: "执行", to: child.id))

        store.delete(root)

        XCTAssertTrue(store.tasks.isEmpty)
    }

    func testSnapshotRejectsBrokenParentLinksAndCycles() {
        let parentID = UUID()
        let orphan = TaskItem(title: "孤儿", quadrant: .schedule, parentTaskID: parentID)
        XCTAssertNotNil(TaskTreeProjection.validationError(in: [orphan]))

        let first = TaskItem(title: "甲", quadrant: .schedule)
        var second = TaskItem(title: "乙", quadrant: .schedule, parentTaskID: first.id)
        var cyclicFirst = first
        cyclicFirst.parentTaskID = second.id
        XCTAssertNotNil(TaskTreeProjection.validationError(in: [cyclicFirst, second]))
        second.parentTaskID = first.id
        XCTAssertNil(TaskTreeProjection.validationError(in: [first, second]))
    }

    func testNestedTreeSurvivesSwiftDataAndLegacyJSONRoundTrip() throws {
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        let child = TaskItem(title: "子任务", quadrant: .schedule, parentTaskID: root.id)
        let grandchild = TaskItem(title: "孙任务", quadrant: .doNow, parentTaskID: child.id)
        let tasks = [root, child, grandchild]

        let persistence = try PersistenceController(inMemory: true)
        try persistence.saveTasks(tasks)
        let loaded = try persistence.loadTasks()
        XCTAssertEqual(TaskTreeProjection.path(to: grandchild.id, in: loaded).map(\.id), [root.id, child.id, grandchild.id])

        let decoded = try JSONDecoder().decode([TaskItem].self, from: JSONEncoder().encode(tasks))
        XCTAssertEqual(TaskTreeProjection.path(to: grandchild.id, in: decoded).map(\.id), [root.id, child.id, grandchild.id])
    }

    func testTaskTreeIsSharedAcrossBlueprintListAndQuadrant() {
        let store = TaskStore(inMemory: true)
        let parent = TaskItem(title: "发布首页", quadrant: .schedule)
        // Explicit times keep the expected order independent of clock resolution and UUIDs.
        let createdAt = Date(timeIntervalSince1970: 1_700_000_000)
        let first = TaskItem(title: "设计检查", quadrant: .schedule, createdAt: createdAt, parentTaskID: parent.id)
        let second = TaskItem(title: "回归测试", quadrant: .delegate,
                              createdAt: createdAt.addingTimeInterval(1), parentTaskID: parent.id)

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

    func testCompletingParentCompletesNestedActiveChildrenTogether() throws {
        let store = TaskStore(inMemory: true)
        let parent = TaskItem(title: "主任务", quadrant: .schedule)
        let child = TaskItem(title: "子任务", quadrant: .schedule, parentTaskID: parent.id)
        let grandchild = TaskItem(title: "孙任务", quadrant: .schedule, parentTaskID: child.id)
        let cancelled = TaskItem(title: "已取消", quadrant: .schedule, parentTaskID: parent.id)
        let unrelated = TaskItem(title: "其他任务", quadrant: .schedule)
        [parent, child, grandchild, cancelled, unrelated].forEach(store.add)
        store.cancel(cancelled)
        store.markCompleted(grandchild)
        let originalCompletedAt = try XCTUnwrap(store.tasks.first { $0.id == grandchild.id }?.completedAt)
        let childAutoCompletedAt = try XCTUnwrap(store.tasks.first { $0.id == child.id }?.autoCompletedAt)

        store.markCompleted(parent)

        let savedParent = try XCTUnwrap(store.tasks.first { $0.id == parent.id })
        let savedChild = try XCTUnwrap(store.tasks.first { $0.id == child.id })
        XCTAssertTrue(savedParent.isCompleted)
        XCTAssertTrue(savedChild.isCompleted)
        XCTAssertNil(savedParent.autoCompletedAt)
        XCTAssertEqual(savedParent.displayStatusTitle, "已完成")
        XCTAssertEqual(savedChild.autoCompletedAt, childAutoCompletedAt)
        XCTAssertEqual(store.tasks.first { $0.id == grandchild.id }?.completedAt, originalCompletedAt)
        XCTAssertTrue(store.tasks.first { $0.id == cancelled.id }?.isCancelled == true)
        XCTAssertFalse(store.tasks.first { $0.id == unrelated.id }?.isCompleted == true)
    }

    func testRestoringManuallyCompletedParentRevertsOnlyItsBatch() throws {
        let store = TaskStore(inMemory: true)
        let parent = TaskItem(title: "主任务", quadrant: .schedule)
        let previouslyCompleted = TaskItem(title: "已单独完成", quadrant: .schedule, parentTaskID: parent.id)
        let child = TaskItem(title: "连带完成", quadrant: .schedule, parentTaskID: parent.id)
        let grandchild = TaskItem(title: "连带完成的孙任务", quadrant: .schedule, parentTaskID: child.id)
        [parent, previouslyCompleted, child, grandchild].forEach(store.add)
        store.markCompleted(previouslyCompleted)
        let originalDate = try XCTUnwrap(store.tasks.first { $0.id == previouslyCompleted.id }?.completedAt)

        store.markCompleted(parent)
        XCTAssertNotNil(store.tasks.first { $0.id == child.id }?.autoCompletedAt)
        store.restore(parent)

        XCTAssertTrue(store.tasks.first { $0.id == parent.id }?.isPending == true)
        XCTAssertTrue(store.tasks.first { $0.id == child.id }?.isPending == true)
        XCTAssertTrue(store.tasks.first { $0.id == grandchild.id }?.isPending == true)
        XCTAssertEqual(store.tasks.first { $0.id == previouslyCompleted.id }?.completedAt, originalDate)
    }

    func testRestoringParentKeepsPreviouslyCompletedChildren() {
        let store = TaskStore(inMemory: true)
        let parent = TaskItem(title: "主任务", quadrant: .schedule)
        let child = TaskItem(title: "子任务", quadrant: .schedule, parentTaskID: parent.id)
        [parent, child].forEach(store.add)
        store.markCompleted(child)
        store.markCompleted(parent)

        store.restore(parent)

        XCTAssertTrue(store.tasks.first { $0.id == parent.id }?.isPending == true)
        XCTAssertTrue(store.tasks.first { $0.id == child.id }?.isCompleted == true)
    }

    func testRestoringParentBatchAlsoReopensCompletedAncestor() {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "总任务", quadrant: .schedule)
        let parent = TaskItem(title: "阶段", quadrant: .schedule, parentTaskID: root.id)
        let child = TaskItem(title: "步骤", quadrant: .schedule, parentTaskID: parent.id)
        [root, parent, child].forEach(store.add)
        store.markCompleted(parent)
        store.markCompleted(root)
        XCTAssertTrue(store.tasks.first { $0.id == root.id }?.isCompleted == true)

        store.restore(parent)

        XCTAssertTrue(store.tasks.first { $0.id == root.id }?.isPending == true)
        XCTAssertTrue(store.tasks.first { $0.id == parent.id }?.isPending == true)
        XCTAssertTrue(store.tasks.first { $0.id == child.id }?.isPending == true)
    }

    func testCompletingParentRespectsDependenciesAndRejectsPartialUpdates() throws {
        let store = TaskStore(inMemory: true)
        let blueprint = BlueprintItem(name: "项目", dueDate: .now)
        store.addBlueprint(blueprint)
        let parent = TaskItem(title: "主任务", quadrant: .schedule, blueprintID: blueprint.id)
        let child = TaskItem(title: "子任务", quadrant: .schedule,
                             blueprintID: blueprint.id, parentTaskID: parent.id)
        let sibling = TaskItem(title: "并行子任务", quadrant: .schedule,
                               blueprintID: blueprint.id, parentTaskID: parent.id)
        XCTAssertTrue(store.addTaskTree(parent: parent, children: [child, sibling]))
        XCTAssertTrue(store.connect(child, to: parent))
        store.markCompleted(parent)
        XCTAssertTrue(store.tasks.first { $0.id == parent.id }?.isCompleted == true)
        XCTAssertTrue(store.tasks.first { $0.id == child.id }?.isCompleted == true)
        XCTAssertTrue(store.tasks.first { $0.id == sibling.id }?.isCompleted == true)

        store.restore(parent)
        store.restore(child)
        store.restore(sibling)
        store.block(child, reason: "等待验收")
        store.markCompleted(parent)
        XCTAssertFalse(store.tasks.first { $0.id == parent.id }?.isCompleted == true)
        XCTAssertTrue(store.tasks.first { $0.id == child.id }?.effectiveStatus == .blocked)
        XCTAssertFalse(store.tasks.first { $0.id == sibling.id }?.isCompleted == true)
        XCTAssertTrue(store.actionMessage?.contains("等待验收") == true)
    }

    func testCompletingAllChildrenAutomaticallyCompletesAncestorsAndRestoringChildReopensThem() throws {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        let branch = TaskItem(title: "阶段", quadrant: .schedule, parentTaskID: root.id)
        let leaf = TaskItem(title: "执行", quadrant: .schedule, parentTaskID: branch.id)
        let sibling = TaskItem(title: "验收", quadrant: .schedule, parentTaskID: root.id)
        [root, branch, leaf, sibling].forEach(store.add)

        store.markCompleted(leaf)
        XCTAssertTrue(store.tasks.first { $0.id == branch.id }?.isCompleted == true)
        XCTAssertNotNil(store.tasks.first { $0.id == branch.id }?.autoCompletedAt)
        XCTAssertFalse(store.tasks.first { $0.id == root.id }?.isCompleted == true)

        store.markCompleted(sibling)
        let completedRoot = try XCTUnwrap(store.tasks.first { $0.id == root.id })
        XCTAssertTrue(completedRoot.isCompleted)
        XCTAssertNotNil(completedRoot.autoCompletedAt)
        XCTAssertEqual(completedRoot.displayStatusTitle, "自动完成")
        XCTAssertTrue(TasksScope.processed.includes(leaf, in: store.tasks))
        XCTAssertFalse(TasksScope.active.includes(leaf, in: store.tasks))

        let persistence = try PersistenceController(inMemory: true)
        try persistence.saveTasks(store.tasks)
        let loaded = try XCTUnwrap(persistence.loadTasks().first { $0.id == root.id })
        XCTAssertEqual(loaded.autoCompletedAt, completedRoot.autoCompletedAt)
        let decoded = try XCTUnwrap(JSONDecoder().decode([TaskItem].self, from: JSONEncoder().encode(store.tasks))
            .first { $0.id == root.id })
        XCTAssertEqual(decoded.autoCompletedAt, completedRoot.autoCompletedAt)

        store.restore(leaf)
        XCTAssertFalse(store.tasks.first { $0.id == branch.id }?.isCompleted == true)
        XCTAssertFalse(store.tasks.first { $0.id == root.id }?.isCompleted == true)
        XCTAssertNil(store.tasks.first { $0.id == root.id }?.autoCompletedAt)
        XCTAssertTrue(store.tasks.first { $0.id == sibling.id }?.isCompleted == true)
        XCTAssertTrue(TasksScope.active.includes(leaf, in: store.tasks))
    }

    func testWorkflowRollbackOfChildReopensCompletedParent() {
        let store = TaskStore(inMemory: true)
        let parent = TaskItem(title: "主任务", quadrant: .schedule)
        let child = TaskItem(title: "子任务", quadrant: .schedule, parentTaskID: parent.id)
        [parent, child].forEach(store.add)
        store.markCompleted(parent)

        store.rollbackWorkflow(from: child)

        XCTAssertTrue(store.tasks.first { $0.id == child.id }?.isPending == true)
        XCTAssertTrue(store.tasks.first { $0.id == parent.id }?.isPending == true)
    }

    func testBlockedParentDoesNotCompleteAfterLastChild() {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "主任务", quadrant: .schedule)
        let child = TaskItem(title: "子任务", quadrant: .schedule, parentTaskID: root.id)
        [root, child].forEach(store.add)
        store.block(root, reason: "等待审批")

        store.markCompleted(child)

        XCTAssertTrue(store.tasks.first { $0.id == child.id }?.isCompleted == true)
        XCTAssertFalse(store.tasks.first { $0.id == root.id }?.isCompleted == true)
        XCTAssertEqual(store.tasks.first { $0.id == root.id }?.effectiveStatus, .blocked)
    }

    func testAddingChildReopensCompletedParent() throws {
        let store = TaskStore(inMemory: true)
        let parent = TaskItem(title: "主任务", quadrant: .schedule)
        let child = TaskItem(title: "原子任务", quadrant: .schedule, parentTaskID: parent.id)
        [parent, child].forEach(store.add)
        store.markCompleted(child)
        store.markCompleted(parent)

        XCTAssertTrue(store.addChild(title: "新增子任务", to: parent.id))
        let reopened = try XCTUnwrap(store.tasks.first { $0.id == parent.id })
        XCTAssertFalse(reopened.isCompleted)
        XCTAssertNil(reopened.autoCompletedAt)
        XCTAssertTrue(store.tasks.first { $0.id == child.id }?.isCompleted == true)
        XCTAssertEqual(TaskTreeProjection.directChildren(of: parent.id, in: store.tasks).count, 2)
    }

    func testExistingCompletedChildrenReconcilePendingParents() {
        let store = TaskStore(inMemory: true)
        let root = TaskItem(title: "旧版待完成父任务", quadrant: .schedule)
        let child = TaskItem(title: "旧版已完成子任务", quadrant: .schedule, status: .completed, parentTaskID: root.id)
        let manualParent = TaskItem(title: "手动完成父任务", quadrant: .schedule, status: .completed)
        let manualChild = TaskItem(title: "手动完成子任务", quadrant: .schedule,
                                   status: .completed, parentTaskID: manualParent.id)
        [root, child, manualParent, manualChild].forEach(store.add)

        store.reconcileCompletedParents()

        XCTAssertEqual(store.tasks.first { $0.id == root.id }?.displayStatusTitle, "自动完成")
        XCTAssertEqual(store.tasks.first { $0.id == manualParent.id }?.displayStatusTitle, "已完成")
        XCTAssertEqual(store.tasks.first { $0.id == child.id }?.displayStatusTitle, "已完成")
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
