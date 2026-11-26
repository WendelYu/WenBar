import Foundation

/// Represents a complete Chinese lunar calendar breakdown for a Gregorian date.
public struct LunarDateInfo: Sendable, Equatable {
    public let lunarYear: Int
    public let lunarMonth: Int
    public let lunarDay: Int
    public let isLeapMonth: Bool
    public let heavenlyStem: String
    public let earthlyBranch: String
    public let zodiac: String
    public let monthName: String
    public let dayName: String
    public let solarTerm: String?
    public let traditionalFestival: String?
    public let gregorianFestival: String?

    public var yearGanZhi: String {
        "\(heavenlyStem)\(earthlyBranch)年"
    }

    public var fullLunarText: String {
        "\(yearGanZhi)[\(zodiac)] \(monthName)\(dayName)"
    }
}

/// Pure Swift Chinese lunar calendar, 24 solar terms, and traditional festival engine.
public enum LunarCalendarEngine {
    private static let stems = ["甲", "乙", "丙", "丁", "戊", "己", "庚", "辛", "壬", "癸"]
    private static let branches = ["子", "丑", "寅", "卯", "辰", "巳", "午", "未", "申", "酉", "戌", "亥"]
    private static let zodiacs = ["鼠", "牛", "虎", "兔", "龙", "蛇", "马", "羊", "猴", "鸡", "狗", "猪"]

    private static let monthNames = [
        "正月", "二月", "三月", "四月", "五月", "六月",
        "七月", "八月", "九月", "十月", "冬月", "腊月"
    ]

