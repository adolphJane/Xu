import AppKit
import CryptoKit
import Foundation

enum GitHubUpdates {
    static let releasesURL = URL(string: "https://api.github.com/repos/adolphJane/Xu/releases?per_page=100")!

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String
            let digest: String?

            enum CodingKeys: String, CodingKey {
                case name, digest
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let htmlURL: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        enum CodingKeys: String, CodingKey {
            case body, draft, prerelease, assets
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    static func newerRelease(in data: Data, than installedVersion: String) throws -> UpdateManifest? {
        let releases = try JSONDecoder().decode([Release].self, from: data)
        guard let installed = versionParts(installedVersion) else { return nil }
        return releases.compactMap { release -> UpdateManifest? in
            guard !release.draft, release.tagName.hasPrefix("v"),
                  let version = versionParts(String(release.tagName.dropFirst())),
                  version.lexicographicallyPrecedes(installed) == false, version != installed else { return nil }
            let name = "Xu-\(release.tagName).dmg"
            let expectedURL = "https://github.com/adolphJane/Xu/releases/download/\(release.tagName)/\(name)"
            let expectedPage = "https://github.com/adolphJane/Xu/releases/tag/\(release.tagName)"
            guard release.htmlURL == expectedPage,
                  let asset = release.assets.first(where: { $0.name == name && $0.browserDownloadURL == expectedURL }),
                  let digest = asset.digest, digest.hasPrefix("sha256:") else { return nil }
            let checksum = String(digest.dropFirst("sha256:".count)).lowercased()
            guard checksum.count == 64, checksum.allSatisfy(\.isHexDigit) else { return nil }
            return UpdateManifest(version: String(release.tagName.dropFirst()), downloadURL: expectedURL,
                                  notes: release.body ?? "", sha256: checksum,
                                  releaseURL: expectedPage, isPrerelease: release.prerelease)
        }.max { lhs, rhs in
            versionParts(lhs.version)!.lexicographicallyPrecedes(versionParts(rhs.version)!)
        }
    }

    private static func versionParts(_ version: String) -> [Int]? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let numbers = parts.map { part -> Int? in
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
            return Int(part)
        }
        guard numbers.allSatisfy({ $0 != nil }) else { return nil }
        return numbers.compactMap { $0 }
    }
}

private enum AppUpdateInstaller {
    static func prepareAndLaunch(download: URL, update: UpdateManifest) throws -> Bool {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory.appendingPathComponent("xu-update-\(UUID().uuidString)", isDirectory: true)
        let mount = root.appendingPathComponent("mounted", isDirectory: true)
        let staged = root.appendingPathComponent("序.app", isDirectory: true)
        let dmg = root.appendingPathComponent("Xu-v\(update.version).dmg")
        try fileManager.createDirectory(at: mount, withIntermediateDirectories: true)
        do {
            try fileManager.moveItem(at: download, to: dmg)
            let bytes = try Data(contentsOf: dmg, options: .mappedIfSafe)
            let actual = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
            guard actual == update.sha256 else { throw failure("下载文件校验失败，请重试。") }

            let target = Bundle.main.bundleURL
            guard target.pathExtension == "app" else { throw failure("当前应用位置无效。") }
            guard fileManager.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
                NSWorkspace.shared.open(dmg)
                return false
            }

            try run("/usr/bin/hdiutil", ["attach", "-readonly", "-nobrowse", "-mountpoint", mount.path, dmg.path])
            defer { try? run("/usr/bin/hdiutil", ["detach", mount.path]) }
            let source = mount.appendingPathComponent("序.app", isDirectory: true)
            guard let bundle = Bundle(url: source),
                  bundle.bundleIdentifier == Bundle.main.bundleIdentifier,
                  bundle.infoDictionary?["CFBundleShortVersionString"] as? String == update.version else {
                throw failure("更新包中的应用身份或版本不匹配。")
            }
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", source.path])
            try run("/usr/bin/ditto", [source.path, staged.path])

            let script = root.appendingPathComponent("install.zsh")
            try """
            #!/bin/zsh
            set -e
            target="$1"
            staged="$2"
            dmg="$3"
            root="$4"
            parent_pid="$5"
            while kill -0 "$parent_pid" 2>/dev/null; do sleep 0.2; done
            backup="$root/previous.app"
            if ! mv "$target" "$backup"; then open "$dmg"; exit 1; fi
            if mv "$staged" "$target"; then
              open "$target"
              rm -rf "$backup" "$root"
            else
              mv "$backup" "$target"
              open "$dmg"
            fi
            """.write(to: script, atomically: true, encoding: .utf8)
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/zsh")
            process.arguments = [script.path, target.path, staged.path, dmg.path, root.path, String(ProcessInfo.processInfo.processIdentifier)]
            try process.run()
            return true
        } catch {
            try? fileManager.removeItem(at: root)
            throw error
        }
    }

    private static func run(_ path: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw failure(message.isEmpty ? "更新包处理失败。" : message)
        }
    }

    private static func failure(_ message: String) -> NSError {
        NSError(domain: "序更新", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}

extension AppPreferences {
    func checkForUpdates(notify: Bool = false) async {
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        defer { isCheckingUpdate = false }
        do {
            var request = URLRequest(url: GitHubUpdates.releasesURL)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("序/\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown")", forHTTPHeaderField: "User-Agent")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
            availableUpdate = try GitHubUpdates.newerRelease(in: data, than: current)
            updateStatus = availableUpdate.map { "发现新版本 \($0.version)。" } ?? "当前已是最新版本（\(current)）。"
            if notify, availableUpdate != nil { shouldPresentUpdatePrompt = true }
        } catch {
            updateStatus = "检查更新失败：\(error.localizedDescription)"
        }
    }

    func downloadAndInstallUpdate() async {
        guard let update = availableUpdate, !isInstallingUpdate,
              let url = URL(string: update.downloadURL) else { return }
        isInstallingUpdate = true
        defer { isInstallingUpdate = false }
        updateStatus = "正在下载版本 \(update.version)…"
        do {
            let (download, response) = try await URLSession.shared.download(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }
            updateStatus = "下载完成，正在校验并准备安装…"
            if try AppUpdateInstaller.prepareAndLaunch(download: download, update: update) {
                updateStatus = "即将安装并重新打开应用…"
                NSApp.terminate(nil)
            } else {
                updateStatus = "已打开更新磁盘映像。请将“序”拖入“应用程序”完成安装。"
            }
        } catch {
            updateStatus = "安装更新失败：\(error.localizedDescription)"
        }
    }
}
