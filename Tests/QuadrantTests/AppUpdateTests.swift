import XCTest
@testable import Quadrant

final class AppUpdateTests: XCTestCase {
    func testSelectsNewestVersionIncludingPrerelease() throws {
        let releases = [release("v0.5.2", prerelease: true), release("v0.5.3", prerelease: false)]
        let result = try GitHubUpdates.newerRelease(in: try JSONSerialization.data(withJSONObject: releases), than: "0.5.1")
        XCTAssertEqual(result?.version, "0.5.3")
        XCTAssertEqual(result?.sha256, String(repeating: "a", count: 64))
        XCTAssertFalse(result?.isPrerelease ?? true)
    }

    func testIgnoresCurrentVersionAndUnsafeAssets() throws {
        var wrongAsset = release("v0.5.9", prerelease: false)
        wrongAsset["assets"] = [[
            "name": "Xu-v0.5.9.dmg",
            "browser_download_url": "https://example.com/Xu-v0.5.9.dmg",
            "digest": "sha256:" + String(repeating: "b", count: 64)
        ]]
        let releases = [release("v0.5.1", prerelease: true), wrongAsset, release("v0.5.0", prerelease: true)]
        XCTAssertNil(try GitHubUpdates.newerRelease(in: JSONSerialization.data(withJSONObject: releases), than: "0.5.1"))
    }

    private func release(_ tag: String, prerelease: Bool) -> [String: Any] {
        [
            "tag_name": tag,
            "html_url": "https://github.com/adolphJane/Xu/releases/tag/\(tag)",
            "body": "更新说明",
            "draft": false,
            "prerelease": prerelease,
            "assets": [[
                "name": "Xu-\(tag).dmg",
                "browser_download_url": "https://github.com/adolphJane/Xu/releases/download/\(tag)/Xu-\(tag).dmg",
                "digest": "sha256:" + String(repeating: "a", count: 64)
            ]]
        ]
    }
}
