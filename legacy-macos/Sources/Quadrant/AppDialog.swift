import AppKit
import SwiftUI

/// One lifecycle for all macOS business dialogs, including prepared task composers.
@MainActor
final class AppDialogPresentation: ObservableObject {
    enum Phase { case prepared, visible, closing, closed }
    @Published private(set) var phase: Phase = .prepared
    var reduceMotion = false
    var cancelAction: (() -> Void)?
    var animateWindow: ((Bool, @escaping () -> Void) -> Void)?
    var onClose: (() -> Void)?
    private var afterDismiss: (() -> Void)?

    var isVisible: Bool { phase == .visible }
    var isClosing: Bool { phase == .closing || phase == .closed }

    func present() {
        guard phase == .prepared else { return }
        withAnimation(reduceMotion ? nil : AppTheme.composerEnterAnimation) { phase = .visible }
        animateWindow?(true, {})
    }

    func cancel() {
        guard phase == .visible else { return }
        if let cancelAction { cancelAction() } else { dismiss() }
    }

    func dismiss(after completion: (() -> Void)? = nil) {
        guard phase == .visible || phase == .prepared else { return }
        afterDismiss = completion
        withAnimation(reduceMotion ? nil : AppTheme.composerExitAnimation) { phase = .closing }
        let finish = { [weak self] in
            guard let self, self.phase == .closing else { return }
            self.phase = .closed
            self.onClose?()
            self.afterDismiss?()
            self.afterDismiss = nil
            self.cancelAction = nil
            self.animateWindow = nil
            self.onClose = nil
        }
        if let animateWindow { animateWindow(false, finish) } else { finish() }
    }
}

private struct AppDialogContextKey: EnvironmentKey {
    static let defaultValue: AppDialogPresentation? = nil
}

extension EnvironmentValues {
    var appDialogPresentation: AppDialogPresentation? {
        get { self[AppDialogContextKey.self] }
        set { self[AppDialogContextKey.self] = newValue }
    }
}

/// Uses the owning panel when presented in a dialog; native dismissal remains a preview fallback.
@propertyWrapper
struct AppDismiss: DynamicProperty {
    @Environment(\.dismiss) private var nativeDismiss
    @Environment(\.appDialogPresentation) private var presentation
    var wrappedValue: @MainActor () -> Void { { if let presentation { presentation.dismiss() } else { nativeDismiss() } } }
}

private struct AppDialogCancelModifier: ViewModifier {
    @Environment(\.appDialogPresentation) private var presentation
    let action: () -> Void
    func body(content: Content) -> some View {
        content.background { AppDialogCancelRegistration(presentation: presentation, action: action).frame(width: 0, height: 0) }
    }
}

private struct AppDialogCancelRegistration: NSViewRepresentable {
    let presentation: AppDialogPresentation?
    let action: () -> Void
    func makeNSView(context: Context) -> NSView {
        presentation?.cancelAction = action
        return NSView()
    }
    func updateNSView(_ view: NSView, context: Context) { presentation?.cancelAction = action }
}

/// Transparent parent-sized panel shared by cached composers and ordinary dialogs.
final class AppDialogPanel: NSPanel {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(parent: NSWindow) {
        super.init(contentRect: parent.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        appearance = parent.effectiveAppearance
        hasShadow = false
        animationBehavior = .none
        collectionBehavior = [.fullScreenAuxiliary]
        alphaValue = 0
        isReleasedWhenClosed = false
    }

    override func cancelOperation(_ sender: Any?) { onCancel?() }
    override func performClose(_ sender: Any?) { onCancel?() }

    func animate(visible: Bool, reduceMotion: Bool, completion: @escaping @MainActor @Sendable () -> Void) {
        guard !reduceMotion else { alphaValue = visible ? 1 : 0; completion(); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = visible ? AppTheme.dialogEnterDuration : AppTheme.composerExitDuration
            context.timingFunction = CAMediaTimingFunction(name: visible ? .easeOut : .easeIn)
            animator().alphaValue = visible ? 1 : 0
        } completionHandler: {
            Task { @MainActor in completion() }
        }
    }
}

/// The same backdrop, surface and motion as Add Task. Oversized content stays scrollable.
struct AppDialogContainer<Popup: View>: View {
    @ObservedObject var presentation: AppDialogPresentation
    @EnvironmentObject private var preferences: AppPreferences
    let isActive: Bool
    let popup: Popup
    @State private var contentSize: CGSize = .zero

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                AppShadows.modalColor
                    .contentShape(Rectangle())
                    .onTapGesture { presentation.cancel() }
                    .accessibilityLabel("关闭弹窗")
                ScrollView([.horizontal, .vertical]) {
                    popup
                        .fixedSize()
                        .background {
                            GeometryReader { proxy in
                                Color.clear
                                    .onAppear { contentSize = proxy.size }
                                    .onChange(of: proxy.size) { _, size in contentSize = size }
                            }
                        }
                }
                .defaultScrollAnchor(.topLeading)
                .scrollDisabled(contentSize.width <= geometry.size.width - AppSpacing.x8
                                && contentSize.height <= geometry.size.height - AppSpacing.x8)
                .frame(width: min(contentSize.width > 0 ? contentSize.width : 560, max(AppSpacing.x8, geometry.size.width - AppSpacing.x8)),
                       height: min(contentSize.height > 0 ? contentSize.height : 440, max(AppSpacing.x8, geometry.size.height - AppSpacing.x8)))
                .background(preferences.pageBackground)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.prominent))
                .shadow(color: AppShadows.modalColor, radius: AppShadows.modalRadius, y: AppShadows.modalOffset)
                .scaleEffect(presentation.reduceMotion || presentation.isVisible ? 1
                             : (presentation.isClosing ? AppTheme.composerDismissedScale : AppTheme.composerInitialScale))
                .offset(y: presentation.reduceMotion || presentation.isVisible ? 0 : AppSpacing.x3)
                .allowsHitTesting(presentation.isVisible)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea()
        .environment(\.appDialogPresentation, presentation)
        .task(id: isActive && contentSize != .zero) {
            guard isActive, contentSize != .zero else { return }
            // Let the first layout finish while the native panel is transparent.
            await Task.yield()
            guard !Task.isCancelled else { return }
            presentation.present()
        }
    }
}

