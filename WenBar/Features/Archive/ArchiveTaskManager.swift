import Foundation
import AppKit
import WenBarCore

struct ArchiveTaskProgress: Identifiable, Sendable {
    let id: UUID
    let title: String
    var fraction: Double
    var detail: String
    var isIndeterminate: Bool
}

struct PasswordPromptRequest: Identifiable {
    let id = UUID()
    let archiveURL: URL
    let mode: ExtractMode
    let trashAfterExtract: Bool
    let errorHint: String?
}

@MainActor
@Observable
final class ArchiveTaskManager {
    var activeTask: ArchiveTaskProgress? {
        didSet { onProgressChanged?() }
    }
    var pendingPasswordRequest: PasswordPromptRequest? {
        didSet {
            if let req = pendingPasswordRequest {
                onPasswordRequired?(req)
            }
        }
    }
    var lastStatusMessage: String?

    @ObservationIgnored var onProgressChanged: (() -> Void)?
    @ObservationIgnored var onPasswordRequired: ((PasswordPromptRequest) -> Void)?

    private var currentProcess: Process?
    private var isCancelled: Bool = false
    private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
    }

    func cancelActiveTask() {
        isCancelled = true
        currentProcess?.terminate()
        activeTask = nil
        lastStatusMessage = "已取消压缩/解压任务"
    }

    func cleanDSStoreInDirectories(_ urls: [URL]) {
        Task {
            var totalRemoved = 0
            var totalFreed: Int64 = 0
            for url in urls {
                var isDir: ObjCBool = false
                let targetDir: URL
                if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue {
                    targetDir = url
                } else {
                    targetDir = url.deletingLastPathComponent()
                }
                guard case .success = DiskSafetyGuard.validateDirectoryTarget(targetDir) else { continue }
                let report = await Task.detached {
                    JunkFileCleaner.clean(rootDirectory: targetDir, rules: [.dsStore])
                }.value
                totalRemoved += report.removedCount
                totalFreed += report.freedBytes
            }

            let sizeStr = ByteCountFormatter.string(fromByteCount: totalFreed, countStyle: .file)
            lastStatusMessage = "已清理 \(totalRemoved) 个 .DS_Store（\(sizeStr)）"
            NotificationService.shared.post(
                title: ".DS_Store 清理完成",
                body: "共清理了 \(totalRemoved) 个 .DS_Store 文件（释放 \(sizeStr)）。"
            )
        }
    }

    func enqueueCompress(
        sources: [URL],
        format: ArchiveFormat,
        level: CompressionLevel,
        password: String?,
        cleanSourceDSStore: Bool
    ) {
        guard !sources.isEmpty else { return }
        let outputURL = defaultOutputURL(for: sources, format: format)

        Task {
            await runCompress(
                sources: sources,
                outputURL: outputURL,
                format: format,
                level: level,
                password: password,
                cleanSourceDSStore: cleanSourceDSStore
            )
        }
    }

    func enqueueExtract(
        archives: [URL],
        mode: ExtractMode,
        trashAfterExtract: Bool,
        password: String? = nil
    ) {
        guard !archives.isEmpty else { return }
        Task {
            for archive in archives {
                await runExtract(
                    archiveURL: archive,
                    mode: mode,
                    trashAfterExtract: trashAfterExtract,
                    password: password
                )
            }
        }
    }

    func defaultOutputURL(for sources: [URL], format: ArchiveFormat) -> URL {
        let parentDir = sources[0].deletingLastPathComponent()
        let baseName: String
        if sources.count == 1 {
            let item = sources[0]
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: item.path, isDirectory: &isDir)
            baseName = isDir.boolValue ? item.lastPathComponent : item.deletingPathExtension().lastPathComponent
        } else {
            baseName = parentDir.lastPathComponent.isEmpty ? "Archive" : parentDir.lastPathComponent
        }

        let existing = (try? FileManager.default.contentsOfDirectory(atPath: parentDir.path)) ?? []
        let existingSet = Set(existing)
        var candidateName = "\(baseName).\(format.fileExtension)"
        var idx = 2
        while existingSet.contains(candidateName) {
            candidateName = "\(baseName) \(idx).\(format.fileExtension)"
            idx += 1
        }
        return parentDir.appendingPathComponent(candidateName)
    }

    private func runCompress(
        sources: [URL],
        outputURL: URL,
        format: ArchiveFormat,
        level: CompressionLevel,
        password: String?,
        cleanSourceDSStore: Bool
    ) async {
        isCancelled = false
        let taskID = UUID()
        activeTask = ArchiveTaskProgress(
            id: taskID,
            title: "正在压缩 \(outputURL.lastPathComponent)",
            fraction: 0,
            detail: "准备文件…",
            isIndeterminate: true
        )

        let workingDir = sources[0].deletingLastPathComponent()
        let inputNames = sources.map { $0.lastPathComponent }

        let result: Result<Void, Error>
        if format == .tarGz {
            let args = ArchiveCommandBuilder.bsdtarCreateTarGzArguments(outputURL: outputURL, inputNames: inputNames)
            result = await executeProcess(
                executable: URL(fileURLWithPath: "/usr/bin/bsdtar"),
                arguments: args,
                workingDirectory: workingDir,
                environment: ["COPYFILE_DISABLE": "1"],
                taskID: taskID
            )
        } else {
            guard let sevenZipURL = resolveSevenZipBinary() else {
                activeTask = nil
                NotificationService.shared.post(title: "压缩失败", body: "未找到内嵌 7zz 引擎，请运行 setup-deps.sh。")
                return
            }
            let args = ArchiveCommandBuilder.sevenZipCompressArguments(
                format: format,
                outputURL: outputURL,
                inputRelativePaths: inputNames,
                level: level,
                password: password
            )
            result = await executeProcess(
                executable: sevenZipURL,
                arguments: args,
                workingDirectory: workingDir,
                environment: [:],
                taskID: taskID
            )
        }

        activeTask = nil

        if isCancelled {
            try? FileManager.default.removeItem(at: outputURL)
            return
        }

        switch result {
        case .success:
            var cleanedCount = 0
            if cleanSourceDSStore {
                for src in sources {
                    var isDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: src.path, isDirectory: &isDir), isDir.boolValue {
                        let report = await Task.detached {
                            JunkFileCleaner.clean(rootDirectory: src, rules: [.dsStore])
                        }.value
                        cleanedCount += report.removedCount
                    }
                }
            }
            let extra = cleanedCount > 0 ? "（同时清理源目录 \(cleanedCount) 个 .DS_Store）" : ""
            lastStatusMessage = "已生成 \(outputURL.lastPathComponent)\(extra)"
            NotificationService.shared.post(
                title: "压缩完成",
                body: "已生成 \(outputURL.lastPathComponent)\(extra)"
            )

        case let .failure(err):
            lastStatusMessage = "压缩失败：\(err.localizedDescription)"
            NotificationService.shared.post(title: "压缩失败", body: err.localizedDescription)
        }
    }

    private func runExtract(
        archiveURL: URL,
        mode: ExtractMode,
        trashAfterExtract: Bool,
        password: String?
    ) async {
        isCancelled = false
        let taskID = UUID()
        activeTask = ArchiveTaskProgress(
            id: taskID,
            title: "正在解压 \(archiveURL.lastPathComponent)",
            fraction: 0,
            detail: "检测编码与目录结构…",
            isIndeterminate: true
        )

        var workingArchiveURL = archiveURL
        var tempNormalizedDir: URL?
        defer {
            if let tempNormalizedDir {
                try? FileManager.default.removeItem(at: tempNormalizedDir)
            }
        }

        // Step 1: Fix legacy Windows Chinese ZIP encodings (GBK/Big5/Shift-JIS)
        if archiveURL.pathExtension.lowercased() == "zip" {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("WenBarZipFix-\(UUID().uuidString)", isDirectory: true)
            let normalizedZip = tempDir.appendingPathComponent(archiveURL.lastPathComponent)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let outcome = await Task.detached {
                try? ZipHeaderNormalizer.normalizeToUTF8IfNeeded(source: archiveURL, destination: normalizedZip)
            }.value

            if case let .normalized(fixedURL, _) = outcome {
                workingArchiveURL = fixedURL
                tempNormalizedDir = tempDir
            } else {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }

        // Step 2: Inspect archive entries to build SmartExtractPlan
        let entries = await listArchiveEntries(archiveURL: workingArchiveURL, password: password)
        let parentDir = archiveURL.deletingLastPathComponent()
        let existing = Set((try? FileManager.default.contentsOfDirectory(atPath: parentDir.path)) ?? [])

        let plan = SmartExtractPlanner.plan(
            entries: entries,
            archiveURL: archiveURL,
            mode: mode,
            existingItemsInParent: existing
        )

        if plan.createsSubfolder {
            try? FileManager.default.createDirectory(at: plan.destinationDirectory, withIntermediateDirectories: true)
        }

        // Step 3: Execute extraction
        let result: Result<Void, Error>
        let lowerName = archiveURL.lastPathComponent.lowercased()
        let useBsdtar = lowerName.hasSuffix(".tar.gz")
            || lowerName.hasSuffix(".tgz")
            || lowerName.hasSuffix(".tar.bz2")
            || lowerName.hasSuffix(".tbz2")
            || lowerName.hasSuffix(".tar.xz")
            || lowerName.hasSuffix(".txz")
            || lowerName.hasSuffix(".tar")

        if useBsdtar {
            let args = ArchiveCommandBuilder.bsdtarExtractArguments(
                archiveURL: workingArchiveURL,
                destinationDirectory: plan.destinationDirectory
            )
            result = await executeProcess(
                executable: URL(fileURLWithPath: "/usr/bin/bsdtar"),
                arguments: args,
                workingDirectory: parentDir,
                environment: [:],
                taskID: taskID
            )
        } else {
            guard let sevenZipURL = resolveSevenZipBinary() else {
                activeTask = nil
                NotificationService.shared.post(title: "解压失败", body: "未找到内嵌 7zz 引擎。")
                return
            }
            let args = ArchiveCommandBuilder.sevenZipExtractArguments(
                archiveURL: workingArchiveURL,
                destinationDirectory: plan.destinationDirectory,
                password: password
            )
            result = await executeProcess(
                executable: sevenZipURL,
                arguments: args,
                workingDirectory: parentDir,
                environment: [:],
                taskID: taskID
            )
        }

        activeTask = nil
        if isCancelled { return }

        switch result {
        case .success:
            if trashAfterExtract {
                try? FileManager.default.trashItem(at: archiveURL, resultingItemURL: nil)
            }
            lastStatusMessage = "已解压 \(archiveURL.lastPathComponent)"
            NotificationService.shared.post(
                title: "解压完成",
                body: "\(archiveURL.lastPathComponent) 已解压到 \(plan.destinationDirectory.lastPathComponent)。"
            )

        case let .failure(err):
            let msg = err.localizedDescription
            if msg.localizedCaseInsensitiveContains("Wrong password")
                || msg.localizedCaseInsensitiveContains("Enter password")
                || msg.localizedCaseInsensitiveContains("Data Error in encrypted")
                || msg.localizedCaseInsensitiveContains("encrypted") {
                pendingPasswordRequest = PasswordPromptRequest(
                    archiveURL: archiveURL,
                    mode: mode,
                    trashAfterExtract: trashAfterExtract,
                    errorHint: password == nil ? nil : "密码不正确，请重新输入"
                )
            } else {
                lastStatusMessage = "解压失败：\(msg)"
                NotificationService.shared.post(title: "解压失败", body: msg)
            }
        }
    }

    private func listArchiveEntries(archiveURL: URL, password: String?) async -> [String] {
        let lower = archiveURL.lastPathComponent.lowercased()
        if lower.hasSuffix(".tar") || lower.hasSuffix(".tar.gz") || lower.hasSuffix(".tgz")
            || lower.hasSuffix(".tar.bz2") || lower.hasSuffix(".tar.xz") {
            let output = await runQuickCommand(
                executable: URL(fileURLWithPath: "/usr/bin/bsdtar"),
                arguments: ["-tf", archiveURL.path]
            )
            return output.split(whereSeparator: \.isNewline).map(String.init)
        }

        guard let sevenZipURL = resolveSevenZipBinary() else { return [] }
        var args = ["l", "-slt", "-ba"]
        if let password, !password.isEmpty {
            args.append("-p\(password)")
        } else {
            args.append("-p-")
        }
        args.append(archiveURL.path)

        let output = await runQuickCommand(executable: sevenZipURL, arguments: args)
        var paths: [String] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let str = String(line)
            if str.hasPrefix("Path = ") {
                paths.append(String(str.dropFirst("Path = ".count)))
            }
        }
        return paths
    }

    private func runQuickCommand(executable: URL, arguments: [String]) async -> String {
        await Task.detached {
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = Pipe()
            do {
                try process.run()
                process.waitUntilExit()
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8) ?? ""
            } catch {
                return ""
            }
        }.value
    }

    private final class ProcessBox: @unchecked Sendable {
        let process: Process
        init(_ process: Process) { self.process = process }
    }

    private func executeProcess(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        taskID: UUID
    ) async -> Result<Void, Error> {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = workingDirectory

        if !environment.isEmpty {
            var env = ProcessInfo.processInfo.environment
            for (k, v) in environment { env[k] = v }
            process.environment = env
        }

        self.currentProcess = process
        let box = ProcessBox(process)
        let result = await Self.runProcessOffMain(processBox: box) { [weak self] pct in
            Task { @MainActor in
                if self?.activeTask?.id == taskID {
                    self?.activeTask?.isIndeterminate = false
                    self?.activeTask?.fraction = Double(pct) / 100.0
                    self?.activeTask?.detail = "进度 \(pct)%"
                }
            }
        }
        self.currentProcess = nil
        return result
    }

    private nonisolated static func runProcessOffMain(
        processBox: ProcessBox,
        onProgress: @escaping @Sendable (Int) -> Void
    ) async -> Result<Void, Error> {
        let process = processBox.process
        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        final class OutputCollector: @unchecked Sendable {
            private let lock = NSLock()
            var errorBuffer = ""
            func appendError(_ str: String) {
                lock.lock()
                errorBuffer += str
                lock.unlock()
            }
            func getError() -> String {
                lock.lock()
                defer { lock.unlock() }
                return errorBuffer
            }
        }
        let collector = OutputCollector()

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
            if let pct = Self.parseSevenZipPercentage(from: chunk) {
                onProgress(pct)
            }
        }

        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if !data.isEmpty, let chunk = String(data: data, encoding: .utf8) {
                collector.appendError(chunk)
            }
        }

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                let remainingErr = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                collector.appendError(remainingErr)

                if proc.terminationStatus == 0 {
                    continuation.resume(returning: .success(()))
                } else {
                    let msg = collector.getError().trimmingCharacters(in: .whitespacesAndNewlines)
                    let fallback = msg.isEmpty ? "进程退出码 \(proc.terminationStatus)" : msg
                    continuation.resume(returning: .failure(
                        NSError(domain: "WenBarArchive", code: Int(proc.terminationStatus), userInfo: [NSLocalizedDescriptionKey: fallback])
                    ))
                }
            }

            do {
                try process.run()
            } catch {
                outPipe.fileHandleForReading.readabilityHandler = nil
                errPipe.fileHandleForReading.readabilityHandler = nil
                continuation.resume(returning: .failure(error))
            }
        }
    }

    private nonisolated static func parseSevenZipPercentage(from chunk: String) -> Int? {
        // 7zz -bsp1 outputs progress like " 42%"
        let tokens = chunk.split(whereSeparator: { $0.isWhitespace || $0 == "\r" })
        for token in tokens.reversed() where token.hasSuffix("%") {
            let numPart = token.dropLast()
            if let value = Int(numPart), (0...100).contains(value) {
                return value
            }
        }
        return nil
    }

    func resolveSevenZipBinary() -> URL? {
        if let resURL = Bundle.main.resourceURL {
            let bundled = resURL.appendingPathComponent("bin/7zz")
            if FileManager.default.isExecutableFile(atPath: bundled.path) {
                return bundled
            }
        }
        let homebrewPaths = ["/opt/homebrew/bin/7zz", "/usr/local/bin/7zz"]
        for path in homebrewPaths where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }
}
