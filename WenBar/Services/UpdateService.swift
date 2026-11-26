import Foundation
import AppKit
import WenBarCore

enum UpdateState: Equatable {
    case idle
    case checking
    case upToDate
    case available(GitHubRelease, GitHubReleaseAsset)
    case downloading(Double)
    case installing
    case failed(String)
}

@MainActor
@Observable
final class UpdateService {
    static let repoOwner = "WendelYu"
    static let repoName = "WenBar"
    static let latestReleaseAPI = URL(string: "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!
    static let releasesPageURL = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases")!

    var state: UpdateState = .idle
    var lastCheckMessage: String?

    var currentShortVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    var currentBuildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var currentVersionDescription: String {
        "v\(currentShortVersion) (\(currentBuildNumber))"
    }

    var availableRelease: GitHubRelease? {
        if case let .available(release, _) = state {
            return release
        }
        return nil
    }

    func checkForUpdates(silent: Bool = false) async {
        if case .checking = state { return }
        if case .downloading = state { return }
        if case .installing = state { return }

        state = .checking
        if !silent {
            lastCheckMessage = "正在从 GitHub 检查最新版本…"
        }

        do {
            var request = URLRequest(url: Self.latestReleaseAPI)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("WenBar/\(currentShortVersion)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 15

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw NSError(domain: "WenBarUpdate", code: -1, userInfo: [NSLocalizedDescriptionKey: "无效的网络响应"])
            }

            if http.statusCode == 404 {
                state = .upToDate
                if !silent {
                    lastCheckMessage = "GitHub 暂无已发布的 Release（当前 \(currentVersionDescription)）。"
                }
                return
            }

            guard (200..<300).contains(http.statusCode) else {
                throw NSError(domain: "WenBarUpdate", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "GitHub 接口返回 HTTP \(http.statusCode)"])
            }

            let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
            if release.draft || release.prerelease {
                state = .upToDate
                if !silent {
                    lastCheckMessage = "当前已是最新正式版本 \(currentVersionDescription)。"
                }
                return
            }

            if ReleaseUpdatePlanner.isNewer(remoteTag: release.tagName, currentVersion: currentShortVersion) {
                if let asset = ReleaseUpdatePlanner.selectBestAsset(from: release.assets) {
                    state = .available(release, asset)
                    lastCheckMessage = "发现新版本 \(release.tagName)（当前 \(currentVersionDescription)）"
                    if silent {
                        NotificationService.shared.post(
                            title: "发现 WenBar 新版本 \(release.tagName)",
                            body: "打开设置或菜单栏即可一键下载安装并自动重启。"
                        )
                    }
                } else {
                    state = .failed("发现新版本 \(release.tagName)，但未找到可用的 .zip 或 .dmg 安装包。")
                    lastCheckMessage = "发现新版本 \(release.tagName)，但缺少安装包附件，请前往 GitHub 下载。"
                }
            } else {
                state = .upToDate
                if !silent {
                    lastCheckMessage = "当前已是最新版本 \(currentVersionDescription)。"
                }
            }
        } catch {
            if silent {
                state = .idle
            } else {
                state = .failed(error.localizedDescription)
                lastCheckMessage = "检查更新失败：\(error.localizedDescription)"
            }
        }
    }

    func downloadAndInstall() async {
        guard case let .available(release, asset) = state else { return }

        let targetAppURL = Bundle.main.bundleURL
        let rv = try? targetAppURL.resourceValues(forKeys: [.volumeIsReadOnlyKey])
        if rv?.volumeIsReadOnly == true {
            let msg = "当前正在从只读磁盘映像（DMG）运行，请先将 WenBar.app 拖入「应用程序 (/Applications)」后再自动更新。"
            state = .failed(msg)
            lastCheckMessage = msg
            return
        }

        let fm = FileManager.default
        let stagingRoot = fm.temporaryDirectory.appendingPathComponent("WenBarUpdate-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
        } catch {
            state = .failed("无法创建更新临时目录：\(error.localizedDescription)")
            return
        }

        state = .downloading(0)
        lastCheckMessage = "正在下载 \(release.tagName)（\(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file))）…"

        do {
            let downloadedTempURL = try await Self.downloadAssetOffMain(url: asset.browserDownloadURL) { [weak self] progress in
                Task { @MainActor in
                    self?.state = .downloading(progress)
                }
            }

            let localArchiveURL = stagingRoot.appendingPathComponent(asset.name)
            try fm.moveItem(at: downloadedTempURL, to: localArchiveURL)

            state = .installing
            lastCheckMessage = "正在校验并安装 \(release.tagName)，软件即将自动重启…"

            let stagedAppURL = try await Task.detached {
                try Self.extractAndVerifyApp(archiveURL: localArchiveURL, stagingRoot: stagingRoot)
            }.value

            let scriptContent = ReleaseUpdatePlanner.buildInstallScript(
                oldPID: ProcessInfo.processInfo.processIdentifier,
                stagedAppPath: stagedAppURL.path,
                targetAppPath: targetAppURL.path,
                stagingRoot: stagingRoot.path
            )
            let scriptURL = stagingRoot.appendingPathComponent("install_update.sh")
            try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = [scriptURL.path]
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()

            NSApp.terminate(nil)
        } catch {
            try? fm.removeItem(at: stagingRoot)
            state = .failed(error.localizedDescription)
            lastCheckMessage = "更新失败：\(error.localizedDescription)"
        }
    }

    func openReleasesPage() {
        let url = availableRelease?.htmlURL ?? Self.releasesPageURL
        NSWorkspace.shared.open(url)
    }

