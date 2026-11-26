import SwiftUI
import WenBarCore

struct ArchiveProgressBannerView: View {
    @Bindable var archiveManager: ArchiveTaskManager

    var body: some View {
        if let task = archiveManager.activeTask {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "archivebox.fill")
                        .foregroundStyle(Color.accentColor)
                    Text(task.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Spacer()
                    Text(task.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Button {
                        archiveManager.cancelActiveTask()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("取消任务")
                }

                if task.isIndeterminate {
                    ProgressView()
                        .progressViewStyle(.linear)
                } else {
                    ProgressView(value: task.fraction)
                        .progressViewStyle(.linear)
                }
            }
            .padding(10)
            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct CustomCompressView: View {
    let sources: [URL]
    @Bindable var archiveManager: ArchiveTaskManager
    @Bindable var settingsStore: SettingsStore
    let onClose: () -> Void

    @State private var selectedFormat: ArchiveFormat
    @State private var selectedLevel: CompressionLevel
    @State private var password: String = ""
    @State private var cleanSourceDSStore: Bool

    init(
        sources: [URL],
        archiveManager: ArchiveTaskManager,
        settingsStore: SettingsStore,
        onClose: @escaping () -> Void
    ) {
        self.sources = sources
        self.archiveManager = archiveManager
        self.settingsStore = settingsStore
        self.onClose = onClose
        _selectedFormat = State(initialValue: settingsStore.settings.defaultArchiveFormat)
        _selectedLevel = State(initialValue: settingsStore.settings.defaultCompressionLevel)
        _cleanSourceDSStore = State(initialValue: settingsStore.settings.deleteSourceDSStoreAfterCompress)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "doc.zipper")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("加密 / 自定义压缩")
                        .font(.headline)
                    Text("已选 \(sources.count) 项：\(sources.map(\.lastPathComponent).joined(separator: ", "))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Form {
                Picker("归档格式", selection: $selectedFormat) {
                    ForEach(ArchiveFormat.allCases) { fmt in
                        Text(fmt.displayName).tag(fmt)
                    }
                }

                Picker("压缩级别", selection: $selectedLevel) {
                    ForEach(CompressionLevel.allCases) { lvl in
                        Text(lvl.displayName).tag(lvl)
                    }
                }
                .disabled(selectedFormat == .tarGz)

                if selectedFormat.supportsEncryption {
                    SecureField("加密密码（留空则不加密）", text: $password)
                } else {
                    Text("TAR.GZ 格式不支持直接加密，如需加密请选择 ZIP 或 7Z。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Toggle("压缩后自动删除源目录中的 .DS_Store", isOn: $cleanSourceDSStore)
            }
            .formStyle(.grouped)

            HStack {
                Text("包内自动过滤 .DS_Store、._*、__MACOSX")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { onClose() }
                Button("开始压缩") {
                    let pwd = (selectedFormat.supportsEncryption && !password.isEmpty) ? password : nil
                    archiveManager.enqueueCompress(
                        sources: sources,
                        format: selectedFormat,
                        level: selectedLevel,
                        password: pwd,
                        cleanSourceDSStore: cleanSourceDSStore
                    )
                    onClose()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

struct PasswordPromptView: View {
    let request: PasswordPromptRequest
    let onSubmit: (String) -> Void
    let onCancel: () -> Void

    @State private var password: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("需要解压密码", systemImage: "lock.shield")
                .font(.headline)

            Text("归档文件「\(request.archiveURL.lastPathComponent)」已加密，请输入密码继续解压：")
                .font(.caption)
                .foregroundStyle(.secondary)

            if let hint = request.errorHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            SecureField("输入密码", text: $password)
                .textFieldStyle(.roundedBorder)

            HStack {
                Spacer()
                Button("取消") { onCancel() }
                Button("解压") {
                    onSubmit(password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(password.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}
