import Cocoa
import FlutterMacOS
import SwiftUI

@main
class AppDelegate: FlutterAppDelegate {
  static var nativeChannel: FlutterMethodChannel?
  static var current: AppDelegate?
  private var statusItem: NSStatusItem?
  private var menuTasks: [[String: String]] = []
  private var menuAnniversaries: [[String: String]] = []
  private var widgetWindow: NSWindow?
  private var widgetHost: NSHostingView<CompactWidgetContent>?

  override init() {
    super.init()
    Self.current = self
  }

  override func applicationDidFinishLaunching(_ notification: Notification) {
    super.applicationDidFinishLaunching(notification)
    Self.current = self
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    item.button?.title = "序"
    statusItem = item
    rebuildMenu()
  }

  func setMenuContent(tasks: [[String: String]], anniversaries: [[String: String]]) {
    menuTasks = tasks
    menuAnniversaries = anniversaries
    if let running = tasks.first(where: { $0["status"] == "inProgress" }) {
      statusItem?.button?.title = "▶ \(String((running["title"] ?? "序").prefix(8)))"
    } else if let upcoming = anniversaries.first,
              let days = Int(upcoming["days"] ?? ""), days <= 7 {
      let name = String((upcoming["title"] ?? "重要日子").prefix(8))
      statusItem?.button?.title = days == 0 ? "\(name) 今天" : "\(name) \(days)天"
    } else {
      statusItem?.button?.title = "序"
    }
    rebuildMenu()
    widgetHost?.rootView = compactWidgetContent()
  }

