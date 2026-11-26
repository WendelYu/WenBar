import XCTest
@testable import WenBarCore

final class HolidayRepositoryTests: XCTestCase {
    private func beijingDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = day
        comps.hour = 12
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        return Calendar(identifier: .gregorian).date(from: comps)!
    }

    func testFallback2026HolidaysAndTiaoxiu() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = HolidayRepository(cacheDirectory: tempDir)

        // 2026-02-14 is Saturday 调休上班
        let feb14 = await repo.holiday(forKey: "2026-02-14")
        XCTAssertNotNil(feb14)
        XCTAssertEqual(feb14?.isOffDay, false)
        XCTAssertEqual(feb14?.name, "春节")

        // 2026-02-17 is off day
        let feb17 = await repo.holiday(forKey: "2026-02-17")
        XCTAssertEqual(feb17?.isOffDay, true)
    }

    func testNextHolidayCountdown() async {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repo = HolidayRepository(cacheDirectory: tempDir)

        let nov26 = beijingDate(2026, 11, 26)
        let next = await repo.nextHoliday(from: nov26)
        XCTAssertNotNil(next)
        XCTAssertEqual(next?.name, "元旦")
        XCTAssertEqual(next?.daysRemaining, 36)
        XCTAssertEqual(next?.isOngoing, false)

        // Ongoing holiday test
        let may1 = beijingDate(2026, 5, 1)
        let ongoing = await repo.nextHoliday(from: may1)
        XCTAssertEqual(ongoing?.name, "劳动节")
        XCTAssertEqual(ongoing?.isOngoing, true)
        XCTAssertEqual(ongoing?.daysRemaining, 0)
    }

    func testWorkingDaysWithTiaoxiu() {
        // 2026-02-13 (Fri) to 2026-02-16 (Mon):
        // Fri 02-13: workday (1)
        // Sat 02-14: 调休 workday (2)
        // Sun 02-15: 春节 off day
        let start = beijingDate(2026, 2, 13)
        let end = beijingDate(2026, 2, 16)
        let diff = DateCalculator.difference(from: start, to: end)
        XCTAssertEqual(diff.calendarDays, 3)
        XCTAssertEqual(diff.workingDays, 2)
    }
}
