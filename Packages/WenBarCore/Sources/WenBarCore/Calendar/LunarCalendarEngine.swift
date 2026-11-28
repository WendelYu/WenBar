import Foundation

public struct FestivalTag: Sendable, Equatable {
    public enum Category: String, Sendable, Equatable {
        case traditional
        case gregorian
        case commemorative
        case seasonal
    }

    public let name: String
    public let shortName: String
    public let category: Category

    public init(name: String, shortName: String? = nil, category: Category) {
        self.name = name
        self.shortName = shortName ?? name
        self.category = category
    }
}

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
    public let extraFestivals: [FestivalTag]
    public let seasonalLabel: String?

    public var yearGanZhi: String {
        "\(heavenlyStem)\(earthlyBranch)年"
    }

    public var fullLunarText: String {
        "\(yearGanZhi)[\(zodiac)] \(monthName)\(dayName)"
    }
}

public struct NextSolarTermInfo: Sendable, Equatable {
    public let name: String
    public let date: Date
    public let lunarText: String
    public let weekdayCN: String
    public let daysRemaining: Int

    public init(name: String, date: Date, lunarText: String, weekdayCN: String, daysRemaining: Int) {
        self.name = name
        self.date = date
        self.lunarText = lunarText
        self.weekdayCN = weekdayCN
        self.daysRemaining = daysRemaining
    }
}

public enum CountdownFormatter {
    public struct Display: Sendable, Equatable {
        public let number: String
        public let unit: String
        public let isOverdue: Bool
    }

