import Foundation
import AppKit
import WenBarCore

@MainActor
final class ActionRouter {
    private let archiveManager: ArchiveTaskManager
    private let settingsStore: SettingsStore
    private let onRequestCustomCompress: ([URL]) -> Void

    init(
        archiveManager: ArchiveTaskManager,
        settingsStore: SettingsStore,
        onRequestCustomCompress: @escaping ([URL]) -> Void
    ) {
        self.archiveManager = archiveManager
        self.settingsStore = settingsStore
        self.onRequestCustomCompress = onRequestCustomCompress
    }

    func handleIncomingURLs(_ urls: [URL]) {
        for url in urls where url.scheme == "wenbar" {
            handle(url: url)
        }
    }

    func handle(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []

        let payload: WenBarActionPayload?
        if let pbName = items.first(where: { $0.name == "pb" })?.value {
            let pb = NSPasteboard(name: NSPasteboard.Name(pbName))
            if let json = pb.string(forType: .string), let data = json.data(using: .utf8) {
                payload = try? JSONDecoder().decode(WenBarActionPayload.self, from: data)
            } else {
                payload = nil
            }
        } else if let encoded = items.first(where: { $0.name == "payload" })?.value {
            payload = try? WenBarActionPayload.decodeBase64URLSafe(encoded)
        } else {
            payload = nil
        }

        guard let payload else { return }
        route(payload)
    }

    func route(_ payload: WenBarActionPayload) {
        guard settingsStore.settings.enableArchiveTools else {
            NotificationService.shared.post(
                title: "WenBar 压缩/清理模块未启用",
                body: "请在 WenBar 设置中开启「压缩与解压」模块。"
            )
            return
        }

        let urls = payload.paths.map { URL(fileURLWithPath: $0) }
        guard !urls.isEmpty else { return }

        switch payload.kind {
        case .compressZip:
            archiveManager.enqueueCompress(
                sources: urls,
                format: settingsStore.settings.defaultArchiveFormat,
                level: settingsStore.settings.defaultCompressionLevel,
                password: nil,
                cleanSourceDSStore: settingsStore.settings.deleteSourceDSStoreAfterCompress
            )

        case .compressCustom:
            onRequestCustomCompress(urls)

        case .extractSmart:
            archiveManager.enqueueExtract(
                archives: urls,
                mode: .smart,
                trashAfterExtract: settingsStore.settings.trashArchiveAfterExtract
            )

        case .extractSubfolder:
            archiveManager.enqueueExtract(
                archives: urls,
                mode: .subfolder,
                trashAfterExtract: settingsStore.settings.trashArchiveAfterExtract
            )

        case .cleanDSStore:
            archiveManager.cleanDSStoreInDirectories(urls)
        }
    }
}