  private func rebuildMenu() {
    guard let item = statusItem else { return }
    let menu = NSMenu()
    let heading = NSMenuItem(title: "今天的计划 · 待处理 \(menuTasks.count) 项", action: nil, keyEquivalent: "")
    heading.isEnabled = false
    menu.addItem(heading)
    menu.addItem(.separator())
    for (index, task) in menuTasks.prefix(8).enumerated() {
      let entry = NSMenuItem(title: "\(task["status"] == "inProgress" ? "▶" : "○") \(String((task["title"] ?? "事项").prefix(36)))", action: nil, keyEquivalent: "")
      entry.tag = index
      entry.target = self
      let submenu = NSMenu()
      let complete = NSMenuItem(title: "完成任务", action: #selector(completeTask(_:)), keyEquivalent: "")
      complete.tag = index
      complete.target = self
      complete.isEnabled = task["canRun"] == "true"
      submenu.addItem(complete)
      if task["status"] != "inProgress" {
        let start = NSMenuItem(title: "开始任务", action: #selector(startTask(_:)), keyEquivalent: "")
        start.tag = index
        start.target = self
        start.isEnabled = task["canRun"] == "true"
        submenu.addItem(start)
      }
      let cancel = NSMenuItem(title: "取消任务（无需完成）", action: #selector(cancelTask(_:)), keyEquivalent: "")
      cancel.tag = index
      cancel.target = self
      submenu.addItem(cancel)
      entry.submenu = submenu
      menu.addItem(entry)
    }
    if menuTasks.isEmpty {
      let empty = NSMenuItem(title: "今天的待办已处理完毕。🎉", action: nil, keyEquivalent: "")
      empty.isEnabled = false
      menu.addItem(empty)
    }
    if !menuTasks.isEmpty { menu.addItem(.separator()) }
    if !menuAnniversaries.isEmpty {
      let heading = NSMenuItem(title: "即将到来的纪念日", action: nil, keyEquivalent: "")
      heading.isEnabled = false
      menu.addItem(heading)
      for anniversary in menuAnniversaries.prefix(5) {
        let days = Int(anniversary["days"] ?? "") ?? 0
        let countdown = days == 0 ? "今天" : "还有 \(days) 天"
        let name = String((anniversary["title"] ?? "重要日子").prefix(32))
        let title = "\(name) · \(anniversary["date"] ?? "") · \(countdown)"
        let entry = NSMenuItem(title: title, action: #selector(openAnniversaries), keyEquivalent: "")
        entry.target = self
        menu.addItem(entry)
      }
      menu.addItem(.separator())
    }
    let add = NSMenuItem(title: "添加事项", action: #selector(addTask), keyEquivalent: "n")
    add.keyEquivalentModifierMask = .command
    add.target = self
    menu.addItem(add)
    let addCompleted = NSMenuItem(title: "添加已完成事项", action: #selector(addCompletedTask), keyEquivalent: "")
    addCompleted.target = self
    menu.addItem(addCompleted)
    let addAI = NSMenuItem(title: "用 AI 添加事项", action: #selector(addAiTask), keyEquivalent: "")
    addAI.target = self
    menu.addItem(addAI)
    let palette = NSMenuItem(title: "命令面板", action: #selector(showCommandPalette), keyEquivalent: "k")
    palette.keyEquivalentModifierMask = .command
    palette.target = self
    menu.addItem(palette)
    let open = NSMenuItem(title: "打开序", action: #selector(openMain), keyEquivalent: "")
    open.target = self
    menu.addItem(open)
    let widget = NSMenuItem(title: "打开桌面小组件", action: #selector(openWidget), keyEquivalent: "")
    widget.target = self
    menu.addItem(widget)
    let settings = NSMenuItem(title: "应用设置", action: #selector(openSettings), keyEquivalent: ",")
    settings.keyEquivalentModifierMask = .command
    settings.target = self
    menu.addItem(settings)
    menu.addItem(.separator())
    let quit = NSMenuItem(title: "退出序", action: #selector(quitApp), keyEquivalent: "q")
    quit.target = self
    menu.addItem(quit)
    item.menu = menu
  }

  @objc private func toggleTask(_ sender: NSMenuItem) {
    guard sender.tag < menuTasks.count, let id = menuTasks[sender.tag]["id"] else { return }
    Self.nativeChannel?.invokeMethod("toggleTask", arguments: id)
  }

  @objc private func startTask(_ sender: NSMenuItem) { sendTaskAction("startTask", sender) }
  @objc private func completeTask(_ sender: NSMenuItem) { sendTaskAction("completeTask", sender) }
  @objc private func cancelTask(_ sender: NSMenuItem) { sendTaskAction("cancelTask", sender) }
  private func sendTaskAction(_ action: String, _ sender: NSMenuItem) {
    guard sender.tag >= 0, sender.tag < menuTasks.count, let id = menuTasks[sender.tag]["id"] else { return }
    Self.nativeChannel?.invokeMethod(action, arguments: id)
  }

  @objc private func addTask() {
    openMain()
    Self.nativeChannel?.invokeMethod("addTask", arguments: nil)
  }
  @objc private func addCompletedTask() { openMain(); Self.nativeChannel?.invokeMethod("addCompletedTask", arguments: nil) }
  @objc private func addAiTask() { openMain(); Self.nativeChannel?.invokeMethod("addAiTask", arguments: nil) }
  @objc private func showCommandPalette() { openMain(); Self.nativeChannel?.invokeMethod("showCommandPalette", arguments: nil) }
  @objc private func openSettings() { openMain(); Self.nativeChannel?.invokeMethod("showSettings", arguments: nil) }
  @objc private func openAnniversaries() {
    openMain()
    Self.nativeChannel?.invokeMethod("showAnniversaries", arguments: nil)
  }
  func showWidget() {
    if widgetWindow == nil {
      let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 330, height: 300),
                            styleMask: [.titled, .closable, .miniaturizable],
                            backing: .buffered, defer: false)
      window.title = "序小组件"
      window.isReleasedWhenClosed = false
      window.minSize = NSSize(width: 300, height: 260)
      let host = NSHostingView(rootView: compactWidgetContent())
      window.contentView = host
      window.center()
      widgetHost = host
      widgetWindow = window
    }
    NSApp.activate(ignoringOtherApps: true)
    widgetWindow?.makeKeyAndOrderFront(nil)
  }
  var widgetVisible: Bool { widgetWindow?.isVisible == true }
  @objc private func openWidget() { showWidget() }
  private func compactWidgetContent() -> CompactWidgetContent {
    CompactWidgetContent(tasks: menuTasks, anniversaries: menuAnniversaries,
      openMain: { [weak self] in self?.openMain() },
      startTask: { id in Self.nativeChannel?.invokeMethod("startTask", arguments: id) },
      completeTask: { id in Self.nativeChannel?.invokeMethod("completeTask", arguments: id) })
  }
  @objc private func openMain() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first(where: { $0 is MainFlutterWindow })?.makeKeyAndOrderFront(nil)
  }
  @objc private func quitApp() { NSApp.terminate(nil) }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}

private struct CompactWidgetContent: View {
  let tasks: [[String: String]]
  let anniversaries: [[String: String]]
  let openMain: () -> Void
  let startTask: (String) -> Void
  let completeTask: (String) -> Void

  private var current: [String: String]? {
    tasks.first(where: { $0["status"] == "inProgress" }) ?? tasks.first
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text("序").font(.title2.bold())
        Spacer()
        Button(action: openMain) { Image(systemName: "arrow.up.right.square") }
          .help("打开主界面")
      }
      if let task = current, let id = task["id"] {
        VStack(alignment: .leading, spacing: 8) {
          Text(task["status"] == "inProgress" ? "正在执行" : "下一项")
            .font(.caption).foregroundStyle(.secondary)
          Text(task["title"] ?? "事项").font(.headline).lineLimit(2)
          if task["status"] == "inProgress", let raw = task["startedAt"],
             let start = ISO8601DateFormatter().date(from: raw) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
              let seconds = max(0, Int(context.date.timeIntervalSince(start)))
              Text(String(format: "%02d:%02d:%02d", seconds / 3600,
                          seconds % 3600 / 60, seconds % 60))
                .font(.title.monospacedDigit().bold())
            }
          }
          HStack {
            if task["status"] != "inProgress" {
              Button("开始") { startTask(id) }
                .disabled(task["canRun"] != "true")
            }
            Button("完成") { completeTask(id) }
              .disabled(task["canRun"] != "true")
              .buttonStyle(.borderedProminent)
          }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 12))
      } else {
        Label("今日已清空", systemImage: "checkmark.circle")
          .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
      if let anniversary = anniversaries.first {
        Divider()
        HStack {
          Image(systemName: "calendar.badge.clock")
          Text(anniversary["title"] ?? "重要日子").lineLimit(1)
          Spacer()
          let days = Int(anniversary["days"] ?? "") ?? 0
          Text(days == 0 ? "今天" : "\(days) 天").monospacedDigit()
        }
        .font(.caption)
      }
      Spacer(minLength: 0)
    }
    .padding(18)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
  }
}
