import Foundation

public struct WorldClockCity: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public let name: String
    public let timeZoneIdentifier: String

    public init(id: String = UUID().uuidString, name: String, timeZoneIdentifier: String) {
        self.id = id
        self.name = name
        self.timeZoneIdentifier = timeZoneIdentifier
    }

    public static let defaults: [WorldClockCity] = [
        WorldClockCity(id: "shanghai", name: "北京 / 上海", timeZoneIdentifier: "Asia/Shanghai"),
        WorldClockCity(id: "tokyo", name: "东京", timeZoneIdentifier: "Asia/Tokyo"),
        WorldClockCity(id: "london", name: "伦敦", timeZoneIdentifier: "Europe/London"),
        WorldClockCity(id: "newyork", name: "纽约", timeZoneIdentifier: "America/New_York"),
        WorldClockCity(id: "sf", name: "旧金山", timeZoneIdentifier: "America/Los_Angeles")
    ]
}

public enum AppLanguageOption: String, CaseIterable, Codable, Sendable, Identifiable {
    case system
    case zhHans = "zh-Hans"
    case en

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .system: return "跟随系统 / System"
        case .zhHans: return "简体中文"
        case .en: return "English"
        }
    }
}

public enum ClockFontWeightOption: String, CaseIterable, Codable, Sendable, Identifiable {
    case regular
    case medium
    case semibold
    case bold

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .regular: return "常规"
        case .medium: return "中等"
        case .semibold: return "半粗"
        case .bold: return "粗体"
        }
    }
}

public struct WenBarSettingsModel: Codable, Sendable, Equatable {
    // Module toggles
    public var enableClockCalendar: Bool
    public var enableDiskManager: Bool
    public var enableArchiveTools: Bool

    // Clock & Calendar
    public var clockFormatTemplate: String
    public var customClockTemplates: [ClockFormatPreset]
    public var clockFontSize: Double
    public var clockFontWeight: ClockFontWeightOption
    public var clockUseMonospacedDigits: Bool
    public var clockShowCalendarIcon: Bool
    public var showCountdownInMenuBar: Bool
    public var showArchiveProgressInMenuBar: Bool
    public var autoSyncHolidays: Bool
    public var worldClockCities: [WorldClockCity]

    // Disk Manager
    public var showStandaloneDiskIcon: Bool
    public var showDisksInMainPopover: Bool
    public var enabledJunkRules: Set<JunkRule>

    // Archive Tools
    public var defaultArchiveFormat: ArchiveFormat
    public var defaultCompressionLevel: CompressionLevel
    public var deleteSourceDSStoreAfterCompress: Bool
    public var trashArchiveAfterExtract: Bool

    // System & Hotkey
    public var language: AppLanguageOption
    public var hotkeyKeyCode: UInt32
    public var hotkeyModifiers: UInt32
    public var hasCompletedOnboarding: Bool
    public var autoCheckUpdates: Bool

