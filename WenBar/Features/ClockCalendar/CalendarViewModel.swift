import Foundation
import EventKit
import WenBarCore

struct CalendarGridDay: Identifiable {
    let id: String
    let date: Date
    let dayNumber: Int
    let isCurrentMonth: Bool
    let isToday: Bool
    let isWeekend: Bool
    let subtitle: String
    let holiday: HolidayDay?
    let lunarInfo: LunarDateInfo
    let hasEvents: Bool
}

struct CalendarReminderItem: Identifiable, Sendable {
    let id: String
    let title: String
    let isCompleted: Bool
    let dueDate: Date?
}

struct CalendarEventItem: Identifiable, Sendable {
    let id: String
    let title: String
    let isAllDay: Bool
    let startDate: Date
    let endDate: Date
    let colorRed: Double
    let colorGreen: Double
    let colorBlue: Double
    let colorAlpha: Double
    let isReadOnlySubscription: Bool
    let isSubscriptionType: Bool
}

private final class EventStoreBox: @unchecked Sendable {
    let store = EKEventStore()
}

@MainActor
@Observable
final class CalendarViewModel {
    var displayedMonth: Date = Date()
    var selectedDate: Date = Date()
    var gridDays: [CalendarGridDay] = []
    var nextHoliday: NextHolidayCountdown?
    var isSyncingHolidays: Bool = false
    var holidaySyncStatus: String = "内置离线数据"

    // EventKit & Selected Day Rich Info
    var eventsForSelectedDate: [CalendarEventItem] = []
    var remindersForSelectedDate: [CalendarReminderItem] = []
    var upcomingReminders: [CalendarReminderItem] = []
    var upcomingEvents: [CalendarEventItem] = []
    var selectedDayHoliday: HolidayDay?
    var nextSolarTerm: NextSolarTermInfo?
    var calendarAccessGranted: Bool = false
    var remindersAccessGranted: Bool = false
    var availableWritableCalendars: [EKCalendar] = []

    private let eventStoreBox = EventStoreBox()
    private var eventStore: EKEventStore { eventStoreBox.store }
    private let holidayRepo: HolidayRepository
    private let settingsStore: SettingsStore

