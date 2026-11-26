import SwiftUI
import Carbon.HIToolbox
import WenBarCore

struct WenBarSwitchToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer()
            Button {
                withAnimation(.spring(response: 0.22, dampingFraction: 0.8)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule(style: .continuous)
                        .fill(configuration.isOn ? Color.accentColor : Color.secondary.opacity(0.32))
                        .frame(width: 36, height: 20)

                    Circle()
                        .fill(Color.white)
                        .frame(width: 16, height: 16)
                        .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 0.5)
                        .padding(2)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("切换开关"))
            .accessibilityValue(Text(configuration.isOn ? "开启" : "关闭"))
        }
    }
}

struct SettingsView: View {
    @Bindable var settingsStore: SettingsStore
    @Bindable var clockVM: ClockViewModel
    @Bindable var calendarVM: CalendarViewModel
    @Bindable var diskManager: ExternalDriveManager
    @Bindable var updateService: UpdateService
    let hotkeyManager: GlobalHotkeyManager
    let onApplyHotkey: () -> Void
    let onModulesChanged: () -> Void

    @State private var draftTemplateName: String = ""
    @State private var editingCustomTemplateID: String?
    @State private var showingFullReleaseNotes = false

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("通用", systemImage: "gearshape")
                }

            clockCalendarTab
                .tabItem {
                    Label("时钟与日历", systemImage: "calendar.badge.clock")
                }

            diskTab
                .tabItem {
                    Label("外接磁盘", systemImage: "externaldrive")
                }

            archiveTab
                .tabItem {
                    Label("压缩与解压", systemImage: "archivebox")
                }
        }
        .toggleStyle(WenBarSwitchToggleStyle())
        .padding(16)
        .frame(minWidth: 580, minHeight: 520)
        .sheet(isPresented: $showingFullReleaseNotes) {
            if let release = updateService.availableRelease {
                ReleaseNotesSheet(release: release) {
                    showingFullReleaseNotes = false
                    Task { await updateService.downloadAndInstall() }
                }
            }
        }
    }

    private var generalTab: some View {
        Form {
            Section("功能模块开关") {
                Toggle("启用自定义时钟与日历面板", isOn: Binding(
                    get: { settingsStore.settings.enableClockCalendar },
                    set: {
                        settingsStore.settings.enableClockCalendar = $0
                        onModulesChanged()
                    }
                ))
                Toggle("启用外接硬盘 / U盘管理与清理", isOn: Binding(
                    get: { settingsStore.settings.enableDiskManager },
                    set: {
                        settingsStore.settings.enableDiskManager = $0
                        onModulesChanged()
                    }
                ))
                Toggle("启用 Finder 右键压缩 / 解压与 .DS_Store 清理", isOn: Binding(
                    get: { settingsStore.settings.enableArchiveTools },
                    set: {
                        settingsStore.settings.enableArchiveTools = $0
                        onModulesChanged()
                    }
                ))
            }

            Section("系统集成") {
                Toggle("开机自动启动", isOn: Binding(
                    get: { settingsStore.launchAtLogin },
                    set: { try? settingsStore.setLaunchAtLogin($0) }
                ))

                Picker("界面语言（重启后完全生效）", selection: Binding(
                    get: { settingsStore.settings.language },
                    set: { settingsStore.settings.language = $0 }
                )) {
                    ForEach(AppLanguageOption.allCases) { opt in
                        Text(opt.displayName).tag(opt)
                    }
                }

                HStack {
                    Text("全局唤起快捷键")
                    Spacer()
                    HotkeyRecorderButton(
                        keyCode: Binding(
                            get: { settingsStore.settings.hotkeyKeyCode },
                            set: {
                                settingsStore.settings.hotkeyKeyCode = $0
                                onApplyHotkey()
                            }
                        ),
                        modifiers: Binding(
                            get: { settingsStore.settings.hotkeyModifiers },
                            set: {
                                settingsStore.settings.hotkeyModifiers = $0
                                onApplyHotkey()
                            }
                        )
                    )
                }
            }

            Section("自动更新（GitHub Releases）") {
                Toggle("启动时自动检查 GitHub 新版本", isOn: Binding(
                    get: { settingsStore.settings.autoCheckUpdates },
                    set: { settingsStore.settings.autoCheckUpdates = $0 }
                ))

                HStack(spacing: 10) {
                    Image("WenBarLogo")
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("WenBar \(updateService.currentVersionDescription)")
                            .font(.subheadline.weight(.medium))
                        if let msg = updateService.lastCheckMessage {
                            Text(msg)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    Button("GitHub") {
                        updateService.openReleasesPage()
                    }

                    switch updateService.state {
                    case .checking:
                        ProgressView()
                            .controlSize(.small)
                    case .available:
                        Button("下载并安装重启") {
                            Task { await updateService.downloadAndInstall() }
                        }
                        .buttonStyle(.borderedProminent)
                    case .downloading, .installing:
                        ProgressView()
                            .controlSize(.small)
                    default:
                        Button("检查更新") {
                            Task { await updateService.checkForUpdates(silent: false) }
                        }
                    }
                }

                if case let .downloading(progress) = updateService.state {
                    ProgressView(value: progress) {
                        Text("正在下载更新包：\(Int(progress * 100))%")
                            .font(.caption2)
                    }
                }

                if let release = updateService.availableRelease, !release.body.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("更新说明（\(release.tagName)）")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("完整查看") {
                                showingFullReleaseNotes = true
                            }
                            .controlSize(.mini)
                            .buttonStyle(.bordered)
                        }

                        ScrollView {
                            Text(release.body)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(8)
                        }
                        .frame(minHeight: 130, maxHeight: 210)
                        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var clockCalendarTab: some View {
        Form {
            Section("菜单栏时间与日期格式") {
                Picker("快速应用模板", selection: Binding(
                    get: { settingsStore.settings.clockFormatTemplate },
                    set: {
                        settingsStore.settings.clockFormatTemplate = $0
                        clockVM.refreshScheduling()
                    }
                )) {
                    if !settingsStore.settings.customClockTemplates.isEmpty {
                        Section("我的自定义模板") {
                            ForEach(settingsStore.settings.customClockTemplates) { preset in
                                Text("★ \(preset.name)  (\(preset.template))").tag(preset.template)
                            }
                        }
                    }
                    Section("内置预设模板") {
                        ForEach(ClockFormatEngine.presets) { preset in
                            Text("\(preset.name)  (\(preset.template))").tag(preset.template)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    TextField("自定义格式字符串", text: Binding(
                        get: { settingsStore.settings.clockFormatTemplate },
                        set: {
                            settingsStore.settings.clockFormatTemplate = $0
                            clockVM.refreshScheduling()
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))

                    HStack(spacing: 8) {
                        Button("插入换行 \\n") {
                            settingsStore.settings.clockFormatTemplate += "\\n"
                            clockVM.refreshScheduling()
                        }
                        Button("清空") {
                            settingsStore.settings.clockFormatTemplate = ""
                            clockVM.refreshScheduling()
                        }
                        Button("恢复默认") {
                            settingsStore.settings.clockFormatTemplate = "MM/dd EEE HH:mm"
                            editingCustomTemplateID = nil
                            draftTemplateName = ""
                            clockVM.refreshScheduling()
                        }
                        Spacer()
                    }
                    .controlSize(.small)

                    Divider()

                    HStack(spacing: 8) {
                        TextField("输入模板名称（如：工作双行）", text: $draftTemplateName)
                            .textFieldStyle(.roundedBorder)

                        Button(editingCustomTemplateID == nil ? "保存为模板" : "更新模板") {
                            saveCurrentAsCustomTemplate()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(
                            settingsStore.settings.clockFormatTemplate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        )

                        if editingCustomTemplateID != nil {
                            Button("取消编辑") {
                                editingCustomTemplateID = nil
                                draftTemplateName = ""
                            }
                        }
                    }
                    .controlSize(.small)
                }

                HStack {
                    Text("菜单栏实时预览")
                    Spacer()
                    HStack(spacing: 4) {
                        if settingsStore.settings.clockShowCalendarIcon {
                            Image(systemName: "calendar")
                                .font(.system(size: settingsStore.settings.clockFontSize))
                        }
                        Text(clockVM.menuBarTitle)
                            .multilineTextAlignment(.center)
                            .font(.system(
                                size: clockVM.menuBarTitle.contains("\n")
                                    ? max(9.5, settingsStore.settings.clockFontSize - 3.5)
                                    : settingsStore.settings.clockFontSize,
                                weight: swiftUIFontWeight(settingsStore.settings.clockFontWeight),
                                design: settingsStore.settings.clockUseMonospacedDigits ? .monospaced : .default
                            ))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }

            if !settingsStore.settings.customClockTemplates.isEmpty {
                Section("我的已保存模板") {
                    ForEach(settingsStore.settings.customClockTemplates) { item in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.name)
                                    .font(.subheadline.weight(.medium))
                                Text(item.template)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Button("使用") {
                                settingsStore.settings.clockFormatTemplate = item.template
                                clockVM.refreshScheduling()
                            }

                            Button("编辑") {
                                editingCustomTemplateID = item.id
                                draftTemplateName = item.name
                                settingsStore.settings.clockFormatTemplate = item.template
                                clockVM.refreshScheduling()
                            }

                            Button(role: .destructive) {
                                settingsStore.settings.customClockTemplates.removeAll { $0.id == item.id }
                                if editingCustomTemplateID == item.id {
                                    editingCustomTemplateID = nil
                                    draftTemplateName = ""
                                }
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                        .controlSize(.small)
                    }
                }
            }

            Section("点击插入常用占位符") {
                ForEach(ClockFormatToken.Category.allCases, id: \.rawValue) { category in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(category.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        let tokens = ClockFormatEngine.availableTokens.filter { $0.category == category }
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(tokens) { item in
                                Button {
                                    let current = settingsStore.settings.clockFormatTemplate
                                    let sep = (current.isEmpty || current.hasSuffix(" ") || current.hasSuffix("\\n")) ? "" : " "
                                    settingsStore.settings.clockFormatTemplate = current + sep + item.token
                                    clockVM.refreshScheduling()
                                } label: {
                                    HStack(spacing: 4) {
                                        Text(item.token)
                                            .font(.system(size: 11, design: .monospaced))
                                        Text(item.label)
                                            .font(.system(size: 11))
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("示例：\(item.example)")
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("菜单栏外观排版") {
                HStack {
                    Text("字体大小：\(Int(settingsStore.settings.clockFontSize)) pt")
                    Slider(
                        value: Binding(
                            get: { settingsStore.settings.clockFontSize },
                            set: {
                                settingsStore.settings.clockFontSize = $0
                                onModulesChanged()
                            }
                        ),
                        in: 10...16,
                        step: 1
                    )
                }

                Picker("字重", selection: Binding(
                    get: { settingsStore.settings.clockFontWeight },
                    set: {
                        settingsStore.settings.clockFontWeight = $0
                        onModulesChanged()
                    }
                )) {
                    ForEach(ClockFontWeightOption.allCases) { opt in
                        Text(opt.displayName).tag(opt)
                    }
                }
                .pickerStyle(.segmented)

                Toggle("使用等宽数字（秒数跳动不抖动）", isOn: Binding(
                    get: { settingsStore.settings.clockUseMonospacedDigits },
                    set: {
                        settingsStore.settings.clockUseMonospacedDigits = $0
                        onModulesChanged()
                    }
                ))

                Toggle("在时间左侧显示日历小图标", isOn: Binding(
                    get: { settingsStore.settings.clockShowCalendarIcon },
                    set: {
                        settingsStore.settings.clockShowCalendarIcon = $0
                        onModulesChanged()
                    }
                ))

                Toggle("计时器运行时在菜单栏显示剩余时间", isOn: Binding(
                    get: { settingsStore.settings.showCountdownInMenuBar },
                    set: {
                        settingsStore.settings.showCountdownInMenuBar = $0
                        clockVM.refreshScheduling()
                    }
                ))
            }

            Section("节假日与调休数据") {
                Toggle("自动在线同步最新国务院放假/调休安排", isOn: Binding(
                    get: { settingsStore.settings.autoSyncHolidays },
                    set: { settingsStore.settings.autoSyncHolidays = $0 }
                ))

                HStack {
                    Text("数据状态：\(calendarVM.holidaySyncStatus)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("立即刷新") {
                        Task { await calendarVM.syncOnlineHolidays() }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func saveCurrentAsCustomTemplate() {
        let template = settingsStore.settings.clockFormatTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !template.isEmpty else { return }

        let trimmedName = draftTemplateName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmedName.isEmpty
            ? "自定义模板 \(settingsStore.settings.customClockTemplates.count + 1)"
            : trimmedName

        if let editID = editingCustomTemplateID,
           let idx = settingsStore.settings.customClockTemplates.firstIndex(where: { $0.id == editID }) {
            settingsStore.settings.customClockTemplates[idx] = ClockFormatPreset(id: editID, name: name, template: template)
            editingCustomTemplateID = nil
        } else if let sameNameIdx = settingsStore.settings.customClockTemplates.firstIndex(where: { $0.name == name }) {
            let existingID = settingsStore.settings.customClockTemplates[sameNameIdx].id
            settingsStore.settings.customClockTemplates[sameNameIdx] = ClockFormatPreset(id: existingID, name: name, template: template)
        } else {
            let newPreset = ClockFormatPreset(id: UUID().uuidString, name: name, template: template)
            settingsStore.settings.customClockTemplates.append(newPreset)
        }

        draftTemplateName = ""
    }

    private func swiftUIFontWeight(_ opt: ClockFontWeightOption) -> Font.Weight {
        switch opt {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        }
    }

    private var diskTab: some View {
        Form {
            Section("菜单栏入口展示") {
                Toggle("插入外接硬盘/U盘时显示独立菜单栏图标", isOn: Binding(
                    get: { settingsStore.settings.showStandaloneDiskIcon },
                    set: {
                        settingsStore.settings.showStandaloneDiskIcon = $0
                        onModulesChanged()
                    }
                ))
                Toggle("同时在时钟/日历主弹窗中显示外接盘卡片", isOn: Binding(
                    get: { settingsStore.settings.showDisksInMainPopover },
                    set: { settingsStore.settings.showDisksInMainPopover = $0 }
                ))
            }

            Section("推出前默认清理规则（自动避让 Time Machine 与系统盘）") {
                ForEach(JunkRule.allCases) { rule in
                    Toggle(rule.displayName, isOn: Binding(
                        get: { settingsStore.settings.enabledJunkRules.contains(rule) },
                        set: { enabled in
                            if enabled {
                                settingsStore.settings.enabledJunkRules.insert(rule)
                            } else {
                                settingsStore.settings.enabledJunkRules.remove(rule)
                            }
                        }
                    ))
                }
            }

            Section("系统级源头防污染") {
                Toggle("禁止向 USB/外接移动盘写入 .DS_Store", isOn: Binding(
                    get: { diskManager.dontWriteUSBStores },
                    set: { diskManager.setDontWriteUSBStores($0) }
                ))
                Toggle("禁止向网络共享盘写入 .DS_Store", isOn: Binding(
                    get: { diskManager.dontWriteNetworkStores },
                    set: { diskManager.setDontWriteNetworkStores($0) }
                ))
                HStack {
                    Text("更改系统写入策略后需重启 Finder 生效")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("立即重启 Finder") {
                        diskManager.restartFinder()
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var archiveTab: some View {
        Form {
            Section("默认压缩策略") {
                Picker("右键「压缩为 ZIP/默认格式」格式", selection: Binding(
                    get: { settingsStore.settings.defaultArchiveFormat },
                    set: { settingsStore.settings.defaultArchiveFormat = $0 }
                )) {
                    ForEach(ArchiveFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }

                Picker("默认压缩级别", selection: Binding(
                    get: { settingsStore.settings.defaultCompressionLevel },
                    set: { settingsStore.settings.defaultCompressionLevel = $0 }
                )) {
                    ForEach(CompressionLevel.allCases) { lvl in
                        Text(lvl.displayName).tag(lvl)
                    }
                }

                Toggle("压缩完成后自动清理源目录中的 .DS_Store", isOn: Binding(
                    get: { settingsStore.settings.deleteSourceDSStoreAfterCompress },
                    set: { settingsStore.settings.deleteSourceDSStoreAfterCompress = $0 }
                ))
            }

            Section("解压策略") {
                Toggle("解压完成后自动将原压缩包移至废纸篓", isOn: Binding(
                    get: { settingsStore.settings.trashArchiveAfterExtract },
                    set: { settingsStore.settings.trashArchiveAfterExtract = $0 }
                ))
                Text("所有压缩包都会自动排除 .DS_Store / ._* / __MACOSX，并在解压 ZIP 时自动修复 Windows 中文文件名乱码。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct HotkeyRecorderButton: View {
    @Binding var keyCode: UInt32
    @Binding var modifiers: UInt32
    @State private var isRecording = false
    @State private var monitor: Any?

    var body: some View {
        Button {
            if isRecording {
                stopRecording()
            } else {
                startRecording()
            }
        } label: {
            Text(isRecording ? "请按下组合键…" : GlobalHotkeyManager.describeHotkey(keyCode: keyCode, modifiers: modifiers))
                .font(.system(.body, design: .monospaced))
                .frame(minWidth: 110)
        }
        .onDisappear {
            stopRecording()
        }
    }

    private func startRecording() {
        isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = GlobalHotkeyManager.carbonModifiers(from: event.modifierFlags)
            if event.keyCode == UInt16(kVK_Escape) && mods == 0 {
                stopRecording()
                return nil
            }
            guard mods != 0 else { return event }
            keyCode = UInt32(event.keyCode)
            modifiers = mods
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }
}

private struct ReleaseNotesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let release: GitHubRelease
    let onInstall: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image("WenBarLogo")
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(release.name.isEmpty ? "WenBar \(release.tagName)" : release.name)
                        .font(.headline)
                    Text("版本标签：\(release.tagName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }

            Divider()

            ScrollView {
                Text(release.body)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
            }
            .frame(minHeight: 260, maxHeight: 380)

            HStack {
                Button("在 GitHub 打开") {
                    NSWorkspace.shared.open(release.htmlURL)
                }
                Spacer()
                Button("关闭") { dismiss() }
                Button("下载并安装重启") {
                    onInstall()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(18)
        .frame(width: 520)
    }
}
