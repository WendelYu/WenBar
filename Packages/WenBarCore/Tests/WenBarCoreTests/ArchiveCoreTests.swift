import XCTest
@testable import WenBarCore

final class ArchiveCoreTests: XCTestCase {
    func testSmartExtractSingleRootFolderVsLooseFiles() {
        let archive = URL(fileURLWithPath: "/tmp/Demo.zip")

        // Single root folder + macOS junk entries -> should NOT create extra nested subfolder
        let singleRootEntries = [
            "__MACOSX/",
            "__MACOSX/._Project",
            "Project/",
            "Project/README.md",
            "Project/.DS_Store"
        ]
        let plan1 = SmartExtractPlanner.plan(
            entries: singleRootEntries,
            archiveURL: archive,
            mode: .smart,
            existingItemsInParent: []
        )
        XCTAssertFalse(plan1.createsSubfolder)
        XCTAssertEqual(plan1.destinationDirectory.path, "/tmp")
        XCTAssertEqual(plan1.singleRootFolderName, "Project")

        // Collision on single root -> fall back to unique subfolder
        let planCollision = SmartExtractPlanner.plan(
            entries: singleRootEntries,
            archiveURL: archive,
            mode: .smart,
            existingItemsInParent: ["Project", "Demo"]
        )
        XCTAssertTrue(planCollision.createsSubfolder)
        XCTAssertEqual(planCollision.destinationDirectory.lastPathComponent, "Demo 2")

        // Multiple loose files -> create Demo subfolder
        let looseEntries = ["a.txt", "b.txt", "dir/c.txt"]
        let planLoose = SmartExtractPlanner.plan(
            entries: looseEntries,
            archiveURL: archive,
            mode: .smart,
            existingItemsInParent: []
        )
        XCTAssertTrue(planLoose.createsSubfolder)
        XCTAssertEqual(planLoose.destinationDirectory.path, "/tmp/Demo")
    }

    func testCommandBuilderExcludesMacJunk() {
        let out = URL(fileURLWithPath: "/tmp/out.zip")
        let args = ArchiveCommandBuilder.sevenZipCompressArguments(
            format: .zip,
            outputURL: out,
            inputRelativePaths: ["Folder"],
            level: .maximum,
            password: "secret"
        )
        XCTAssertTrue(args.contains("-xr!.DS_Store"))
        XCTAssertTrue(args.contains("-xr!._*"))
        XCTAssertTrue(args.contains("-xr!__MACOSX"))
        XCTAssertTrue(args.contains("-mem=AES256"))
        XCTAssertTrue(args.contains("-psecret"))
        XCTAssertTrue(args.contains("-mx=9"))
    }

