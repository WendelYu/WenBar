import Foundation

public enum ArchiveFormat: String, CaseIterable, Codable, Sendable, Identifiable {
    case zip
    case sevenZ = "7z"
    case tarGz = "tar.gz"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .zip: return "ZIP (.zip)"
        case .sevenZ: return "7-Zip (.7z)"
        case .tarGz: return "TAR.GZ (.tar.gz)"
        }
    }

    public var fileExtension: String {
        rawValue
    }

    public var supportsEncryption: Bool {
        switch self {
        case .zip, .sevenZ: return true
        case .tarGz: return false
        }
    }
}

public enum CompressionLevel: String, CaseIterable, Codable, Sendable, Identifiable {
    case fast
    case normal
    case maximum

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .fast: return "快速"
        case .normal: return "标准"
        case .maximum: return "极限"
        }
    }

    public var sevenZipLevelFlag: String {
        switch self {
        case .fast: return "-mx=1"
        case .normal: return "-mx=5"
        case .maximum: return "-mx=9"
        }
    }
}

public enum ExtractMode: String, Codable, Sendable {
    case smart
    case subfolder
    case here
}

public struct ExtractPlan: Sendable, Equatable {
    public let destinationDirectory: URL
    public let createsSubfolder: Bool
    public let singleRootFolderName: String?

    public init(destinationDirectory: URL, createsSubfolder: Bool, singleRootFolderName: String?) {
        self.destinationDirectory = destinationDirectory
        self.createsSubfolder = createsSubfolder
        self.singleRootFolderName = singleRootFolderName
    }
}

public enum ArchiveFileSupport {
    public static let supportedExtractExtensions: Set<String> = [
        "zip", "7z", "rar", "tar", "gz", "tgz", "bz2", "tbz2", "xz", "txz"
    ]

    public static func isSupportedArchive(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        if supportedExtractExtensions.contains(ext) {
            return true
        }
        let lower = url.lastPathComponent.lowercased()
        return lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tar.xz")
    }

    public static func archiveBaseName(for url: URL) -> String {
        let name = url.lastPathComponent
        let lower = name.lowercased()
        for compound in [".tar.gz", ".tar.bz2", ".tar.xz"] where lower.hasSuffix(compound) {
            return String(name.dropLast(compound.count))
        }
        return url.deletingPathExtension().lastPathComponent
    }
}

