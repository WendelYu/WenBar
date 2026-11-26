import XCTest
@testable import WenBarCore

final class DiskCleanerTests: XCTestCase {
    func testSafetyGuardBlocksProtectedAndTimeMachineVolumes() {
        let rootVol = VolumeDescriptor(
            name: "Macintosh HD",
            mountPoint: URL(fileURLWithPath: "/"),
            fileSystemType: "APFS",
            totalBytes: 500_000,
            availableBytes: 100_000,
            isExternal: false,
            isRemovable: false,
            isEjectable: false,
            isReadOnly: false,
            isInternal: true,
            isTimeMachine: false
        )
        if case .failure(.systemVolume) = DiskSafetyGuard.validateForCleanup(rootVol) {} else {
            XCTFail("Expected .systemVolume rejection")
        }

        let tmVol = VolumeDescriptor(
            name: "Time Machine",
            mountPoint: URL(fileURLWithPath: "/Volumes/TM"),
            fileSystemType: "APFS",
            totalBytes: 2_000_000,
            availableBytes: 500_000,
            isExternal: true,
            isRemovable: true,
            isEjectable: true,
            isReadOnly: false,
            isInternal: false,
            isTimeMachine: true
        )
        if case .failure(.timeMachineBackup) = DiskSafetyGuard.validateForCleanup(tmVol) {} else {
            XCTFail("Expected .timeMachineBackup rejection")
        }

        let roVol = VolumeDescriptor(
            name: "Installer",
            mountPoint: URL(fileURLWithPath: "/Volumes/Installer"),
            fileSystemType: "HFS+",
            totalBytes: 1_000_000,
            availableBytes: 0,
            isExternal: true,
            isRemovable: true,
            isEjectable: true,
            isReadOnly: true,
            isInternal: false,
            isTimeMachine: false
        )
        if case .failure(.readOnlyVolume) = DiskSafetyGuard.validateForCleanup(roVol) {} else {
            XCTFail("Expected .readOnlyVolume rejection")
        }

        let usbVol = VolumeDescriptor(
            name: "MY_USB",
            mountPoint: URL(fileURLWithPath: "/Volumes/MY_USB"),
            fileSystemType: "ExFAT",
            totalBytes: 64_000_000,
            availableBytes: 32_000_000,
            isExternal: true,
            isRemovable: true,
            isEjectable: true,
            isReadOnly: false,
            isInternal: false,
            isTimeMachine: false
        )
        if case .success = DiskSafetyGuard.validateForCleanup(usbVol) {} else {
            XCTFail("Expected USB volume to be allowed")
        }
    }

    func testJunkFileCleanerDeletesJunkWithoutFollowingSymlinks() throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("WenBarCleanerTest-\(UUID().uuidString)", isDirectory: true)
        let targetDir = base.appendingPathComponent("Drive", isDirectory: true)
        let subDir = targetDir.appendingPathComponent("Docs", isDirectory: true)
        let outsideDir = base.appendingPathComponent("Outside", isDirectory: true)

        try fm.createDirectory(at: subDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: outsideDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base) }

        // Junk files inside targetDir
        let ds1 = targetDir.appendingPathComponent(".DS_Store")
        let ds2 = subDir.appendingPathComponent(".DS_Store")
        let ad1 = subDir.appendingPathComponent("._notes.txt")
        let spotlight = targetDir.appendingPathComponent(".Spotlight-V100", isDirectory: true)
        try fm.createDirectory(at: spotlight, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: spotlight.appendingPathComponent("store.db"))
        try Data("ds".utf8).write(to: ds1)
        try Data("ds2".utf8).write(to: ds2)
        try Data("ad".utf8).write(to: ad1)

        // Normal file that must survive
        let keepFile = subDir.appendingPathComponent("report.pdf")
        try Data("important".utf8).write(to: keepFile)

        // Outside file linked via symlink inside targetDir — MUST NOT BE DELETED
        let outsideDS = outsideDir.appendingPathComponent(".DS_Store")
        try Data("outside".utf8).write(to: outsideDS)
        let linkURL = targetDir.appendingPathComponent("LinkToOutside")
        try fm.createSymbolicLink(at: linkURL, withDestinationURL: outsideDir)

        let report = JunkFileCleaner.clean(
            rootDirectory: targetDir,
            rules: [.dsStore, .appleDouble, .spotlight]
        )

        XCTAssertEqual(report.removedCount, 4)
        XCTAssertTrue(report.failures.isEmpty)
        XCTAssertFalse(fm.fileExists(atPath: ds1.path))
        XCTAssertFalse(fm.fileExists(atPath: ds2.path))
        XCTAssertFalse(fm.fileExists(atPath: ad1.path))
        XCTAssertFalse(fm.fileExists(atPath: spotlight.path))
        XCTAssertTrue(fm.fileExists(atPath: keepFile.path))
        XCTAssertTrue(fm.fileExists(atPath: outsideDS.path), "Symlink target must never be traversed or cleaned")
    }

    func testLsofParser() {
        let sample = """
        COMMAND   PID USER   FD   TYPE DEVICE SIZE/OFF NODE NAME
        Finder    512 ven    12r   DIR    1,9      512    2 /Volumes/USB
        zsh      1400 ven   cwd    DIR    1,9      512    2 /Volumes/USB/work
        zsh      1400 ven   10r   REG    1,9     1024    9 /Volumes/USB/a.txt
        """
        let procs = LsofParser.parseStandardOutput(sample)
        XCTAssertEqual(procs.count, 2)
        XCTAssertEqual(procs[0], OccupyingProcess(pid: 512, command: "Finder", user: "ven"))
        XCTAssertEqual(procs[1], OccupyingProcess(pid: 1400, command: "zsh", user: "ven"))
    }
}
