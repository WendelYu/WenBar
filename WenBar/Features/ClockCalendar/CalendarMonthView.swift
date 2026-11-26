import SwiftUI
import WenBarCore

struct CalendarMonthView: View {
    @Bindable var calendarVM: CalendarViewModel

    private let weekdayHeaders = ["一", "二", "三", "四", "五", "六", "日"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 8) {
            // Header: Clean single-chevron Year/Month picker + navigation
            HStack(spacing: 6) {
                Button {
                    calendarVM.goToPreviousYear()
                } label: {
                    Image(systemName: "chevron.left.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("上一年")

                Button {
                    calendarVM.goToPreviousMonth()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    HStack(spacing: 3) {
                        Text("\(String(calendarVM.displayedYear))年")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Menu {
                    ForEach(1...12, id: \.self) { m in
                        Button("\(m) 月") {
                            calendarVM.jumpTo(year: calendarVM.displayedYear, month: m)
                        }
                    }
                } label: {
                    HStack(spacing: 3) {
                        Text("\(calendarVM.displayedMonthNumber)月")
                            .font(.system(size: 16, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()

                Button {
                    calendarVM.goToNextMonth()
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("下一月")

                Button {
                    calendarVM.goToNextYear()
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("下一年")

                Spacer()

                Button {
                    Task { await calendarVM.syncOnlineHolidays() }
                } label: {
                    Image(systemName: calendarVM.isSyncingHolidays ? "arrow.triangle.2.circlepath.circle.fill" : "arrow.clockwise")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .help("节假日数据：\(calendarVM.holidaySyncStatus)")

                Button("今天") {
                    calendarVM.goToToday()
                }
                .controlSize(.small)
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 2)

            // Weekday header
            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { index, title in
                    Text(title)
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(index >= 5 ? Color.red.opacity(0.78) : Color.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // Clean airy 6x7 day grid
            LazyVGrid(columns: columns, spacing: 3) {
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
                VStack(spacing: 1.5) {
                    Text("\(day.dayNumber)")
                        .font(.system(size: 14, weight: day.isToday || isSelected ? .semibold : .medium, design: .rounded))
                        .foregroundStyle(dayTextColor(day: day, isSelected: isSelected))

                    Text(day.subtitle)
                        .font(.system(size: 9.5))
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
            .opacity(day.isCurrentMonth ? 1.0 : 0.35)
        }
        .buttonStyle(.plain)
    }

    private func dayTextColor(day: CalendarGridDay, isSelected: Bool) -> Color {
        if isSelected { return .white }
        if day.isToday { return .accentColor }
        if day.holiday?.isOffDay == true { return .green }
        if day.holiday?.isOffDay == false { return .primary }
        if day.isWeekend { return .red.opacity(0.82) }
        return .primary
    }

    private func subtitleColor(day: CalendarGridDay, isSelected: Bool) -> Color {
        if isSelected { return .white.opacity(0.92) }
        if day.holiday?.isOffDay == true
            || day.lunarInfo.traditionalFestival != nil
            || day.lunarInfo.solarTerm != nil
            || day.lunarInfo.gregorianFestival != nil {
            return .accentColor
        }
        return .secondary
    }

    @ViewBuilder
    private func cellBackground(day: CalendarGridDay, isSelected: Bool) -> some View {
        if isSelected {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor)
        } else if day.isToday {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.45), lineWidth: 1)
                )
        } else {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(Color.clear)
        }
    }
}
