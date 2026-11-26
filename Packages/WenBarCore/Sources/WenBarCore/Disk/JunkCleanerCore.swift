import Foundation

public enum JunkRule: String, CaseIterable, Codable, Sendable, Identifiable {
    case dsStore
    case appleDouble
    case spotlight
    case trashes
    case fseventsd
    case temporaryItems

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dsStore: return ".DS_Store"
        case .appleDouble: return "._* (AppleDouble)"
        case .spotlight: return ".Spotlight-V100"
        case .trashes: return ".Trashes"
        case .fseventsd: return ".fseventsd"
        case .temporaryItems: return ".TemporaryItems"
        }
    }

    public func matches(fileName: String) -> Bool {
        switch self {
        case .dsStore:
            return fileName == ".DS_Store"
        case .appleDouble:
            return fileName.hasPrefix("._") && fileName.count > 2
        case .spotlight:
            return fileName == ".Spotlight-V100"
        case .trashes:
            return fileName == ".Trashes"
        case .fseventsd:
            return fileName == ".fseventsd"
        case .temporaryItems:
            return fileName == ".TemporaryItems"
        }
    }
}

public struct VolumeDescriptor: Sendable, Equatable, Identifiable {
    public var id: String { mountPoint.path }
    public let name: String
    public let mountPoint: URL
    public let fileSystemType: String
    public let totalBytes: Int64
    public let availableBytes: Int64
    public let isExternal: Bool
    public let isRemovable: Bool
    public let isEjectable: Bool
    public let isReadOnly: Bool
    public let isInternal: Bool
    public let isTimeMachine: Bool

    public init(
        name: String,
        mountPoint: URL,
        fileSystemType: String,
        totalBytes: Int64,
        availableBytes: Int64,
        isExternal: Bool,
        isRemovable: Bool,
        isEjectable: Bool,
        isReadOnly: Bool,
        isInternal: Bool,
        isTimeMachine: Bool
    ) {
        self.name = name
        self.mountPoint = mountPoint
        self.fileSystemType = fileSystemType
        self.totalBytes = totalBytes
        self.availableBytes = availableBytes
        self.isExternal = isExternal
        self.isRemovable = isRemovable
        self.isEjectable = isEjectable
        self.isReadOnly = isReadOnly
        self.isInternal = isInternal
        self.isTimeMachine = isTimeMachine
    }

    public var usedBytes: Int64 {
        max(0, totalBytes - availableBytes)
    }

    public var usedFraction: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes)
    }
}

public enum SafetyRejectionReason: Error, Sendable, Equatable {
    case systemVolume
    case readOnlyVolume
    case internalNonRemovable
    case timeMachineBackup
    case invalidPath
}

public enum DiskSafetyGuard {
    private static let protectedPrefixes = ["/System", "/Library", "/bin", "/sbin", "/usr", "/private", "/dev"]

    public static func validateForCleanup(_ volume: VolumeDescriptor) -> Result<Void, SafetyRejectionReason> {
        let path = volume.mountPoint.standardizedFileURL.path
        if path == "/" || path.isEmpty {
            return .failure(.systemVolume)
        }
        for prefix in protectedPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return .failure(.systemVolume)
        }
        if volume.isReadOnly {
            return .failure(.readOnlyVolume)
        }
        if volume.isTimeMachine {
            return .failure(.timeMachineBackup)
        }
        if volume.isInternal && !volume.isExternal && !volume.isRemovable && !volume.isEjectable {
            return .failure(.internalNonRemovable)
        }
        return .success(())
    }

    public static func detectTimeMachineMarkers(at mountPoint: URL, fileManager: FileManager = .default) -> Bool {
        let markers = [
            "Backups.backupdb",
            ".com.apple.timemachine.donotpresent",
            ".TimeMachine.plist",
            "tmbootpicker.efi"
        ]
        for marker in markers {
            let candidate = mountPoint.appendingPathComponent(marker)
            if fileManager.fileExists(atPath: candidate.path) {
                return true
            }
        }
        return false
    }

    public static func validateDirectoryTarget(_ directory: URL) -> Result<Void, SafetyRejectionReason> {
        let path = directory.standardizedFileURL.path
        if path == "/" || path.isEmpty {
            return .failure(.systemVolume)
        }
        for prefix in protectedPrefixes where path == prefix || path.hasPrefix(prefix + "/") {
            return .failure(.systemVolume)
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else {
            return .failure(.invalidPath)
        }
        return .success(())
    }
}

public struct CleanupFailure: Sendable, Equatable {
    public let path: String
    public let message: String
}

public struct CleanupReport: Sendable, Equatable {
    public let removedCount: Int
    public let freedBytes: Int64
    public let failures: [CleanupFailure]

