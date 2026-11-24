import EventKit
import Flutter
import Security
import UIKit
import UserNotifications

final class MobileBridge {
  private lazy var events = EKEventStore()
  private let sync = SyncFolder()
  private let keyQuery: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: "com.xu.sequence.mobile",
    kSecAttrAccount as String: "deepseek-api-key",
  ]

  func register(messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "com.xu.sequence/native", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else { result(FlutterMethodNotImplemented); return }
      self.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let options = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "appVersion":
      result(Bundle.main.infoDictionary?["CFBundleShortVersionString"])
    case "readClipboardImage":
      result(UIPasteboard.general.image?.pngData().map { FlutterStandardTypedData(bytes: $0) })
    case "selectSyncFolder":
      sync.select(result)
    case "restoreSyncFolder":
      sync.restore(call.arguments as? String, result: result)
    case "readSyncDocument":
      sync.read(call.arguments as? String, result: result)
    case "writeSyncDocument":
      sync.write(options, result: result)
    case "keychainRead":
      readKey(result)
    case "keychainWrite":
      guard let value = call.arguments as? String else {
        result(failure("keychain", "API Key 格式无效"))
        return
      }
      writeKey(value, result: result)
    case "anniversaryNextOccurrence":
      result(occurrence(options).map { ISO8601DateFormatter().string(from: $0) })
    case "dailyReviewNotification":
      let content = UNMutableNotificationContent()
      content.title = "每日复盘"
      content.body = "回顾今天完成的事项并整理日报。"
      let hour = min(23, max(0, options["hour"] as? Int ?? 18))
      let trigger = UNCalendarNotificationTrigger(
        dateMatching: DateComponents(hour: hour, minute: 0), repeats: true
      )
      schedule(
        "xu.daily-review", enabled: options["enabled"] as? Bool == true,
        content: content, trigger: trigger, result: result
      )
    case "anniversaryNotification":
      scheduleAnniversary(options, result: result)
    case "calendarEvents", "calendarCreate", "calendarDelete":
      handleCalendar(call, options: options, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func failure(_ code: String, _ message: String) -> FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }

  private func readKey(_ result: FlutterResult) {
    var query = keyQuery
    query[kSecReturnData as String] = true
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound {
      result(nil)
    } else if status == errSecSuccess, let data = item as? Data {
      result(String(data: data, encoding: .utf8))
    } else {
      result(failure("keychain", "无法读取 API Key"))
    }
  }

  private func writeKey(_ value: String, result: FlutterResult) {
    if value.isEmpty {
      let status = SecItemDelete(keyQuery as CFDictionary)
      result(status == errSecSuccess || status == errSecItemNotFound)
      return
    }
    let attributes: [String: Any] = [kSecValueData as String: Data(value.utf8)]
    var status = SecItemUpdate(keyQuery as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
      var item = keyQuery.merging(attributes) { _, new in new }
      item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
      status = SecItemAdd(item as CFDictionary, nil)
    }
    if status == errSecSuccess {
      result(true)
    } else {
      result(failure("keychain", "无法保存 API Key"))
    }
  }

  private func occurrence(_ options: [String: Any], from reference: Date = Date()) -> Date? {
    guard let year = options["year"] as? Int, let month = options["month"] as? Int,
          let day = options["day"] as? Int else { return nil }
    let solar = Calendar.current
    guard let source = solar.date(from: DateComponents(year: year, month: month, day: day))
    else { return nil }
    let sourceParts = solar.dateComponents([.year, .month, .day], from: source)
    guard sourceParts.year == year, sourceParts.month == month, sourceParts.day == day
    else { return nil }

    let today = solar.startOfDay(for: reference)
    guard options["repeatYearly"] as? Bool == true else {
      return source >= today ? source : nil
    }
    if options["lunar"] as? Bool != true {
      let startYear = solar.component(.year, from: today)
      for targetYear in startYear...(startYear + 8) {
        if let date = solar.date(from: DateComponents(year: targetYear, month: month, day: day)),
           solar.component(.month, from: date) == month, solar.component(.day, from: date) == day,
           date >= today {
          return date
        }
      }
      return nil
    }

    var lunar = Calendar(identifier: .chinese)
    lunar.timeZone = solar.timeZone
    let target = lunar.dateComponents([.month, .day], from: source)
    guard let horizon = solar.date(byAdding: .year, value: 20, to: today) else { return nil }
    var date = today
    while date <= horizon {
      let parts = lunar.dateComponents([.month, .day], from: date)
      if parts.month == target.month && parts.day == target.day
        && (parts.isLeapMonth ?? false) == (target.isLeapMonth ?? false) {
        return date
      }
      guard let next = solar.date(byAdding: .day, value: 1, to: date) else { break }
      date = next
    }
    return nil
  }

  private func scheduleAnniversary(_ options: [String: Any], result: @escaping FlutterResult) {
    guard let id = options["id"] as? String, !id.isEmpty else {
      result(failure("anniversary", "纪念日参数无效"))
      return
    }
    let solar = Calendar.current
    let now = Date()
    let days = max(0, min(365, options["reminderDays"] as? Int ?? 0))
    let isPrivate = options["privacyMode"] as? Bool == true
    let title = options["title"] as? String ?? "纪念日"
    let content = UNMutableNotificationContent()
    content.title = isPrivate ? "重要日子即将到来" : "\(title)即将到来"
    content.body = isPrivate ? "打开“序”查看倒计时和准备事项。" : "还有 \(days) 天，记得提前准备。"

    let enabled = options["enabled"] as? Bool == true
    var trigger: UNCalendarNotificationTrigger?
    if enabled, let reference = solar.date(byAdding: .day, value: days, to: now),
       let date = occurrence(options, from: reference),
       let reminder = solar.date(byAdding: .day, value: -days, to: date),
       let fire = solar.date(bySettingHour: 9, minute: 0, second: 0, of: reminder) {
      var nextFire: Date? = fire
      if fire <= now {
        nextFire = solar.date(byAdding: .day, value: 1, to: reference)
          .flatMap { occurrence(options, from: $0) }
          .flatMap { solar.date(byAdding: .day, value: -days, to: $0) }
          .flatMap { solar.date(bySettingHour: 9, minute: 0, second: 0, of: $0) }
      }
      if let nextFire, nextFire > now {
        let date = solar.dateComponents([.year, .month, .day, .hour, .minute], from: nextFire)
        trigger = UNCalendarNotificationTrigger(dateMatching: date, repeats: false)
      }
    }
    schedule("xu.anniversary.\(id)", enabled: enabled, content: content, trigger: trigger, result: result)
  }

  private func schedule(
    _ id: String, enabled: Bool, content: UNMutableNotificationContent,
    trigger: UNNotificationTrigger?, result: @escaping FlutterResult
  ) {
    let center = UNUserNotificationCenter.current()
    guard enabled, let trigger else {
      center.removePendingNotificationRequests(withIdentifiers: [id])
      result(true)
      return
    }
    center.requestAuthorization(options: [.alert, .sound]) { granted, error in
      if let error {
        result(self.failure("notifications", error.localizedDescription))
      } else if !granted {
        result(false)
      } else {
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: trigger)
        center.add(request) { error in
          if let error {
            result(self.failure("notifications", error.localizedDescription))
          } else {
            result(true)
          }
        }
      }
    }
  }

  private func handleCalendar(
    _ call: FlutterMethodCall, options: [String: Any], result: @escaping FlutterResult
  ) {
    let completion: (Bool, Error?) -> Void = { granted, error in
      DispatchQueue.main.async {
        guard granted else {
          result(self.failure("calendar", error?.localizedDescription ?? "未获得日历访问权限"))
          return
        }
        self.runCalendar(call, options: options, result: result)
      }
    }
    if #available(iOS 17, *) {
      events.requestFullAccessToEvents(completion: completion)
    } else {
      events.requestAccess(to: .event, completion: completion)
    }
  }

  private func runCalendar(_ call: FlutterMethodCall, options: [String: Any], result: FlutterResult) {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    switch call.method {
    case "calendarEvents":
      guard let from = options["start"] as? String, let to = options["end"] as? String,
            let start = formatter.date(from: from), let end = formatter.date(from: to), end > start
      else { result(failure("calendar", "日期范围无效")); return }

      let request = events.predicateForEvents(withStart: start, end: end, calendars: nil)
      result(events.events(matching: request).map { event -> [String: Any] in
        [
          "id": event.eventIdentifier ?? "",
          "title": event.title ?? "",
          "start": formatter.string(from: event.startDate),
          "end": formatter.string(from: event.endDate),
          "calendarTitle": event.calendar.title,
          "isAllDay": event.isAllDay,
          "isBusy": event.availability != .free,
        ]
      })
    case "calendarCreate":
      guard let title = options["title"] as? String, let value = options["start"] as? String,
            let start = formatter.date(from: value)
      else { result(failure("calendar", "日历事项参数无效")); return }

      let event: EKEvent
      if let id = options["eventID"] as? String, !id.isEmpty {
        guard let stored = events.event(withIdentifier: id) else {
          result(failure("calendarMissing", "原日历事件不存在"))
          return
        }
        event = stored
      } else {
        guard let calendar = events.defaultCalendarForNewEvents else {
          result(failure("calendar", "没有可写入的系统日历"))
          return
        }
        event = EKEvent(eventStore: events)
        event.calendar = calendar
      }
      event.title = title
      event.startDate = start
      event.endDate = start.addingTimeInterval(TimeInterval(max(1, options["minutes"] as? Int ?? 30)) * 60)
      do {
        try events.save(event, span: .thisEvent)
        result(event.eventIdentifier)
      } catch {
        result(failure("calendar", error.localizedDescription))
      }
    case "calendarDelete":
      guard let id = call.arguments as? String, !id.isEmpty else {
        result(failure("calendar", "日历事件 ID 无效"))
        return
      }
      do {
        if let event = events.event(withIdentifier: id) {
          try events.remove(event, span: .thisEvent)
        }
        result(true)
      } catch {
        result(failure("calendar", error.localizedDescription))
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
