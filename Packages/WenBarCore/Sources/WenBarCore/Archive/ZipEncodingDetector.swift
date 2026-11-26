import Foundation

public enum DetectedZipEncoding: Sendable, Equatable {
    case utf8OrAscii
    case legacy(encodingName: String, cfEncoding: UInt32)
    case unknown
}

public enum ZipNormalizationOutcome: Sendable, Equatable {
    case alreadyUTF8
    case normalized(outputURL: URL, encodingName: String)
    case unsupportedZip64
    case notAZipArchive
}

/// Inspects ZIP Central Directory headers for missing UTF-8 flags (Bit 11) and detects Windows legacy codepages.
public enum ZipEncodingDetector {
    private static let eocdSignature: UInt32 = 0x06054b50
    private static let cdSignature: UInt32 = 0x02014b50
    private static let utf8Flag: UInt16 = 0x0800

    struct CentralDirectoryEntry {
        let flags: UInt16
        let fileNameData: Data
        let cdOffset: Int
        let localHeaderOffset: Int
        let compressedSize: UInt32
        let uncompressedSize: UInt32
        let extraLen: Int
        let commentLen: Int
    }

    public static func detectEncoding(at zipURL: URL) throws -> DetectedZipEncoding {
        let data = try Data(contentsOf: zipURL, options: .mappedIfSafe)
        return detectEncoding(in: data)
    }

    public static func detectEncoding(in data: Data) -> DetectedZipEncoding {
        guard let parsed = parseCentralDirectory(in: data) else {
            return .unknown
        }

        var legacySamples: [Data] = []
        for entry in parsed.entries {
            let hasUTF8Flag = (entry.flags & utf8Flag) != 0
            let isPureASCII = entry.fileNameData.allSatisfy { $0 < 0x80 }
            if hasUTF8Flag || isPureASCII {
                continue
            }
            if String(data: entry.fileNameData, encoding: .utf8) != nil {
                continue
            }
            legacySamples.append(entry.fileNameData)
        }

        guard !legacySamples.isEmpty else {
            return .utf8OrAscii
        }

        // Candidate encodings in priority order for Chinese/East-Asian Windows ZIPs
        let candidates: [(String, CFStringEncodings)] = [
            ("GB18030", .GB_18030_2000),
            ("Big5", .big5),
            ("Shift-JIS", .shiftJIS)
        ]

        for (label, cfEnc) in candidates {
            let rawCF = CFStringEncoding(cfEnc.rawValue)
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(rawCF)
            let swiftEnc = String.Encoding(rawValue: nsEnc)

            let allValid = legacySamples.allSatisfy { sample in
                guard let decoded = String(data: sample, encoding: swiftEnc) else { return false }
                return !decoded.contains("\u{FFFD}")
            }
            if allValid {
                return .legacy(encodingName: label, cfEncoding: rawCF)
            }
        }

        return .unknown
    }

