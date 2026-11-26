import XCTest
@testable import WenBarCore

final class LunarCalendarTests: XCTestCase {
    private func beijingDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    func testSpringFestival2026AndChuXi() {
        // 2026 Chinese New Year is 2026-02-17 (丙午马年 正月初一)
        let cny = beijingDate(2026, 2, 17)
        let cnyInfo = LunarCalendarEngine.info(for: cny)
        XCTAssertEqual(cnyInfo.lunarMonth, 1)
        XCTAssertEqual(cnyInfo.lunarDay, 1)
        XCTAssertEqual(cnyInfo.monthName, "正月")
        XCTAssertEqual(cnyInfo.dayName, "初一")
        XCTAssertEqual(cnyInfo.traditionalFestival, "春节")
        XCTAssertEqual(cnyInfo.zodiac, "马")

        // 2026-02-16 is 除夕
        let chuxi = beijingDate(2026, 2, 16)
        let chuxiInfo = LunarCalendarEngine.info(for: chuxi)
        XCTAssertEqual(chuxiInfo.traditionalFestival, "除夕")
    }

    func testLeapMonth2025() {
        // 2025 has 闰六月 (Leap 6th lunar month, e.g. 2025-07-25 is 闰六月初一)
        let leapDay = beijingDate(2025, 7, 25)
        let info = LunarCalendarEngine.info(for: leapDay)
        XCTAssertTrue(info.isLeapMonth)
        XCTAssertEqual(info.lunarMonth, 6)
        XCTAssertEqual(info.monthName, "闰六月")
        XCTAssertEqual(info.dayName, "初一")
    }

    func testSolarTerms2026() {
        XCTAssertEqual(LunarCalendarEngine.solarTermName(year: 2026, month: 2, day: 4), "立春")
        XCTAssertEqual(LunarCalendarEngine.solarTermName(year: 2026, month: 2, day: 18), "雨水")
        XCTAssertEqual(LunarCalendarEngine.solarTermName(year: 2026, month: 4, day: 5), "清明")
        XCTAssertEqual(LunarCalendarEngine.solarTermName(year: 2026, month: 6, day: 21), "夏至")
        XCTAssertEqual(LunarCalendarEngine.solarTermName(year: 2026, month: 12, day: 22), "冬至")
    }

    func testCellSubtitlePriority() {
        // 2026-10-01 has statutory holiday 国庆节
        let oct1 = beijingDate(2026, 10, 1)
        let holiday = HolidayDay(name: "国庆节", date: "2026-10-01", isOffDay: true)
        XCTAssertEqual(LunarCalendarEngine.cellSubtitle(for: oct1, holiday: holiday), "国庆节")

        // 2026-04-05 is 清明 (solar term)
        let qingming = beijingDate(2026, 4, 5)
        XCTAssertEqual(LunarCalendarEngine.cellSubtitle(for: qingming, holiday: nil), "清明")

        // 2026-11-26 is 感恩节 (4th Thursday of November)
        let thanksgiving = beijingDate(2026, 11, 26)
        XCTAssertEqual(LunarCalendarEngine.info(for: thanksgiving).gregorianFestival, "感恩节")
        XCTAssertEqual(LunarCalendarEngine.cellSubtitle(for: thanksgiving, holiday: nil), "感恩节")
    }

    func testAdditionalFestivalsNextSolarTermAndCountdown() {
        // 2026-05-10 is Mother's Day (2nd Sunday of May)
        let mothersDay = beijingDate(2026, 5, 10)
        XCTAssertEqual(LunarCalendarEngine.info(for: mothersDay).gregorianFestival, "母亲节")

        // 2026-11-09 is 十月初一 (寒衣节), 2026-11-23 is 十月十五 (下元节)
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 11, 9)).traditionalFestival, "寒衣节")
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 11, 23)).traditionalFestival, "下元节")

        // Next solar term after 2026-11-26 is 大雪 (2026-12-07, 11 days)
        let nov26 = beijingDate(2026, 11, 26)
        let nextTerm = LunarCalendarEngine.nextSolarTerm(after: nov26)
        XCTAssertEqual(nextTerm?.name, "大雪")
        XCTAssertEqual(nextTerm?.daysRemaining, 11)
        XCTAssertEqual(nextTerm?.weekdayCN, "周一")

        // CountdownFormatter checks
        let d1 = CountdownFormatter.describe(from: nov26, to: nov26.addingTimeInterval(35 * 60))
        XCTAssertEqual(d1.number, "35")
        XCTAssertEqual(d1.unit, "分钟")

        let d2 = CountdownFormatter.describe(from: nov26, to: nov26.addingTimeInterval(3 * 3600))
        XCTAssertEqual(d2.number, "3")
        XCTAssertEqual(d2.unit, "小时")

        let d3 = CountdownFormatter.describe(from: nov26, to: beijingDate(2026, 12, 7), isAllDay: true)
        XCTAssertEqual(d3.number, "11")
        XCTAssertEqual(d3.unit, "天")
    }

    func testCommemorativeDaysEasterSanfuAndShujiu() {
        // 2026-04-04 is 寒食节 (day before 清明 04-05)
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 4, 4)).traditionalFestival, "寒食节")

        // 2026-04-05 is Easter Sunday
        let easter2026 = LunarCalendarEngine.info(for: beijingDate(2026, 4, 5))
        XCTAssertTrue(easter2026.extraFestivals.contains(where: { $0.name == "复活节" }))

        // Commemorative days
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 3, 15)).gregorianFestival, "国际消费者权益日")
        XCTAssertEqual(LunarCalendarEngine.cellSubtitle(for: beijingDate(2026, 3, 15), holiday: nil), "3·15")
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 9, 3)).gregorianFestival, "抗战胜利纪念日")
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 12, 4)).gregorianFestival, "国家宪法日")
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 12, 13)).gregorianFestival, "国家公祭日")

        // 2026 三伏: 初伏 7/15, 中伏 7/25, 末伏 8/14
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 7, 15)).seasonalLabel, "三伏 · 初伏第1天")
        XCTAssertEqual(LunarCalendarEngine.cellSubtitle(for: beijingDate(2026, 7, 15), holiday: nil), "初伏")
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 7, 25)).seasonalLabel, "三伏 · 中伏第1天")
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 8, 14)).seasonalLabel, "三伏 · 末伏第1天")

        // 2026-2027 数九: 2026-12-22 冬至 is 一九第1天; 2027-01-09 is 三九第1天
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2026, 12, 22)).seasonalLabel, "数九 · 一九第1天")
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2027, 1, 9)).seasonalLabel, "数九 · 三九第1天")
        XCTAssertEqual(LunarCalendarEngine.cellSubtitle(for: beijingDate(2027, 1, 9), holiday: nil), "三九")
    }
}
