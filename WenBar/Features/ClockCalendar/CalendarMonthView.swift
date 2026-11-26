import SwiftUI
import WenBarCore

struct CalendarMonthView: View {
    @Bindable var calendarVM: CalendarViewModel

    private let weekdayHeaders = ["一", "二", "三", "四", "五", "六", "日"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            // Row 1: Quick Year & Month Switcher
            HStack(spacing: 6) {
                Button {
                    calendarVM.goToPreviousYear()
                } label: {
                    Image(systemName: "chevron.left.2")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("上一年")

                Button {
                    calendarVM.goToPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("上一月")

                Menu {
                    let current = calendarVM.displayedYear
                    ForEach((current - 8)...(current + 8), id: \.self) { year in
                        Button("\(year) 年") {
                            calendarVM.jumpTo(year: year, month: calendarVM.displayedMonthNumber)
                        }
                    }
                    Divider()
                    ForEach([1980, 1990, 2000, 2010, 2020, 2030, 2040], id: \.self) { decade in
                        Menu("\(decade)–\(decade + 9) 年") {
                            ForEach(decade...(decade + 9), id: \.self) { y in
                                Button("\(y) 年") {
                                    calendarVM.jumpTo(year: y, month: calendarVM.displayedMonthNumber)
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("\(String(calendarVM.displayedYear))年")
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Menu {
                    ForEach(1...12, id: \.self) { m in
                        Button("\(m) 月") {
                            calendarVM.jumpTo(year: calendarVM.displayedYear, month: m)
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text("\(calendarVM.displayedMonthNumber)月")
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                Button {
                    calendarVM.goToNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("下一月")

                Button {
                    calendarVM.goToNextYear()
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("下一年")

                Spacer()

                Button("今天") {
                    calendarVM.goToToday()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }

            // Row 2: Holiday countdown + Sync
            HStack(spacing: 6) {
                if let next = calendarVM.nextHoliday {
                    HStack(spacing: 4) {
                        Image(systemName: "sparkles")
                            .font(.caption2)
                        if next.isOngoing {
                            Text("\(next.name)假期中")
                        } else {
                            Text("距离下个假期「\(next.name)」还有 \(next.daysRemaining) 天")
                        }
                    }
                    .font(.caption2.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                    .foregroundStyle(Color.accentColor)
                }

                Spacer()

                Button {
                    Task { await calendarVM.syncOnlineHolidays() }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: calendarVM.isSyncingHolidays ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                        Text(calendarVM.holidaySyncStatus)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("刷新国务院最新放假与调休数据")
            }

            // Weekday header
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { index, title in
                    Text(title)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(index >= 5 ? Color.red.opacity(0.8) : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 6x7 day grid
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(calendarVM.gridDays) { day in
                    dayCell(day)
                }
            }
        }
    }

    @ViewBuilder
    private func dayCell(_ day: CalendarGridDay) -> some View {
        let isSelected = Calendar.current.isDate(day.date, inSameDayAs: calendarVM.selectedDate)

        Button {
            calendarVM.selectDate(day.date)
        } label: {
            ZStack(alignment: .topTrailing) {
                VStack(spacing: 1) {
                    Text("\(day.dayNumber)")
                        .font(.system(size: 13, weight: day.isToday || isSelected ? .bold : .medium, design: .rounded))
                        .foregroundStyle(dayTextColor(day: day, isSelected: isSelected))

                    Text(day.subtitle)
                        .font(.system(size: 9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .foregroundStyle(subtitleColor(day: day, isSelected: isSelected))

                    Circle()
                        .fill(day.hasEvents ? (isSelected ? Color.white : Color.accentColor) : Color.clear)
                        .frame(width: 4, height: 4)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)

                if let holiday = day.holiday {
                    Text(holiday.isOffDay ? "休" : "班")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(holiday.isOffDay ? Color.green : Color.orange, in: RoundedRectangle(cornerRadius: 3))
                        .padding(2)
                }
            }
            .background(cellBackground(day: day, isSelected: isSelected))
            .opacity(day.isCurrentMonth ? 1.0 : 0.42)
        }
        .buttonStyle(.plain)
    }

    private func dayTextColor(day: CalendarGridDay, isSelected: Bool) -> Color {
        if isSelected { return .white }
        if day.isToday { return .accentColor }
        if day.holiday?.isOffDay == true { return .green }
        if day.holiday?.isOffDay == false { return .primary }
        if day.isWeekend { return .red.opacity(0.85) }
        return .primary
    }

    private func subtitleColor(day: CalendarGridDay, isSelected: Bool) -> Color {
        if isSelected { return .white.opacity(0.9) }
        if day.holiday?.isOffDay == true || day.lunarInfo.traditionalFestival != nil || day.lunarInfo.solarTerm != nil {
            return .accentColor
        }
        return .secondary
    }

    @ViewBuilder
    private func cellBackground(day: CalendarGridDay, isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor)
        } else if day.isToday {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.accentColor.opacity(0.14))
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.primary.opacity(0.03))
        }
    }
}