    func testZipEncodingDetectorAndNormalizerFixesGBKZip() throws {
        let gbkCF = CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)
        let gbkEnc = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(gbkCF))

        let entryName = "测试目录/中文文档.txt"
        guard let gbkNameData = entryName.data(using: gbkEnc) else {
            XCTFail("Failed to encode test filename as GBK")
            return
        }
        let payload = Data("Hello WenBar".utf8)

        let rawZip = buildMinimalStoredZip(fileNameData: gbkNameData, payload: payload, utf8Flag: false)

        let detection = ZipEncodingDetector.detectEncoding(in: rawZip)
        guard case let .legacy(encodingName, _) = detection else {
            XCTFail("Expected legacy encoding detection, got \(detection)")
            return
        }
        XCTAssertEqual(encodingName, "GB18030")

        let fm = FileManager.default
        let tempDir = fm.temporaryDirectory.appendingPathComponent("WenBarZipTest-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: tempDir) }

        let srcZip = tempDir.appendingPathComponent("win_gbk.zip")
        let dstZip = tempDir.appendingPathComponent("fixed_utf8.zip")
        try rawZip.write(to: srcZip)

        let outcome = try ZipHeaderNormalizer.normalizeToUTF8IfNeeded(source: srcZip, destination: dstZip)
        guard case let .normalized(outURL, detectedName) = outcome else {
            XCTFail("Expected normalized outcome, got \(outcome)")
            return
        }
        XCTAssertEqual(detectedName, "GB18030")

        let normalizedData = try Data(contentsOf: outURL)
        XCTAssertEqual(ZipEncodingDetector.detectEncoding(in: normalizedData), .utf8OrAscii)

        // Verify Central Directory entry now contains exact UTF-8 bytes and bit 11 set
        let parsed = ZipEncodingDetector.parseCentralDirectory(in: normalizedData)
        XCTAssertEqual(parsed?.entries.count, 1)
        let rewrittenEntry = parsed!.entries[0]
        XCTAssertNotEqual(rewrittenEntry.flags & 0x0800, 0)
        XCTAssertEqual(String(data: rewrittenEntry.fileNameData, encoding: .utf8), entryName)

        // End-to-end extraction with 7zz if installed
        let sevenZipPath = "/opt/homebrew/bin/7zz"
        if FileManager.default.isExecutableFile(atPath: sevenZipPath) {
            let extractDir = tempDir.appendingPathComponent("extracted", isDirectory: true)
            try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: sevenZipPath)
            proc.arguments = ArchiveCommandBuilder.sevenZipExtractArguments(
                archiveURL: outURL,
                destinationDirectory: extractDir
            )
            try proc.run()
            proc.waitUntilExit()
            XCTAssertEqual(proc.terminationStatus, 0)

            let extractedFile = extractDir.appendingPathComponent("测试目录/中文文档.txt")
            XCTAssertTrue(fm.fileExists(atPath: extractedFile.path), "7zz should extract UTF-8 normalized Chinese path")
            let content = try String(contentsOf: extractedFile, encoding: .utf8)
            XCTAssertEqual(content, "Hello WenBar")
        }
    }

    private func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFFFFFF
        for byte in data {
            crc ^= UInt32(byte)
            for _ in 0..<8 {
                crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1)
            }
        }
        return ~crc
    }

    private func buildMinimalStoredZip(fileNameData: Data, payload: Data, utf8Flag: Bool) -> Data {
        var data = Data()
        let flags: UInt16 = utf8Flag ? 0x0800 : 0x0000
        let nameLen = UInt16(fileNameData.count)
        let size = UInt32(payload.count)
        let checksum = crc32(payload)

        // Local File Header (30 bytes + name)
        appendUInt32(0x04034b50, to: &data)
        appendUInt16(20, to: &data) // version needed
        appendUInt16(flags, to: &data)
        appendUInt16(0, to: &data) // compression: stored
        appendUInt16(0, to: &data) // mod time
        appendUInt16(0, to: &data) // mod date
        appendUInt32(checksum, to: &data)
        appendUInt32(size, to: &data)
        appendUInt32(size, to: &data)
        appendUInt16(nameLen, to: &data)
        appendUInt16(0, to: &data) // extra len
        data.append(fileNameData)
        data.append(payload)

        let cdOffset = UInt32(data.count)
        // Central Directory Header (46 bytes + name)
        appendUInt32(0x02014b50, to: &data)
        appendUInt16(20, to: &data) // version made by
        appendUInt16(20, to: &data) // version needed
        appendUInt16(flags, to: &data)
        appendUInt16(0, to: &data) // compression
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt32(checksum, to: &data)
        appendUInt32(size, to: &data)
        appendUInt32(size, to: &data)
        appendUInt16(nameLen, to: &data)
        appendUInt16(0, to: &data) // extra
        appendUInt16(0, to: &data) // comment
        appendUInt16(0, to: &data) // disk
        appendUInt16(0, to: &data) // internal attr
        appendUInt32(0, to: &data) // external attr
        appendUInt32(0, to: &data) // local header offset
        data.append(fileNameData)

        let cdSize = UInt32(data.count) - cdOffset
        // End of Central Directory (22 bytes)
        appendUInt32(0x06054b50, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(0, to: &data)
        appendUInt16(1, to: &data)
        appendUInt16(1, to: &data)
        appendUInt32(cdSize, to: &data)
        appendUInt32(cdOffset, to: &data)
        appendUInt16(0, to: &data)
        return data
    }

    private func appendUInt16(_ value: UInt16, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private func appendUInt32(_ value: UInt32, to data: inout Data) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