    public init(removedCount: Int, freedBytes: Int64, failures: [CleanupFailure]) {
        self.removedCount = removedCount
        self.freedBytes = freedBytes
        self.failures = failures
    }
}

/// Recursively deletes macOS junk files inside a target root without ever following symlinks.
/// Uses POSIX `opendir`/`readdir` + `lstat` because `FileManager.contentsOfDirectory` hides `._*` AppleDouble files on macOS.
public enum JunkFileCleaner {
    public static func clean(
        rootDirectory: URL,
        rules: Set<JunkRule>,
        fileManager: FileManager = .default
    ) -> CleanupReport {
        guard !rules.isEmpty else {
            return CleanupReport(removedCount: 0, freedBytes: 0, failures: [])
        }
        let resolvedRoot = rootDirectory.standardizedFileURL
        var rootStat = stat()
        guard lstat(resolvedRoot.path, &rootStat) == 0,
              (rootStat.st_mode & S_IFMT) == S_IFDIR else {
            return CleanupReport(
                removedCount: 0,
                freedBytes: 0,
                failures: [CleanupFailure(path: resolvedRoot.path, message: "Invalid or symlinked root directory")]
            )
        }

        var removedCount = 0
        var freedBytes: Int64 = 0
        var failures: [CleanupFailure] = []
        var stack: [URL] = [resolvedRoot]

        while let currentDir = stack.popLast() {
            guard let dirHandle = opendir(currentDir.path) else {
                continue
            }
            defer { closedir(dirHandle) }

            while let entry = readdir(dirHandle) {
                let name = withUnsafePointer(to: entry.pointee.d_name) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }

                let child = currentDir.appendingPathComponent(name)
                var childStat = stat()
                guard lstat(child.path, &childStat) == 0 else { continue }

                let fileType = childStat.st_mode & S_IFMT
                let isSymlink = (fileType == S_IFLNK)
                let isDir = (fileType == S_IFDIR)

                if rules.contains(where: { $0.matches(fileName: name) }) {
                    let size = isDir && !isSymlink
                        ? directorySizePosix(at: child)
                        : Int64(max(0, childStat.st_size))
                    do {
                        try fileManager.removeItem(at: child)
                        removedCount += 1
                        freedBytes += size
                    } catch {
                        failures.append(CleanupFailure(path: child.path, message: error.localizedDescription))
                    }
                    continue
                }

                // Never follow symlinks when descending
                if isDir && !isSymlink {
                    stack.append(child)
                }
            }
        }

        return CleanupReport(removedCount: removedCount, freedBytes: freedBytes, failures: failures)
    }

    private static func directorySizePosix(at url: URL) -> Int64 {
        var total: Int64 = 0
        var stack: [URL] = [url]
        while let dir = stack.popLast() {
            guard let handle = opendir(dir.path) else { continue }
            defer { closedir(handle) }
            while let entry = readdir(handle) {
                let name = withUnsafePointer(to: entry.pointee.d_name) { ptr in
                    ptr.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) {
                        String(cString: $0)
                    }
                }
                if name == "." || name == ".." { continue }
                let child = dir.appendingPathComponent(name)
                var st = stat()
                guard lstat(child.path, &st) == 0 else { continue }
                let ft = st.st_mode & S_IFMT
                if ft == S_IFLNK { continue }
                if ft == S_IFDIR {
                    stack.append(child)
                } else {
                    total += Int64(max(0, st.st_size))
                }
            }
        }
        return total
    }
}

public struct OccupyingProcess: Sendable, Equatable, Identifiable {
    public var id: Int { pid }
    public let pid: Int
    public let command: String
    public let user: String

    public init(pid: Int, command: String, user: String) {
        self.pid = pid
        self.command = command
        self.user = user
    }
}

/// Parses `lsof` standard tabular output or `-F pcu` machine output into deduplicated processes.
public enum LsofParser {
    public static func parseStandardOutput(_ output: String) -> [OccupyingProcess] {
        var seenPids = Set<Int>()
        var results: [OccupyingProcess] = []

        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }
            let parts = line.split(whereSeparator: \.isWhitespace)
            guard parts.count >= 3 else { continue }
            // Skip header row: COMMAND PID USER ...
            if parts[0] == "COMMAND" && parts[1] == "PID" { continue }
            guard let pid = Int(parts[1]), !seenPids.contains(pid) else { continue }
            seenPids.insert(pid)
            results.append(OccupyingProcess(pid: pid, command: String(parts[0]), user: String(parts[2])))
        }

        return results.sorted { $0.pid < $1.pid }
    }
}