    private let gregorianCal: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday first
        return cal
    }()

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        let fallbackURL = Bundle.main.url(forResource: "holidays_fallback", withExtension: "json")
        let fallbackData = fallbackURL.flatMap { try? Data(contentsOf: $0) }
        self.holidayRepo = HolidayRepository(fallbackJSONData: fallbackData)

        refreshAuthorizationStatus(loadCalendars: false)
        Task {
            await refreshWritableCalendarsOffMain()
            await rebuildGrid()
            await refreshNextHoliday()
            await loadSelectedDateItems()
        }
        if settingsStore.settings.autoSyncHolidays {
            Task {
                await syncOnlineHolidays()
            }
        }
    }

    func refreshAuthorizationStatus(loadCalendars: Bool = true) {
        let calStatus = EKEventStore.authorizationStatus(for: .event)
        let remStatus = EKEventStore.authorizationStatus(for: .reminder)
        calendarAccessGranted = (calStatus == .fullAccess)
        remindersAccessGranted = (remStatus == .fullAccess)
        if calendarAccessGranted && loadCalendars {
            availableWritableCalendars = eventStore.calendars(for: .event).filter { $0.allowsContentModifications }
        } else if !calendarAccessGranted {
            availableWritableCalendars = []
        }
    }

    private func refreshWritableCalendarsOffMain() async {
        guard calendarAccessGranted else {
            availableWritableCalendars = []
            return
        }
        let box = eventStoreBox
        let idsAndWritable = await Task.detached {
            box.store.calendars(for: .event)
                .filter { $0.allowsContentModifications }
                .map { $0.calendarIdentifier }
        }.value
        availableWritableCalendars = idsAndWritable.compactMap { eventStore.calendar(withIdentifier: $0) }
    }

    func requestCalendarAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToEvents()
            calendarAccessGranted = granted
            if granted {
                await refreshWritableCalendarsOffMain()
                await loadSelectedDateItems()
                await rebuildGrid()
            }
            return granted
        } catch {
            return false
        }
    }

    func requestRemindersAccess() async -> Bool {
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            remindersAccessGranted = granted
            if granted {
                await loadSelectedDateItems()
            }
            return granted
        } catch {
            return false
        }
    }

    var displayedYear: Int {
        gregorianCal.component(.year, from: displayedMonth)
    }

    var displayedMonthNumber: Int {
        gregorianCal.component(.month, from: displayedMonth)
    }

    func goToPreviousYear() {
        guard let prev = gregorianCal.date(byAdding: .year, value: -1, to: displayedMonth) else { return }
        displayedMonth = prev
        Task { await rebuildGrid() }
    }

    func goToNextYear() {
        guard let next = gregorianCal.date(byAdding: .year, value: 1, to: displayedMonth) else { return }
        displayedMonth = next
        Task { await rebuildGrid() }
    }

    func jumpTo(year: Int, month: Int) {
        var comps = DateComponents()
        comps.year = year
        comps.month = month
        comps.day = 1
        if let target = gregorianCal.date(from: comps) {
            displayedMonth = target
            Task { await rebuildGrid() }
        }
    }

    func goToPreviousMonth() {
        guard let prev = gregorianCal.date(byAdding: .month, value: -1, to: displayedMonth) else { return }
        displayedMonth = prev
        Task { await rebuildGrid() }
    }

    func goToNextMonth() {
        guard let next = gregorianCal.date(byAdding: .month, value: 1, to: displayedMonth) else { return }
        displayedMonth = next
        Task { await rebuildGrid() }
    }

    func goToToday() {
        let now = Date()
        displayedMonth = now
        selectedDate = now
        Task {
            await rebuildGrid()
            await loadSelectedDateItems()
            await refreshNextHoliday()
        }
    }

    func selectDate(_ date: Date) {
        selectedDate = date
        if !gregorianCal.isDate(date, equalTo: displayedMonth, toGranularity: .month) {
            displayedMonth = date
            Task { await rebuildGrid() }
        }
        Task { await loadSelectedDateItems() }
    }

    func syncOnlineHolidays() async {
        guard !isSyncingHolidays else { return }
        isSyncingHolidays = true
        defer { isSyncingHolidays = false }

        let currentYear = gregorianCal.component(.year, from: Date())
        let updated = await holidayRepo.syncYears([currentYear, currentYear + 1])
        if updated > 0 {
            let df = DateFormatter()
            df.dateFormat = "MM-dd HH:mm"
            holidaySyncStatus = "已同步 (\(df.string(from: Date())))"
            await rebuildGrid()
            await refreshNextHoliday()
        } else {
            holidaySyncStatus = "使用离线缓存"
        }
    }

    func refreshNextHoliday() async {
        nextHoliday = await holidayRepo.nextHoliday(from: Date())
        nextSolarTerm = LunarCalendarEngine.nextSolarTerm(after: Date())
    }

    func rebuildGrid() async {
        let monthStart = gregorianCal.date(
            from: gregorianCal.dateComponents([.year, .month], from: displayedMonth)
        ) ?? displayedMonth

        let weekday = gregorianCal.component(.weekday, from: monthStart)
        // Monday = 2 -> offset 0; Sunday = 1 -> offset 6
        let leadingOffset = (weekday - 2 + 7) % 7
        guard let gridStart = gregorianCal.date(byAdding: .day, value: -leadingOffset, to: monthStart) else {
            return
        }

        let eventDatesSet = await fetchEventDaysInMonthRange(start: gridStart, count: 42)
        var days: [CalendarGridDay] = []
        days.reserveCapacity(42)

        for idx in 0..<42 {
            guard let date = gregorianCal.date(byAdding: .day, value: idx, to: gridStart) else { continue }
            let key = HolidayRepository.dateKey(for: date)
            let holiday = await holidayRepo.holiday(forKey: key)
            let lunar = LunarCalendarEngine.info(for: date)
            let subtitle = LunarCalendarEngine.cellSubtitle(for: date, holiday: holiday)
            let wd = gregorianCal.component(.weekday, from: date)

            days.append(
                CalendarGridDay(
                    id: key,
                    date: date,
                    dayNumber: gregorianCal.component(.day, from: date),
                    isCurrentMonth: gregorianCal.isDate(date, equalTo: displayedMonth, toGranularity: .month),
                    isToday: gregorianCal.isDateInToday(date),
                    isWeekend: wd == 1 || wd == 7,
                    subtitle: subtitle,
                    holiday: holiday,
                    lunarInfo: lunar,
                    hasEvents: eventDatesSet.contains(key)
                )
            )
        }

        gridDays = days
    }

    func loadSelectedDateItems() async {
        refreshAuthorizationStatus()
        let now = Date()
        let start = gregorianCal.startOfDay(for: selectedDate)
        guard let end = gregorianCal.date(byAdding: .day, value: 1, to: start) else { return }

        let selectedKey = HolidayRepository.dateKey(for: selectedDate)
        selectedDayHoliday = await holidayRepo.holiday(forKey: selectedKey)
        nextSolarTerm = LunarCalendarEngine.nextSolarTerm(after: now)

        if calendarAccessGranted {
            let futureEnd = gregorianCal.date(byAdding: .day, value: 60, to: now) ?? end
            let queryStart = min(start, gregorianCal.startOfDay(for: now))
            let queryEnd = max(end, futureEnd)
            let rawAll = await Self.fetchEventsOffMain(using: eventStoreBox, from: queryStart, to: queryEnd)

            let rawForSelected = rawAll.filter { ev in
                ev.endDate > start && ev.startDate < end
            }
            eventsForSelectedDate = filterAndDeduplicateEvents(rawForSelected, for: selectedDate, holiday: selectedDayHoliday)

            let todayStart = gregorianCal.startOfDay(for: now)
            let rawUpcoming = rawAll.filter { ev in
                ev.endDate >= todayStart && ev.startDate <= futureEnd
            }
            let dedupUpcoming = filterAndDeduplicateUpcomingEvents(rawUpcoming)
            upcomingEvents = dedupUpcoming.filter { ev in
                if ev.isAllDay {
                    return gregorianCal.startOfDay(for: ev.startDate) >= todayStart
                }
                return ev.endDate >= now
            }
        } else {
            eventsForSelectedDate = []
            upcomingEvents = []
        }

        if remindersAccessGranted {
            let fetched = await Self.fetchRemindersOffMain(using: eventStoreBox)
            remindersForSelectedDate = fetched
                .filter { reminder in
                    guard let due = reminder.dueDate else { return false }
                    return gregorianCal.isDate(due, inSameDayAs: start)
                }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }

            let todayStart = gregorianCal.startOfDay(for: now)
            let futureCutoff = gregorianCal.date(byAdding: .day, value: 90, to: todayStart) ?? .distantFuture
            upcomingReminders = fetched
                .filter { !$0.isCompleted }
                .filter { rem in
                    guard let due = rem.dueDate else { return false }
                    return due >= todayStart && due <= futureCutoff
                }
                .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
        } else {
            remindersForSelectedDate = []
            upcomingReminders = []
        }
    }

    private nonisolated static func fetchRemindersOffMain(using box: EventStoreBox) async -> [CalendarReminderItem] {
        await withCheckedContinuation { continuation in
            let predicate = box.store.predicateForReminders(in: nil)
            box.store.fetchReminders(matching: predicate) { reminders in
                let mapped = (reminders ?? []).map { rem in
                    CalendarReminderItem(
                        id: rem.calendarItemIdentifier,
                        title: rem.title ?? "(待办)",
                        isCompleted: rem.isCompleted,
                        dueDate: rem.dueDateComponents?.date
                    )
                }
                continuation.resume(returning: mapped)
            }
        }
    }

    func toggleReminder(_ item: CalendarReminderItem) async {
        guard remindersAccessGranted,
              let reminder = eventStore.calendarItem(withIdentifier: item.id) as? EKReminder else { return }
        reminder.isCompleted.toggle()
        try? eventStore.save(reminder, commit: true)
        await loadSelectedDateItems()
    }

    func createEvent(
        title: String,
        isAllDay: Bool,
        startDate: Date,
        endDate: Date,
        calendarIdentifier: String?,
        alarmMinutesBefore: Int?
    ) async throws {
        if !calendarAccessGranted {
            let granted = await requestCalendarAccess()
            if !granted {
                throw NSError(domain: "WenBarCalendar", code: 403, userInfo: [NSLocalizedDescriptionKey: "未授予系统日历权限"])
            }
        }

        let event = EKEvent(eventStore: eventStore)
        event.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        event.isAllDay = isAllDay
        event.startDate = startDate
        event.endDate = max(endDate, startDate.addingTimeInterval(isAllDay ? 0 : 1800))

        if let calID = calendarIdentifier, let cal = eventStore.calendar(withIdentifier: calID) {
            event.calendar = cal
        } else {
            event.calendar = eventStore.defaultCalendarForNewEvents
        }

        if let mins = alarmMinutesBefore, mins >= 0 {
            event.addAlarm(EKAlarm(relativeOffset: TimeInterval(-mins * 60)))
        }

        try eventStore.save(event, span: .thisEvent, commit: true)
        await loadSelectedDateItems()
        await rebuildGrid()
    }

    func createReminder(title: String, dueDate: Date, notes: String?) async throws {
        if !remindersAccessGranted {
            let granted = await requestRemindersAccess()
            if !granted {
                throw NSError(domain: "WenBarCalendar", code: 403, userInfo: [NSLocalizedDescriptionKey: "未授予系统提醒事项权限"])
            }
        }

        let reminder = EKReminder(eventStore: eventStore)
        reminder.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        reminder.calendar = eventStore.defaultCalendarForNewReminders()
        reminder.dueDateComponents = gregorianCal.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
        if let notes, !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            reminder.notes = notes
        }
        try eventStore.save(reminder, commit: true)
        await loadSelectedDateItems()
    }

    var selectedDayLunar: LunarDateInfo {
        LunarCalendarEngine.info(for: selectedDate)
    }

    var selectedDayAlmanac: ChineseAlmanacInfo {
        ChineseAlmanacEngine.info(for: selectedDate)
    }

    var selectedDayRelativeDescription: String {
        let today = gregorianCal.startOfDay(for: Date())
        let target = gregorianCal.startOfDay(for: selectedDate)
        let days = gregorianCal.dateComponents([.day], from: today, to: target).day ?? 0
        let week = gregorianCal.component(.weekOfYear, from: selectedDate)
        let rel: String
        switch days {
        case 0: rel = "今天"
        case 1: rel = "明天"
        case -1: rel = "昨天"
        case let d where d > 1: rel = "\(d)天后"
        default: rel = "\(-days)天前"
        }
        return "\(rel) · 第\(week)周"
    }

    var selectedDayGregorianTitle: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy年M月d日 EEEE"
        return df.string(from: selectedDate)
    }

    var selectedDayFestivalsAndTerms: [String] {
        var badges: [String] = []
        let lunar = selectedDayLunar
        if let h = selectedDayHoliday {
            badges.append(h.isOffDay ? "\(h.name) · 休" : "\(h.name) · 调休上班")
        }
        if let term = lunar.solarTerm {
            badges.append("节气 · \(term)")
        }
        if let trad = lunar.traditionalFestival, !badges.contains(where: { $0.contains(trad) }) {
            badges.append(trad)
        }
        if let greg = lunar.gregorianFestival, !badges.contains(where: { $0.contains(greg) }) {
            badges.append(greg)
        }
        return badges
    }

    func calculateDateDiff(from: Date, to: Date) async -> DateCalculator.DiffResult {
        let all = await holidayRepo.allHolidays()
        let map = Dictionary(uniqueKeysWithValues: all.map { ($0.date, $0) })
        return DateCalculator.difference(from: from, to: to, holidays: map)
    }

    var monthTitleString: String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "yyyy年 M月"
        return df.string(from: displayedMonth)
    }

    var selectedDayFullSummary: String {
        let lunar = LunarCalendarEngine.info(for: selectedDate)
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M月d日 EEEE"
        var parts = [df.string(from: selectedDate), lunar.fullLunarText]
        if let term = lunar.solarTerm { parts.append(term) }
        if let fest = lunar.traditionalFestival { parts.append(fest) }
        return parts.joined(separator: " · ")
    }

    private func fetchEventDaysInMonthRange(start: Date, count: Int) async -> Set<String> {
        guard calendarAccessGranted,
              let end = gregorianCal.date(byAdding: .day, value: count, to: start) else {
            return []
        }
        let events = await Self.fetchEventsOffMain(using: eventStoreBox, from: start, to: end)
        var keys = Set<String>()
        for ev in events {
            if isRedundantSubscribedHolidayEvent(ev) { continue }
            keys.insert(HolidayRepository.dateKey(for: ev.startDate))
        }
        return keys
    }

    private nonisolated static func fetchEventsOffMain(using box: EventStoreBox, from start: Date, to end: Date) async -> [CalendarEventItem] {
        await Task.detached {
            let predicate = box.store.predicateForEvents(withStart: start, end: end, calendars: nil)
            return box.store.events(matching: predicate)
                .sorted { $0.startDate < $1.startDate }
                .map { ev in
                    let rgba = Self.extractRGBAComponents(from: ev.calendar.cgColor)
                    return CalendarEventItem(
                        id: ev.eventIdentifier ?? UUID().uuidString,
                        title: ev.title ?? "(无标题)",
                        isAllDay: ev.isAllDay,
                        startDate: ev.startDate,
                        endDate: ev.endDate,
                        colorRed: rgba.r,
                        colorGreen: rgba.g,
                        colorBlue: rgba.b,
                        colorAlpha: rgba.a,
                        isReadOnlySubscription: !ev.calendar.allowsContentModifications || ev.calendar.type == .subscription,
                        isSubscriptionType: ev.calendar.type == .subscription
                    )
                }
        }.value
    }

    private nonisolated static func extractRGBAComponents(from cgColor: CGColor?) -> (r: Double, g: Double, b: Double, a: Double) {
        guard let cgColor,
              let rgb = cgColor.converted(to: CGColorSpaceCreateDeviceRGB(), intent: .defaultIntent, options: nil),
              let comps = rgb.components, comps.count >= 3 else {
            return (0.2, 0.5, 1.0, 1.0)
        }
        let alpha = comps.count >= 4 ? comps[3] : 1.0
        return (Double(comps[0]), Double(comps[1]), Double(comps[2]), Double(alpha))
    }

    private func isRedundantSubscribedHolidayEvent(_ event: CalendarEventItem) -> Bool {
        guard event.isReadOnlySubscription && event.isAllDay else { return false }

        let title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return false }

        // Skip Apple/subscribed holiday & solar-term calendars whose entries WenBar already renders natively
        let lunar = LunarCalendarEngine.info(for: event.startDate)
        var knownNames = [
            lunar.solarTerm,
            lunar.traditionalFestival,
            lunar.gregorianFestival
        ].compactMap { $0 }
        knownNames.append(contentsOf: lunar.extraFestivals.flatMap { [$0.name, $0.shortName] })
        if knownNames.contains(where: { title == $0 || title.contains($0) || $0.contains(title) }) {
            return true
        }

        let solarTerms: Set<String> = [
            "小寒", "大寒", "立春", "雨水", "惊蛰", "春分",
            "清明", "谷雨", "立夏", "小满", "芒种", "夏至",
            "小暑", "大暑", "立秋", "处暑", "白露", "秋分",
            "寒露", "霜降", "立冬", "小雪", "大雪", "冬至"
        ]
        if solarTerms.contains(title) {
            return true
        }
        if event.isSubscriptionType && (title.contains("假期") || title.contains("放假") || title.contains("上班") || title.contains("节")) {
            return true
        }
        return false
    }

    private func filterAndDeduplicateEvents(_ events: [CalendarEventItem], for date: Date, holiday: HolidayDay?) -> [CalendarEventItem] {
        var seen = Set<String>()
        var result: [CalendarEventItem] = []
        for ev in events {
            if isRedundantSubscribedHolidayEvent(ev) { continue }
            if let h = holiday, ev.isReadOnlySubscription {
                let t = ev.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if t.contains(h.name) { continue }
            }
            let key = "\(ev.title)|\(ev.isAllDay)|\(ev.startDate.timeIntervalSince1970)|\(ev.endDate.timeIntervalSince1970)"
            if seen.insert(key).inserted {
                result.append(ev)
            }
        }
        return result
    }

    private func filterAndDeduplicateUpcomingEvents(_ events: [CalendarEventItem]) -> [CalendarEventItem] {
        var seen = Set<String>()
        var result: [CalendarEventItem] = []
        for ev in events {
            if isRedundantSubscribedHolidayEvent(ev) { continue }
            let key = "\(ev.title)|\(ev.isAllDay)|\(ev.startDate.timeIntervalSince1970)"
            if seen.insert(key).inserted {
                result.append(ev)
            }
        }
        return result
    }
}