    static func parseCentralDirectory(in data: Data) -> (eocdOffset: Int, cdOffset: Int, cdSize: Int, entries: [CentralDirectoryEntry])? {
        guard data.count >= 22 else { return nil }
        let searchStart = max(0, data.count - 65557)
        var eocdOffset: Int?
        var idx = data.count - 22
        while idx >= searchStart {
            if readUInt32(data, at: idx) == eocdSignature {
                let commentLen = Int(readUInt16(data, at: idx + 20))
                if idx + 22 + commentLen == data.count {
                    eocdOffset = idx
                    break
                }
            }
            idx -= 1
        }
        guard let eocd = eocdOffset else { return nil }

        let diskEntries = readUInt16(data, at: eocd + 8)
        let totalEntries = readUInt16(data, at: eocd + 10)
        let cdSize = readUInt32(data, at: eocd + 12)
        let cdOffset = readUInt32(data, at: eocd + 16)

        if diskEntries == 0xFFFF || totalEntries == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF {
            return nil
        }

        let start = Int(cdOffset)
        let end = start + Int(cdSize)
        guard start >= 0, end <= data.count else { return nil }

        var cursor = start
        var entries: [CentralDirectoryEntry] = []
        entries.reserveCapacity(Int(totalEntries))

        while cursor + 46 <= end {
            guard readUInt32(data, at: cursor) == cdSignature else { return nil }
            let flags = readUInt16(data, at: cursor + 8)
            let compressedSize = readUInt32(data, at: cursor + 20)
            let uncompressedSize = readUInt32(data, at: cursor + 24)
            let nameLen = Int(readUInt16(data, at: cursor + 28))
            let extraLen = Int(readUInt16(data, at: cursor + 30))
            let commentLen = Int(readUInt16(data, at: cursor + 32))
            let localOffset = Int(readUInt32(data, at: cursor + 42))

            let nameStart = cursor + 46
            let nameEnd = nameStart + nameLen
            let nextRecord = nameEnd + extraLen + commentLen
            guard nextRecord <= end else { return nil }

            let nameData = data.subdata(in: nameStart..<nameEnd)
            entries.append(
                CentralDirectoryEntry(
                    flags: flags,
                    fileNameData: nameData,
                    cdOffset: cursor,
                    localHeaderOffset: localOffset,
                    compressedSize: compressedSize,
                    uncompressedSize: uncompressedSize,
                    extraLen: extraLen,
                    commentLen: commentLen
                )
            )
            cursor = nextRecord
        }

        return (eocd, start, Int(cdSize), entries)
    }

    static func readUInt16(_ data: Data, at offset: Int) -> UInt16 {
        UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    static func readUInt32(_ data: Data, at offset: Int) -> UInt32 {
        UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }
}

/// Rewrites legacy-encoded ZIP headers into UTF-8 + Bit 11 (`0x0800`) without altering compressed payloads.
public enum ZipHeaderNormalizer {
    private static let localFileHeaderSignature: UInt32 = 0x04034b50
    private static let cdSignature: UInt32 = 0x02014b50
    private static let utf8Flag: UInt16 = 0x0800

