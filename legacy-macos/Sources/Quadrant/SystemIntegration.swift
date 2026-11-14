import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var localMonitor: Any?
    private var globalMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installGlobalShortcut()
        installEventMonitorFallback()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
    }

    private func installGlobalShortcut() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.presentCommandPalette() }
            return noErr
        }, 1, &eventType, nil, &handler)

        let identifier = EventHotKeyID(signature: fourCharacterCode("XUCM"), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(cmdKey | shiftKey), identifier, GetApplicationEventTarget(), 0, &hotKey)
    }

    private func installEventMonitorFallback() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard AppDelegate.isCommandShortcut(event) else { return event }
            DispatchQueue.main.async { AppDelegate.presentCommandPalette() }
            return nil
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            guard AppDelegate.isCommandShortcut(event) else { return }
            DispatchQueue.main.async { AppDelegate.presentCommandPalette() }
        }
    }

    private static func isCommandShortcut(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        return event.keyCode == UInt16(kVK_Space) && flags.contains(.command) && flags.contains(.shift)
    }

    @MainActor
    private static func presentCommandPalette() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { $0.identifier?.rawValue == "main-AppWindow-1" || $0.title == "序" })?.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .showCommandPalette, object: nil)
    }

    private func fourCharacterCode(_ value: String) -> OSType {
        value.utf8.reduce(0) { ($0 << 8) + OSType($1) }
    }
}