    private nonisolated static func downloadAssetOffMain(
        url: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        final class DownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
            private var continuation: CheckedContinuation<URL, Error>?
            private let onProgress: @Sendable (Double) -> Void
            private let lock = NSLock()

            init(continuation: CheckedContinuation<URL, Error>, onProgress: @escaping @Sendable (Double) -> Void) {
                self.continuation = continuation
                self.onProgress = onProgress
            }

            private func finish(with result: Result<URL, Error>) {
                lock.lock()
                let cont = continuation
                continuation = nil
                lock.unlock()
                cont?.resume(with: result)
            }

            func urlSession(
                _ session: URLSession,
                downloadTask: URLSessionDownloadTask,
                didWriteData bytesWritten: Int64,
                totalBytesWritten: Int64,
                totalBytesExpectedToWrite: Int64
            ) {
                guard totalBytesExpectedToWrite > 0 else { return }
                let fraction = min(1.0, max(0.0, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
                onProgress(fraction)
            }

            func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
                let copyURL = FileManager.default.temporaryDirectory.appendingPathComponent("wenbar-dl-\(UUID().uuidString)")
                do {
                    try FileManager.default.copyItem(at: location, to: copyURL)
                    finish(with: .success(copyURL))
                } catch {
                    finish(with: .failure(error))
                }
            }

            func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
                if let error {
                    finish(with: .failure(error))
                }
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            let delegate = DownloadDelegate(continuation: continuation, onProgress: onProgress)
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            var request = URLRequest(url: url)
            request.setValue("WenBar-Updater", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 120
            let task = session.downloadTask(with: request)
            task.resume()
        }
    }

    private nonisolated static func extractAndVerifyApp(archiveURL: URL, stagingRoot: URL) throws -> URL {
        let fm = FileManager.default
        let extractDir = stagingRoot.appendingPathComponent("extracted", isDirectory: true)
        try fm.createDirectory(at: extractDir, withIntermediateDirectories: true)

        let ext = archiveURL.pathExtension.lowercased()
        let appURL: URL

        if ext == "zip" {
            let status = try runProcess(
                "/usr/bin/ditto",
                arguments: ["-x", "-k", archiveURL.path, extractDir.path]
            )
            guard status == 0 else {
                throw NSError(domain: "WenBarUpdate", code: Int(status), userInfo: [NSLocalizedDescriptionKey: "解压更新包失败（ditto 退出码 \(status)）"])
            }
            guard let found = findAppBundle(in: extractDir) else {
                throw NSError(domain: "WenBarUpdate", code: -2, userInfo: [NSLocalizedDescriptionKey: "压缩包内未找到 WenBar.app"])
            }
            appURL = found
        } else if ext == "dmg" {
            let mountPoint = stagingRoot.appendingPathComponent("dmg-mount", isDirectory: true)
            try fm.createDirectory(at: mountPoint, withIntermediateDirectories: true)
            let attachStatus = try runProcess(
                "/usr/bin/hdiutil",
                arguments: ["attach", archiveURL.path, "-nobrowse", "-readonly", "-mountpoint", mountPoint.path]
            )
            guard attachStatus == 0 else {
                throw NSError(domain: "WenBarUpdate", code: Int(attachStatus), userInfo: [NSLocalizedDescriptionKey: "挂载 DMG 失败"])
            }
            defer {
                _ = try? runProcess("/usr/bin/hdiutil", arguments: ["detach", mountPoint.path, "-force"])
            }
            guard let sourceApp = findAppBundle(in: mountPoint) else {
                throw NSError(domain: "WenBarUpdate", code: -3, userInfo: [NSLocalizedDescriptionKey: "DMG 内未找到 WenBar.app"])
            }
            let copiedApp = extractDir.appendingPathComponent("WenBar.app")
            let copyStatus = try runProcess("/usr/bin/ditto", arguments: [sourceApp.path, copiedApp.path])
            guard copyStatus == 0 else {
                throw NSError(domain: "WenBarUpdate", code: Int(copyStatus), userInfo: [NSLocalizedDescriptionKey: "复制 DMG 内应用失败"])
            }
            appURL = copiedApp
        } else {
            throw NSError(domain: "WenBarUpdate", code: -4, userInfo: [NSLocalizedDescriptionKey: "不支持的更新包格式：.\(ext)"])
        }

        // Verify bundle identifier matches com.wenbar.app
        let plistURL = appURL.appendingPathComponent("Contents/Info.plist")
        guard let plistDict = NSDictionary(contentsOf: plistURL),
              let bundleID = plistDict["CFBundleIdentifier"] as? String,
              bundleID == "com.wenbar.app" else {
            throw NSError(domain: "WenBarUpdate", code: -5, userInfo: [NSLocalizedDescriptionKey: "更新包 Bundle Identifier 校验不通过"])
        }

        // Strip quarantine and verify signature before replacing current app
        _ = try? runProcess("/usr/bin/xattr", arguments: ["-dr", "com.apple.quarantine", appURL.path])
        let verifyStatus = try runProcess("/usr/bin/codesign", arguments: ["--verify", "--deep", "--strict", appURL.path])
        guard verifyStatus == 0 else {
            throw NSError(domain: "WenBarUpdate", code: -6, userInfo: [NSLocalizedDescriptionKey: "更新包代码签名完整性校验失败"])
        }

        return appURL
    }

    private nonisolated static func findAppBundle(in directory: URL) -> URL? {
        let direct = directory.appendingPathComponent("WenBar.app")
        if FileManager.default.fileExists(atPath: direct.path) {
            return direct
        }
        guard let children = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return nil
        }
        for child in children where child.pathExtension == "app" {
            return child
        }
        return nil
    }

    private nonisolated static func runProcess(_ path: String, arguments: [String]) throws -> Int32 {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: path)
        proc.arguments = arguments
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        try proc.run()
        proc.waitUntilExit()
        return proc.terminationStatus
    }
}