    public static func normalizeToUTF8IfNeeded(
        source: URL,
        destination: URL
    ) throws -> ZipNormalizationOutcome {
        let data = try Data(contentsOf: source)
        let detection = ZipEncodingDetector.detectEncoding(in: data)

        switch detection {
        case .utf8OrAscii:
            return .alreadyUTF8
        case .unknown:
            // Might be ZIP64 or non-ZIP
            guard ZipEncodingDetector.parseCentralDirectory(in: data) != nil else {
                return .unsupportedZip64
            }
            return .alreadyUTF8
        case let .legacy(encodingName, cfEncoding):
            let nsEnc = CFStringConvertEncodingToNSStringEncoding(cfEncoding)
            let swiftEnc = String.Encoding(rawValue: nsEnc)

            guard let parsed = ZipEncodingDetector.parseCentralDirectory(in: data) else {
                return .unsupportedZip64
            }

            // Sort entries by localHeaderOffset so we rebuild file sequentially and keep exact new offsets
            let sortedEntries = parsed.entries.sorted { $0.localHeaderOffset < $1.localHeaderOffset }
            guard !sortedEntries.isEmpty else { return .alreadyUTF8 }

            var output = Data()
            output.reserveCapacity(data.count + 512)

            struct RewrittenEntry {
                let oldEntry: ZipEncodingDetector.CentralDirectoryEntry
                let newLocalOffset: UInt32
                let newNameData: Data
                let newFlags: UInt16
            }

            var rewritten: [RewrittenEntry] = []
            rewritten.reserveCapacity(sortedEntries.count)

            for (index, entry) in sortedEntries.enumerated() {
                let lfhOffset = entry.localHeaderOffset
                guard lfhOffset + 30 <= parsed.cdOffset,
                      ZipEncodingDetector.readUInt32(data, at: lfhOffset) == localFileHeaderSignature else {
                    return .notAZipArchive
                }

                let localFlags = ZipEncodingDetector.readUInt16(data, at: lfhOffset + 6)
                let localNameLen = Int(ZipEncodingDetector.readUInt16(data, at: lfhOffset + 26))
                let localExtraLen = Int(ZipEncodingDetector.readUInt16(data, at: lfhOffset + 28))
                let payloadStart = lfhOffset + 30 + localNameLen + localExtraLen
                let payloadEnd: Int
                if index + 1 < sortedEntries.count {
                    payloadEnd = sortedEntries[index + 1].localHeaderOffset
                } else {
                    payloadEnd = parsed.cdOffset
                }
                guard payloadStart <= payloadEnd, payloadEnd <= data.count else {
                    return .notAZipArchive
                }

                let decodedName = String(data: entry.fileNameData, encoding: swiftEnc)
                    ?? String(decoding: entry.fileNameData, as: UTF8.self)
                let utf8NameData = Data(decodedName.utf8)

                let newLocalOffset = UInt32(output.count)
                let newLocalFlags = localFlags | utf8Flag
                let newCDFlags = entry.flags | utf8Flag

                // Copy LFH fixed 30 bytes, patch flags (offset 6) & filename length (offset 26)
                var lfhHeader = data.subdata(in: lfhOffset..<(lfhOffset + 30))
                writeUInt16(newLocalFlags, into: &lfhHeader, at: 6)
                writeUInt16(UInt16(utf8NameData.count), into: &lfhHeader, at: 26)
                output.append(lfhHeader)

                // New UTF-8 filename
                output.append(utf8NameData)

                // Original local extra + compressed payload (+ optional data descriptor up to next entry)
                let extraStart = lfhOffset + 30 + localNameLen
                output.append(data.subdata(in: extraStart..<payloadEnd))

                rewritten.append(
                    RewrittenEntry(
                        oldEntry: entry,
                        newLocalOffset: newLocalOffset,
                        newNameData: utf8NameData,
                        newFlags: newCDFlags
                    )
                )
            }

            // Build Central Directory in original CD order
            let newCDOffset = UInt32(output.count)
            let rewrittenByCD = Dictionary(uniqueKeysWithValues: rewritten.map { ($0.oldEntry.cdOffset, $0) })

            for entry in parsed.entries {
                guard let item = rewrittenByCD[entry.cdOffset],
                      ZipEncodingDetector.readUInt32(data, at: entry.cdOffset) == cdSignature else {
                    return .notAZipArchive
                }

                var cdHeader = data.subdata(in: entry.cdOffset..<(entry.cdOffset + 46))
                writeUInt16(item.newFlags, into: &cdHeader, at: 8)
                writeUInt16(UInt16(item.newNameData.count), into: &cdHeader, at: 28)
                writeUInt32(item.newLocalOffset, into: &cdHeader, at: 42)
                output.append(cdHeader)
                output.append(item.newNameData)

                let oldNameLen = entry.fileNameData.count
                let tailStart = entry.cdOffset + 46 + oldNameLen
                let tailEnd = tailStart + entry.extraLen + entry.commentLen
                output.append(data.subdata(in: tailStart..<tailEnd))
            }

            let newCDSize = UInt32(output.count) - newCDOffset
            var eocdData = data.subdata(in: parsed.eocdOffset..<data.count)
            writeUInt32(newCDSize, into: &eocdData, at: 12)
            writeUInt32(newCDOffset, into: &eocdData, at: 16)
            output.append(eocdData)

            try output.write(to: destination, options: .atomic)
            return .normalized(outputURL: destination, encodingName: encodingName)
        }
    }

    private static func writeUInt16(_ value: UInt16, into data: inout Data, at offset: Int) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
    }

    private static func writeUInt32(_ value: UInt32, into data: inout Data, at offset: Int) {
        data[offset] = UInt8(value & 0xFF)
        data[offset + 1] = UInt8((value >> 8) & 0xFF)
        data[offset + 2] = UInt8((value >> 16) & 0xFF)
        data[offset + 3] = UInt8((value >> 24) & 0xFF)
    }
}
