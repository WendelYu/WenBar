import Foundation

/// Manages offline fallback + cached + online-synced Chinese statutory holiday & 调休 schedules.
public actor HolidayRepository {
    public static let defaultDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.calendar = Calendar(identifier: .gregorian)
        df.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        return df
    }()

    private var daysByDateString: [String: HolidayDay] = [:]
    private var lastSyncDate: Date?
    private let cacheDirectory: URL

    public init(cacheDirectory: URL? = nil, fallbackJSONData: Data? = nil) {
        if let cacheDirectory {
            self.cacheDirectory = cacheDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? FileManager.default.temporaryDirectory
            self.cacheDirectory = appSupport.appendingPathComponent("WenBar/holidays", isDirectory: true)
        }

        // Load embedded static fallback first
        for (date, day) in Self.embeddedFallbackDays {
            daysByDateString[date] = day
        }

        // Overlay bundled JSON if provided
        if let fallbackJSONData {
            Self.decodeInto(&daysByDateString, from: fallbackJSONData)
        }

        // Overlay locally cached year JSON files
        Self.loadCachedFiles(in: self.cacheDirectory, into: &daysByDateString)
    }

    public func reloadBundledData(_ data: Data) {
        Self.decodeInto(&daysByDateString, from: data)
        Self.loadCachedFiles(in: cacheDirectory, into: &daysByDateString)
    }

    public func holiday(for date: Date) -> HolidayDay? {
        let key = Self.dateKey(for: date)
        return daysByDateString[key]
    }

    public func holiday(forKey key: String) -> HolidayDay? {
        daysByDateString[key]
    }

    public func allHolidays() -> [HolidayDay] {
        daysByDateString.values.sorted { $0.date < $1.date }
    }

    public func lastSyncedAt() -> Date? {
        lastSyncDate
    }

    public func nextHoliday(from date: Date = Date()) -> NextHolidayCountdown? {
        let cal = Self.beijingCalendar
        let startOfToday = cal.startOfDay(for: date)
        let todayKey = Self.dateKey(for: startOfToday)

        if let todayHoliday = daysByDateString[todayKey], todayHoliday.isOffDay {
            return NextHolidayCountdown(
                name: todayHoliday.name,
                startDate: startOfToday,
                daysRemaining: 0,
                isOngoing: true
            )
        }

        let upcomingOffDays = daysByDateString.values
            .filter { $0.isOffDay && $0.date > todayKey }
            .sorted { $0.date < $1.date }

        guard let next = upcomingOffDays.first,
              let targetDate = Self.defaultDateFormatter.date(from: next.date) else {
            return nil
        }

        let diff = cal.dateComponents([.day], from: startOfToday, to: cal.startOfDay(for: targetDate)).day ?? 0
        return NextHolidayCountdown(
            name: next.name,
            startDate: targetDate,
            daysRemaining: max(0, diff),
            isOngoing: false
        )
    }

    /// Syncs holiday JSON feeds for the specified years from online sources (primary + jsDelivr mirror).
    @discardableResult
    public func syncYears(_ years: [Int], session: URLSession = .shared) async -> Int {
        var updatedYears = 0
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        for year in years {
            let urls = [
                URL(string: "https://raw.githubusercontent.com/NateScarlet/holiday-cn/master/\(year).json")!,
                URL(string: "https://fastly.jsdelivr.net/gh/NateScarlet/holiday-cn@master/\(year).json")!
            ]

            for url in urls {
                var request = URLRequest(url: url)
                request.timeoutInterval = 10
                do {
                    let (data, response) = try await session.data(for: request)
                    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                        continue
                    }
                    let feed = try JSONDecoder().decode(HolidayFeed.self, from: data)
                    for day in feed.days {
                        daysByDateString[day.date] = day
                    }
                    let cacheFile = cacheDirectory.appendingPathComponent("\(year).json")
                    try? data.write(to: cacheFile, options: .atomic)
                    updatedYears += 1
                    break
                } catch {
                    continue
                }
            }
        }

        if updatedYears > 0 {
            lastSyncDate = Date()
        }
        return updatedYears
    }

    public static func dateKey(for date: Date) -> String {
        defaultDateFormatter.string(from: date)
    }

    public static let beijingCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Asia/Shanghai") ?? .current
        return cal
    }()

    private static func decodeInto(_ map: inout [String: HolidayDay], from data: Data) {
        if let bundle = try? JSONDecoder().decode(HolidayBundleFile.self, from: data) {
            for yearFeed in bundle.years {
                for day in yearFeed.days {
                    map[day.date] = day
                }
            }
            return
        }
        if let feed = try? JSONDecoder().decode(HolidayFeed.self, from: data) {
            for day in feed.days {
                map[day.date] = day
            }
        }
    }

    private static func loadCachedFiles(in dir: URL, into map: inout [String: HolidayDay]) {
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else {
            return
        }
        for url in items where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url) {
                decodeInto(&map, from: data)
            }
        }
    }

    /// Built-in 2025-2027 Chinese statutory holiday & 调休 baseline so core logic works even without resource bundles.
    public static let embeddedFallbackDays: [String: HolidayDay] = {
        let entries: [(String, String, Bool)] = [
            // 2025
            ("2025-01-01", "元旦", true),
            ("2025-01-26", "春节", false),
            ("2025-01-28", "春节", true), ("2025-01-29", "春节", true), ("2025-01-30", "春节", true),
            ("2025-01-31", "春节", true), ("2025-02-01", "春节", true), ("2025-02-02", "春节", true),
            ("2025-02-03", "春节", true), ("2025-02-04", "春节", true),
            ("2025-02-08", "春节", false),
            ("2025-04-04", "清明节", true), ("2025-04-05", "清明节", true), ("2025-04-06", "清明节", true),
            ("2025-04-27", "劳动节", false),
            ("2025-05-01", "劳动节", true), ("2025-05-02", "劳动节", true), ("2025-05-03", "劳动节", true),
            ("2025-05-04", "劳动节", true), ("2025-05-05", "劳动节", true),
            ("2025-05-31", "端午节", true), ("2025-06-01", "端午节", true), ("2025-06-02", "端午节", true),
            ("2025-09-28", "国庆节", false),
            ("2025-10-01", "国庆节", true), ("2025-10-02", "国庆节", true), ("2025-10-03", "国庆节", true),
            ("2025-10-04", "国庆节", true), ("2025-10-05", "国庆节", true), ("2025-10-06", "中秋节", true),
            ("2025-10-07", "国庆节", true), ("2025-10-08", "国庆节", true),
            ("2025-10-11", "国庆节", false),

            // 2026
            ("2026-01-01", "元旦", true), ("2026-01-02", "元旦", true), ("2026-01-03", "元旦", true),
            ("2026-01-04", "元旦", false),
            ("2026-02-14", "春节", false),
            ("2026-02-15", "春节", true), ("2026-02-16", "春节", true), ("2026-02-17", "春节", true),
            ("2026-02-18", "春节", true), ("2026-02-19", "春节", true), ("2026-02-20", "春节", true),
            ("2026-02-21", "春节", true), ("2026-02-22", "春节", true), ("2026-02-23", "春节", true),
            ("2026-02-28", "春节", false),
            ("2026-04-04", "清明节", true), ("2026-04-05", "清明节", true), ("2026-04-06", "清明节", true),
            ("2026-05-01", "劳动节", true), ("2026-05-02", "劳动节", true), ("2026-05-03", "劳动节", true),
            ("2026-05-04", "劳动节", true), ("2026-05-05", "劳动节", true),
            ("2026-05-09", "劳动节", false),
            ("2026-06-19", "端午节", true), ("2026-06-20", "端午节", true), ("2026-06-21", "端午节", true),
            ("2026-09-20", "中秋节", false),
            ("2026-09-25", "中秋节", true), ("2026-09-26", "中秋节", true), ("2026-09-27", "中秋节", true),
            ("2026-10-01", "国庆节", true), ("2026-10-02", "国庆节", true), ("2026-10-03", "国庆节", true),
            ("2026-10-04", "国庆节", true), ("2026-10-05", "国庆节", true), ("2026-10-06", "国庆节", true),
            ("2026-10-07", "国庆节", true),
            ("2026-10-10", "国庆节", false),

            // 2027 (provisional standard statutory holidays, synced automatically when published)
            ("2027-01-01", "元旦", true), ("2027-01-02", "元旦", true), ("2027-01-03", "元旦", true),
            ("2027-02-05", "除夕", true), ("2027-02-06", "春节", true), ("2027-02-07", "春节", true),
            ("2027-02-08", "春节", true), ("2027-02-09", "春节", true), ("2027-02-10", "春节", true),
            ("2027-02-11", "春节", true),
            ("2027-04-05", "清明节", true),
            ("2027-05-01", "劳动节", true), ("2027-05-02", "劳动节", true), ("2027-05-03", "劳动节", true),
            ("2027-06-09", "端午节", true),
            ("2027-09-15", "中秋节", true),
            ("2027-10-01", "国庆节", true), ("2027-10-02", "国庆节", true), ("2027-10-03", "国庆节", true),
            ("2027-10-04", "国庆节", true), ("2027-10-05", "国庆节", true), ("2027-10-06", "国庆节", true),
            ("2027-10-07", "国庆节", true)
        ]

        var result: [String: HolidayDay] = [:]
        for (date, name, isOff) in entries {
            result[date] = HolidayDay(name: name, date: date, isOffDay: isOff)
        }
        return result
    }()
}

