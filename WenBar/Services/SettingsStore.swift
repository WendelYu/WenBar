import Foundation
import Combine
import ServiceManagement
import WenBarCore

@MainActor
@Observable
final class SettingsStore {
    private static let storageKey = "WenBar.Settings.v1"

    var settings: WenBarSettingsModel {
        didSet {
            persist()
            onSettingsChanged?()
        }
    }

    var onSettingsChanged: (() -> Void)?

    var launchAtLogin: Bool {
        SMAppService.mainApp.status == .enabled
    }

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storageKey),
           let decoded = try? JSONDecoder().decode(WenBarSettingsModel.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = WenBarSettingsModel()
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func resetDefaults() {
        settings = WenBarSettingsModel()
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }
}
