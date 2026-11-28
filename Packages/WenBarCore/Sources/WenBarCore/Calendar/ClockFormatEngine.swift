import Foundation

public struct ClockFormatPreset: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let template: String

    public init(id: String, name: String, template: String) {
        self.id = id
        self.name = name
        self.template = template
    }
}

public struct ClockFormatToken: Identifiable, Sendable, Equatable {
    public enum Category: String, CaseIterable, Sendable {
        case dateTime = "日期与时间"
        case chineseLunar = "中文与农历"
        case extras = "节气、周数与假期"
    }

    public let id: String
    public let token: String
    public let label: String
    public let example: String
    public let category: Category

    public init(token: String, label: String, example: String, category: Category) {
        self.id = "\(category.rawValue)-\(token)"
        self.token = token
        self.label = label
        self.example = example
        self.category = category
    }
}

/// Formats menu bar clock titles with DateFormatter tokens plus custom lunar/solar-term/week/holiday macros.
public enum ClockFormatEngine {
    public static let presets: [ClockFormatPreset] = [
        ClockFormatPreset(id: "compact", name: "紧凑日期时间", template: "MM/dd EEE HH:mm"),
        ClockFormatPreset(id: "cn_compact", name: "中文月日 + 星期 + 时间", template: "M月d日 {weekday_cn} HH:mm"),
        ClockFormatPreset(id: "seconds", name: "带秒精确时间", template: "MM/dd {weekday_cn} HH:mm:ss"),
        ClockFormatPreset(id: "lunar", name: "公历 + 农历 + 星期", template: "M月d日 {lunar} {weekday_cn} HH:mm"),
        ClockFormatPreset(id: "lunar_jieqi", name: "农历 + 节气/节日 + 时间", template: "M月d日 {lunar} {jieqi}{festival} HH:mm"),
        ClockFormatPreset(id: "full_iso", name: "完整年月日 + 秒", template: "yyyy-MM-dd {weekday_cn} HH:mm:ss"),
        ClockFormatPreset(id: "full_slash", name: "斜杠完整日期 + 星期", template: "yyyy/MM/dd {weekday_full} HH:mm"),
        ClockFormatPreset(id: "ampm_12h", name: "12 小时制（上午/下午）", template: "M月d日 {weekday_cn} {ampm} h:mm"),
        ClockFormatPreset(id: "week_holiday", name: "周数 + 下个假期倒计时", template: "W{week} M/d {holiday_cd} HH:mm"),
        ClockFormatPreset(id: "twoline_compact", name: "双行紧凑（日期星期 / 时间）", template: "MM/dd {weekday_cn}\\nHH:mm"),
        ClockFormatPreset(id: "twoline_lunar", name: "双行农历（公历农历 / 星期秒）", template: "M月d日 {lunar}\\n{weekday_cn} HH:mm:ss"),
        ClockFormatPreset(id: "time_only", name: "极简纯时间（带秒）", template: "HH:mm:ss")
    ]

    public static let availableTokens: [ClockFormatToken] = [
        // Date & Time
        ClockFormatToken(token: "yyyy", label: "四位年", example: "2026", category: .dateTime),
        ClockFormatToken(token: "MM", label: "两位月", example: "11", category: .dateTime),
        ClockFormatToken(token: "M", label: "月份", example: "11", category: .dateTime),
        ClockFormatToken(token: "dd", label: "两位日", example: "26", category: .dateTime),
        ClockFormatToken(token: "d", label: "日期", example: "26", category: .dateTime),
        ClockFormatToken(token: "HH", label: "24小时", example: "17", category: .dateTime),
        ClockFormatToken(token: "hh", label: "12小时", example: "05", category: .dateTime),
        ClockFormatToken(token: "mm", label: "分钟", example: "09", category: .dateTime),
        ClockFormatToken(token: "ss", label: "秒数", example: "42", category: .dateTime),
        ClockFormatToken(token: "EEE", label: "短星期", example: "周四", category: .dateTime),
        // Chinese & Lunar
        ClockFormatToken(token: "{weekday_cn}", label: "周几", example: "周四", category: .chineseLunar),
        ClockFormatToken(token: "{weekday_full}", label: "星期几", example: "星期四", category: .chineseLunar),
        ClockFormatToken(token: "{ampm}", label: "上午/下午", example: "下午", category: .chineseLunar),
        ClockFormatToken(token: "{lunar}", label: "农历月日", example: "十月十八", category: .chineseLunar),
        ClockFormatToken(token: "{lunar_month}", label: "农历月", example: "十月", category: .chineseLunar),
        ClockFormatToken(token: "{lunar_day}", label: "农历日", example: "十八", category: .chineseLunar),
        ClockFormatToken(token: "{lunar_full}", label: "干支农历", example: "丙午年十月十八", category: .chineseLunar),
        ClockFormatToken(token: "{ganzhi}", label: "干支年", example: "丙午年", category: .chineseLunar),
        ClockFormatToken(token: "{zodiac}", label: "生肖", example: "马", category: .chineseLunar),
        // Extras
        ClockFormatToken(token: "{jieqi}", label: "节气", example: "小雪", category: .extras),
        ClockFormatToken(token: "{festival}", label: "节日", example: "春节", category: .extras),
        ClockFormatToken(token: "{week}", label: "第几周", example: "48", category: .extras),
        ClockFormatToken(token: "{holiday_cd}", label: "假期倒数", example: "距元旦36天", category: .extras)
    ]

