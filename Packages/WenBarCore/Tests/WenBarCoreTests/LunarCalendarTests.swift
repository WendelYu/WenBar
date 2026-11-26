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
    }
}
