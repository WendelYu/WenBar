import SwiftUI
import EventKit
import UserNotifications

struct OnboardingView: View {
    @Bindable var calendarVM: CalendarViewModel
    let onDone: () -> Void

    @State private var finderExtensionEnabled: Bool = false
    @State private var notificationStatus: UNAuthorizationStatus = .notDetermined
    @State private var isChecking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image("WenBarLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("欢迎使用 WenBar")
                        .font(.title2.bold())
                    Text("请按以下几步确认系统权限，确保右键菜单、日历日程和通知功能正常工作。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            VStack(spacing: 10) {
                permissionRow(
                    title: "Finder 右键菜单扩展",
                    subtitle: "用于提供右键压缩、解压与清理 .DS_Store 菜单",
                    granted: finderExtensionEnabled,
                    actionTitle: "打开系统扩展设置"
                ) {
                    openFinderExtensionsSettings()
                }

                permissionRow(
                    title: "系统日历（EventKit）",
                    subtitle: "在菜单栏日历中显示并快速新建日程",
                    granted: calendarVM.calendarAccessGranted,
                    actionTitle: "立即授权"
                ) {
                    Task {
                        _ = await calendarVM.requestCalendarAccess()
                        await refreshStatuses()
                    }
                }

                permissionRow(
                    title: "系统提醒事项（EventKit）",
                    subtitle: "在日历下方展示当日待办并支持勾选完成",
                    granted: calendarVM.remindersAccessGranted,
                    actionTitle: "立即授权"
                ) {
                    Task {
                        _ = await calendarVM.requestRemindersAccess()
                        await refreshStatuses()
                    }
                }

                permissionRow(
                    title: "系统通知",
                    subtitle: "用于压缩/解压完成、磁盘推出结果及番茄钟结束提醒",
                    granted: notificationStatus == .authorized,
                    actionTitle: "允许通知"
                ) {
                    Task {
                        _ = await NotificationService.shared.requestAuthorizationIfNeeded()
                        await refreshStatuses()
                    }
                }
            }

            HStack {
                Button {
                    Task { await refreshStatuses() }
                } label: {
                    Label("重新检测状态", systemImage: "arrow.clockwise")
                }
                .disabled(isChecking)

                Spacer()

                Button("开始使用 WenBar") {
                    onDone()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 500)
        .task {
            await refreshStatuses()
        }
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        subtitle: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .font(.title3)
                .foregroundStyle(granted ? Color.green : Color.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if granted {
                Text("已就绪")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle, action: action)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func refreshStatuses() async {
        isChecking = true
        defer { isChecking = false }

        calendarVM.refreshAuthorizationStatus()
        notificationStatus = await NotificationService.shared.authorizationStatus()
        finderExtensionEnabled = await Task.detached {
            Self.checkFinderExtensionEnabled()
        }.value
    }

    private func openFinderExtensionsSettings() {
        // Attempt registering extension first so it appears in System Settings immediately
        if let pluginsURL = Bundle.main.builtInPlugInsURL {
            let appex = pluginsURL.appendingPathComponent("WenBarFinderSync.appex")
            if FileManager.default.fileExists(atPath: appex.path) {
                let reg = Process()
                reg.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
                reg.arguments = ["-a", appex.path]
                try? reg.run()
                reg.waitUntilExit()
            }
        }

        if let url = URL(string: "x-apple.systempreferences:com.apple.ExtensionsPreferences") {
            NSWorkspace.shared.open(url)
        }
    }

    private nonisolated static func checkFinderExtensionEnabled() -> Bool {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/pluginkit")
        proc.arguments = ["-m", "-v", "-i", "com.wenbar.app.FinderSync"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let out = String(data: data, encoding: .utf8) ?? ""
            return out.contains("+")
        } catch {
            return false
        }
    }
}
