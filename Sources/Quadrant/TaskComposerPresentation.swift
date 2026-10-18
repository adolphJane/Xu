import AppKit
import SwiftUI

@MainActor
final class TaskComposerPresentation: ObservableObject {
    @Published var mode: TaskComposerMode?

    func show(_ mode: TaskComposerMode) {
        self.mode = mode
    }
}

@MainActor
private final class ComposerPanelActivation: ObservableObject {
    @Published var isActive = false
}

/// Prepares untouched forms offscreen so opening the transparent panel skips initial layout.
struct TaskComposerPanelHost: View {
    @ObservedObject var presentation: TaskComposerPresentation
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion

    var body: some View {
        ComposerPanelAttachment(
            presentation: presentation,
            mode: presentation.mode,
            store: store,
            preferences: preferences,
            reduceMotion: preferences.reduceMotion || systemReduceMotion
        )
        .frame(width: 0, height: 0)
    }
}

private struct ComposerPanelAttachment: NSViewRepresentable {
    let presentation: TaskComposerPresentation
    let mode: TaskComposerMode?
    let store: TaskStore
    let preferences: AppPreferences
    let reduceMotion: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in
            coordinator?.updateParent(window)
        }
        return view
    }

    func updateNSView(_ view: AnchorView, context: Context) {
        context.coordinator.update(
            parent: view.window,
            presentation: presentation,
            mode: mode,
            store: store,
            preferences: preferences,
            reduceMotion: reduceMotion
        )
    }

    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        view.onWindowChange = nil
        coordinator.detach()
    }

    final class AnchorView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onWindowChange?(window)
        }
    }

    @MainActor
    final class Coordinator {
        private struct PreparedPanel {
            let window: AppDialogPanel
            let presentation: AppDialogPresentation
            let activation: ComposerPanelActivation
        }

        private weak var parent: NSWindow?
        private weak var presentation: TaskComposerPresentation?
        private var mode: TaskComposerMode?
        private var panel: AppDialogPanel?
        private var activePresentation: AppDialogPresentation?
        private weak var previousResponder: NSResponder?
        private var preparedPanels: [TaskComposerMode: PreparedPanel] = [:]
        private var preloadWork: DispatchWorkItem?
        private var presentedMode: TaskComposerMode?
        private var observers: [NSObjectProtocol] = []
        private var store: TaskStore?
        private var preferences: AppPreferences?
        private var reduceMotion = false
        private var preparedColorScheme: ColorScheme?

        func update(parent: NSWindow?, presentation: TaskComposerPresentation, mode: TaskComposerMode?,
                    store: TaskStore, preferences: AppPreferences, reduceMotion: Bool) {
            self.presentation = presentation
            self.mode = mode
            self.store = store
            self.preferences = preferences
            self.reduceMotion = reduceMotion
            updateParent(parent)
            if preparedColorScheme != preferences.colorScheme {
                clearPreparedPanels()
                preparedColorScheme = preferences.colorScheme
            }
            syncPresentation()
        }

        func updateParent(_ window: NSWindow?) {
            guard parent !== window else { return }
            dismissPanel()
            clearPreparedPanels()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            parent = window
            guard let window else { return }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: window, queue: .main
                ) { [weak self] _ in
                    Task { @MainActor in self?.syncFrame() }
                })
            }
            observers.append(NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification, object: window, queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.dismissPanel()
                    self?.clearPreparedPanels()
                    self?.parent = nil
                    self?.presentation?.mode = nil
                }
            })
            syncPresentation()
        }

        private func syncPresentation() {
            guard let mode, let parent, let store, let preferences else {
                dismissPanel()
                schedulePreload()
                return
            }
            guard panel == nil || presentedMode != mode else { return }
            dismissPanel()
            preloadWork?.cancel()
            preloadWork = nil
            // A consumed panel is never cached again; the next one has fresh SwiftUI @State.
            let prepared = preparedPanels.removeValue(forKey: mode)
                ?? makePanel(mode: mode, parent: parent, store: store, preferences: preferences)
            let panel = prepared.window
            panel.setFrame(parent.frame, display: false)
            panel.appearance = parent.effectiveAppearance
            panel.alphaValue = reduceMotion ? 1 : 0
            self.panel = panel
            activePresentation = prepared.presentation
            activePresentation?.reduceMotion = reduceMotion
            previousResponder = parent.firstResponder
            presentedMode = mode
            parent.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
            prepared.activation.isActive = true
        }

        private func makePanel(mode: TaskComposerMode, parent: NSWindow,
                               store: TaskStore, preferences: AppPreferences) -> PreparedPanel {
            let activation = ComposerPanelActivation()
            let panel = AppDialogPanel(parent: parent)
            let dialog = AppDialogPresentation()
            dialog.reduceMotion = reduceMotion
            dialog.onClose = { [weak self] in self?.presentation?.mode = nil }
            dialog.animateWindow = { [weak panel, weak dialog] visible, completion in
                guard let panel else { completion(); return }
                panel.animate(visible: visible, reduceMotion: dialog?.reduceMotion ?? true, completion: completion)
            }
            panel.onCancel = { [weak dialog] in dialog?.cancel() }
            let hosting = NSHostingView(rootView:
                ComposerPanelContent(
                    mode: mode,
                    activation: activation,
                    presentation: dialog
                )
                .environmentObject(store)
                .environmentObject(preferences)
                .preferredColorScheme(preferences.colorScheme)
            )
            hosting.sizingOptions = []
            panel.contentView = hosting
            // Precompute the form tree while the panel is not ordered or interactive.
            hosting.layoutSubtreeIfNeeded()
            return PreparedPanel(window: panel, presentation: dialog, activation: activation)
        }

        private func schedulePreload() {
            guard panel == nil, preloadWork == nil, let parent, let store, let preferences,
                  let mode = TaskComposerMode.allCases.first(where: { preparedPanels[$0] == nil })
            else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.preloadWork = nil
                guard self.mode == nil, self.parent === parent else { return }
                self.preparedPanels[mode] = self.makePanel(
                    mode: mode, parent: parent, store: store, preferences: preferences
                )
                self.schedulePreload()
            }
            preloadWork = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + (mode == .task ? 0.15 : 0.5), execute: work
            )
        }

        private func clearPreparedPanels() {
            preloadWork?.cancel()
            preloadWork = nil
            for prepared in preparedPanels.values {
                prepared.presentation.cancelAction = nil
                prepared.presentation.onClose = nil
                prepared.presentation.animateWindow = nil
                prepared.window.contentView = nil
                prepared.window.orderOut(nil)
            }
            preparedPanels.removeAll()
        }

        private func syncFrame() {
            guard let parent else { return }
            panel?.setFrame(parent.frame, display: true)
            for prepared in preparedPanels.values {
                prepared.window.setFrame(parent.frame, display: false)
            }
        }

        func dismissPanel() {
            if let panel {
                parent?.removeChildWindow(panel)
                panel.orderOut(nil)
                panel.contentView = nil
                self.panel = nil
                activePresentation?.cancelAction = nil
                activePresentation?.onClose = nil
                activePresentation?.animateWindow = nil
                activePresentation = nil
                if let parent, parent.isVisible {
                    let focusWindow = parent.childWindows?.last(where: { $0.isVisible }) ?? parent
                    focusWindow.makeKey()
                    if focusWindow === parent, let previousResponder { parent.makeFirstResponder(previousResponder) }
                }
            }
            presentedMode = nil
        }

        func detach() {
            dismissPanel()
            clearPreparedPanels()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            parent = nil
        }
    }
}

private struct ComposerPanelContent: View {
    let mode: TaskComposerMode
    @ObservedObject var activation: ComposerPanelActivation
    @ObservedObject var presentation: AppDialogPresentation

    var body: some View {
        AppDialogContainer(presentation: presentation, isActive: activation.isActive,
                           popup: TaskComposerView(mode: mode, isPresentationActive: activation.isActive))
    }
}

private struct TaskComposerPanelPreview: View {
    @State private var presentation = TaskComposerPresentation()
    @StateObject private var store = TaskStore(inMemory: true)
    @StateObject private var preferences = AppPreferences()

    var body: some View {
        Button("添加事项") { presentation.show(.task) }
            .frame(width: 1000, height: 760)
            .background(AppColors.canvas)
            .overlay { TaskComposerPanelHost(presentation: presentation) }
            .environmentObject(store)
            .environmentObject(preferences)
    }
}

#Preview("添加事项 · 缩放与渐变") { TaskComposerPanelPreview() }
#Preview("添加事项 · 深色") { TaskComposerPanelPreview().preferredColorScheme(.dark) }
