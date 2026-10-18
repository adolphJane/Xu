import XCTest
@testable import Quadrant

@MainActor
final class AppDialogPresentationTests: XCTestCase {
    func testDismissWaitsForAnimationAndRunsFollowUpAfterRemoval() {
        let presentation = AppDialogPresentation()
        var finish: (() -> Void)?
        var events: [String] = []
        presentation.animateWindow = { visible, completion in
            if !visible { finish = completion }
        }
        presentation.onClose = { events.append("removed") }
        presentation.present()
        presentation.dismiss { events.append("follow-up") }
        XCTAssertEqual(presentation.phase, .closing)
        XCTAssertTrue(events.isEmpty)
        finish?()
        XCTAssertEqual(presentation.phase, .closed)
        XCTAssertEqual(events, ["removed", "follow-up"])
    }

    func testCancelAllowsUnsavedFormToKeepDialogOpen() {
        let presentation = AppDialogPresentation()
        var cancellationRequests = 0
        presentation.cancelAction = { cancellationRequests += 1 }
        presentation.present()
        presentation.cancel()
        XCTAssertEqual(cancellationRequests, 1)
        XCTAssertEqual(presentation.phase, .visible)
        presentation.dismiss()
        XCTAssertEqual(presentation.phase, .closed)
    }

    func testRepeatedCloseOnlyFinalizesOnce() {
        let presentation = AppDialogPresentation()
        var finish: (() -> Void)?
        var closeCount = 0
        presentation.animateWindow = { visible, completion in if !visible { finish = completion } }
        presentation.onClose = { closeCount += 1 }
        presentation.present()
        presentation.dismiss()
        presentation.dismiss()
        presentation.cancel()
        finish?()
        finish?()
        XCTAssertEqual(closeCount, 1)
    }
}
