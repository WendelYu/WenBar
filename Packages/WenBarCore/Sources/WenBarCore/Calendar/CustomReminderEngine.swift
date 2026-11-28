import Foundation

public enum ReminderCalendarType: String, Codable, CaseIterable, Sendable, Identifiable {
    case gregorian
    case lunar

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gregorian: return "公历"
        case .lunar: return "农历"
        }
    }
}

public enum ReminderRepeatRule: String, Codable, CaseIterable, Sendable, Identifiable {
    case once
    case yearly
    case monthly
    case weekly
    case daily

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .once: return "不重复"
        case .yearly: return "每年"
        case .monthly: return "每月"
        case .weekly: return "每周"
        case .daily: return "每天"
        }
    }

    public static func supportedCases(for calendarType: ReminderCalendarType) -> [ReminderRepeatRule] {
        switch calendarType {
        case .gregorian: return [.once, .yearly, .monthly, .weekly, .daily]
        case .lunar: return [.once, .yearly, .monthly]
        }
    }
}

public struct CustomReminder: Codable, Identifiable, Equatable, Sendable {
    public let id: UUID
    public var title: String
    public var notes: String
    public var calendarType: ReminderCalendarType
    public var gregorianYear: Int
    public var gregorianMonth: Int
    public var gregorianDay: Int
    public var lunarYear: Int
    public var lunarMonth: Int
    public var lunarDay: Int
    public var isLeapMonth: Bool
    public var hour: Int
    public var minute: Int
    public var repeatRule: ReminderRepeatRule
    public var advanceDays: [Int]
    public var isEnabled: Bool
    public var completedOccurrenceKeys: Set<String>
    public var createdAt: Date

    public init(
        id: UUID = UUID(),
        title: String,
        notes: String = "",
        calendarType: ReminderCalendarType = .gregorian,
        gregorianYear: Int,
        gregorianMonth: Int,
        gregorianDay: Int,
        lunarYear: Int,
        lunarMonth: Int,
        lunarDay: Int,
        isLeapMonth: Bool = false,
        hour: Int = 9,
        minute: Int = 0,
        repeatRule: ReminderRepeatRule = .once,
        advanceDays: [Int] = [0],
        isEnabled: Bool = true,
        completedOccurrenceKeys: Set<String> = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.notes = notes
        self.calendarType = calendarType
        self.gregorianYear = gregorianYear
        self.gregorianMonth = min(12, max(1, gregorianMonth))
        self.gregorianDay = min(31, max(1, gregorianDay))
        self.lunarYear = lunarYear
        self.lunarMonth = min(12, max(1, lunarMonth))
        self.lunarDay = min(30, max(1, lunarDay))
        self.isLeapMonth = isLeapMonth
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
        self.repeatRule = repeatRule
        self.advanceDays = CustomReminderEngine.normalizedAdvanceDays(advanceDays)
        self.isEnabled = isEnabled
        self.completedOccurrenceKeys = completedOccurrenceKeys
        self.createdAt = createdAt
    }

    public func isCompleted(forDateKey dateKey: String) -> Bool {
        completedOccurrenceKeys.contains(dateKey)
    }
}

public struct ReminderOccurrence: Identifiable, Equatable, Sendable {
    public let id: String
    public let reminder: CustomReminder
    public let targetDate: Date
    public let dateKey: String
    public let isCompleted: Bool

    public init(reminder: CustomReminder, targetDate: Date, dateKey: String, isCompleted: Bool) {
        self.id = "\(reminder.id.uuidString)|\(dateKey)"
        self.reminder = reminder
        self.targetDate = targetDate
        self.dateKey = dateKey
        self.isCompleted = isCompleted
    }
}

public struct ScheduledReminderAlert: Identifiable, Equatable, Sendable {
    public static let identifierPrefix = "wenbar.reminder."

    public let id: String
    public let reminderID: UUID
    public let occurrenceDateKey: String
    public let advanceDays: Int
    public let fireDate: Date
    public let fireYear: Int
    public let fireMonth: Int
    public let fireDay: Int
    public let fireHour: Int
    public let fireMinute: Int
    public let title: String
    public let body: String
}

public enum CustomReminderEngine {
    public static let lunarMonthNames: [String] = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    public static let lunarDayNames: [String] = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    public static let defaultPresetAdvanceDays: [Int] = [0, 1, 3, 7, 15, 30]