    private static let cnWeekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]
    private static let cnFullWeekdays = ["星期日", "星期一", "星期二", "星期三", "星期四", "星期五", "星期六"]
    private static let beijingTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    private final class EngineCache: @unchecked Sendable {
        private let lock = NSLock()
        private var formatters: [String: DateFormatter] = [:]
        private var calendars: [String: Calendar] = [:]
        private var lunarByBeijingDayKey: [Int: LunarDateInfo] = [:]

        func calendar(for timeZone: TimeZone) -> Calendar {
            lock.lock()
            defer { lock.unlock() }
            if let existing = calendars[timeZone.identifier] {
                return existing
            }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = timeZone
            if calendars.count >= 16 { calendars.removeAll() }
            calendars[timeZone.identifier] = cal
            return cal
        }

        func formatter(locale: Locale, timeZone: TimeZone, dateFormat: String) -> DateFormatter {
            let key = "\(locale.identifier)|\(timeZone.identifier)|\(dateFormat)"
            lock.lock()
            defer { lock.unlock() }
            if let existing = formatters[key] {
                return existing
            }
            let df = DateFormatter()
            df.locale = locale
            df.timeZone = timeZone
            df.dateFormat = dateFormat
            if formatters.count >= 48 { formatters.removeAll() }
            formatters[key] = df
            return df
        }

        func lunarInfo(for date: Date) -> LunarDateInfo {
            let cal = calendar(for: beijingTimeZone)
            let comps = cal.dateComponents([.year, .month, .day], from: date)
            let dayKey = (comps.year ?? 2026) * 10000 + (comps.month ?? 1) * 100 + (comps.day ?? 1)
            lock.lock()
            if let cached = lunarByBeijingDayKey[dayKey] {
                lock.unlock()
                return cached
            }
            lock.unlock()

            let computed = LunarCalendarEngine.info(for: date)
            lock.lock()
            if lunarByBeijingDayKey.count >= 16 { lunarByBeijingDayKey.removeAll() }
            lunarByBeijingDayKey[dayKey] = computed
            lock.unlock()
            return computed
        }
    }

    private static let cache = EngineCache()

    /// Checks whether the template contains seconds tokens (`s` or `S`) outside literal quotes or `{...}` macros.
    public static func requiresPerSecondUpdates(template: String) -> Bool {
        var inQuotes = false
        var inMacro = false
        for ch in template {
            if ch == "'" {
                inQuotes.toggle()
            } else if ch == "{" && !inQuotes {
                inMacro = true
            } else if ch == "}" && inMacro {
                inMacro = false
            } else if !inQuotes && !inMacro && (ch == "s" || ch == "S") {
                return true
            }
        }
        return false
    }

    public static func format(
        date: Date,
        template: String,
        locale: Locale = Locale(identifier: "zh_CN"),
        timeZone: TimeZone = .current,
        nextHoliday: NextHolidayCountdown? = nil
    ) -> String {
        let cal = cache.calendar(for: timeZone)

        let needsLunar = template.contains("{lunar")
            || template.contains("{ganzhi}")
            || template.contains("{zodiac}")
            || template.contains("{jieqi}")
            || template.contains("{festival}")

        let lunarShort: String
        let lunarMonthName: String
        let lunarDayName: String
        let lunarFull: String
        let ganzhiText: String
        let zodiacText: String
        let jieqiText: String
        let festivalText: String

        if needsLunar {
            let lunar = cache.lunarInfo(for: date)
            lunarShort = lunar.lunarDay == 1 ? lunar.monthName : "\(lunar.monthName)\(lunar.dayName)"
            lunarMonthName = lunar.monthName
            lunarDayName = lunar.dayName
            lunarFull = "\(lunar.yearGanZhi)\(lunar.monthName)\(lunar.dayName)"
            ganzhiText = lunar.yearGanZhi
            zodiacText = lunar.zodiac
            jieqiText = lunar.solarTerm ?? ""
            festivalText = lunar.traditionalFestival ?? lunar.gregorianFestival ?? ""
        } else {
            lunarShort = ""
            lunarMonthName = ""
            lunarDayName = ""
            lunarFull = ""
            ganzhiText = ""
            zodiacText = ""
            jieqiText = ""
            festivalText = ""
        }

        let weekOfYear = template.contains("{week}") ? cal.component(.weekOfYear, from: date) : 0
        let weekdayIdx = (template.contains("{weekday_cn}") || template.contains("{weekday_full}"))
            ? (cal.component(.weekday, from: date) - 1)
            : -1
        let weekdayCN = (weekdayIdx >= 0 && weekdayIdx < cnWeekdays.count) ? cnWeekdays[weekdayIdx] : ""
        let weekdayFull = (weekdayIdx >= 0 && weekdayIdx < cnFullWeekdays.count) ? cnFullWeekdays[weekdayIdx] : ""

        let ampmText: String
        if template.contains("{ampm}") {
            let hour = cal.component(.hour, from: date)
            switch hour {
            case 0..<6: ampmText = "凌晨"
            case 6..<12: ampmText = "上午"
            case 12: ampmText = "中午"
            case 13..<18: ampmText = "下午"
            default: ampmText = "晚上"
            }
        } else {
            ampmText = ""
        }

        let holidayCDText: String
        if template.contains("{holiday_cd}"), let nextHoliday {
            holidayCDText = nextHoliday.isOngoing ? "\(nextHoliday.name)中" : "距\(nextHoliday.name)\(nextHoliday.daysRemaining)天"
        } else {
            holidayCDText = ""
        }

        let normalizedTemplate = template.replacingOccurrences(of: "\\n", with: "\n")
        let rawLines = normalizedTemplate.components(separatedBy: "\n")

        let formattedLines = rawLines.map { line -> String in
            let resolved = line
                .replacingOccurrences(of: "{lunar}", with: quoteLiteral(lunarShort))
                .replacingOccurrences(of: "{lunar_month}", with: quoteLiteral(lunarMonthName))
                .replacingOccurrences(of: "{lunar_day}", with: quoteLiteral(lunarDayName))
                .replacingOccurrences(of: "{lunar_full}", with: quoteLiteral(lunarFull))
                .replacingOccurrences(of: "{ganzhi}", with: quoteLiteral(ganzhiText))
                .replacingOccurrences(of: "{zodiac}", with: quoteLiteral(zodiacText))
                .replacingOccurrences(of: "{jieqi}", with: quoteLiteral(jieqiText))
                .replacingOccurrences(of: "{festival}", with: quoteLiteral(festivalText))
                .replacingOccurrences(of: "{week}", with: quoteLiteral("\(weekOfYear)"))
                .replacingOccurrences(of: "{weekday_cn}", with: quoteLiteral(weekdayCN))
                .replacingOccurrences(of: "{weekday_full}", with: quoteLiteral(weekdayFull))
                .replacingOccurrences(of: "{ampm}", with: quoteLiteral(ampmText))
                .replacingOccurrences(of: "{holiday_cd}", with: quoteLiteral(holidayCDText))

            let df = cache.formatter(locale: locale, timeZone: timeZone, dateFormat: resolved)
            var output = df.string(from: date)
            while output.contains("  ") {
                output = output.replacingOccurrences(of: "  ", with: " ")
            }
            return output.trimmingCharacters(in: .whitespaces)
        }

        return formattedLines.joined(separator: "\n")
    }

    private static func quoteLiteral(_ text: String) -> String {
        guard !text.isEmpty else { return "" }
        let escaped = text.replacingOccurrences(of: "'", with: "''")
        return "'\(escaped)'"
    }
}
