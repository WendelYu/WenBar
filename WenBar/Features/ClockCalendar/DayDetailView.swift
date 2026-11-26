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
        let badges = calendarVM.selectedDayFestivalsAndTerms

        VStack(alignment: .leading, spacing: 8) {
            // 1. Selected Date + Lunar + Relative Header
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(calendarVM.selectedDayGregorianTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(calendarVM.selectedDayRelativeDescription)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Text("农历：\(lunar.fullLunarText)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

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
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // 2. Holiday / Solar Term / Festival Badges
            if !badges.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(badges, id: \.self) { badge in
                            Text(badge)
                                .font(.caption2.weight(.medium))
                                .padding(.horizontal, 7)
                                .padding(.vertical, 2)
                                .background(badgeColor(badge).opacity(0.14), in: Capsule())
                                .foregroundStyle(badgeColor(badge))
                        }
                    }
                }
            }

            // 3. Almanac (老黄历) Card
            VStack(alignment: .leading, spacing: 5) {
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
                    .help(isAlmanacExpanded ? "收起干支与彭祖百忌" : "展开干支三柱与彭祖百忌")
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
                        .lineLimit(1)
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
                        .lineLimit(1)
                }

                if isAlmanacExpanded {
                    Divider()
                    Text("干支：\(almanac.yearPillar)年 \(almanac.monthPillar)月 \(almanac.dayPillar)日")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("彭祖百忌：\(almanac.pengZu)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 8))

            // 4. Events & Reminders List
            if !calendarVM.calendarAccessGranted && !calendarVM.remindersAccessGranted {
                HStack(spacing: 8) {
                    Image(systemName: "calendar.badge.exclamationmark")
                        .foregroundStyle(.orange)
                    Text("尚未授权系统日历与提醒事项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("授权读取") {
                        Task {
                            _ = await calendarVM.requestCalendarAccess()
                            _ = await calendarVM.requestRemindersAccess()
                        }
                    }
                    .controlSize(.small)
                }
                .padding(8)
                .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        if calendarVM.eventsForSelectedDate.isEmpty && calendarVM.remindersForSelectedDate.isEmpty {
                            Text("当天暂无日程或提醒事项")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .padding(.vertical, 8)
                        }

                        ForEach(calendarVM.eventsForSelectedDate, id: \.eventIdentifier) { event in
                            HStack(spacing: 8) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color(cgColor: event.calendar.cgColor))
                                    .frame(width: 3, height: 22)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(event.title ?? "(无标题)")
                                        .font(.caption.weight(.medium))
                                        .lineLimit(1)
                                    Text(formatEventTime(event))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                        }

                        ForEach(calendarVM.remindersForSelectedDate) { reminder in
                            Button {
                                Task { await calendarVM.toggleReminder(reminder) }
                            } label: {
                                HStack(spacing: 8) {
                                    Image(systemName: reminder.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(reminder.isCompleted ? Color.green : Color.secondary)
                                    Text(reminder.title)
                                        .font(.caption)
                                        .strikethrough(reminder.isCompleted)
                                        .foregroundStyle(reminder.isCompleted ? .secondary : .primary)
                                        .lineLimit(1)
                                    Spacer()
                                    if let due = reminder.dueDate {
                                        Text(formatHourMinute(due))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 110)
            }
        }
        .sheet(isPresented: $showingNewEventSheet) {
            QuickNewEventSheet(calendarVM: calendarVM)
        }
        .sheet(isPresented: $showingNewReminderSheet) {
            QuickNewReminderSheet(calendarVM: calendarVM)
        }
    }

    private func badgeColor(_ badge: String) -> Color {
        if badge.contains("休") && !badge.contains("调休") { return .green }
        if badge.contains("调休") { return .orange }
        if badge.contains("节气") { return .teal }
        return .accentColor
    }

    private func formatEventTime(_ event: EKEvent) -> String {
        if event.isAllDay { return "全天" }
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return "\(df.string(from: event.startDate)) - \(df.string(from: event.endDate))"
    }

    private func formatHourMinute(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateFormat = "HH:mm"
        return df.string(from: date)
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
