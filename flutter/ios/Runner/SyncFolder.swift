import Flutter
import UIKit
import UniformTypeIdentifiers

final class SyncFolder: NSObject, UIDocumentPickerDelegate {
  private static let fileName = "xu-workspace-v1.json"
  private static let recoveryName = "xu-workspace-v1.recovery.json"
  private let queue = DispatchQueue(label: "com.xu.sequence.mobile.sync-folder")
  private var pending: FlutterResult?
  private var selected: URL?

  func select(_ result: @escaping FlutterResult) {
    guard pending == nil else {
      result(error("请先完成当前的文件夹选择"))
      return
    }
    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
      .first { $0.activationState == .foregroundActive }
    guard var presenter = scene?.windows.first(where: { $0.isKeyWindow })?.rootViewController
    else {
      result(error("无法打开系统文件选择器"))
      return
    }
    while let presented = presenter.presentedViewController { presenter = presented }
    pending = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
    picker.delegate = self
    picker.directoryURL = selected
    presenter.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    let result = pending
    pending = nil
    guard let folder = urls.first else { result?(nil); return }
    guard folder.startAccessingSecurityScopedResource() else {
      result?(error("文件夹访问权限不可用"))
      return
    }
    defer { folder.stopAccessingSecurityScopedResource() }
    do {
      let bookmark = try folder.bookmarkData(options: .minimalBookmark)
      selected = folder
      result?(["path": folder.absoluteString, "bookmark": bookmark.base64EncodedString()])
    } catch {
      result?(self.error(error.localizedDescription))
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    let result = pending
    pending = nil
    result?(nil)
  }

  func restore(_ bookmark: String?, result: FlutterResult) {
    guard let bookmark, let bytes = Data(base64Encoded: bookmark) else {
      result(error("文件夹书签无效"))
      return
    }
    var stale = false
    do {
      let folder = try URL(
        resolvingBookmarkData: bytes, options: .withoutUI, relativeTo: nil, bookmarkDataIsStale: &stale
      )
      guard !stale, folder.startAccessingSecurityScopedResource() else {
        result(error("文件夹授权已失效，请重新选择"))
        return
      }
      folder.stopAccessingSecurityScopedResource()
      selected = folder
      result(folder.absoluteString)
    } catch {
      result(self.error(error.localizedDescription))
    }
  }

  func read(_ key: String?, result: @escaping FlutterResult) {
    access(key, write: false, result: result) { folder in
      try self.contents(folder)
    }
  }

  func write(_ args: [String: Any], result: @escaping FlutterResult) {
    guard let content = args["content"] as? String else {
      result(error("同步内容无效"))
      return
    }
    access(args["folder"] as? String, write: true, result: result) { folder in
      guard try self.contents(folder) == args["previous"] as? String else {
        throw NSError(domain: "XuSync", code: 1, userInfo: [
          NSLocalizedDescriptionKey: "同步文件已被更新，请重新同步",
        ])
      }
      try Data(content.utf8).write(to: folder.appendingPathComponent(Self.fileName), options: .atomic)
      return nil
    }
  }

  private func contents(_ folder: URL) throws -> String? {
    if let current = try readFile(folder.appendingPathComponent(Self.fileName)) {
      return current
    }
    return try readFile(folder.appendingPathComponent(Self.recoveryName))
  }

  private func readFile(_ file: URL) throws -> String? {
    do {
      return try String(contentsOf: file, encoding: .utf8)
    } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
      return nil
    }
  }

  private func access(
    _ key: String?, write: Bool, result: @escaping FlutterResult,
    body: @escaping (URL) throws -> Any?
  ) {
    guard let folder = selected, folder.absoluteString == key else {
      result(error("文件夹授权已失效，请重新选择"))
      return
    }
    queue.async {
      guard folder.startAccessingSecurityScopedResource() else {
        result(self.error("文件夹访问权限不可用"))
        return
      }
      defer { folder.stopAccessingSecurityScopedResource() }
      let coordinator = NSFileCoordinator()
      var coordinationError: NSError?
      var outcome: Result<Any?, Error>?
      let run: (URL) -> Void = { url in outcome = Result { try body(url) } }
      if write {
        coordinator.coordinate(writingItemAt: folder, options: [], error: &coordinationError, byAccessor: run)
      } else {
        coordinator.coordinate(readingItemAt: folder, options: [], error: &coordinationError, byAccessor: run)
      }
      switch outcome {
      case .success(let value):
        result(value)
      case .failure(let error):
        result(self.error(error.localizedDescription))
      case nil:
        result(self.error(coordinationError?.localizedDescription ?? "无法访问同步文件夹"))
      }
    }
  }

  private func error(_ message: String) -> FlutterError {
    FlutterError(code: "sync", message: message, details: nil)
  }
}