    public init(
        enableClockCalendar: Bool = true,
        enableDiskManager: Bool = true,
        enableArchiveTools: Bool = true,
        clockFormatTemplate: String = "MM/dd EEE HH:mm",
        customClockTemplates: [ClockFormatPreset] = [],
        clockFontSize: Double = 13,
        clockFontWeight: ClockFontWeightOption = .regular,
        clockUseMonospacedDigits: Bool = true,
        clockShowCalendarIcon: Bool = false,
        showCountdownInMenuBar: Bool = true,
        showArchiveProgressInMenuBar: Bool = true,
        autoSyncHolidays: Bool = true,
        worldClockCities: [WorldClockCity] = WorldClockCity.defaults,
        showStandaloneDiskIcon: Bool = true,
        showDisksInMainPopover: Bool = true,
        enabledJunkRules: Set<JunkRule> = Set(JunkRule.allCases),
        defaultArchiveFormat: ArchiveFormat = .zip,
        defaultCompressionLevel: CompressionLevel = .normal,
        deleteSourceDSStoreAfterCompress: Bool = true,
        trashArchiveAfterExtract: Bool = false,
        language: AppLanguageOption = .system,
        hotkeyKeyCode: UInt32 = 49, // kVK_Space
        hotkeyModifiers: UInt32 = 2048, // optionKey
        hasCompletedOnboarding: Bool = false,
        autoCheckUpdates: Bool = true
    ) {
        self.enableClockCalendar = enableClockCalendar
        self.enableDiskManager = enableDiskManager
        self.enableArchiveTools = enableArchiveTools
        self.clockFormatTemplate = clockFormatTemplate
        self.customClockTemplates = customClockTemplates
        self.clockFontSize = clockFontSize
        self.clockFontWeight = clockFontWeight
        self.clockUseMonospacedDigits = clockUseMonospacedDigits
        self.clockShowCalendarIcon = clockShowCalendarIcon
        self.showCountdownInMenuBar = showCountdownInMenuBar
        self.showArchiveProgressInMenuBar = showArchiveProgressInMenuBar
        self.autoSyncHolidays = autoSyncHolidays
        self.worldClockCities = worldClockCities
        self.showStandaloneDiskIcon = showStandaloneDiskIcon
        self.showDisksInMainPopover = showDisksInMainPopover
        self.enabledJunkRules = enabledJunkRules
        self.defaultArchiveFormat = defaultArchiveFormat
        self.defaultCompressionLevel = defaultCompressionLevel
        self.deleteSourceDSStoreAfterCompress = deleteSourceDSStoreAfterCompress
        self.trashArchiveAfterExtract = trashArchiveAfterExtract
        self.language = language
        self.hotkeyKeyCode = hotkeyKeyCode
        self.hotkeyModifiers = hotkeyModifiers
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.autoCheckUpdates = autoCheckUpdates
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WenBarSettingsModel()
        enableClockCalendar = try c.decodeIfPresent(Bool.self, forKey: .enableClockCalendar) ?? d.enableClockCalendar
        enableDiskManager = try c.decodeIfPresent(Bool.self, forKey: .enableDiskManager) ?? d.enableDiskManager
        enableArchiveTools = try c.decodeIfPresent(Bool.self, forKey: .enableArchiveTools) ?? d.enableArchiveTools
        clockFormatTemplate = try c.decodeIfPresent(String.self, forKey: .clockFormatTemplate) ?? d.clockFormatTemplate
        customClockTemplates = try c.decodeIfPresent([ClockFormatPreset].self, forKey: .customClockTemplates) ?? d.customClockTemplates
        clockFontSize = try c.decodeIfPresent(Double.self, forKey: .clockFontSize) ?? d.clockFontSize
        clockFontWeight = try c.decodeIfPresent(ClockFontWeightOption.self, forKey: .clockFontWeight) ?? d.clockFontWeight
        clockUseMonospacedDigits = try c.decodeIfPresent(Bool.self, forKey: .clockUseMonospacedDigits) ?? d.clockUseMonospacedDigits
        clockShowCalendarIcon = try c.decodeIfPresent(Bool.self, forKey: .clockShowCalendarIcon) ?? d.clockShowCalendarIcon
        showCountdownInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showCountdownInMenuBar) ?? d.showCountdownInMenuBar
        showArchiveProgressInMenuBar = try c.decodeIfPresent(Bool.self, forKey: .showArchiveProgressInMenuBar) ?? d.showArchiveProgressInMenuBar
        autoSyncHolidays = try c.decodeIfPresent(Bool.self, forKey: .autoSyncHolidays) ?? d.autoSyncHolidays
        worldClockCities = try c.decodeIfPresent([WorldClockCity].self, forKey: .worldClockCities) ?? d.worldClockCities
        showStandaloneDiskIcon = try c.decodeIfPresent(Bool.self, forKey: .showStandaloneDiskIcon) ?? d.showStandaloneDiskIcon
        showDisksInMainPopover = try c.decodeIfPresent(Bool.self, forKey: .showDisksInMainPopover) ?? d.showDisksInMainPopover
        enabledJunkRules = try c.decodeIfPresent(Set<JunkRule>.self, forKey: .enabledJunkRules) ?? d.enabledJunkRules
        defaultArchiveFormat = try c.decodeIfPresent(ArchiveFormat.self, forKey: .defaultArchiveFormat) ?? d.defaultArchiveFormat
        defaultCompressionLevel = try c.decodeIfPresent(CompressionLevel.self, forKey: .defaultCompressionLevel) ?? d.defaultCompressionLevel
        deleteSourceDSStoreAfterCompress = try c.decodeIfPresent(Bool.self, forKey: .deleteSourceDSStoreAfterCompress) ?? d.deleteSourceDSStoreAfterCompress
        trashArchiveAfterExtract = try c.decodeIfPresent(Bool.self, forKey: .trashArchiveAfterExtract) ?? d.trashArchiveAfterExtract
        language = try c.decodeIfPresent(AppLanguageOption.self, forKey: .language) ?? d.language
        hotkeyKeyCode = try c.decodeIfPresent(UInt32.self, forKey: .hotkeyKeyCode) ?? d.hotkeyKeyCode
        hotkeyModifiers = try c.decodeIfPresent(UInt32.self, forKey: .hotkeyModifiers) ?? d.hotkeyModifiers
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? d.hasCompletedOnboarding
        autoCheckUpdates = try c.decodeIfPresent(Bool.self, forKey: .autoCheckUpdates) ?? d.autoCheckUpdates
    }
}
