import Foundation

public struct HolidayFeed: Codable, Sendable, Equatable {
    public let year: Int
    public let days: [HolidayDay]

    public init(year: Int, days: [HolidayDay]) {
        self.year = year
        self.days = days
    }
}

public struct HolidayDay: Codable, Sendable, Equatable {
    public let name: String
    /// ISO-8601 date string in yyyy-MM-dd format.
    public let date: String
    /// true = statutory rest day (休), false = adjusted workday (班)
    public let isOffDay: Bool

    public init(name: String, date: String, isOffDay: Bool) {
        self.name = name
        self.date = date
        self.isOffDay = isOffDay
    }
}

public struct HolidayBundleFile: Codable, Sendable, Equatable {
    public let updatedAt: String
    public let years: [HolidayFeed]

    public init(updatedAt: String, years: [HolidayFeed]) {
        self.updatedAt = updatedAt
        self.years = years
    }
}

public struct NextHolidayCountdown: Sendable, Equatable {
    public let name: String
    public let startDate: Date
    public let daysRemaining: Int
    public let isOngoing: Bool
}