/// Computes collision-safe extraction targets so loose archives don't pollute Finder directories.
public enum SmartExtractPlanner {
    public static func plan(
        entries: [String],
        archiveURL: URL,
        mode: ExtractMode,
        existingItemsInParent: Set<String>
    ) -> ExtractPlan {
        let parentDir = archiveURL.deletingLastPathComponent()
        let baseName = ArchiveFileSupport.archiveBaseName(for: archiveURL)

        let meaningfulEntries = entries
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "/")) }
            .filter { entry in
                guard !entry.isEmpty else { return false }
                let components = entry.split(separator: "/").map(String.init)
                guard let first = components.first else { return false }
                if first == "__MACOSX" { return false }
                if let last = components.last, last == ".DS_Store" || (last.hasPrefix("._") && last.count > 2) {
                    return false
                }
                return true
            }

        var topLevelNames = Set<String>()
        var hasTopLevelFile = false
        for entry in meaningfulEntries {
            let parts = entry.split(separator: "/").map(String.init)
            if let first = parts.first {
                topLevelNames.insert(first)
                if parts.count == 1 && !entry.hasSuffix("/") {
                    // Note: entries list might include a single folder name without slash; if there are children under it, we check below.
                }
            }
        }

        // Determine if all meaningful entries share exactly one top-level folder
        let singleRootName: String?
        if topLevelNames.count == 1, let root = topLevelNames.first {
            let hasNested = meaningfulEntries.contains { $0.hasPrefix(root + "/") }
            if hasNested {
                singleRootName = root
            } else {
                hasTopLevelFile = true
                singleRootName = nil
            }
        } else {
            singleRootName = nil
        }

        switch mode {
        case .here:
            return ExtractPlan(destinationDirectory: parentDir, createsSubfolder: false, singleRootFolderName: singleRootName)

        case .subfolder:
            let folderName = uniqueName(base: baseName, existing: existingItemsInParent)
            return ExtractPlan(
                destinationDirectory: parentDir.appendingPathComponent(folderName, isDirectory: true),
                createsSubfolder: true,
                singleRootFolderName: singleRootName
            )

        case .smart:
            if let root = singleRootName, !hasTopLevelFile {
                if existingItemsInParent.contains(root) {
                    let uniqueSub = uniqueName(base: baseName, existing: existingItemsInParent)
                    return ExtractPlan(
                        destinationDirectory: parentDir.appendingPathComponent(uniqueSub, isDirectory: true),
                        createsSubfolder: true,
                        singleRootFolderName: root
                    )
                }
                return ExtractPlan(
                    destinationDirectory: parentDir,
                    createsSubfolder: false,
                    singleRootFolderName: root
                )
            } else {
                let folderName = uniqueName(base: baseName, existing: existingItemsInParent)
                return ExtractPlan(
                    destinationDirectory: parentDir.appendingPathComponent(folderName, isDirectory: true),
                    createsSubfolder: true,
                    singleRootFolderName: nil
                )
            }
        }
    }

    public static func uniqueName(base: String, existing: Set<String>) -> String {
        let sanitized = base.isEmpty ? "Archive" : base
        if !existing.contains(sanitized) {
            return sanitized
        }
        var counter = 2
        while existing.contains("\(sanitized) \(counter)") {
            counter += 1
        }
        return "\(sanitized) \(counter)"
    }
}

/// Builds deterministic CLI arguments for `7zz` and `bsdtar`, enforcing macOS junk exclusions.
public enum ArchiveCommandBuilder {
    public static func sevenZipCompressArguments(
        format: ArchiveFormat,
        outputURL: URL,
        inputRelativePaths: [String],
        level: CompressionLevel = .normal,
        password: String? = nil
    ) -> [String] {
        var args: [String] = ["a", "-y", "-bsp1"]

        switch format {
        case .zip:
            args.append("-tzip")
            args.append("-mcu=on")
            if let password, !password.isEmpty {
                args.append("-mem=AES256")
            }
        case .sevenZ:
            args.append("-t7z")
            if let password, !password.isEmpty {
                args.append("-mhe=on")
            }
        case .tarGz:
            args.append("-tgzip")
        }

        args.append(level.sevenZipLevelFlag)
        args.append(contentsOf: [
            "-xr!.DS_Store",
            "-xr!._*",
            "-xr!__MACOSX"
        ])

        if let password, !password.isEmpty {
            args.append("-p\(password)")
        }

        args.append(outputURL.path)
        args.append(contentsOf: inputRelativePaths)
        return args
    }

    public static func bsdtarCreateTarGzArguments(
        outputURL: URL,
        inputNames: [String]
    ) -> [String] {
        var args = [
            "--no-mac-metadata",
            "--no-xattrs",
            "--exclude=.DS_Store",
            "--exclude=._*",
            "--exclude=__MACOSX",
            "-czf",
            outputURL.path
        ]
        args.append(contentsOf: inputNames)
        return args
    }

    public static func sevenZipExtractArguments(
        archiveURL: URL,
        destinationDirectory: URL,
        password: String? = nil
    ) -> [String] {
        var args = [
            "x",
            "-y",
            "-bsp1",
            "-o\(destinationDirectory.path)"
        ]
        if let password, !password.isEmpty {
            args.append("-p\(password)")
        }
        args.append(archiveURL.path)
        return args
    }

    public static func bsdtarExtractArguments(
        archiveURL: URL,
        destinationDirectory: URL
    ) -> [String] {
        [
            "-xf",
            archiveURL.path,
            "-C",
            destinationDirectory.path
        ]
    }
}
