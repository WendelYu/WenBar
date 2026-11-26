import XCTest
@testable import WenBarCore

final class AlmanacTests: XCTestCase {
    private func beijingDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    func testKnownDayPillars() {
        // 2000-01-01 is 戊午日
        let y2k = beijingDate(2000, 1, 1)
        let info2k = ChineseAlmanacEngine.info(for: y2k)
        XCTAssertEqual(info2k.dayPillar, "戊午")
        XCTAssertEqual(info2k.yearPillar, "己卯") // Before 立春 in 2000

        // 2026-02-17 (春节) is 壬戌日
        let cny = beijingDate(2026, 2, 17)
        let cnyInfo = ChineseAlmanacEngine.info(for: cny)
        XCTAssertEqual(cnyInfo.dayPillar, "壬戌")
        XCTAssertEqual(cnyInfo.yearPillar, "丙午")
        XCTAssertEqual(cnyInfo.monthPillar, "庚寅")
    }

    func testNov2026AlmanacCompleteness() {
        let nov26 = beijingDate(2026, 11, 26)
        let info = ChineseAlmanacEngine.info(for: nov26)
        XCTAssertEqual(info.yearPillar, "丙午")
        XCTAssertEqual(info.monthPillar, "己亥")
        XCTAssertFalse(info.dayNaYin.isEmpty)
        XCTAssertFalse(info.jianChu.isEmpty)
        XCTAssertFalse(info.twelveSpirit.isEmpty)
        XCTAssertFalse(info.chongSha.isEmpty)
        XCTAssertFalse(info.pengZu.isEmpty)
        XCTAssertFalse(info.yi.isEmpty)
        XCTAssertFalse(info.ji.isEmpty)
    }
}
