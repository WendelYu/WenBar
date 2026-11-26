import SwiftUI
import EventKit
import WenBarCore

struct DayDetailView: View {
    @Bindable var calendarVM: CalendarViewModel
    @State private var showingNewEventSheet = false
    @State private var showingNewReminderSheet = false
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
        let now = Date()
        let selectedTags = selectedDayRowItems(lunar: lunar)
        let isViewingToday = Calendar.current.isDateInToday(calendarVM.selectedDate)

        // Upcoming reminders excluding items already shown for selectedDate
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
                    Text("授权系统日历与提醒事项后可显示日程倒计时")
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

            // 2. Selected day's user reminders (checkable + live countdown!)
            ForEach(calendarVM.remindersForSelectedDate) { rem in
                reminderRow(rem, now: now)
                Divider().opacity(0.45)
            }

            // 3. Selected day's deduplicated user events
            ForEach(calendarVM.eventsForSelectedDate) { event in
                eventRow(event, now: now)
                Divider().opacity(0.45)
            }

            // 4. Upcoming reminders (always show how far away user's reminders are!)
            ForEach(Array(extraUpcomingReminders)) { rem in
                reminderRow(rem, now: now, tagPrefix: "待办")
                Divider().opacity(0.45)
            }

            // 5. Upcoming events
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

    @State private var title: String = ""
    @State private var dueDate: Date
    @State private var notes: String = ""
    @State private var errorMessage: String?

    init(calendarVM: CalendarViewModel) {
        self.calendarVM = calendarVM
        let cal = Calendar.current
        let base = cal.date(bySettingHour: 10, minute: 0, second: 0, of: calendarVM.selectedDate) ?? calendarVM.selectedDate
        _dueDate = State(initialValue: base)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("新建提醒事项")
                .font(.headline)

            TextField("待办事项内容", text: $title)
                .textFieldStyle(.roundedBorder)

            DatePicker("提醒时间", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])

            TextField("备注（可选）", text: $notes)
                .textFieldStyle(.roundedBorder)

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
                            try await calendarVM.createReminder(title: title, dueDate: dueDate, notes: notes)
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
