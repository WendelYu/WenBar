import SwiftUI
import WenBarCore

enum MainPopoverTab: String, CaseIterable, Identifiable {
    case calendar = "日历"
    case utilities = "工具"
    case disks = "磁盘"

    var id: String { rawValue }
}

struct MainPopoverView: View {
    @Bindable var clockVM: ClockViewModel
    @Bindable var calendarVM: CalendarViewModel
    @Bindable var diskManager: ExternalDriveManager
    @Bindable var archiveManager: ArchiveTaskManager
    @Bindable var settingsStore: SettingsStore
    @Bindable var updateService: UpdateService

    let onOpenSettings: () -> Void
    let onOpenOnboarding: () -> Void

    @State private var selectedTab: MainPopoverTab = .calendar

    var body: some View {
        VStack(spacing: 10) {
            // Top bar
            HStack(spacing: 8) {
                Picker("", selection: $selectedTab) {
                    if settingsStore.settings.enableClockCalendar {
                        Text("日历").tag(MainPopoverTab.calendar)
                        Text("工具").tag(MainPopoverTab.utilities)
                    }
                    if settingsStore.settings.enableDiskManager {
                        Text("磁盘 (\(diskManager.externalVolumes.count))").tag(MainPopoverTab.disks)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                Spacer()

                Button {
                    onOpenOnboarding()
                } label: {
                    Image(systemName: "checkmark.shield")
                }
                .buttonStyle(.borderless)
                .help("权限检测与使用引导")

                Button {
                    onOpenSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("打开设置")
            }

            ArchiveProgressBannerView(archiveManager: archiveManager)

            updateBannerView

            switch selectedTab {
            case .calendar:
                if settingsStore.settings.enableClockCalendar {
                    ScrollView(.vertical) {
                        VStack(spacing: 10) {
                            CalendarMonthView(calendarVM: calendarVM)
                            DayDetailView(calendarVM: calendarVM)

                            if settingsStore.settings.enableDiskManager
                                && settingsStore.settings.showDisksInMainPopover
                                && !diskManager.externalVolumes.isEmpty {
                                compactDiskBar
                            }
                        }
                        .padding(.bottom, 4)
                    }
                    .scrollIndicators(.hidden)
                } else {
                    Spacer()
                    Text("时钟与日历模块已在设置中关闭")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }

            case .utilities:
                UtilitiesTabView(
                    clockVM: clockVM,
                    calendarVM: calendarVM,
                    settingsStore: settingsStore
                )

            case .disks:
                DiskPopoverView(diskManager: diskManager, settingsStore: settingsStore)
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(width: 420, height: 640, alignment: .top)
        .background(adaptiveBackground)
        .onAppear {
            if !settingsStore.settings.enableClockCalendar && settingsStore.settings.enableDiskManager {
                selectedTab = .disks
            }
        }
    }

    @ViewBuilder
    private var updateBannerView: some View {
        switch updateService.state {
        case let .available(release, _):
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("发现新版本 \(release.tagName)")
                    .font(.caption.weight(.medium))
                Spacer()
                Button("立即更新") {
                    Task { await updateService.downloadAndInstall() }
                }
                .controlSize(.mini)
                .buttonStyle(.borderedProminent)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

        case let .downloading(progress):
            HStack(spacing: 8) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                Text("\(Int(progress * 100))%")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

        case .installing:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("正在自动替换并重启…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))

        default:
            EmptyView()
        }
    }

    private var compactDiskBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("外接卷 (\(diskManager.externalVolumes.count))", systemImage: "externaldrive.fill")
                    .font(.caption.weight(.semibold))
                Spacer()
                Button("管理") {
                    selectedTab = .disks
                }
                .controlSize(.mini)
                .buttonStyle(.bordered)

                Button("全部清理并推出") {
                    diskManager.cleanAndEjectAll()
                }
                .controlSize(.mini)
                .buttonStyle(.borderedProminent)
                .disabled(diskManager.isProcessing)
            }

            ForEach(diskManager.externalVolumes.prefix(2)) { vol in
                HStack(spacing: 6) {
                    Text(vol.name)
                        .font(.caption2.weight(.medium))
                        .lineLimit(1)
                    Text(vol.fileSystemType)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !vol.isTimeMachine && !vol.isReadOnly {
                        Button("清理推出") {
                            diskManager.cleanAndEject(volume: vol)
                        }
                        .controlSize(.mini)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    @ViewBuilder
    private var adaptiveBackground: some View {
        if #available(macOS 26.0, *) {
            Color.clear.background(.ultraThinMaterial)
        } else {
            Color.clear.background(.regularMaterial)
        }
    }
}
