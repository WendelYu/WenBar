import Cocoa
import FinderSync
import WenBarCore

final class FinderSync: FIFinderSync {
    override init() {
        super.init()
        FIFinderSyncController.default().directoryURLs = [URL(fileURLWithPath: "/")]
    }

    override func menu(for menuKind: FIMenuKind) -> NSMenu {
        let menu = NSMenu(title: "")
        guard menuKind == .contextualMenuForItems || menuKind == .contextualMenuForContainer else {
            return menu
        }

        let controller = FIFinderSyncController.default()
        let selectedURLs = controller.selectedItemURLs() ?? []
        let targetURL = controller.targetedURL()

        let wenBarMenuItem = NSMenuItem(title: "WenBar", action: nil, keyEquivalent: "")
        if let icon = NSImage(systemSymbolName: "archivebox.circle", accessibilityDescription: "WenBar") {
            icon.isTemplate = true
            wenBarMenuItem.image = icon
        }

        let submenu = NSMenu(title: "WenBar")

        if menuKind == .contextualMenuForItems && !selectedURLs.isEmpty {
            let compressZipItem = NSMenuItem(
                title: localized("压缩为 ZIP", "Compress to ZIP"),
                action: #selector(handleCompressZip(_:)),
                keyEquivalent: ""
            )
            compressZipItem.target = self
            submenu.addItem(compressZipItem)

            let compressCustomItem = NSMenuItem(
                title: localized("加密 / 自定义压缩…", "Custom / Encrypted Compress…"),
                action: #selector(handleCompressCustom(_:)),
                keyEquivalent: ""
            )
            compressCustomItem.target = self
            submenu.addItem(compressCustomItem)

            let allArchives = selectedURLs.allSatisfy { ArchiveFileSupport.isSupportedArchive($0) }
            if allArchives {
                submenu.addItem(.separator())

                let extractSmartItem = NSMenuItem(
                    title: localized("解压到当前目录", "Extract Here (Smart)"),
                    action: #selector(handleExtractSmart(_:)),
                    keyEquivalent: ""
                )
                extractSmartItem.target = self
                submenu.addItem(extractSmartItem)

                let extractSubfolderItem = NSMenuItem(
                    title: localized("解压到同名文件夹", "Extract to Subfolder"),
                    action: #selector(handleExtractSubfolder(_:)),
                    keyEquivalent: ""
                )
                extractSubfolderItem.target = self
                submenu.addItem(extractSubfolderItem)
            }

            let hasDirectory = selectedURLs.contains { url in
                (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
            }
            if hasDirectory {
                submenu.addItem(.separator())
                let cleanItem = NSMenuItem(
                    title: localized("清理此目录 .DS_Store", "Clean .DS_Store Here"),
                    action: #selector(handleCleanSelectedDirs(_:)),
                    keyEquivalent: ""
                )
                cleanItem.target = self
                submenu.addItem(cleanItem)
            }
        } else if menuKind == .contextualMenuForContainer, targetURL != nil {
            let cleanItem = NSMenuItem(
                title: localized("清理此目录 .DS_Store", "Clean .DS_Store Here"),
                action: #selector(handleCleanContainer(_:)),
                keyEquivalent: ""
            )
            cleanItem.target = self
            submenu.addItem(cleanItem)
        }

        if !submenu.items.isEmpty {
            wenBarMenuItem.submenu = submenu
            menu.addItem(wenBarMenuItem)
        }

        return menu
    }

    @objc private func handleCompressZip(_ sender: Any?) {
        let controller = FIFinderSyncController.default()
        let paths = (controller.selectedItemURLs() ?? []).map(\.path)
        guard !paths.isEmpty else { return }
        dispatchAction(WenBarActionPayload(
            kind: .compressZip,
            paths: paths,
            targetDirectory: controller.targetedURL()?.path
        ))
    }

    @objc private func handleCompressCustom(_ sender: Any?) {
        let controller = FIFinderSyncController.default()
        let paths = (controller.selectedItemURLs() ?? []).map(\.path)
        guard !paths.isEmpty else { return }
        dispatchAction(WenBarActionPayload(
            kind: .compressCustom,
            paths: paths,
            targetDirectory: controller.targetedURL()?.path
        ))
    }

    @objc private func handleExtractSmart(_ sender: Any?) {
        let controller = FIFinderSyncController.default()
        let paths = (controller.selectedItemURLs() ?? []).map(\.path)
        guard !paths.isEmpty else { return }
        dispatchAction(WenBarActionPayload(
            kind: .extractSmart,
            paths: paths,
            targetDirectory: controller.targetedURL()?.path
        ))
    }

    @objc private func handleExtractSubfolder(_ sender: Any?) {
        let controller = FIFinderSyncController.default()
        let paths = (controller.selectedItemURLs() ?? []).map(\.path)
        guard !paths.isEmpty else { return }
        dispatchAction(WenBarActionPayload(
            kind: .extractSubfolder,
            paths: paths,
            targetDirectory: controller.targetedURL()?.path
        ))
    }

    @objc private func handleCleanSelectedDirs(_ sender: Any?) {
        let controller = FIFinderSyncController.default()
        let paths = (controller.selectedItemURLs() ?? []).map(\.path)
        guard !paths.isEmpty else { return }
        dispatchAction(WenBarActionPayload(
            kind: .cleanDSStore,
            paths: paths,
            targetDirectory: controller.targetedURL()?.path
        ))
    }

    @objc private func handleCleanContainer(_ sender: Any?) {
        let controller = FIFinderSyncController.default()
        guard let target = controller.targetedURL()?.path else { return }
        dispatchAction(WenBarActionPayload(
            kind: .cleanDSStore,
            paths: [target],
            targetDirectory: target
        ))
    }

    private func dispatchAction(_ payload: WenBarActionPayload) {
        let activatesApp = (payload.kind == .compressCustom)
        let url: URL?
        if let direct = payload.makeURL(), direct.absoluteString.count <= 3000 {
            url = direct
        } else {
            // Large selection fallback via named NSPasteboard
            let pbName = NSPasteboard.Name("com.wenbar.action.\(UUID().uuidString)")
            let pb = NSPasteboard(name: pbName)
            pb.clearContents()
            if let data = try? JSONEncoder().encode(payload),
               let str = String(data: data, encoding: .utf8) {
                pb.setString(str, forType: .string)
                url = payload.makeURL(pasteboardFallbackName: pbName.rawValue)
            } else {
                url = nil
            }
        }

        guard let targetURL = url else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = activatesApp
        config.hides = !activatesApp
        config.addsToRecentItems = false
        NSWorkspace.shared.open(targetURL, configuration: config) { _, _ in }
    }

    private func localized(_ zh: String, _ en: String) -> String {
        let preferred = Locale.preferredLanguages.first ?? "zh"
        return preferred.hasPrefix("zh") ? zh : en
    }
}