private struct AppDialogModifier<Popup: View>: ViewModifier {
    @Binding var isPresented: Bool
    @EnvironmentObject private var store: TaskStore
    @EnvironmentObject private var preferences: AppPreferences
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    let identity: AnyHashable
    let onDismiss: (() -> Void)?
    @ViewBuilder let popup: () -> Popup

    func body(content: Content) -> some View {
        content.background {
            AppDialogAttachment(identity: isPresented ? identity : nil,
                                popup: isPresented ? AnyView(popup()) : nil,
                                store: store, preferences: preferences,
                                reduceMotion: preferences.reduceMotion || systemReduceMotion) {
                isPresented = false
                onDismiss?()
            }
            .frame(width: 0, height: 0)
        }
    }
}

private struct AppDialogAttachment: NSViewRepresentable {
    let identity: AnyHashable?
    let popup: AnyView?
    let store: TaskStore
    let preferences: AppPreferences
    let reduceMotion: Bool
    let onDismiss: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> AnchorView {
        let view = AnchorView()
        view.onWindowChange = { [weak coordinator = context.coordinator] window in coordinator?.setParent(window) }
        return view
    }
    func updateNSView(_ view: AnchorView, context: Context) {
        context.coordinator.update(parent: view.window, configuration: self)
    }
    static func dismantleNSView(_ view: AnchorView, coordinator: Coordinator) {
        view.onWindowChange = nil
        coordinator.detach()
    }
    final class AnchorView: NSView {
        var onWindowChange: ((NSWindow?) -> Void)?
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindowChange?(window) }
    }

    @MainActor
    final class Coordinator {
        private weak var parent: NSWindow?
        private weak var previousResponder: NSResponder?
        private var configuration: AppDialogAttachment?
        private var identity: AnyHashable?
        private var panel: AppDialogPanel?
        private var presentation: AppDialogPresentation?
        private var hosting: NSHostingView<AnyView>?
        private var observers: [NSObjectProtocol] = []
        private var isDetached = false

        func setParent(_ window: NSWindow?) {
            guard parent !== window else { return }
            removePanel()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            parent = window
            guard let window else { return }
            for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor in self?.syncFrame() }
                })
            }
            observers.append(NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification,
                                                                   object: window, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.detach() }
            })
            sync()
        }
        func update(parent: NSWindow?, configuration: AppDialogAttachment) {
            self.configuration = configuration
            isDetached = false
            setParent(parent)
            sync()
        }
        private func sync() {
            guard !isDetached, let configuration, let parent else { return }
            guard let requested = configuration.identity, let popup = configuration.popup else {
                presentation?.dismiss()
                return
            }
            if let presentation, let hosting {
                guard requested == identity, !presentation.isClosing else { presentation.dismiss(); return }
                presentation.reduceMotion = configuration.reduceMotion
                hosting.rootView = root(popup, presentation: presentation, configuration: configuration)
                return
            }
            let presentation = AppDialogPresentation()
            presentation.reduceMotion = configuration.reduceMotion
            let panel = AppDialogPanel(parent: parent)
            panel.onCancel = { [weak presentation] in presentation?.cancel() }
            presentation.animateWindow = { [weak panel, weak presentation] visible, completion in
                guard let panel else { completion(); return }
                panel.animate(visible: visible, reduceMotion: presentation?.reduceMotion ?? true, completion: completion)
            }
            presentation.onClose = { [weak self] in
                guard let self else { return }
                let finishedID = self.identity
                let callback = self.configuration?.onDismiss
                self.removePanel()
                // Do not clear a replacement item that arrived while the old one was closing.
                if self.configuration?.identity == nil || self.configuration?.identity == finishedID { callback?() }
                else { self.sync() }
            }
            identity = requested
            self.presentation = presentation
            self.panel = panel
            previousResponder = parent.firstResponder
            let hosting = NSHostingView(rootView: root(popup, presentation: presentation, configuration: configuration))
            hosting.sizingOptions = []
            self.hosting = hosting
            panel.contentView = hosting
            parent.addChildWindow(panel, ordered: .above)
            panel.makeKeyAndOrderFront(nil)
        }
        private func root(_ popup: AnyView, presentation: AppDialogPresentation,
                          configuration: AppDialogAttachment) -> AnyView {
            AnyView(AppDialogContainer(presentation: presentation, isActive: true, popup: popup)
                .environmentObject(configuration.store)
                .environmentObject(configuration.preferences)
                .preferredColorScheme(configuration.preferences.colorScheme))
        }
        private func syncFrame() {
            if let parent { panel?.setFrame(parent.frame, display: true) }
        }
        private func removePanel() {
            guard let panel else { return }
            parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            panel.contentView = nil
            self.panel = nil
            hosting = nil
            presentation?.onClose = nil
            presentation?.animateWindow = nil
            presentation?.cancelAction = nil
            presentation = nil
            identity = nil
            if let parent, parent.isVisible {
                let focusWindow = parent.childWindows?.last(where: { $0.isVisible }) ?? parent
                focusWindow.makeKey()
                if focusWindow === parent, let previousResponder { parent.makeFirstResponder(previousResponder) }
            }
        }
        func detach() {
            isDetached = true
            removePanel()
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
            parent = nil
            configuration = nil
        }
    }
}