    private static let dayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十"
    ]

    /// 24 Solar Terms ordered starting from 小寒 (Jan) through 冬至 (Dec).
    private static let solarTermNames = [
        "小寒", "大寒", "立春", "雨水", "惊蛰", "春分",
        "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
        "小暑", "大暑", "立秋", "处暑", "白露", "秋分",
        "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
    ]

    /// Solar term C-constants for 21st century (2000-2099) and 20th century (1900-1999)
    /// using the standard ShouXing (寿星) astronomical approximation.
    private static let solarTermC21: [Double] = [
        5.4055, 20.12, 3.87, 18.73, 5.63, 20.646,
        4.81, 20.1, 5.52, 21.04, 5.678, 21.37,
        7.108, 22.83, 7.5, 23.13, 7.646, 23.042,
        8.318, 23.438, 7.438, 22.36, 7.18, 21.94
    ]

    private static let solarTermC20: [Double] = [
        6.11, 20.84, 4.15, 19.04, 6.11, 20.84,
        5.59, 20.888, 6.318, 21.86, 6.5, 22.2,
        7.928, 23.65, 8.35, 23.95, 8.44, 23.822,
        9.098, 24.218, 8.218, 23.08, 7.9, 22.6
    ]

    private static let chineseCalendar: Calendar = {
        var cal = Calendar(identifier: .chinese)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }()

    private static let gregorianCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }()

    public static func info(for date: Date) -> LunarDateInfo {
        let comps = chineseCalendar.dateComponents([.era, .year, .month, .day, .isLeapMonth], from: date)
        let cycleYear = comps.year ?? 1
        let stemIdx = (cycleYear - 1) % 10
        let branchIdx = (cycleYear - 1) % 12

        let lunarMonth = comps.month ?? 1
        let lunarDay = comps.day ?? 1
        let isLeap = comps.isLeapMonth ?? false

        let rawMonth = (lunarMonth >= 1 && lunarMonth <= 12) ? monthNames[lunarMonth - 1] : "\(lunarMonth)月"
        let monthName = isLeap ? "闰\(rawMonth)" : rawMonth
        let dayName = (lunarDay >= 1 && lunarDay <= 30) ? dayNames[lunarDay - 1] : "\(lunarDay)"

        let gComps = gregorianCalendar.dateComponents([.year, .month, .day], from: date)
        let gYear = gComps.year ?? 2026
        let gMonth = gComps.month ?? 1
        let gDay = gComps.day ?? 1

        let solarTerm = solarTermName(year: gYear, month: gMonth, day: gDay)
        let tradFestival = traditionalFestivalName(for: date, month: lunarMonth, day: lunarDay, isLeap: isLeap)
        let gregFestival = gregorianFestivalName(month: gMonth, day: gDay)

        // Approximate numeric lunar year aligned with Gregorian year (adjusted for Jan/Feb before CNY)
        var approxYear = gYear
        if gMonth <= 2 && lunarMonth >= 11 {
            approxYear -= 1
        }

        return LunarDateInfo(
            lunarYear: approxYear,
            lunarMonth: lunarMonth,
            lunarDay: lunarDay,
            isLeapMonth: isLeap,
            heavenlyStem: stems[stemIdx],
            earthlyBranch: branches[branchIdx],
            zodiac: zodiacs[branchIdx],
            monthName: monthName,
            dayName: dayName,
            solarTerm: solarTerm,
            traditionalFestival: tradFestival,
            gregorianFestival: gregFestival
        )
    }

    /// Priority display subtitle for a calendar grid cell:
    /// Statutory Holiday > Traditional Festival > Solar Term > Gregorian Festival > Lunar Month (on 初一) > Lunar Day
    public static func cellSubtitle(for date: Date, holiday: HolidayDay?) -> String {
        let info = self.info(for: date)
        if let holiday, holiday.isOffDay, !holiday.name.isEmpty {
            return shortHolidayLabel(holiday.name)
        }
        if let trad = info.traditionalFestival {
            return trad
        }
        if let term = info.solarTerm {
            return term
        }
        if let greg = info.gregorianFestival {
            return greg
        }
        if info.lunarDay == 1 {
            return info.monthName
        }
        return info.dayName
    }

    private static func shortHolidayLabel(_ name: String) -> String {
        if name.count <= 4 { return name }
        return String(name.prefix(4))
    }

    /// Computes the 24 solar term (if any) on the given Gregorian year/month/day.
    public static func solarTermName(year: Int, month: Int, day: Int) -> String? {
        guard month >= 1, month <= 12, year >= 1900, year <= 2099 else { return nil }
        let idx1 = (month - 1) * 2
        let idx2 = idx1 + 1

        if day == solarTermDay(year: year, index: idx1) {
            return solarTermNames[idx1]
        }
        if day == solarTermDay(year: year, index: idx2) {
            return solarTermNames[idx2]
        }
        return nil
    }

    /// ShouXing formula: `Int(Y * 0.2422 + C) - Int((Y - 1) / 4)` with known historical offsets.
    public static func solarTermDay(year: Int, index: Int) -> Int {
        let y = year % 100
        let is21st = year >= 2000
        let c = is21st ? solarTermC21[index] : solarTermC20[index]

        var day: Int
        if year == 2000 && index <= 3 {
            // Year 2000 Jan-Feb leap offset
            day = Int(Double(y) * 0.2422 + c) - Int(Double(y) / 4.0)
        } else {
            day = Int(Double(y) * 0.2422 + c) - Int(Double(y - 1) / 4.0)
        }

        // Known 21st-century 1-day astronomical adjustments
        switch (year, index) {
        case (2019, 0): day -= 1 // 小寒
        case (2082, 1): day += 1 // 大寒
        case (2026, 3): day -= 1 // 雨水 2026-02-18
        case (2084, 5): day += 1 // 春分
        case (2008, 9): day += 1 // 小满
        case (2016, 13): day += 1 // 大暑
        case (2002, 14): day += 1 // 立秋
        case (2089, 18): day += 1 // 寒露
        case (2089, 19): day += 1 // 霜降
        case (2021, 23): day -= 1 // 冬至
        case (1982, 0): day += 1
        default: break
        }

        return day
    }

    private static func traditionalFestivalName(for date: Date, month: Int, day: Int, isLeap: Bool) -> String? {
        guard !isLeap else { return nil }

        // Check 除夕: tomorrow is 正月初一
        if month == 12 && (day == 29 || day == 30) {
            if let tomorrow = gregorianCalendar.date(byAdding: .day, value: 1, to: date) {
                let tComps = chineseCalendar.dateComponents([.month, .day, .isLeapMonth], from: tomorrow)
                if tComps.month == 1 && tComps.day == 1 && !(tComps.isLeapMonth ?? false) {
                    return "除夕"
                }
            }
        }

        switch (month, day) {
        case (1, 1): return "春节"
        case (1, 15): return "元宵节"
        case (2, 2): return "龙抬头"
        case (5, 5): return "端午节"
        case (7, 7): return "七夕"
        case (7, 15): return "中元节"
        case (8, 15): return "中秋节"
        case (9, 9): return "重阳节"
        case (12, 8): return "腊八节"
        case (12, 23): return "北方小年"
        case (12, 24): return "南方小年"
        default: return nil
        }
    }

    private static func gregorianFestivalName(month: Int, day: Int) -> String? {
        switch (month, day) {
        case (1, 1): return "元旦"
        case (2, 14): return "情人节"
        case (3, 8): return "妇女节"
        case (3, 12): return "植树节"
        case (4, 1): return "愚人节"
        case (5, 1): return "劳动节"
        case (5, 4): return "青年节"
        case (6, 1): return "儿童节"
        case (9, 10): return "教师节"
        case (10, 1): return "国庆节"
        case (12, 24): return "平安夜"
        case (12, 25): return "圣诞节"
        default: return nil
        }
    }
}
