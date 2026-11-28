import XCTest
@testable import WenBarCore

final class CustomReminderTests: XCTestCase {
    private let beijingTZ = TimeZone(identifier: "Asia/Shanghai")!

    private func beijingDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 9, _ minute: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = beijingTZ
        return cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    func testLunarToGregorianConversionAndFallbacks() {
        // 2026 正月初一 -> 2026-02-17
        let cny2026 = CustomReminderEngine.gregorianDate(
            forLunarYear: 2026,
            month: 1,
            day: 1,
            isLeapMonth: false,
            timeZone: beijingTZ
        )
        XCTAssertNotNil(cny2026)
        XCTAssertEqual(CustomReminderEngine.dateKey(for: cny2026!, timeZone: beijingTZ), "2026-02-17")

        // 2025 闰六月初一 -> 2025-07-25
        let leapSix2025 = CustomReminderEngine.gregorianDate(
            forLunarYear: 2025,
            month: 6,
            day: 1,
            isLeapMonth: true,
            timeZone: beijingTZ
        )
        XCTAssertNotNil(leapSix2025)
        XCTAssertEqual(CustomReminderEngine.dateKey(for: leapSix2025!, timeZone: beijingTZ), "2025-07-25")

        // 2026 has no 闰六月 -> falls back to non-leap 六月初一 (2026-07-14)
        let fallbackNonLeap = CustomReminderEngine.gregorianDate(
            forLunarYear: 2026,
            month: 6,
            day: 1,
            isLeapMonth: true,
            timeZone: beijingTZ
        )
        XCTAssertNotNil(fallbackNonLeap)
        XCTAssertEqual(CustomReminderEngine.dateKey(for: fallbackNonLeap!, timeZone: beijingTZ), "2026-07-14")
        XCTAssertEqual(LunarCalendarEngine.info(for: fallbackNonLeap!).lunarMonth, 6)
        XCTAssertEqual(LunarCalendarEngine.info(for: fallbackNonLeap!).lunarDay, 1)

        // Small lunar month fallback: request day 30 when month only has 29 days -> falls back to 廿九
        // 2026-02-17 is 正月初一, 2026-03-19 is 二月初一 -> 正月 has 30 days; check 二月 (03-19 .. 04-16 = 29 days)
        let erYue30Fallback = CustomReminderEngine.gregorianDate(
            forLunarYear: 2026,
            month: 2,
            day: 30,
            isLeapMonth: false,
            timeZone: beijingTZ
        )
        XCTAssertNotNil(erYue30Fallback)
        XCTAssertEqual(CustomReminderEngine.dateKey(for: erYue30Fallback!, timeZone: beijingTZ), "2026-04-16")
    }

    func testLunarYearlyRecurrenceAndCompletionPerYear() {
        // Lunar 十月十八 in 2026 is 2026-11-26; in 2027 it's 2027-11-15
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2027, 11, 15)).lunarMonth, 10)
        XCTAssertEqual(LunarCalendarEngine.info(for: beijingDate(2027, 11, 15)).lunarDay, 18)
        var reminder = CustomReminder(
            title: "农历生日",
            calendarType: .lunar,
            gregorianYear: 2026,
            gregorianMonth: 11,
            gregorianDay: 26,
            lunarYear: 2026,
            lunarMonth: 10,
            lunarDay: 18,
            isLeapMonth: false,
            hour: 9,
            minute: 0,
            repeatRule: .yearly,
            advanceDays: [7, 3, 0]
        )

        let occs = CustomReminderEngine.occurrences(
            of: reminder,
            from: beijingDate(2026, 1, 1),
            to: beijingDate(2027, 12, 31),
            timeZone: beijingTZ
        )
        XCTAssertEqual(occs.map(\.dateKey), ["2026-11-26", "2027-11-15"])
        XCTAssertFalse(occs[0].isCompleted)
        XCTAssertFalse(occs[1].isCompleted)

        // Marking 2026-11-26 completed should keep 2027-11-15 pending
        reminder.completedOccurrenceKeys.insert("2026-11-26")
        let next = CustomReminderEngine.nextOccurrence(
            of: reminder,
            after: beijingDate(2026, 11, 1),
            timeZone: beijingTZ
        )
        XCTAssertEqual(next?.dateKey, "2027-11-15")
    }

    func testGregorianMonthlyClampingAndAdvanceNotifications() {
        let reminder = CustomReminder(
            title: "账单还款",
            notes: "招商银行",
            calendarType: .gregorian,
            gregorianYear: 2026,
            gregorianMonth: 1,
            gregorianDay: 31,
            lunarYear: 2025,
            lunarMonth: 12,
            lunarDay: 13,
            hour: 10,
            minute: 30,
            repeatRule: .monthly,
            advanceDays: [7, 3, 0]
        )

        let occs = CustomReminderEngine.occurrences(
            of: reminder,
            from: beijingDate(2026, 1, 1),
            to: beijingDate(2026, 4, 30),
            timeZone: beijingTZ
        )
        XCTAssertEqual(occs.map(\.dateKey), ["2026-01-31", "2026-02-28", "2026-03-31", "2026-04-30"])

        // Plan notifications from 2026-11-28 for a single occurrence on 2026-12-10
        let decReminder = CustomReminder(
            title: "项目汇报",
            calendarType: .gregorian,
            gregorianYear: 2026,
            gregorianMonth: 12,
            gregorianDay: 10,
            lunarYear: 2026,
            lunarMonth: 11,
            lunarDay: 2,
            hour: 9,
            minute: 0,
            repeatRule: .once,
            advanceDays: [30, 7, 3, 0]
        )

        let now = beijingDate(2026, 12, 4, 8, 0) // Dec 4 morning -> 30d(Nov 10) & 7d(Dec 3) already past; 3d(Dec 7) & 0d(Dec 10) remain
        let alerts = CustomReminderEngine.plannedNotifications(
            for: [decReminder],
            from: now,
            horizonDays: 60,
            timeZone: beijingTZ
        )
        XCTAssertEqual(alerts.count, 2)
        XCTAssertEqual(alerts[0].advanceDays, 3)
        XCTAssertEqual(CustomReminderEngine.dateKey(year: alerts[0].fireYear, month: alerts[0].fireMonth, day: alerts[0].fireDay), "2026-12-07")
        XCTAssertEqual(alerts[0].fireHour, 9)
        XCTAssertEqual(alerts[0].fireMinute, 0)

        XCTAssertEqual(alerts[1].advanceDays, 0)
        XCTAssertEqual(CustomReminderEngine.dateKey(year: alerts[1].fireYear, month: alerts[1].fireMonth, day: alerts[1].fireDay), "2026-12-10")
    }
}