extension View {
    func appDialog<Popup: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil,
                               @ViewBuilder content: @escaping () -> Popup) -> some View {
        modifier(AppDialogModifier(isPresented: isPresented, identity: true, onDismiss: onDismiss, popup: content))
    }
    func appDialog<Item: Identifiable, Popup: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil,
                                                   @ViewBuilder content: @escaping (Item) -> Popup) -> some View {
        modifier(AppDialogModifier(isPresented: Binding(get: { item.wrappedValue != nil }, set: { if !$0 { item.wrappedValue = nil } }),
                                   identity: item.wrappedValue.map { AnyHashable($0.id) } ?? AnyHashable(false),
                                   onDismiss: onDismiss,
                                   popup: { if let value = item.wrappedValue { content(value) } }))
    }
    func onAppDialogCancel(_ action: @escaping () -> Void) -> some View {
        modifier(AppDialogCancelModifier(action: action))
    }
}

struct AppDialogExample: View {
    @State private var isPresented = false
    @State private var isNestedPresented = false
    @State private var isInputPresented = false
    @State private var sampleName = "工作"
    var body: some View {
        Button("打开统一弹窗") { isPresented = true }
            .appDialog(isPresented: $isPresented) {
                VStack(spacing: AppSpacing.x4) {
                    Text("统一弹窗").font(AppTypography.title)
                    Text("居中面板、外侧取消与独立的嵌套弹窗。")
                    Button("打开嵌套弹窗") { isNestedPresented = true }
                    Button("文本输入示例") { isInputPresented = true }
                    Button("关闭") { isPresented = false }
                }
                .padding(AppSpacing.page).frame(width: 420)
                .appDialog(isPresented: $isNestedPresented) {
                    VStack(spacing: AppSpacing.x4) {
                        Text("只关闭当前层")
                        Button("返回上一层") { isNestedPresented = false }
                    }.padding(AppSpacing.page).frame(width: 320)
                }
                .appDialog(isPresented: $isInputPresented) {
                    AppTextInputDialog(title: "重命名示例", message: "仅修改预览中的文本。",
                                       prompt: "名称", text: $sampleName) { _ in nil }
                }
            }
    }
}

/// Small text-entry forms share the same dialog host rather than using an input alert.
struct AppTextInputDialog: View {
    @AppDismiss private var dismiss
    let title: String
    let message: String
    let prompt: String
    @Binding var text: String
    var primaryTitle = "保存"
    let submit: (String) -> String?
    @State private var error: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.x4) {
            Text(title).font(AppTypography.title)
            Text(message).font(AppTypography.callout).foregroundStyle(.secondary)
            TextField(prompt, text: $text).textFieldStyle(.roundedBorder)
                .focused($isFocused).onSubmit(save)
            if let error { Text(error).font(AppTypography.caption).foregroundStyle(AppColors.danger) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button(primaryTitle, action: save).buttonStyle(.borderedProminent)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(AppSpacing.page).frame(width: 420)
        .task { isFocused = true }
    }
    private func save() {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }
        if let message = submit(value) { error = message } else { dismiss() }
    }
}

private struct AppDialogPreview: View {
    @StateObject private var store = TaskStore(inMemory: true)
    @StateObject private var preferences = AppPreferences()
    var body: some View {
        AppDialogExample().frame(width: 900, height: 700)
            .environmentObject(store).environmentObject(preferences)
    }
}
#Preview("统一弹窗 · 浅色") { AppDialogPreview().preferredColorScheme(.light) }
#Preview("统一弹窗 · 深色") { AppDialogPreview().preferredColorScheme(.dark) }
#Preview("统一弹窗 · 文本输入") {
    AppTextInputDialog(title: "重命名类别", message: "名称支持长中文与错误提示。",
                       prompt: "类别名称", text: .constant("长期学习与个人成长")) { _ in nil }
}