    public static func describe(from now: Date, to target: Date, isAllDay: Bool = false) -> Display {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current

        let todayStart = cal.startOfDay(for: now)
        let targetStart = cal.startOfDay(for: target)
        let dayDiff = cal.dateComponents([.day], from: todayStart, to: targetStart).day ?? 0

        if isAllDay || dayDiff != 0 {
            if dayDiff == 0 {
                return Display(number: "今天", unit: "", isOverdue: false)
            } else if dayDiff > 0 {
                return Display(number: "\(dayDiff)", unit: "天", isOverdue: false)
            } else {
                return Display(number: "已过\(-dayDiff)", unit: "天", isOverdue: true)
            }
        }

        // Same day timed event/reminder
        let seconds = Int(target.timeIntervalSince(now))
        if seconds <= 0 {
            let minsAgo = max(1, (-seconds) / 60)
            if minsAgo < 60 {
                return Display(number: "已过\(minsAgo)", unit: "分钟", isOverdue: true)
            }
            return Display(number: "已过\(minsAgo / 60)", unit: "小时", isOverdue: true)
        }

        let minutes = max(1, seconds / 60)
        if minutes < 60 {
            return Display(number: "\(minutes)", unit: "分钟", isOverdue: false)
        }
        let hours = minutes / 60
        let remMinutes = minutes % 60
        if remMinutes == 0 || hours >= 5 {
            return Display(number: "\(hours)", unit: "小时", isOverdue: false)
        }
        return Display(number: "\(hours)h\(remMinutes)m", unit: "后", isOverdue: false)
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
        let tradFestival = traditionalFestivalName(
            for: date,
            gYear: gYear,
            gMonth: gMonth,
            gDay: gDay,
            month: lunarMonth,
            day: lunarDay,
            isLeap: isLeap
        )
        let gregTags = gregorianFestivalTags(for: date, year: gYear, month: gMonth, day: gDay)
        let seasonal = seasonalPeriodInfo(for: date, year: gYear, month: gMonth, day: gDay)

        var allExtras: [FestivalTag] = []
        if let tradFestival {
            allExtras.append(FestivalTag(name: tradFestival, category: .traditional))
        }
        allExtras.append(contentsOf: gregTags)
        if let seasonalFirstDay = seasonal.gridShortName {
            allExtras.append(FestivalTag(name: seasonal.fullLabel, shortName: seasonalFirstDay, category: .seasonal))
        }

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
            gregorianFestival: gregTags.first?.name,
            extraFestivals: allExtras,
            seasonalLabel: seasonal.fullLabel.isEmpty ? nil : seasonal.fullLabel
        )
    }

    /// Priority display subtitle for a calendar grid cell:
    /// Statutory Holiday > Traditional Festival > Solar Term > Gregorian/Commemorative Festival > 三伏/数九首日 > Lunar Month (on 初一) > Lunar Day
    public static func cellSubtitle(for date: Date, holiday: HolidayDay?) -> String {
        cellSubtitle(for: date, holiday: holiday, precomputedInfo: self.info(for: date))
    }

    public static func cellSubtitle(for date: Date, holiday: HolidayDay?, precomputedInfo info: LunarDateInfo) -> String {
        if let holiday, holiday.isOffDay, !holiday.name.isEmpty {
            return shortHolidayLabel(holiday.name)
        }
        if let trad = info.traditionalFestival {
            return trad
        }
        if let term = info.solarTerm {
            return term
        }
        if let gregTag = info.extraFestivals.first(where: { $0.category == .gregorian || $0.category == .commemorative }) {
            return gregTag.shortName
        }
        if let seasonalTag = info.extraFestivals.first(where: { $0.category == .seasonal }) {
            return seasonalTag.shortName
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

    private static func traditionalFestivalName(
        for date: Date,
        gYear: Int,
        gMonth: Int,
        gDay: Int,
        month: Int,
        day: Int,
        isLeap: Bool
    ) -> String? {
        // 寒食节 is the day before 清明 (solar-based traditional festival)
        if gMonth == 4 {
            let qingMingDay = solarTermDay(year: gYear, index: 6)
            if gDay == qingMingDay - 1 {
                return "寒食节"
            }
        }

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
        case (1, 5): return "破五节"
        case (1, 15): return "元宵节"
        case (2, 2): return "龙抬头"
        case (2, 12): return "花朝节"
        case (3, 3): return "上巳节"
        case (5, 5): return "端午节"
        case (6, 24): return "火把节"
        case (7, 7): return "七夕"
        case (7, 15): return "中元节"
        case (8, 15): return "中秋节"
        case (9, 9): return "重阳节"
        case (10, 1): return "寒衣节"
        case (10, 15): return "下元节"
        case (12, 8): return "腊八节"
        case (12, 23): return "北方小年"
        case (12, 24): return "南方小年"
        default: return nil
        }
    }

    private static func gregorianFestivalTags(for date: Date, year: Int, month: Int, day: Int) -> [FestivalTag] {
        var tags: [FestivalTag] = []

        switch (month, day) {
        case (1, 1): tags.append(FestivalTag(name: "元旦", category: .gregorian))
        case (1, 10): tags.append(FestivalTag(name: "中国人民警察节", shortName: "警察节", category: .commemorative))
        case (2, 14): tags.append(FestivalTag(name: "情人节", category: .gregorian))
        case (3, 5): tags.append(FestivalTag(name: "学雷锋纪念日", shortName: "学雷锋", category: .commemorative))
        case (3, 8): tags.append(FestivalTag(name: "妇女节", category: .gregorian))
        case (3, 12): tags.append(FestivalTag(name: "植树节", category: .commemorative))
        case (3, 14): tags.append(FestivalTag(name: "白色情人节", shortName: "白色情人", category: .gregorian))
        case (3, 15): tags.append(FestivalTag(name: "国际消费者权益日", shortName: "3·15", category: .commemorative))
        case (3, 21): tags.append(FestivalTag(name: "世界睡眠日", shortName: "睡眠日", category: .commemorative))
        case (3, 22): tags.append(FestivalTag(name: "世界水日", category: .commemorative))
        case (4, 1): tags.append(FestivalTag(name: "愚人节", category: .gregorian))
        case (4, 22): tags.append(FestivalTag(name: "世界地球日", shortName: "地球日", category: .commemorative))
        case (4, 23): tags.append(FestivalTag(name: "世界读书日", shortName: "读书日", category: .commemorative))
        case (4, 24): tags.append(FestivalTag(name: "中国航天日", shortName: "航天日", category: .commemorative))
        case (5, 1): tags.append(FestivalTag(name: "劳动节", category: .gregorian))
        case (5, 4): tags.append(FestivalTag(name: "青年节", category: .commemorative))
        case (5, 12): tags.append(FestivalTag(name: "国际护士节", shortName: "护士节", category: .commemorative))
        case (5, 18): tags.append(FestivalTag(name: "国际博物馆日", shortName: "博物馆日", category: .commemorative))
        case (5, 19): tags.append(FestivalTag(name: "中国旅游日", shortName: "旅游日", category: .commemorative))
        case (5, 20): tags.append(FestivalTag(name: "网络情人节", shortName: "520", category: .gregorian))
        case (5, 31): tags.append(FestivalTag(name: "世界无烟日", shortName: "无烟日", category: .commemorative))
        case (6, 1): tags.append(FestivalTag(name: "儿童节", category: .gregorian))
        case (6, 5): tags.append(FestivalTag(name: "世界环境日", shortName: "环境日", category: .commemorative))
        case (6, 6): tags.append(FestivalTag(name: "全国爱眼日", shortName: "爱眼日", category: .commemorative))
        case (6, 26): tags.append(FestivalTag(name: "国际禁毒日", shortName: "禁毒日", category: .commemorative))
        case (7, 1): tags.append(FestivalTag(name: "建党节", category: .commemorative))
        case (7, 7): tags.append(FestivalTag(name: "七七事变纪念日", shortName: "七七事变", category: .commemorative))
        case (8, 1): tags.append(FestivalTag(name: "建军节", category: .commemorative))
        case (8, 8): tags.append(FestivalTag(name: "全民健身日", shortName: "健身日", category: .commemorative))
        case (8, 19): tags.append(FestivalTag(name: "中国医师节", shortName: "医师节", category: .commemorative))
        case (9, 3): tags.append(FestivalTag(name: "抗战胜利纪念日", shortName: "抗战胜利", category: .commemorative))
        case (9, 10): tags.append(FestivalTag(name: "教师节", category: .commemorative))
        case (9, 18): tags.append(FestivalTag(name: "九一八事变纪念日", shortName: "九一八", category: .commemorative))
        case (9, 20): tags.append(FestivalTag(name: "全国爱牙日", shortName: "爱牙日", category: .commemorative))
        case (9, 30): tags.append(FestivalTag(name: "烈士纪念日", shortName: "烈士日", category: .commemorative))
        case (10, 1): tags.append(FestivalTag(name: "国庆节", category: .gregorian))
        case (10, 16): tags.append(FestivalTag(name: "世界粮食日", shortName: "粮食日", category: .commemorative))
        case (10, 24): tags.append(FestivalTag(name: "程序员节", category: .gregorian))
        case (10, 31): tags.append(FestivalTag(name: "万圣夜", category: .gregorian))
        case (11, 1): tags.append(FestivalTag(name: "万圣节", category: .gregorian))
        case (11, 8): tags.append(FestivalTag(name: "记者节", category: .commemorative))
        case (11, 9): tags.append(FestivalTag(name: "全国消防日", shortName: "消防日", category: .commemorative))
        case (11, 11): tags.append(FestivalTag(name: "双十一", category: .gregorian))
        case (12, 1): tags.append(FestivalTag(name: "世界艾滋病日", shortName: "艾滋病日", category: .commemorative))
        case (12, 2): tags.append(FestivalTag(name: "全国交通安全日", shortName: "交通日", category: .commemorative))
        case (12, 4): tags.append(FestivalTag(name: "国家宪法日", shortName: "宪法日", category: .commemorative))
        case (12, 13): tags.append(FestivalTag(name: "国家公祭日", shortName: "公祭日", category: .commemorative))
        case (12, 20): tags.append(FestivalTag(name: "澳门回归纪念日", shortName: "澳门回归", category: .commemorative))
        case (12, 24): tags.append(FestivalTag(name: "平安夜", category: .gregorian))
        case (12, 25): tags.append(FestivalTag(name: "圣诞节", category: .gregorian))
        default: break
        }

        // Floating weekday-based holidays (weekday: 1 = Sun, 5 = Thu, 7 = Sat)
        let comps = gregorianCalendar.dateComponents([.weekday, .weekdayOrdinal], from: date)
        if month == 5 && comps.weekday == 1 && comps.weekdayOrdinal == 2 {
            tags.append(FestivalTag(name: "母亲节", category: .gregorian))
        }
        if month == 6 && comps.weekday == 1 && comps.weekdayOrdinal == 3 {
            tags.append(FestivalTag(name: "父亲节", category: .gregorian))
        }
        if month == 9 && comps.weekday == 7 && comps.weekdayOrdinal == 3 {
            tags.append(FestivalTag(name: "全民国防教育日", shortName: "国防教育", category: .commemorative))
        }
        if month == 11 && comps.weekday == 5 && comps.weekdayOrdinal == 4 {
            tags.append(FestivalTag(name: "感恩节", category: .gregorian))
        }

        // Gregorian Easter (Meeus/Jones/Butcher)
        let easter = gregorianEasterDate(year: year)
        if month == easter.month && day == easter.day {
            tags.append(FestivalTag(name: "复活节", category: .gregorian))
        }

        return tags
    }

    private static func gregorianEasterDate(year: Int) -> (month: Int, day: Int) {
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        return (month, day)
    }

    private static func julianDayNumber(year: Int, month: Int, day: Int) -> Int {
        let a = (14 - month) / 12
        let y = year + 4800 - a
        let m = month + 12 * a - 3
        return day + (153 * m + 2) / 5 + 365 * y + y / 4 - y / 100 + y / 400 - 32045
    }

    /// Computes Chinese 三伏 (Sanfu) and 数九 (Shujiu) periods.
    private static func seasonalPeriodInfo(for date: Date, year: Int, month: Int, day: Int) -> (fullLabel: String, gridShortName: String?) {
        let jdn = julianDayNumber(year: year, month: month, day: day)

        // 1. 三伏 (July - August)
        if month >= 7 && month <= 8 {
            let xiaZhiDay = solarTermDay(year: year, index: 11) // June
            let xiaZhiJDN = julianDayNumber(year: year, month: 6, day: xiaZhiDay)
            let xiaZhiStem = (xiaZhiJDN + 49) % 10
            let firstGengAfterXiaZhi = (6 - xiaZhiStem + 10) % 10
            let chuFuStart = xiaZhiJDN + firstGengAfterXiaZhi + 20
            let zhongFuStart = chuFuStart + 10

            let liQiuDay = solarTermDay(year: year, index: 14) // August
            let liQiuJDN = julianDayNumber(year: year, month: 8, day: liQiuDay)
            let liQiuStem = (liQiuJDN + 49) % 10
            let firstGengAfterLiQiu = (6 - liQiuStem + 10) % 10
            let moFuStart = liQiuJDN + firstGengAfterLiQiu
            let moFuEnd = moFuStart + 10

            if jdn >= chuFuStart && jdn < zhongFuStart {
                let dayNum = jdn - chuFuStart + 1
                return ("三伏 · 初伏第\(dayNum)天", dayNum == 1 ? "初伏" : nil)
            } else if jdn >= zhongFuStart && jdn < moFuStart {
                let dayNum = jdn - zhongFuStart + 1
                return ("三伏 · 中伏第\(dayNum)天", dayNum == 1 ? "中伏" : nil)
            } else if jdn >= moFuStart && jdn < moFuEnd {
                let dayNum = jdn - moFuStart + 1
                return ("三伏 · 末伏第\(dayNum)天", dayNum == 1 ? "末伏" : nil)
            }
        }

        // 2. 数九 (starting from 冬至 in Dec, continuing Jan-Mar)
        let jiuNames = ["一九", "二九", "三九", "四九", "五九", "六九", "七九", "八九", "九九"]
        if month == 12 || month <= 3 {
            let dongZhiYear = (month == 12) ? year : (year - 1)
            let dongZhiDay = solarTermDay(year: dongZhiYear, index: 23)
            let dongZhiJDN = julianDayNumber(year: dongZhiYear, month: 12, day: dongZhiDay)
            let offset = jdn - dongZhiJDN
            if offset >= 0 && offset < 81 {
                let idx = offset / 9
                let dayNum = (offset % 9) + 1
                let gridLabel = (dayNum == 1 && offset > 0) ? jiuNames[idx] : nil
                return ("数九 · \(jiuNames[idx])第\(dayNum)天", gridLabel)
            }
        }

        return ("", nil)
    }

    private static let cnWeekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    public static func nextSolarTerm(after date: Date) -> NextSolarTermInfo? {
        let startOfDay = gregorianCalendar.startOfDay(for: date)
        for offset in 1...25 {
            guard let candidate = gregorianCalendar.date(byAdding: .day, value: offset, to: startOfDay) else { continue }
            let g = gregorianCalendar.dateComponents([.year, .month, .day, .weekday], from: candidate)
            guard let y = g.year, let m = g.month, let d = g.day,
                  let termName = solarTermName(year: y, month: m, day: d) else {
                continue
            }
            let lunar = info(for: candidate)
            let wdIdx = (g.weekday ?? 1) - 1
            let weekdayCN = (wdIdx >= 0 && wdIdx < cnWeekdays.count) ? cnWeekdays[wdIdx] : ""
            return NextSolarTermInfo(
                name: termName,
                date: candidate,
                lunarText: "\(lunar.monthName)\(lunar.dayName)",
                weekdayCN: weekdayCN,
                daysRemaining: offset
            )
        }
        return nil
    }
}
