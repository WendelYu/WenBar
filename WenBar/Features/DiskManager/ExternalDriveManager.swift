import Foundation
import AppKit
import DiskArbitration
import WenBarCore

struct BusyVolumeAlertState: Identifiable, Sendable {
    let id = UUID()
    let volume: VolumeDescriptor
    let processes: [OccupyingProcess]
    let errorMessage: String
}

@MainActor
@Observable
final class ExternalDriveManager {
    var externalVolumes: [VolumeDescriptor] = []
    var busyAlert: BusyVolumeAlertState?
    var statusMessage: String?
    var isProcessing: Bool = false

    // System-level anti-pollution preferences
    var dontWriteUSBStores: Bool = false
    var dontWriteNetworkStores: Bool = false

    private let settingsStore: SettingsStore
    private var observers: [NSObjectProtocol] = []
    @ObservationIgnored var onVolumesChanged: (() -> Void)?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        refreshVolumes()
        refreshSystemAntiPollutionFlags()
        startObservingMountEvents()
    }

    func refreshVolumes() {
        let keys: [URLResourceKey] = [
            .volumeNameKey,
            .volumeLocalizedFormatDescriptionKey,
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeIsRemovableKey,
            .volumeIsEjectableKey,
            .volumeIsInternalKey,
            .volumeIsReadOnlyKey,
            .volumeIsLocalKey
        ]

        guard let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: keys,
            options: [.skipHiddenVolumes]
        ) else {
            externalVolumes = []
            return
        }

        var found: [VolumeDescriptor] = []
        for url in urls {
            guard let rv = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            let isInternal = rv.volumeIsInternal ?? true
            let isRemovable = rv.volumeIsRemovable ?? false
            let isEjectable = rv.volumeIsEjectable ?? false
            let isLocal = rv.volumeIsLocal ?? true

            // Keep external / removable / ejectable local drives, skip network shares unless mounted under /Volumes as removable
            let isExternal = !isInternal || isRemovable || isEjectable
            guard isExternal && isLocal && url.path != "/" else { continue }

            let name = rv.volumeName ?? url.lastPathComponent
            let fsType = rv.volumeLocalizedFormatDescription ?? "Unknown"
            let total = Int64(rv.volumeTotalCapacity ?? 0)
            let available = Int64(rv.volumeAvailableCapacity ?? 0)
            let isReadOnly = rv.volumeIsReadOnly ?? false
            let isTimeMachine = DiskSafetyGuard.detectTimeMachineMarkers(at: url)

            found.append(
                VolumeDescriptor(
                    name: name,
                    mountPoint: url,
                    fileSystemType: fsType,
                    totalBytes: total,
                    availableBytes: available,
                    isExternal: isExternal,
                    isRemovable: isRemovable,
                    isEjectable: isEjectable,
                    isReadOnly: isReadOnly,
                    isInternal: isInternal,
                    isTimeMachine: isTimeMachine
                )
            )
        }

        externalVolumes = found.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        onVolumesChanged?()
    }

    func hasMetadataNeverIndex(for volume: VolumeDescriptor) -> Bool {
        let marker = volume.mountPoint.appendingPathComponent(".metadata_never_index")
        return FileManager.default.fileExists(atPath: marker.path)
    }

    func toggleMetadataNeverIndex(for volume: VolumeDescriptor) {
        guard case .success = DiskSafetyGuard.validateForCleanup(volume) else {
            statusMessage = "该卷受安全保护（只读或 Time Machine 备份盘），无法写入防索引标记。"
            return
        }
        let marker = volume.mountPoint.appendingPathComponent(".metadata_never_index")
        do {
            if FileManager.default.fileExists(atPath: marker.path) {
                try FileManager.default.removeItem(at: marker)
                statusMessage = "已移除 \(volume.name) 的 Spotlight 防索引标记"
            } else {
                try Data().write(to: marker, options: .atomic)
                statusMessage = "已为 \(volume.name) 写入 .metadata_never_index，阻止 Spotlight 索引"
            }
        } catch {
            statusMessage = "操作失败：\(error.localizedDescription)"
        }
    }

    func refreshSystemAntiPollutionFlags() {
        let defaults = UserDefaults(suiteName: "com.apple.desktopservices")
        dontWriteUSBStores = defaults?.bool(forKey: "DSDontWriteUSBStores") ?? false
        dontWriteNetworkStores = defaults?.bool(forKey: "DSDontWriteNetworkStores") ?? false
    }

    func setDontWriteUSBStores(_ enabled: Bool) {
        let defaults = UserDefaults(suiteName: "com.apple.desktopservices")
        defaults?.set(enabled, forKey: "DSDontWriteUSBStores")
        defaults?.synchronize()
        dontWriteUSBStores = enabled
    }

    func setDontWriteNetworkStores(_ enabled: Bool) {
        let defaults = UserDefaults(suiteName: "com.apple.desktopservices")
        defaults?.set(enabled, forKey: "DSDontWriteNetworkStores")
        defaults?.synchronize()
        dontWriteNetworkStores = enabled
    }

    func restartFinder() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Finder"]
        try? task.run()
    }

    func cleanAndEject(volume: VolumeDescriptor) {
        Task {
            await performCleanAndEject(volumes: [volume], cleanFirst: true)
        }
    }

    func ejectOnly(volume: VolumeDescriptor) {
        Task {
            await performCleanAndEject(volumes: [volume], cleanFirst: false)
        }
    }

    func cleanAndEjectAll() {
        let snapshot = externalVolumes
        guard !snapshot.isEmpty else { return }
        Task {
            await performCleanAndEject(volumes: snapshot, cleanFirst: true)
        }
    }

    func forceEject(volume: VolumeDescriptor) {
        Task {
            isProcessing = true
            defer { isProcessing = false }
            let result = await Task.detached {
                Self.ejectVolumeSync(at: volume.mountPoint, force: true)
            }.value

            switch result {
            case .success:
                busyAlert = nil
                statusMessage = "已强制推出 \(volume.name)"
                NotificationService.shared.post(title: "已强制推出磁盘", body: "\(volume.name) 已安全断开。")
                refreshVolumes()
            case let .failure(err):
                statusMessage = "强制推出失败：\(err.localizedDescription)"
            }
        }
    }

    private func performCleanAndEject(volumes: [VolumeDescriptor], cleanFirst: Bool) async {
        isProcessing = true
        defer { isProcessing = false }

        var cleanedTotal = 0
        var freedBytesTotal: Int64 = 0
        let rules = settingsStore.settings.enabledJunkRules

        for volume in volumes {
            if cleanFirst {
                switch DiskSafetyGuard.validateForCleanup(volume) {
                case .success:
                    let report = await Task.detached {
                        JunkFileCleaner.clean(rootDirectory: volume.mountPoint, rules: rules)
                    }.value
                    cleanedTotal += report.removedCount
                    freedBytesTotal += report.freedBytes
                case let .failure(reason):
                    // Time Machine or read-only: skip junk deletion, allow normal eject
                    if reason == .timeMachineBackup {
                        statusMessage = "已跳过 Time Machine 备份盘 \(volume.name) 的清理，仅执行推出。"
                    }
                }
            }

            let ejectResult = await Task.detached {
                Self.ejectVolumeSync(at: volume.mountPoint, force: false)
            }.value

            switch ejectResult {
            case .success:
                let sizeText = ByteCountFormatter.string(fromByteCount: freedBytesTotal, countStyle: .file)
                if cleanFirst && cleanedTotal > 0 {
                    statusMessage = "已清理 \(cleanedTotal) 个垃圾文件（\(sizeText)）并推出 \(volume.name)"
                    NotificationService.shared.post(
                        title: "外接磁盘已清理并安全推出",
                        body: "\(volume.name)：清理了 \(cleanedTotal) 项系统垃圾（\(sizeText)）。"
                    )
                } else {
                    statusMessage = "已安全推出 \(volume.name)"
                    NotificationService.shared.post(title: "外接磁盘已安全推出", body: "\(volume.name) 可以安全拔出了。")
                }
                refreshVolumes()

            case let .failure(err):
                let processes = await Task.detached {
                    Self.detectOccupyingProcesses(at: volume.mountPoint)
                }.value
                busyAlert = BusyVolumeAlertState(
                    volume: volume,
                    processes: processes,
                    errorMessage: err.localizedDescription
                )
                statusMessage = "推出 \(volume.name) 失败：设备正忙"
                return
            }
        }
    }

    private func startObservingMountEvents() {
        let nc = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didMountNotification,
            NSWorkspace.didUnmountNotification,
            NSWorkspace.didRenameVolumeNotification
        ]
        for name in names {
            let obs = nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    self?.refreshVolumes()
                }
            }
            observers.append(obs)
        }
    }

    private nonisolated static func detectOccupyingProcesses(at mountPoint: URL) -> [OccupyingProcess] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/lsof")
        process.arguments = ["+D", mountPoint.path]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        let semaphore = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            semaphore.signal()
        }

        do {
            try process.run()
        } catch {
            return []
        }

        if semaphore.wait(timeout: .now() + 4.0) == .timedOut, process.isRunning {
            process.terminate()
            _ = semaphore.wait(timeout: .now() + 0.5)
        }

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return LsofParser.parseStandardOutput(output)
    }

    private nonisolated static func ejectVolumeSync(at mountPoint: URL, force: Bool) -> Result<Void, NSError> {
        // First try NSWorkspace unmountAndEjectDevice when not forcing
        if !force {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: mountPoint)
                return .success(())
            } catch {
                // Fallback to DiskArbitration for finer control / error code
            }
        }

        guard let session = DASessionCreate(kCFAllocatorDefault) else {
            return .failure(NSError(domain: "WenBarDisk", code: -1, userInfo: [NSLocalizedDescriptionKey: "无法创建 DiskArbitration 会话"]))
        }

        let queue = DispatchQueue(label: "com.wenbar.diskarbitration")
        DASessionSetDispatchQueue(session, queue)
        defer { DASessionSetDispatchQueue(session, nil) }

        guard let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, mountPoint as CFURL) else {
            return .failure(NSError(domain: "WenBarDisk", code: -2, userInfo: [NSLocalizedDescriptionKey: "找不到磁盘设备句柄"]))
        }

        final class CallbackBox: @unchecked Sendable {
            let semaphore = DispatchSemaphore(value: 0)
            var status: DAReturn = DAReturn(kDAReturnSuccess)
            var message: String = "推出失败"
        }

        let box = CallbackBox()
        let options: DADiskUnmountOptions = DADiskUnmountOptions(
            force ? kDADiskUnmountOptionForce : kDADiskUnmountOptionDefault
        )

        let unmountCallback: DADiskUnmountCallback = { _, dissenter, context in
            guard let context else { return }
            let state = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            if let dissenter {
                state.status = DADissenterGetStatus(dissenter)
                if let str = DADissenterGetStatusString(dissenter) as String? {
                    state.message = str
                } else {
                    state.message = "卷正在被其他程序占用"
                }
            }
            state.semaphore.signal()
        }

        let ctx = Unmanaged.passUnretained(box).toOpaque()
        DADiskUnmount(disk, options, unmountCallback, ctx)
        _ = box.semaphore.wait(timeout: .now() + 15)

        if box.status != DAReturn(kDAReturnSuccess) {
            return .failure(NSError(domain: "WenBarDisk", code: Int(box.status), userInfo: [NSLocalizedDescriptionKey: box.message]))
        }

        // Also eject whole physical media if ejectable
        let ejectBox = CallbackBox()
        let ejectCallback: DADiskEjectCallback = { _, dissenter, context in
            guard let context else { return }
            let state = Unmanaged<CallbackBox>.fromOpaque(context).takeUnretainedValue()
            if let dissenter {
                state.status = DADissenterGetStatus(dissenter)
            }
            state.semaphore.signal()
        }
        DADiskEject(disk, DADiskEjectOptions(kDADiskEjectOptionDefault), ejectCallback, Unmanaged.passUnretained(ejectBox).toOpaque())
        _ = ejectBox.semaphore.wait(timeout: .now() + 10)

        return .success(())
    }
}
