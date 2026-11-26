import XCTest
@testable import WenBarCore

final class UpdatePlannerTests: XCTestCase {
    func testSemanticVersionComparison() {
        XCTAssertTrue(SemanticVersion("v1.2.0")! > SemanticVersion("1.1.9")!)
        XCTAssertTrue(SemanticVersion("1.0.1")! > SemanticVersion("1.0")!)
        XCTAssertEqual(SemanticVersion("v1.0.0"), SemanticVersion("1.0"))
        XCTAssertFalse(ReleaseUpdatePlanner.isNewer(remoteTag: "v1.0.0", currentVersion: "1.0.0"))
        XCTAssertTrue(ReleaseUpdatePlanner.isNewer(remoteTag: "v1.0.1", currentVersion: "1.0.0"))
        XCTAssertTrue(ReleaseUpdatePlanner.isNewer(remoteTag: "v1.2.0-beta.1", currentVersion: "1.1.0"))
    }

    func testSelectBestAssetPrefersZipThenDmg() {
        let dmg = GitHubReleaseAsset(
            name: "WenBar-1.1.0.dmg",
            browserDownloadURL: URL(string: "https://example.com/WenBar-1.1.0.dmg")!,
            size: 100
        )
        let zip = GitHubReleaseAsset(
            name: "WenBar-1.1.0.zip",
            browserDownloadURL: URL(string: "https://example.com/WenBar-1.1.0.zip")!,
            size: 90
        )
        let notes = GitHubReleaseAsset(
            name: "checksums.txt",
            browserDownloadURL: URL(string: "https://example.com/checksums.txt")!,
            size: 10
        )

        XCTAssertEqual(ReleaseUpdatePlanner.selectBestAsset(from: [notes, dmg, zip]), zip)
        XCTAssertEqual(ReleaseUpdatePlanner.selectBestAsset(from: [notes, dmg]), dmg)
        XCTAssertNil(ReleaseUpdatePlanner.selectBestAsset(from: [notes]))
    }

    func testBuildInstallScriptQuotesPathsSafely() {
        let script = ReleaseUpdatePlanner.buildInstallScript(
            oldPID: 1234,
            stagedAppPath: "/tmp/WenBar Stage/WenBar.app",
            targetAppPath: "/Applications/WenBar.app",
            stagingRoot: "/tmp/WenBar Stage"
        )
        XCTAssertTrue(script.contains("OLD_PID=1234"))
        XCTAssertTrue(script.contains("'/tmp/WenBar Stage/WenBar.app'"))
        XCTAssertTrue(script.contains("'/Applications/WenBar.app'"))
        XCTAssertTrue(script.contains("xattr -dr com.apple.quarantine"))
        XCTAssertTrue(script.contains("pluginkit -e use -i com.wenbar.app.FinderSync"))
        XCTAssertTrue(script.contains("/usr/bin/open -n \"$TARGET\""))
    }
}