    private static let beijingTimeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

    public static func normalizedAdvanceDays(_ days: [Int]) -> [Int] {
        let unique = Set(days.map { max(0, min(365, $0)) })
        if unique.isEmpty {
            return [0]
        }
        return unique.sorted(by: >)
    }

    public static func dateKey(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }

    public static func dateKey(for date: Date, timeZone: TimeZone = .current) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        return dateKey(year: comps.year ?? 2026, month: comps.month ?? 1, day: comps.day ?? 1)
    }

    /// Resolves a Chinese lunar (year, month, day, isLeapMonth) into the exact Gregorian Date
    /// consistent with `LunarCalendarEngine.info(for:)`.
    public static func gregorianDate(
        forLunarYear lunarYear: Int,
        month: Int,
        day: Int,
        isLeapMonth: Bool,
        hour: Int = 12,
        minute: Int = 0,
        timeZone: TimeZone? = nil
    ) -> Date? {
        let clampedMonth = min(12, max(1, month))
        let clampedDay = min(30, max(1, day))
        let tz = timeZone ?? beijingTimeZone

        var scanCal = Calendar(identifier: .gregorian)
        scanCal.timeZone = beijingTimeZone

        guard let scanStart = scanCal.date(from: DateComponents(year: lunarYear, month: 1, day: 15, hour: 12)),
              let scanEnd = scanCal.date(from: DateComponents(year: lunarYear + 1, month: 2, day: 25, hour: 12)) else {
            return nil
        }

        var exactMatch: Date?
        var nonLeapMatch: Date?
        var exactDay29Fallback: Date?
        var nonLeapDay29Fallback: Date?

        var cursor = scanStart
        while cursor <= scanEnd {
            let info = LunarCalendarEngine.info(for: cursor)
            if info.lunarYear == lunarYear && info.lunarMonth == clampedMonth {
                if info.isLeapMonth == isLeapMonth {
                    if info.lunarDay == clampedDay {
                        exactMatch = cursor
                        break
                    } else if clampedDay == 30 && info.lunarDay == 29 {
                        exactDay29Fallback = cursor
                    }
                } else if isLeapMonth && !info.isLeapMonth {
                    if info.lunarDay == clampedDay && nonLeapMatch == nil {
                        nonLeapMatch = cursor
                    } else if clampedDay == 30 && info.lunarDay == 29 && nonLeapDay29Fallback == nil {
                        nonLeapDay29Fallback = cursor
                    }
                }
            }
            guard let next = scanCal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        guard let resolvedBeijingNoon = exactMatch ?? exactDay29Fallback ?? nonLeapMatch ?? nonLeapDay29Fallback else {
            return nil
        }

        let gComps = scanCal.dateComponents([.year, .month, .day], from: resolvedBeijingNoon)
        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = tz
        return targetCal.date(from: DateComponents(
            year: gComps.year,
            month: gComps.month,
            day: gComps.day,
            hour: hour,
            minute: minute,
            second: 0
        ))
    }

    public static func occurrences(
        of reminder: CustomReminder,
        from startDate: Date,
        to endDate: Date,
        timeZone: TimeZone = .current
    ) -> [ReminderOccurrence] {
        guard reminder.isEnabled else { return [] }

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone

        let rangeStart = cal.startOfDay(for: startDate)
        let rangeEnd = cal.startOfDay(for: endDate)
        guard rangeStart <= rangeEnd else { return [] }

        var results: [ReminderOccurrence] = []
        var seenKeys = Set<String>()

        func appendIfInRange(_ date: Date) {
            let dayStart = cal.startOfDay(for: date)
            guard dayStart >= rangeStart && dayStart <= rangeEnd else { return }
            let key = dateKey(for: date, timeZone: timeZone)
            guard seenKeys.insert(key).inserted else { return }
            results.append(
                ReminderOccurrence(
                    reminder: reminder,
                    targetDate: date,
                    dateKey: key,
                    isCompleted: reminder.isCompleted(forDateKey: key)
                )
            )
        }

        switch reminder.calendarType {
        case .gregorian:
            switch reminder.repeatRule {
            case .once:
                if let date = makeGregorianDate(
                    year: reminder.gregorianYear,
                    month: reminder.gregorianMonth,
                    day: reminder.gregorianDay,
                    hour: reminder.hour,
                    minute: reminder.minute,
                    calendar: cal
                ) {
                    appendIfInRange(date)
                }

            case .yearly:
                let minY = cal.component(.year, from: rangeStart)
                let maxY = cal.component(.year, from: rangeEnd)
                if minY <= maxY {
                    for y in minY...maxY where y >= reminder.gregorianYear {
                        if let date = makeGregorianDate(
                            year: y,
                            month: reminder.gregorianMonth,
                            day: reminder.gregorianDay,
                            hour: reminder.hour,
                            minute: reminder.minute,
                            calendar: cal
                        ) {
                            appendIfInRange(date)
                        }
                    }
                }

            case .monthly:
                let startComps = cal.dateComponents([.year, .month], from: rangeStart)
                let endComps = cal.dateComponents([.year, .month], from: rangeEnd)
                guard let sy = startComps.year, let sm = startComps.month,
                      let ey = endComps.year, let em = endComps.month else { break }
                let anchorTotalMonths = reminder.gregorianYear * 12 + reminder.gregorianMonth
                let startTotalMonths = sy * 12 + sm
                let endTotalMonths = ey * 12 + em
                if startTotalMonths <= endTotalMonths {
                    for tm in max(anchorTotalMonths, startTotalMonths)...endTotalMonths {
                        let y = (tm - 1) / 12
                        let m = ((tm - 1) % 12) + 1
                        if let date = makeGregorianDate(
                            year: y,
                            month: m,
                            day: reminder.gregorianDay,
                            hour: reminder.hour,
                            minute: reminder.minute,
                            calendar: cal
                        ) {
                            appendIfInRange(date)
                        }
                    }
                }

            case .weekly, .daily:
                let stepDays = reminder.repeatRule == .weekly ? 7 : 1
                guard let anchor = makeGregorianDate(
                    year: reminder.gregorianYear,
                    month: reminder.gregorianMonth,
                    day: reminder.gregorianDay,
                    hour: reminder.hour,
                    minute: reminder.minute,
                    calendar: cal
                ) else { break }

                let anchorDay = cal.startOfDay(for: anchor)
                let effectiveStart = max(anchorDay, rangeStart)
                guard effectiveStart <= rangeEnd else { break }

                let deltaDays = cal.dateComponents([.day], from: anchorDay, to: effectiveStart).day ?? 0
                let rem = ((deltaDays % stepDays) + stepDays) % stepDays
                let firstOffset = rem == 0 ? 0 : (stepDays - rem)
                guard var cursorDay = cal.date(byAdding: .day, value: firstOffset, to: effectiveStart) else { break }

                while cursorDay <= rangeEnd {
                    let comps = cal.dateComponents([.year, .month, .day], from: cursorDay)
                    if let dt = cal.date(from: DateComponents(
                        year: comps.year,
                        month: comps.month,
                        day: comps.day,
                        hour: reminder.hour,
                        minute: reminder.minute,
                        second: 0
                    )) {
                        appendIfInRange(dt)
                    }
                    guard let next = cal.date(byAdding: .day, value: stepDays, to: cursorDay) else { break }
                    cursorDay = next
                }
            }

        case .lunar:
            switch reminder.repeatRule {
            case .once:
                if let date = gregorianDate(
                    forLunarYear: reminder.lunarYear,
                    month: reminder.lunarMonth,
                    day: reminder.lunarDay,
                    isLeapMonth: reminder.isLeapMonth,
                    hour: reminder.hour,
                    minute: reminder.minute,
                    timeZone: timeZone
                ) {
                    appendIfInRange(date)
                }

            case .yearly:
                let minY = cal.component(.year, from: rangeStart) - 1
                let maxY = cal.component(.year, from: rangeEnd) + 1
                if minY <= maxY {
                    for ly in minY...maxY where ly >= reminder.lunarYear {
                        if let date = gregorianDate(
                            forLunarYear: ly,
                            month: reminder.lunarMonth,
                            day: reminder.lunarDay,
                            isLeapMonth: reminder.isLeapMonth,
                            hour: reminder.hour,
                            minute: reminder.minute,
                            timeZone: timeZone
                        ) {
                            appendIfInRange(date)
                        }
                    }
                }

            case .monthly:
                var scanCal = Calendar(identifier: .gregorian)
                scanCal.timeZone = beijingTimeZone
                let startComps = cal.dateComponents([.year, .month, .day], from: rangeStart)
                let endComps = cal.dateComponents([.year, .month, .day], from: rangeEnd)
                guard let sMid = scanCal.date(from: DateComponents(year: startComps.year, month: startComps.month, day: startComps.day, hour: 12)),
                      let eMid = scanCal.date(from: DateComponents(year: endComps.year, month: endComps.month, day: endComps.day, hour: 12)) else {
                    break
                }

                var cursor = sMid
                while cursor <= eMid {
                    let info = LunarCalendarEngine.info(for: cursor)
                    let afterAnchor = info.lunarYear > reminder.lunarYear
                        || (info.lunarYear == reminder.lunarYear && info.lunarMonth >= reminder.lunarMonth)
                    if afterAnchor {
                        let dayMatches = info.lunarDay == reminder.lunarDay
                            || (reminder.lunarDay == 30 && info.lunarDay == 29 && isLastDayOfLunarMonth(cursor))
                        if dayMatches {
                            let g = scanCal.dateComponents([.year, .month, .day], from: cursor)
                            if let dt = cal.date(from: DateComponents(
                                year: g.year,
                                month: g.month,
                                day: g.day,
                                hour: reminder.hour,
                                minute: reminder.minute,
                                second: 0
                            )) {
                                appendIfInRange(dt)
                            }
                        }
                    }
                    guard let next = scanCal.date(byAdding: .day, value: 1, to: cursor) else { break }
                    cursor = next
                }

            case .weekly, .daily:
                let stepDays = reminder.repeatRule == .weekly ? 7 : 1
                guard let anchor = gregorianDate(
                    forLunarYear: reminder.lunarYear,
                    month: reminder.lunarMonth,
                    day: reminder.lunarDay,
                    isLeapMonth: reminder.isLeapMonth,
                    hour: reminder.hour,
                    minute: reminder.minute,
                    timeZone: timeZone
                ) else { break }

                let anchorDay = cal.startOfDay(for: anchor)
                let effectiveStart = max(anchorDay, rangeStart)
                guard effectiveStart <= rangeEnd else { break }
                let deltaDays = cal.dateComponents([.day], from: anchorDay, to: effectiveStart).day ?? 0
                let rem = ((deltaDays % stepDays) + stepDays) % stepDays
                let firstOffset = rem == 0 ? 0 : (stepDays - rem)
                guard var cursorDay = cal.date(byAdding: .day, value: firstOffset, to: effectiveStart) else { break }

                while cursorDay <= rangeEnd {
                    let comps = cal.dateComponents([.year, .month, .day], from: cursorDay)
                    if let dt = cal.date(from: DateComponents(
                        year: comps.year,
                        month: comps.month,
                        day: comps.day,
                        hour: reminder.hour,
                        minute: reminder.minute,
                        second: 0
                    )) {
                        appendIfInRange(dt)
                    }
                    guard let next = cal.date(byAdding: .day, value: stepDays, to: cursorDay) else { break }
                    cursorDay = next
                }
            }
        }

        return results.sorted { $0.targetDate < $1.targetDate }
    }

    public static func nextOccurrence(
        of reminder: CustomReminder,
        after referenceDate: Date = Date(),
        lookaheadDays: Int = 400,
        timeZone: TimeZone = .current
    ) -> ReminderOccurrence? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: referenceDate)
        guard let end = cal.date(byAdding: .day, value: lookaheadDays, to: start) else { return nil }
        return occurrences(of: reminder, from: start, to: end, timeZone: timeZone)
            .first { !$0.isCompleted }
    }

    public static func plannedNotifications(
        for reminders: [CustomReminder],
        from now: Date = Date(),
        horizonDays: Int = 60,
        maxTotal: Int = 56,
        timeZone: TimeZone = .current
    ) -> [ScheduledReminderAlert] {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let start = cal.startOfDay(for: now)

        var alerts: [ScheduledReminderAlert] = []
        for reminder in reminders where reminder.isEnabled {
            let maxOffset = reminder.advanceDays.max() ?? 0
            guard let end = cal.date(byAdding: .day, value: horizonDays + maxOffset, to: start) else { continue }

            let upcomingOccurrences = occurrences(of: reminder, from: start, to: end, timeZone: timeZone)
            for occ in upcomingOccurrences where !occ.isCompleted {
                for offset in normalizedAdvanceDays(reminder.advanceDays) {
                    guard let fireDate = cal.date(byAdding: .day, value: -offset, to: occ.targetDate),
                          fireDate > now else {
                        continue
                    }

                    let fireComps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
                    guard let fy = fireComps.year,
                          let fm = fireComps.month,
                          let fd = fireComps.day,
                          let fh = fireComps.hour,
                          let fmin = fireComps.minute else {
                        continue
                    }

                    let lunar = LunarCalendarEngine.info(for: occ.targetDate)
                    let targetComps = cal.dateComponents([.month, .day], from: occ.targetDate)
                    let targetDateText = "\(targetComps.month ?? 1)月\(targetComps.day ?? 1)日（农历\(lunar.monthName)\(lunar.dayName)）"

                    let title: String
                    let body: String
                    if offset == 0 {
                        title = "今日提醒：\(reminder.title)"
                        body = reminder.notes.isEmpty ? "目标日期：\(targetDateText)" : "\(targetDateText) · \(reminder.notes)"
                    } else {
                        title = "还有 \(offset) 天：\(reminder.title)"
                        body = reminder.notes.isEmpty ? "目标日期：\(targetDateText)" : "\(targetDateText) · \(reminder.notes)"
                    }

                    let id = "\(ScheduledReminderAlert.identifierPrefix)\(reminder.id.uuidString).\(occ.dateKey).\(offset)"
                    alerts.append(
                        ScheduledReminderAlert(
                            id: id,
                            reminderID: reminder.id,
                            occurrenceDateKey: occ.dateKey,
                            advanceDays: offset,
                            fireDate: fireDate,
                            fireYear: fy,
                            fireMonth: fm,
                            fireDay: fd,
                            fireHour: fh,
                            fireMinute: fmin,
                            title: title,
                            body: body
                        )
                    )
                }
            }
        }

        return alerts
            .sorted { $0.fireDate < $1.fireDate }
            .prefix(maxTotal)
            .map { $0 }
    }

    public static func scheduleSummary(for reminder: CustomReminder) -> String {
        let calPrefix: String
        switch reminder.calendarType {
        case .gregorian:
            if reminder.repeatRule == .once {
                calPrefix = "公历 \(reminder.gregorianYear)/\(reminder.gregorianMonth)/\(reminder.gregorianDay)"
            } else {
                calPrefix = "公历 \(reminder.gregorianMonth)月\(reminder.gregorianDay)日"
            }
        case .lunar:
            let mName = lunarMonthName(reminder.lunarMonth, isLeap: reminder.isLeapMonth)
            let dName = lunarDayName(reminder.lunarDay)
            calPrefix = "农历 \(mName)\(dName)"
        }
        let repeatPart = reminder.repeatRule.displayName
        let timeStr = String(format: "%02d:%02d", reminder.hour, reminder.minute)
        let advancePart = advanceDaysSummary(for: reminder.advanceDays)
        return "\(calPrefix) · \(repeatPart) \(timeStr) · \(advancePart)"
    }

    public static func advanceDaysSummary(for advanceDays: [Int]) -> String {
        let sorted = normalizedAdvanceDays(advanceDays)
        let labels = sorted.map { day -> String in
            day == 0 ? "当天" : "提前\(day)天"
        }
        return labels.joined(separator: " / ")
    }

    public static func lunarMonthName(_ month: Int, isLeap: Bool = false) -> String {
        let idx = min(11, max(0, month - 1))
        let base = lunarMonthNames[idx]
        return isLeap ? "闰\(base)" : base
    }

    public static func lunarDayName(_ day: Int) -> String {
        let idx = min(29, max(0, day - 1))
        return lunarDayNames[idx]
    }

    private static func makeGregorianDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int,
        calendar: Calendar
    ) -> Date? {
        guard let firstOfMonth = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let dayRange = calendar.range(of: .day, in: .month, for: firstOfMonth) else {
            return nil
        }
        let clampedDay = min(dayRange.upperBound - 1, max(1, day))
        return calendar.date(from: DateComponents(
            year: year,
            month: month,
            day: clampedDay,
            hour: hour,
            minute: minute,
            second: 0
        ))
    }

    private static func isLastDayOfLunarMonth(_ noonDate: Date) -> Bool {
        var scanCal = Calendar(identifier: .gregorian)
        scanCal.timeZone = beijingTimeZone
        guard let nextDay = scanCal.date(byAdding: .day, value: 1, to: noonDate) else { return false }
        return LunarCalendarEngine.info(for: nextDay).lunarDay == 1
    }
}
