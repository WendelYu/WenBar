import SwiftUI
import EventKit
import WenBarCore

struct DayDetailView: View {
    @Bindable var calendarVM: CalendarViewModel
    @State private var showingNewEventSheet = false
    @State private var showingNewReminderSheet = false
    @State private var editingCustomReminder: CustomReminder?
    @State private var isAlmanacExpanded = false

    var body: some View {
        let lunar = calendarVM.selectedDayLunar
        let almanac = calendarVM.selectedDayAlmanac

        VStack(alignment: .leading, spacing: 10) {
            // Card 1: Lunar & GanZhi Hero Card
            heroLunarCard(lunar: lunar, almanac: almanac)

            // Card 2: Multi-Row Highlights, Reminders & Countdowns Card
            highlightsAndRemindersCard(lunar: lunar)

            // Card 3: Compact Chinese Almanac Card
            almanacCard(almanac: almanac)
        }
        .sheet(isPresented: $showingNewEventSheet) {
            QuickNewEventSheet(calendarVM: calendarVM)
        }
        .sheet(isPresented: $showingNewReminderSheet) {
            QuickNewReminderSheet(calendarVM: calendarVM)
        }
        .sheet(item: $editingCustomReminder) { reminder in
            QuickNewReminderSheet(calendarVM: calendarVM, editingReminder: reminder)
        }
    }

