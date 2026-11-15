import Cocoa
import FlutterMacOS
import Security
import UserNotifications
import EventKit

class MainFlutterWindow: NSWindow {
  private let eventStore = EKEventStore()
  private var syncFolderAccess: URL?
  override func awakeFromNib() {
    styleMask.insert(.fullSizeContentView)
    titlebarAppearsTransparent = true
    titleVisibility = .hidden
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    contentViewController = flutterViewController
    setFrame(windowFrame, display: true)
    minSize = NSSize(width: 900, height: 620)
    let channel = FlutterMethodChannel(name: "com.xu.sequence/native", binaryMessenger: flutterViewController.engine.binaryMessenger)
    AppDelegate.nativeChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "appVersion":
        result(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0")
      case "openReleasePage":
        guard let text = call.arguments as? String,
              text.hasPrefix("https://github.com/adolphJane/Xu/releases/tag/v"),
              let url = URL(string: text) else { result(false); return }
        result(NSWorkspace.shared.open(url))
      case "openVerifiedUpdate":
        guard let path = call.arguments as? String,
              path.hasSuffix(".dmg"),
              FileManager.default.fileExists(atPath: path) else {
          result(FlutterError(code: "update", message: "更新包不存在或格式无效", details: nil)); return
        }
        result(NSWorkspace.shared.open(URL(fileURLWithPath: path)))
      case "updateMenu":
        let content = call.arguments as? [String: Any] ?? [:]
        AppDelegate.current?.setMenuContent(
          tasks: content["tasks"] as? [[String: String]] ?? [],
          anniversaries: content["anniversaries"] as? [[String: String]] ?? [])
        result(true)
      case "openWidget":
        guard let delegate = AppDelegate.current else {
          result(FlutterError(code: "widget", message: "应用窗口控制器不可用", details: nil)); return
        }
        delegate.showWidget()
        result(delegate.widgetVisible)
      case "selectSyncFolder":
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.beginSheetModal(for: self) { response in
          guard response == .OK, let url = panel.url else { result(nil); return }
          do {
            let bookmark = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
            self.syncFolderAccess?.stopAccessingSecurityScopedResource()
            guard url.startAccessingSecurityScopedResource() else {
              result(FlutterError(code: "sync", message: "无法获取文件夹访问权限", details: nil)); return
            }
            self.syncFolderAccess = url
            result(["path": url.path, "bookmark": bookmark.base64EncodedString()])
          } catch { result(FlutterError(code: "sync", message: error.localizedDescription, details: nil)) }
        }
      case "restoreSyncFolder":
        guard let encoded = call.arguments as? String, let data = Data(base64Encoded: encoded) else {
          result(FlutterError(code: "sync", message: "同步文件夹授权无效", details: nil)); return
        }
        do {
          var stale = false
          let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
          guard !stale, url.startAccessingSecurityScopedResource() else {
            result(FlutterError(code: "sync", message: "同步文件夹授权已失效，请重新选择", details: nil)); return
          }
          self.syncFolderAccess?.stopAccessingSecurityScopedResource()
          self.syncFolderAccess = url
          result(url.path)
        } catch { result(FlutterError(code: "sync", message: error.localizedDescription, details: nil)) }
      case "dailyReviewNotification":
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["xu.daily-review"])
        guard let options = call.arguments as? [String: Any], options["enabled"] as? Bool == true else { result(true); return }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          if let error = error { result(FlutterError(code: "notifications", message: error.localizedDescription, details: nil)); return }
          guard granted else { result(false); return }
          let content = UNMutableNotificationContent()
          content.title = "每日复盘"
          content.body = "回顾今天完成的事项并整理日报。"
          content.sound = .default
          var date = DateComponents()
          date.hour = options["hour"] as? Int ?? 18
          date.minute = 0
          let request = UNNotificationRequest(identifier: "xu.daily-review", content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: true))
          center.add(request) { error in
            if let error = error { result(FlutterError(code: "notifications", message: error.localizedDescription, details: nil)) }
            else { result(true) }
          }
        }
      case "anniversaryNotification":
        guard let options = call.arguments as? [String: Any], let id = options["id"] as? String else {
          result(FlutterError(code: "anniversary", message: "纪念日参数无效", details: nil)); return
        }
        let center = UNUserNotificationCenter.current()
        let identifier = "xu.anniversary.\(id)"
        center.removePendingNotificationRequests(withIdentifiers: [identifier])
        guard options["enabled"] as? Bool == true else { result(true); return }
        guard let year = options["year"] as? Int, let month = options["month"] as? Int, let day = options["day"] as? Int else {
          result(FlutterError(code: "anniversary", message: "纪念日日期无效", details: nil)); return
        }
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
          if let error = error { result(FlutterError(code: "anniversary", message: error.localizedDescription, details: nil)); return }
          guard granted else { result(false); return }
          let content = UNMutableNotificationContent()
          let reminderDays = max(0, min(365, options["reminderDays"] as? Int ?? 0))
          let privateName = options["privacyMode"] as? Bool == true
          content.title = privateName ? "重要日子即将到来" : "\(options["title"] as? String ?? "纪念日")即将到来"
          content.body = privateName ? "打开“序”查看倒计时和准备事项。" : "还有 \(reminderDays) 天，记得提前准备。"
          content.sound = .default
          var reference = Calendar.current.startOfDay(for: Date())
          var fireDate: Date?
          for _ in 0..<2 {
            guard let occurrence = self.anniversaryOccurrence(year: year, month: month, day: day,
                lunar: options["lunar"] as? Bool == true, yearly: options["repeatYearly"] as? Bool == true,
                from: reference),
                  let reminderDay = Calendar.current.date(byAdding: .day, value: -reminderDays, to: occurrence),
                  let candidate = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: reminderDay) else { break }
            if candidate > Date() { fireDate = candidate; break }
            guard let next = Calendar.current.date(byAdding: .day, value: 1, to: occurrence) else { break }
            reference = next
          }
          guard let fireDate else { result(true); return }
          let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
          let request = UNNotificationRequest(identifier: identifier, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
          center.add(request) { error in
            if let error = error { result(FlutterError(code: "anniversary", message: error.localizedDescription, details: nil)) }
            else { result(true) }
          }
        }
      case "anniversaryNextOccurrence":
        guard let options = call.arguments as? [String: Any], let year = options["year"] as? Int,
              let month = options["month"] as? Int, let day = options["day"] as? Int else {
          result(FlutterError(code: "anniversary", message: "纪念日日期无效", details: nil)); return
        }
        let next = self.anniversaryOccurrence(year: year, month: month, day: day,
            lunar: options["lunar"] as? Bool == true, yearly: options["repeatYearly"] as? Bool == true)
        result(next.map { ISO8601DateFormatter().string(from: $0) })
      case "calendarEvents":
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let arguments = call.arguments as? [String: String],
              let startText = arguments["start"], let endText = arguments["end"],
              let start = formatter.date(from: startText),
              let end = formatter.date(from: endText) else {
          result(FlutterError(code: "calendar", message: "日期范围无效", details: nil)); return
        }
        self.eventStore.requestFullAccessToEvents { granted, error in
          if let error = error { result(FlutterError(code: "calendar", message: error.localizedDescription, details: nil)); return }
          guard granted else { result(FlutterError(code: "calendar", message: "未获得日历访问权限", details: nil)); return }
          let predicate = self.eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
          let events = self.eventStore.events(matching: predicate).map { event in
            ["id": event.eventIdentifier ?? "", "title": event.title ?? "", "start": formatter.string(from: event.startDate), "end": formatter.string(from: event.endDate), "calendarTitle": event.calendar.title, "isAllDay": event.isAllDay, "isBusy": event.availability != .free] as [String: Any]
          }
          result(events)
        }
      case "calendarCreate":
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let arguments = call.arguments as? [String: Any],
              let title = arguments["title"] as? String,
              let startText = arguments["start"] as? String,
              let start = formatter.date(from: startText) else {
          result(FlutterError(code: "calendar", message: "日历事项参数无效", details: nil)); return
        }
        self.eventStore.requestFullAccessToEvents { granted, error in
          if let error = error { result(FlutterError(code: "calendar", message: error.localizedDescription, details: nil)); return }
          guard granted else { result(FlutterError(code: "calendar", message: "未获得日历访问权限", details: nil)); return }
          let existingID = arguments["eventID"] as? String
          let event: EKEvent
          if let existingID, !existingID.isEmpty {
            guard let stored = self.eventStore.event(withIdentifier: existingID) else {
              result(FlutterError(code: "calendarMissing", message: "原日历事件不存在", details: nil)); return
            }
            event = stored
          } else {
            guard let calendar = self.eventStore.defaultCalendarForNewEvents else { result(FlutterError(code: "calendar", message: "没有可写入的系统日历", details: nil)); return }
            event = EKEvent(eventStore: self.eventStore)
            event.calendar = calendar
          }
          event.title = title
          event.startDate = start
          event.endDate = start.addingTimeInterval(TimeInterval(max(1, arguments["minutes"] as? Int ?? 30) * 60))
          do { try self.eventStore.save(event, span: .thisEvent); result(event.eventIdentifier) }
          catch { result(FlutterError(code: "calendar", message: error.localizedDescription, details: nil)) }
        }
      case "calendarDelete":
        guard let eventID = call.arguments as? String, !eventID.isEmpty else {
          result(FlutterError(code: "calendar", message: "日历事件 ID 无效", details: nil)); return
        }
        self.eventStore.requestFullAccessToEvents { granted, error in
          if let error = error { result(FlutterError(code: "calendar", message: error.localizedDescription, details: nil)); return }
          guard granted else { result(FlutterError(code: "calendar", message: "未获得日历访问权限", details: nil)); return }
          guard let event = self.eventStore.event(withIdentifier: eventID) else { result(true); return }
          do { try self.eventStore.remove(event, span: .thisEvent); result(true) }
          catch { result(FlutterError(code: "calendar", message: error.localizedDescription, details: nil)) }
        }
      case "keychainRead":
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.xu.sequence.flutter",
          kSecAttrAccount as String: "deepseek-api-key",
          kSecReturnData as String: true,
          kSecMatchLimit as String: kSecMatchLimitOne]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data { result(String(data: data, encoding: .utf8)) }
        else { result(nil) }
      case "keychainWrite":
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: "com.xu.sequence.flutter",
          kSecAttrAccount as String: "deepseek-api-key"]
        SecItemDelete(query as CFDictionary)
        if let value = call.arguments as? String, !value.isEmpty {
          var add = query
          add[kSecValueData as String] = Data(value.utf8)
          let status = SecItemAdd(add as CFDictionary, nil)
          result(status == errSecSuccess)
        } else { result(true) }
      default: result(FlutterMethodNotImplemented)
      }
    }
    RegisterGeneratedPlugins(registry: flutterViewController)
    super.awakeFromNib()
  }

  private func anniversaryOccurrence(year: Int, month: Int, day: Int, lunar: Bool, yearly: Bool,
                                     from reference: Date = Date()) -> Date? {
    let solar = Calendar.current
    guard let source = solar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
    let sourceParts = solar.dateComponents([.year, .month, .day], from: source)
    guard sourceParts.year == year && sourceParts.month == month && sourceParts.day == day else { return nil }
    let today = solar.startOfDay(for: reference)
    if !yearly { return source >= today ? source : nil }
    if !lunar {
      let currentYear = solar.component(.year, from: today)
      for targetYear in currentYear...(currentYear + 4) {
        if let candidate = solar.date(from: DateComponents(year: targetYear, month: month, day: day)),
           solar.component(.month, from: candidate) == month && solar.component(.day, from: candidate) == day,
           candidate >= today {
          return candidate
        }
      }
      return nil
    }
    var chinese = Calendar(identifier: .chinese)
    chinese.timeZone = solar.timeZone
    let target = chinese.dateComponents([.month, .day, .isLeapMonth], from: source)
    // 闰月可能相隔多年；覆盖完整的十九年农历周期。
    guard let horizon = solar.date(byAdding: .year, value: 20, to: today) else { return nil }
    var cursor = today
    while cursor <= horizon {
      let components = chinese.dateComponents([.month, .day, .isLeapMonth], from: cursor)
      if components.month == target.month && components.day == target.day &&
         (components.isLeapMonth ?? false) == (target.isLeapMonth ?? false) { return cursor }
      guard let next = solar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }
    return nil
  }
}
