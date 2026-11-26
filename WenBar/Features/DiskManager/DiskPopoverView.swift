import SwiftUI
import WenBarCore

struct DiskPopoverView: View {
    @Bindable var diskManager: ExternalDriveManager
    @Bindable var settingsStore: SettingsStore
    @State private var confirmForceVolume: VolumeDescriptor?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("外接硬盘 / U盘", systemImage: "externaldrive.connected.to.line.below")
                    .font(.headline)
                Spacer()
                Button {
                    diskManager.refreshVolumes()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("刷新外接卷列表")

                if diskManager.externalVolumes.count > 1 {
                    Button("全部清理并推出") {
                        diskManager.cleanAndEjectAll()
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(diskManager.isProcessing)
                }
            }

            if diskManager.externalVolumes.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "externaldrive.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text("当前未检测到外接硬盘或 U 盘")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 10))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(diskManager.externalVolumes) { volume in
                            DiskVolumeCardView(volume: volume, diskManager: diskManager)
                        }
                    }
                }
                .frame(maxHeight: 260)
            }

            if let msg = diskManager.statusMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            // Quick anti-pollution toggles
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Toggle("禁止向 U盘/外接卷写入 .DS_Store", isOn: Binding(
                        get: { diskManager.dontWriteUSBStores },
                        set: { diskManager.setDontWriteUSBStores($0) }
                    ))
                    .toggleStyle(WenBarSwitchToggleStyle())
                    .font(.caption)

                    Spacer()

                    Button("重启 Finder 生效") {
                        diskManager.restartFinder()
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                }
            }
        }
        .sheet(item: $diskManager.busyAlert) { alertState in
            BusyVolumeSheet(
                alertState: alertState,
                onRetry: {
                    let vol = alertState.volume
                    diskManager.busyAlert = nil
                    diskManager.cleanAndEject(volume: vol)
                },
                onRequestForce: {
                    confirmForceVolume = alertState.volume
                },
                onDismiss: {
                    diskManager.busyAlert = nil
                }
            )
            .alert(
                "确认强制推出「\(confirmForceVolume?.name ?? "")」？",
                isPresented: Binding(
                    get: { confirmForceVolume != nil },
                    set: { if !$0 { confirmForceVolume = nil } }
                )
            ) {
                Button("取消", role: .cancel) { confirmForceVolume = nil }
                Button("强制推出", role: .destructive) {
                    if let vol = confirmForceVolume {
                        confirmForceVolume = nil
                        diskManager.forceEject(volume: vol)
                    }
                }
            } message: {
                Text("强制推出可能导致正在写入的数据丢失，请确认没有文件正在传输。")
            }
        }
    }
}

struct DiskVolumeCardView: View {
    let volume: VolumeDescriptor
    @Bindable var diskManager: ExternalDriveManager

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: volume.isTimeMachine ? "clock.arrow.circlepath" : "externaldrive.fill")
                    .foregroundStyle(volume.isTimeMachine ? Color.green : Color.accentColor)

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(volume.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text(volume.fileSystemType)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())

                        if volume.isTimeMachine {
                            Text("Time Machine 保护")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.green, in: Capsule())
                        } else if volume.isReadOnly {
                            Text("只读")
                                .font(.system(size: 10))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(Color.orange.opacity(0.2), in: Capsule())
                        }
                    }

                    Text("\(formatBytes(volume.availableBytes)) 可用 / 共 \(formatBytes(volume.totalBytes))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            ProgressView(value: volume.usedFraction)
                .progressViewStyle(.linear)

            HStack(spacing: 6) {
                if !volume.isTimeMachine && !volume.isReadOnly {
                    Button {
                        diskManager.toggleMetadataNeverIndex(for: volume)
                    } label: {
                        let active = diskManager.hasMetadataNeverIndex(for: volume)
                        Label(active ? "已禁 Spotlight" : "禁止索引", systemImage: active ? "eye.slash.fill" : "eye.slash")
                            .font(.caption2)
                    }
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                }

                Spacer()

                Button("仅推出") {
                    diskManager.ejectOnly(volume: volume)
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
                .disabled(diskManager.isProcessing)

                if !volume.isTimeMachine && !volume.isReadOnly {
                    Button("清理并推出") {
                        diskManager.cleanAndEject(volume: volume)
                    }
                    .controlSize(.small)
                    .buttonStyle(.borderedProminent)
                    .disabled(diskManager.isProcessing)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct BusyVolumeSheet: View {
    let alertState: BusyVolumeAlertState
    let onRetry: () -> Void
    let onRequestForce: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("无法推出「\(alertState.volume.name)」", systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            Text(alertState.errorMessage)
                .font(.caption)
                .foregroundStyle(.secondary)

            if alertState.processes.isEmpty {
                Text("未检测到明确的 lsof 文件句柄占用（可能是 Finder 或系统后台索引正在使用）。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("检测到以下进程正在占用此卷：")
                    .font(.caption.weight(.semibold))

                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(alertState.processes) { proc in
                            HStack {
                                Text(proc.command)
                                    .font(.caption.weight(.medium))
                                Spacer()
                                Text("PID \(proc.pid) (\(proc.user))")
                                    .font(.caption2.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
                .frame(maxHeight: 120)
                .padding(8)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            }

            HStack {
                Button("取消") { onDismiss() }
                Spacer()
                Button("强制推出", role: .destructive) { onRequestForce() }
                Button("重试推出") { onRetry() }
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(width: 360)
    }
}