/// Calculates natural days and Chinese working days (respecting 调休) between two dates.
public enum DateCalculator {
    public struct DiffResult: Sendable, Equatable {
        public let calendarDays: Int
        public let workingDays: Int
        public let weekendAndHolidayDays: Int
    }

    public static func difference(
        from startDate: Date,
        to endDate: Date,
        holidays: [String: HolidayDay] = HolidayRepository.embeddedFallbackDays
    ) -> DiffResult {
        let cal = HolidayRepository.beijingCalendar
        let s = cal.startOfDay(for: startDate)
        let e = cal.startOfDay(for: endDate)
        let (low, high) = s <= e ? (s, e) : (e, s)

        let totalDays = cal.dateComponents([.day], from: low, to: high).day ?? 0
        var working = 0
        var cursor = low
        while cursor < high {
            let key = HolidayRepository.dateKey(for: cursor)
            if let override = holidays[key] {
                if !override.isOffDay {
                    working += 1
                }
            } else {
                let weekday = cal.component(.weekday, from: cursor)
                if weekday != 1 && weekday != 7 {
                    working += 1
                }
            }
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }

        let sign = s <= e ? 1 : -1
        return DiffResult(
            calendarDays: totalDays * sign,
            workingDays: working * sign,
            weekendAndHolidayDays: (totalDays - working) * sign
        )
    }
}
