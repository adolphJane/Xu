import AppKit
import SwiftUI
import XCTest
@testable import Quadrant

@MainActor
final class AppDialogHostingTests: XCTestCase {
    final class StateModel: ObservableObject {
        @Published var outer = false
        @Published var inner = false
        @Published var task: TaskItem?
        var closed = 0
        @Published var text = ""
        var cancellationRequests = 0
    }

    private struct Harness: View {
        @ObservedObject var model: StateModel
        var body: some View {
            Text("Host")
                .frame(width: 1000, height: 760)
                .appDialog(isPresented: $model.outer, onDismiss: { model.closed += 1 }) {
                    TextField("Draft", text: $model.text).padding().frame(width: 420, height: 240)
                        .onAppDialogCancel {
                            if model.text.isEmpty { model.outer = false }
                            else { model.cancellationRequests += 1 }
                        }
                        .appDialog(isPresented: $model.inner) {
                            Text("Inner").padding().frame(width: 300, height: 180)
                        }
                }
                .appDialog(item: $model.task) { task in Text(task.title).padding() }
        }
    }

    func testNestedPanelsDismissIndependently() throws {
        try withWindow { window, model in
            model.outer = true
            settle()
            let outer = try XCTUnwrap(window.childWindows?.first as? AppDialogPanel)
            XCTAssertEqual(outer.frame, window.frame)
            model.text = "Unsaved draft"
            settle()
            outer.onCancel?()
            settle()
            XCTAssertEqual(model.cancellationRequests, 1)
            XCTAssertTrue(model.outer)
            model.inner = true
            settle()
            XCTAssertEqual(outer.childWindows?.count, 1)
            model.inner = false
            settle()
            XCTAssertTrue(outer.childWindows?.isEmpty ?? true)
            XCTAssertEqual(window.childWindows?.count, 1)
            model.outer = false
            settle()
            XCTAssertTrue(window.childWindows?.isEmpty ?? true)
            XCTAssertEqual(model.closed, 1)
        }
    }

    func testReplacingItemKeepsTheReplacementPresented() throws {
        try withWindow { window, model in
            model.task = TaskItem(title: "First", quadrant: .schedule)
            settle()
            let first = try XCTUnwrap(window.childWindows?.first)
            let replacement = TaskItem(title: "Second", quadrant: .schedule)
            model.task = replacement
            settle()
            XCTAssertEqual(model.task?.id, replacement.id)
            XCTAssertEqual(window.childWindows?.count, 1)
            XCTAssertFalse(window.childWindows?.first === first)
            model.task = nil
            settle()
            XCTAssertTrue(window.childWindows?.isEmpty ?? true)
        }
    }

    private func withWindow(_ check: (NSWindow, StateModel) throws -> Void) throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "reduceMotion")
        defer {
            if let previous { defaults.set(previous, forKey: "reduceMotion") }
            else { defaults.removeObject(forKey: "reduceMotion") }
        }
        let preferences = AppPreferences()
        preferences.reduceMotion = true
        let model = StateModel()
        _ = NSApplication.shared
        let window = NSWindow(contentRect: NSRect(x: -10000, y: -10000, width: 1000, height: 760),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: Harness(model: model)
            .environmentObject(TaskStore(inMemory: true)).environmentObject(preferences))
        window.orderFront(nil)
        defer { window.orderOut(nil); window.close() }
        settle()
        try check(window, model)
    }

    private func settle() { RunLoop.main.run(until: Date().addingTimeInterval(0.12)) }
}
