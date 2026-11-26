import XCTest
@testable import WenBarCore

final class ClockAndActionTests: XCTestCase {
    func testSecondsDetection() {
        XCTAssertFalse(ClockFormatEngine.requiresPerSecondUpdates(template: "MM/dd EEE HH:mm"))
        XCTAssertTrue(ClockFormatEngine.requiresPerSecondUpdates(template: "MM/dd EEE HH:mm:ss"))
        XCTAssertFalse(ClockFormatEngine.requiresPerSecondUpdates(template: "HH:mm 'sec'"))
        XCTAssertFalse(ClockFormatEngine.requiresPerSecondUpdates(template: "M月d日 {lunar} HH:mm"))
    }

    func testClockFormattingWithLunarAndExtendedMacros() {
        var comps = DateComponents()
        comps.year = 2026
        comps.month = 2
        comps.day = 17
        comps.hour = 15
        comps.minute = 5
        comps.timeZone = TimeZone(identifier: "Asia/Shanghai")
        let date = Calendar(identifier: .gregorian).date(from: comps)!

        let nextHoliday = NextHolidayCountdown(
            name: "清明节",
            startDate: date.addingTimeInterval(46 * 86400),
            daysRemaining: 46,
            isOngoing: false
        )

        let formatted = ClockFormatEngine.format(
            date: date,
            template: "M月d日 {lunar_full} {zodiac} {weekday_full} {ampm} {festival} {holiday_cd}\\nHH:mm",
            locale: Locale(identifier: "zh_CN"),
            timeZone: TimeZone(identifier: "Asia/Shanghai")!,
            nextHoliday: nextHoliday
        )
        let lines = formatted.components(separatedBy: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertTrue(lines[0].contains("2月17日"))
        XCTAssertTrue(lines[0].contains("正月初一"))
        XCTAssertTrue(lines[0].contains("马"))
        XCTAssertTrue(lines[0].contains("星期二"))
        XCTAssertTrue(lines[0].contains("下午"))
        XCTAssertTrue(lines[0].contains("春节"))
        XCTAssertTrue(lines[0].contains("距清明节46天"))
        XCTAssertEqual(lines[1], "15:05")
    }

    func testSettingsBackwardsCompatibleDecoding() throws {
        // Simulate older persisted settings missing new clock typography keys
        let legacyJSON = """
        {
          "enableClockCalendar": true,
          "enableDiskManager": true,
          "enableArchiveTools": true,
          "clockFormatTemplate": "MM/dd EEE HH:mm"
        }
        """
        let decoded = try JSONDecoder().decode(WenBarSettingsModel.self, from: Data(legacyJSON.utf8))
        XCTAssertEqual(decoded.clockFontSize, 13)
        XCTAssertEqual(decoded.clockFontWeight, .regular)
        XCTAssertTrue(decoded.clockUseMonospacedDigits)
        XCTAssertFalse(decoded.clockShowCalendarIcon)
        XCTAssertTrue(decoded.deleteSourceDSStoreAfterCompress)
        XCTAssertTrue(decoded.customClockTemplates.isEmpty)
    }

    func testCustomClockTemplatesRoundTrip() throws {
        var model = WenBarSettingsModel()
        model.customClockTemplates = [
            ClockFormatPreset(id: "c1", name: "工作双行", template: "M月d日 {lunar}\\n{weekday_cn} HH:mm")
        ]
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(WenBarSettingsModel.self, from: data)
        XCTAssertEqual(decoded.customClockTemplates, model.customClockTemplates)
    }

    func testActionPayloadURLRoundTrip() throws {
        let original = WenBarActionPayload(
            kind: .compressCustom,
            paths: ["/Users/ven/Desktop/测试文件.txt", "/Users/ven/Desktop/文件夹"],
            targetDirectory: "/Users/ven/Desktop"
        )
        let url = original.makeURL()
        XCTAssertNotNil(url)
        let queryItems = URLComponents(url: url!, resolvingAgainstBaseURL: false)?.queryItems
        let encoded = queryItems?.first(where: { $0.name == "payload" })?.value
        XCTAssertNotNil(encoded)

        let decoded = try WenBarActionPayload.decodeBase64URLSafe(encoded!)
        XCTAssertEqual(decoded, original)
    }
}