    // MARK: - Card 1: Hero Lunar Card
    private func heroLunarCard(lunar: LunarDateInfo, almanac: ChineseAlmanacInfo) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(lunar.monthName)\(lunar.dayName)")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(calendarVM.selectedDayRelativeDescription)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 6) {
                    Text("\(almanac.yearPillar)\(lunar.zodiac)年 \(almanac.monthPillar)月 \(almanac.dayPillar)日")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let seasonal = lunar.seasonalLabel {
                        Text(seasonal)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(shortGregorianTitle(calendarVM.selectedDate))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                Menu {
                    Button {
                        showingNewEventSheet = true
                    } label: {
                        Label("新建日历日程…", systemImage: "calendar.badge.plus")
                    }
                    Button {
                        showingNewReminderSheet = true
                    } label: {
                        Label("新建提醒事项…", systemImage: "checklist")
                    }
                } label: {
                    Label("新建", systemImage: "plus")
                        .font(.caption2.weight(.medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.12), in: Capsule())
                        .foregroundStyle(Color.accentColor)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    // MARK: - Card 2: Multi-Row Highlights, Reminders & Countdowns
    private func highlightsAndRemindersCard(lunar: LunarDateInfo) -> some View {
        let now = max(Date(), calendarVM.currentDayReference)
        let selectedTags = selectedDayRowItems(lunar: lunar)
        let isViewingToday = Calendar.current.isDateInToday(calendarVM.selectedDate)

        // Upcoming custom reminders excluding occurrences already shown for selectedDate
        let selectedCustomIDs = Set(calendarVM.customRemindersForSelectedDate.map(\.id))
        let extraUpcomingCustom = calendarVM.upcomingCustomReminders
            .filter { !selectedCustomIDs.contains($0.id) }
            .prefix(4)

        // Upcoming system reminders excluding items already shown for selectedDate
        let selectedRemIDs = Set(calendarVM.remindersForSelectedDate.map(\.id))
        let extraUpcomingReminders = calendarVM.upcomingReminders
            .filter { !selectedRemIDs.contains($0.id) }
            .prefix(3)

        let selectedEventIDs = Set(calendarVM.eventsForSelectedDate.map(\.id))
        let extraUpcomingEvents = calendarVM.upcomingEvents
            .filter { !selectedEventIDs.contains($0.id) }
            .prefix(2)

        return VStack(alignment: .leading, spacing: 0) {
            if !calendarVM.calendarAccessGranted && !calendarVM.remindersAccessGranted {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("授权系统日历与提醒事项可同步日程（本地提醒免授权）")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("授权") {
                        Task {
                            _ = await calendarVM.requestCalendarAccess()
                            _ = await calendarVM.requestRemindersAccess()
                        }
                    }
                    .controlSize(.mini)
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                Divider().opacity(0.5)
            }

            // 1. Selected day's festivals / solar term / holiday rows
            ForEach(selectedTags, id: \.title) { tag in
                countdownRow(
                    accentColor: tag.color,
                    title: tag.title,
                    subtitle: tag.subtitle,
                    rightNumber: isViewingToday ? "今天" : relativeNumber(to: calendarVM.selectedDate),
                    rightUnit: isViewingToday ? "" : "天"
                )
                Divider().opacity(0.45)
            }

            // 2. Selected day's WenBar custom reminders (Gregorian / Lunar / Multi-Alert)
            ForEach(calendarVM.customRemindersForSelectedDate) { occ in
                customReminderRow(occ, now: now, isUpcomingPreview: false)
                Divider().opacity(0.45)
            }

            // 3. Selected day's user system reminders (checkable + live countdown!)
            ForEach(calendarVM.remindersForSelectedDate) { rem in
                reminderRow(rem, now: now)
                Divider().opacity(0.45)
            }

            // 4. Selected day's deduplicated user events
            ForEach(calendarVM.eventsForSelectedDate) { event in
                eventRow(event, now: now)
                Divider().opacity(0.45)
            }

            // 5. Upcoming WenBar custom reminders
            ForEach(Array(extraUpcomingCustom)) { occ in
                customReminderRow(occ, now: now, isUpcomingPreview: true)
                Divider().opacity(0.45)
            }

            // 6. Upcoming system reminders
            ForEach(Array(extraUpcomingReminders)) { rem in
                reminderRow(rem, now: now, tagPrefix: "系统待办")
                Divider().opacity(0.45)
            }

            // 7. Upcoming events
            ForEach(Array(extraUpcomingEvents)) { event in
                eventRow(event, now: now, tagPrefix: "日程")
                Divider().opacity(0.45)
            }

            // 6. Next Solar Term countdown (e.g. 大雪 · 十月廿九 | 周一 · 11 天)
            if let term = calendarVM.nextSolarTerm, term.name != lunar.solarTerm {
                countdownRow(
                    accentColor: .teal,
                    title: term.name,
                    subtitle: "\(term.lunarText) | \(term.weekdayCN)",
                    rightNumber: "\(term.daysRemaining)",
                    rightUnit: "天"
                )
                if calendarVM.nextHoliday != nil {
                    Divider().opacity(0.45)
                }
            }

            // 7. Next Statutory Holiday countdown (e.g. 元旦 · 1月1日 | 周五 · 36 天)
            if let nextHol = calendarVM.nextHoliday {
                countdownRow(
                    accentColor: .orange,
                    title: nextHol.isOngoing ? "\(nextHol.name)假期中" : nextHol.name,
                    subtitle: "\(monthDayAndWeekday(nextHol.startDate)) · 法定假期",
                    rightNumber: nextHol.isOngoing ? "假期中" : "\(nextHol.daysRemaining)",
                    rightUnit: nextHol.isOngoing ? "" : "天"
                )
            }
        }
        .background(cardBackground)
    }

    // MARK: - Card 3: Almanac (老黄历)
    private func almanacCard(almanac: ChineseAlmanacInfo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(almanac.dayTypeLabel)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(almanac.isAuspiciousDay ? Color.green : Color.secondary, in: Capsule())

                Text("\(almanac.twelveSpirit)日 · \(almanac.jianChu)执 · \(almanac.chongSha) · \(almanac.dayNaYin)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer()

                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        isAlmanacExpanded.toggle()
                    }
                } label: {
                    Image(systemName: isAlmanacExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help(isAlmanacExpanded ? "收起彭祖百忌" : "展开彭祖百忌")
            }

            HStack(alignment: .top, spacing: 6) {
                Text("宜")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.green, in: RoundedRectangle(cornerRadius: 4))
                Text(almanac.yi.joined(separator: "、"))
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(alignment: .top, spacing: 6) {
                Text("忌")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Color.red.opacity(0.85), in: RoundedRectangle(cornerRadius: 4))
                Text(almanac.ji.joined(separator: "、"))
                    .font(.caption2)
                    .foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if isAlmanacExpanded {
                Divider().opacity(0.5)
                Text("彭祖百忌：\(almanac.pengZu)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(cardBackground)
    }

    // MARK: - Row Components
    private func countdownRow(
        accentColor: Color,
        title: String,
        subtitle: String,
        rightNumber: String,
        rightUnit: String,
        isOverdue: Bool = false
    ) -> some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentColor)
                .frame(width: 3, height: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(rightNumber)
                    .font(.system(size: rightUnit.isEmpty ? 12 : 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(isOverdue ? Color.red.opacity(0.85) : Color.primary)
                if !rightUnit.isEmpty {
                    Text(rightUnit)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func customReminderRow(_ occ: ReminderOccurrence, now: Date, isUpcomingPreview: Bool) -> some View {
        let countdown = CountdownFormatter.describe(from: now, to: occ.targetDate, isAllDay: false)
        let cal = Calendar.current
        let dayDiff = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: occ.targetDate)).day ?? 0
        let isAdvanceAlertToday = isUpcomingPreview && dayDiff > 0 && occ.reminder.advanceDays.contains(dayDiff)
        let lunar = LunarCalendarEngine.info(for: occ.targetDate)
        let subtitle: String
        if isUpcomingPreview {
            let dateStr = dateAndTimeText(occ.targetDate)
            let advanceStr = CustomReminderEngine.advanceDaysSummary(for: occ.reminder.advanceDays)
            subtitle = "\(dateStr) · 农历\(lunar.monthName)\(lunar.dayName) · \(advanceStr)"
        } else {
            let advanceStr = CustomReminderEngine.advanceDaysSummary(for: occ.reminder.advanceDays)
            let timeStr = String(format: "%02d:%02d", occ.reminder.hour, occ.reminder.minute)
            subtitle = "\(occ.reminder.calendarType.displayName)\(occ.reminder.repeatRule == .once ? "" : "·\(occ.reminder.repeatRule.displayName)") · \(timeStr) · \(advanceStr)"
        }

        return HStack(spacing: 10) {
            Button {
                Task { await calendarVM.toggleCustomReminderOccurrence(occ) }
            } label: {
                Image(systemName: occ.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(occ.isCompleted ? Color.green : (occ.reminder.calendarType == .lunar ? Color.orange : Color.accentColor))
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(occ.reminder.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .strikethrough(occ.isCompleted)
                        .foregroundStyle(occ.isCompleted ? .secondary : .primary)
                        .lineLimit(1)

                    if occ.reminder.calendarType == .lunar {
                        Text("农历")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.12), in: Capsule())
                    }
                    if isAdvanceAlertToday {
                        Text("今日预提醒")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                    }
                }
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !occ.isCompleted {
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(countdown.number)
                        .font(.system(size: countdown.unit.isEmpty ? 12 : 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(countdown.isOverdue ? Color.red.opacity(0.85) : (isAdvanceAlertToday ? Color.orange : Color.accentColor))
                    if !countdown.unit.isEmpty {
                        Text(countdown.unit)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                editingCustomReminder = occ.reminder
            } label: {
                Image(systemName: "pencil")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("编辑提醒事项")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())
        .contextMenu {
            Button("编辑提醒…") {
                editingCustomReminder = occ.reminder
            }
            Button(occ.isCompleted ? "标为未完成" : "标为已完成") {
                Task { await calendarVM.toggleCustomReminderOccurrence(occ) }
            }
            Divider()
            Button("删除提醒", role: .destructive) {
                Task { await calendarVM.deleteCustomReminder(id: occ.reminder.id) }
            }
        }
    }

    private func reminderRow(_ rem: CalendarReminderItem, now: Date, tagPrefix: String? = nil) -> some View {
        let countdown = rem.dueDate.map { CountdownFormatter.describe(from: now, to: $0, isAllDay: false) }
        let dueText = rem.dueDate.map { dateAndTimeText($0) } ?? "无截止时间"
        let subtitle = tagPrefix != nil ? "\(tagPrefix!) · \(dueText)" : dueText

        return Button {
            Task { await calendarVM.toggleReminder(rem) }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: rem.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(rem.isCompleted ? Color.green : Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(rem.title)
                        .font(.system(size: 13.5, weight: .medium))
                        .strikethrough(rem.isCompleted)
                        .foregroundStyle(rem.isCompleted ? .secondary : .primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if !rem.isCompleted, let countdown {
                    HStack(alignment: .firstTextBaseline, spacing: 2) {
                        Text(countdown.number)
                            .font(.system(size: countdown.unit.isEmpty ? 12 : 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(countdown.isOverdue ? Color.red.opacity(0.85) : Color.accentColor)
                        if !countdown.unit.isEmpty {
                            Text(countdown.unit)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func eventRow(_ event: CalendarEventItem, now: Date, tagPrefix: String? = nil) -> some View {
        let start = event.startDate
        let countdown = CountdownFormatter.describe(from: now, to: start, isAllDay: event.isAllDay)
        let timeStr = event.isAllDay ? "\(monthDayAndWeekday(start)) · 全天" : dateAndTimeText(start)
        let subtitle = tagPrefix != nil ? "\(tagPrefix!) · \(timeStr)" : timeStr

        return countdownRow(
            accentColor: Color(.sRGB, red: event.colorRed, green: event.colorGreen, blue: event.colorBlue, opacity: event.colorAlpha),
            title: event.title,
            subtitle: subtitle,
            rightNumber: countdown.number,
            rightUnit: countdown.unit,
            isOverdue: countdown.isOverdue
        )
    }

    // MARK: - Helpers
    private struct TagRowModel {
        let title: String
        let subtitle: String
        let color: Color
    }

    private func selectedDayRowItems(lunar: LunarDateInfo) -> [TagRowModel] {
        let dateSub = monthDayAndWeekday(calendarVM.selectedDate)
        var items: [TagRowModel] = []
        var seenTitles = Set<String>()

        if let h = calendarVM.selectedDayHoliday {
            let label = h.isOffDay ? "\(h.name)（休）" : "\(h.name)（调休上班）"
            items.append(TagRowModel(title: label, subtitle: "\(dateSub) · 法定安排", color: h.isOffDay ? .green : .orange))
            seenTitles.insert(h.name)
        }
        if let term = lunar.solarTerm, !seenTitles.contains(term) {
            items.append(TagRowModel(title: "节气 · \(term)", subtitle: "\(dateSub) · 二十四节气", color: .teal))
            seenTitles.insert(term)
        }
        for tag in lunar.extraFestivals where !seenTitles.contains(tag.name) {
            let subLabel: String
            let color: Color
            switch tag.category {
            case .traditional:
                subLabel = "\(dateSub) · 传统节日"
                color = .accentColor
            case .gregorian:
                subLabel = "\(dateSub) · 节日"
                color = .accentColor
            case .commemorative:
                subLabel = "\(dateSub) · 纪念日"
                color = .indigo
            case .seasonal:
                subLabel = "\(dateSub) · 伏九时令"
                color = .orange
            }
            items.append(TagRowModel(title: tag.name, subtitle: subLabel, color: color))
            seenTitles.insert(tag.name)
        }
        return items
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }

    private func shortGregorianTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M月d日 EEEE"
        return df.string(from: date)
    }

    private func monthDayAndWeekday(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M月d日 | EEE"
        return df.string(from: date)
    }

    private func dateAndTimeText(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "M月d日 HH:mm | EEE"
        return df.string(from: date)
    }

    private func relativeNumber(to date: Date) -> String {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let target = cal.startOfDay(for: date)
        let days = cal.dateComponents([.day], from: today, to: target).day ?? 0
        if days > 0 { return "\(days)" }
        return "已过\(-days)"
    }
}

private struct QuickNewEventSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var calendarVM: CalendarViewModel

    @State private var title: String = ""
    @State private var isAllDay: Bool = false
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var selectedCalendarID: String = ""
    @State private var alarmMinutes: Int = 15
    @State private var errorMessage: String?

    init(calendarVM: CalendarViewModel) {
        self.calendarVM = calendarVM
        let cal = Calendar.current
        let base = cal.date(bySettingHour: 9, minute: 0, second: 0, of: calendarVM.selectedDate) ?? calendarVM.selectedDate
        _startDate = State(initialValue: base)
        _endDate = State(initialValue: base.addingTimeInterval(3600))
        _selectedCalendarID = State(initialValue: calendarVM.availableWritableCalendars.first?.calendarIdentifier ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建日历日程")
                .font(.headline)

            TextField("日程标题", text: $title)
                .textFieldStyle(.roundedBorder)

            Toggle("全天日程", isOn: $isAllDay)

            DatePicker("开始时间", selection: $startDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])
            DatePicker("结束时间", selection: $endDate, displayedComponents: isAllDay ? [.date] : [.date, .hourAndMinute])

            if !calendarVM.availableWritableCalendars.isEmpty {
                Picker("目标日历", selection: $selectedCalendarID) {
                    ForEach(calendarVM.availableWritableCalendars, id: \.calendarIdentifier) { cal in
                        Text(cal.title).tag(cal.calendarIdentifier)
                    }
                }
            }

            Picker("提前提醒", selection: $alarmMinutes) {
                Text("无").tag(-1)
                Text("准时").tag(0)
                Text("提前 15 分钟").tag(15)
                Text("提前 30 分钟").tag(30)
                Text("提前 1 小时").tag(60)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    Task {
                        do {
                            try await calendarVM.createEvent(
                                title: title,
                                isAllDay: isAllDay,
                                startDate: startDate,
                                endDate: endDate,
                                calendarIdentifier: selectedCalendarID.isEmpty ? nil : selectedCalendarID,
                                alarmMinutesBefore: alarmMinutes >= 0 ? alarmMinutes : nil
                            )
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 340)
    }
}

private struct QuickNewReminderSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var calendarVM: CalendarViewModel
    let editingReminder: CustomReminder?

    @State private var title: String
    @State private var calendarType: ReminderCalendarType
    @State private var gregorianDate: Date
    @State private var lunarYear: Int
    @State private var lunarMonth: Int
    @State private var lunarDay: Int
    @State private var isLeapMonth: Bool
    @State private var reminderTime: Date
    @State private var repeatRule: ReminderRepeatRule
    @State private var selectedAdvanceDays: Set<Int>
    @State private var customAdvanceInput: String = ""
    @State private var notes: String
    @State private var alsoSyncToSystem: Bool = false
    @State private var errorMessage: String?

    init(calendarVM: CalendarViewModel, editingReminder: CustomReminder? = nil) {
        self.calendarVM = calendarVM
        self.editingReminder = editingReminder

        let cal = Calendar.current
        if let editing = editingReminder {
            _title = State(initialValue: editing.title)
            _calendarType = State(initialValue: editing.calendarType)
            let gDate = cal.date(from: DateComponents(
                year: editing.gregorianYear,
                month: editing.gregorianMonth,
                day: editing.gregorianDay,
                hour: editing.hour,
                minute: editing.minute
            )) ?? calendarVM.selectedDate
            _gregorianDate = State(initialValue: gDate)
            _lunarYear = State(initialValue: editing.lunarYear)
            _lunarMonth = State(initialValue: editing.lunarMonth)
            _lunarDay = State(initialValue: editing.lunarDay)
            _isLeapMonth = State(initialValue: editing.isLeapMonth)
            let tDate = cal.date(bySettingHour: editing.hour, minute: editing.minute, second: 0, of: gDate) ?? gDate
            _reminderTime = State(initialValue: tDate)
            _repeatRule = State(initialValue: editing.repeatRule)
            _selectedAdvanceDays = State(initialValue: Set(editing.advanceDays))
            _notes = State(initialValue: editing.notes)
        } else {
            let baseDate = calendarVM.selectedDate
            let gComps = cal.dateComponents([.year, .month, .day], from: baseDate)
            let lunarInfo = LunarCalendarEngine.info(for: baseDate)
            let defaultTime = cal.date(bySettingHour: 9, minute: 0, second: 0, of: baseDate) ?? baseDate

            _title = State(initialValue: "")
            _calendarType = State(initialValue: .gregorian)
            _gregorianDate = State(initialValue: baseDate)
            _lunarYear = State(initialValue: lunarInfo.lunarYear)
            _lunarMonth = State(initialValue: lunarInfo.lunarMonth)
            _lunarDay = State(initialValue: lunarInfo.lunarDay)
            _isLeapMonth = State(initialValue: lunarInfo.isLeapMonth)
            _reminderTime = State(initialValue: defaultTime)
            _repeatRule = State(initialValue: .once)
            _selectedAdvanceDays = State(initialValue: [0])
            _notes = State(initialValue: "")
            _ = gComps
        }
    }

    private var availableRepeatRules: [ReminderRepeatRule] {
        ReminderRepeatRule.supportedCases(for: calendarType)
    }

    private var customOnlyAdvanceDays: [Int] {
        let presets = Set(CustomReminderEngine.defaultPresetAdvanceDays)
        return selectedAdvanceDays.filter { !presets.contains($0) }.sorted(by: >)
    }

    private var draftReminder: CustomReminder {
        let cal = Calendar.current
        let gComps = cal.dateComponents([.year, .month, .day], from: gregorianDate)
        let tComps = cal.dateComponents([.hour, .minute], from: reminderTime)
        let normalizedDays = CustomReminderEngine.normalizedAdvanceDays(Array(selectedAdvanceDays))

        return CustomReminder(
            id: editingReminder?.id ?? UUID(),
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            calendarType: calendarType,
            gregorianYear: gComps.year ?? 2026,
            gregorianMonth: gComps.month ?? 1,
            gregorianDay: gComps.day ?? 1,
            lunarYear: lunarYear,
            lunarMonth: lunarMonth,
            lunarDay: lunarDay,
            isLeapMonth: isLeapMonth,
            hour: tComps.hour ?? 9,
            minute: tComps.minute ?? 0,
            repeatRule: repeatRule,
            advanceDays: normalizedDays,
            isEnabled: true,
            completedOccurrenceKeys: editingReminder?.completedOccurrenceKeys ?? [],
            createdAt: editingReminder?.createdAt ?? Date()
        )
    }

    private var lunarPreviewText: String {
        let effectiveYear: Int
        if repeatRule == .once {
            effectiveYear = lunarYear
        } else if let next = CustomReminderEngine.nextOccurrence(of: draftReminder, after: Date()) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "zh_CN")
            df.dateFormat = "yyyy年M月d日 EEE"
            return "下次对应公历：\(df.string(from: next.targetDate))"
        } else {
            effectiveYear = Calendar.current.component(.year, from: Date())
        }

        if let gDate = CustomReminderEngine.gregorianDate(
            forLunarYear: effectiveYear,
            month: lunarMonth,
            day: lunarDay,
            isLeapMonth: isLeapMonth,
            timeZone: .current
        ) {
            let df = DateFormatter()
            df.locale = Locale(identifier: "zh_CN")
            df.dateFormat = "yyyy年M月d日 EEE"
            return "对应公历：\(df.string(from: gDate))"
        }
        return "未能匹配到对应公历日期"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(editingReminder == nil ? "新建提醒事项" : "编辑提醒事项")
                .font(.headline)

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("例如：妈妈生日、还信用卡、体检", text: $title)
                        .textFieldStyle(.roundedBorder)

                    Picker("历法类型", selection: $calendarType) {
                        ForEach(ReminderCalendarType.allCases) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: calendarType) { _, newType in
                        let supported = ReminderRepeatRule.supportedCases(for: newType)
                        if !supported.contains(repeatRule) {
                            repeatRule = .yearly
                        }
                    }

                    if calendarType == .gregorian {
                        DatePicker("目标日期", selection: $gregorianDate, displayedComponents: [.date])
                    } else {
                        lunarDatePickerSection
                    }

                    HStack {
                        DatePicker("提醒时间", selection: $reminderTime, displayedComponents: [.hourAndMinute])
                        Spacer()
                        Picker("重复", selection: $repeatRule) {
                            ForEach(availableRepeatRules) { rule in
                                Text(rule.displayName).tag(rule)
                            }
                        }
                        .frame(width: 145)
                    }

                    advanceDaysSection

                    TextField("备注（可选）", text: $notes)
                        .textFieldStyle(.roundedBorder)

                    if editingReminder == nil && calendarVM.remindersAccessGranted {
                        Toggle("同时写入系统「提醒事项」（仅最近一次）", isOn: $alsoSyncToSystem)
                            .toggleStyle(WenBarSwitchToggleStyle())
                            .font(.caption)
                    }

                    Text("保存在 WenBar 本地（支持农历与多次提醒，更新软件无需重新授权）。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
            .frame(maxHeight: 420)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            HStack {
                if let editingReminder {
                    Button("删除", role: .destructive) {
                        Task {
                            await calendarVM.deleteCustomReminder(id: editingReminder.id)
                            dismiss()
                        }
                    }
                }
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") {
                    let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !cleanTitle.isEmpty else {
                        errorMessage = "请输入提醒标题"
                        return
                    }
                    let model = draftReminder
                    Task {
                        await calendarVM.saveCustomReminder(model, alsoSyncToSystemReminders: alsoSyncToSystem)
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private var lunarDatePickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if repeatRule == .once {
                    let currentYear = Calendar.current.component(.year, from: Date())
                    Picker("农历年", selection: $lunarYear) {
                        ForEach((currentYear - 1)...(currentYear + 10), id: \.self) { y in
                            Text("\(String(y))年").tag(y)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)
                }

                Picker("农历月", selection: $lunarMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(CustomReminderEngine.lunarMonthName(m)).tag(m)
                    }
                }
                .labelsHidden()

                Picker("农历日", selection: $lunarDay) {
                    ForEach(1...30, id: \.self) { d in
                        Text(CustomReminderEngine.lunarDayName(d)).tag(d)
                    }
                }
                .labelsHidden()

                Toggle("闰月", isOn: $isLeapMonth)
                    .toggleStyle(WenBarSwitchToggleStyle())
                    .font(.caption)
            }

            Text(lunarPreviewText)
                .font(.caption2)
                .foregroundStyle(.orange)
        }
        .padding(8)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
    }

    private var advanceDaysSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("多次提前提醒（可多选组合）")
                .font(.caption.weight(.semibold))

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 84), spacing: 6)], alignment: .leading, spacing: 6) {
                ForEach(CustomReminderEngine.defaultPresetAdvanceDays, id: \.self) { day in
                    let isSelected = selectedAdvanceDays.contains(day)
                    Button {
                        toggleAdvanceDay(day)
                    } label: {
                        Text(day == 0 ? "当天" : "提前 \(day) 天")
                            .font(.caption2.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(
                                isSelected ? Color.accentColor : Color.secondary.opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 7)
                            )
                            .foregroundStyle(isSelected ? .white : .primary)
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack(spacing: 6) {
                TextField("自定义提前天数（如 5）", text: $customAdvanceInput)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                Button("添加") {
                    if let parsed = Int(customAdvanceInput.trimmingCharacters(in: .whitespacesAndNewlines)),
                       parsed >= 0, parsed <= 365 {
                        selectedAdvanceDays.insert(parsed)
                        customAdvanceInput = ""
                    }
                }
                .controlSize(.small)
                .disabled(Int(customAdvanceInput.trimmingCharacters(in: .whitespacesAndNewlines)) == nil)
            }

            if !customOnlyAdvanceDays.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 6) {
                        ForEach(customOnlyAdvanceDays, id: \.self) { day in
                            Button {
                                toggleAdvanceDay(day)
                            } label: {
                                HStack(spacing: 3) {
                                    Text("提前 \(day) 天")
                                    Image(systemName: "xmark.circle.fill")
                                }
                                .font(.caption2)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.14), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .scrollIndicators(.hidden)
            }

            let timeComps = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
            let timeStr = String(format: "%02d:%02d", timeComps.hour ?? 9, timeComps.minute ?? 0)
            let summary = CustomReminderEngine.advanceDaysSummary(for: Array(selectedAdvanceDays))
            Text("将在 \(summary) 的 \(timeStr) 推送系统通知")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func toggleAdvanceDay(_ day: Int) {
        if selectedAdvanceDays.contains(day) {
            if selectedAdvanceDays.count > 1 {
                selectedAdvanceDays.remove(day)
            }
        } else {
            selectedAdvanceDays.insert(day)
        }
    }
}
