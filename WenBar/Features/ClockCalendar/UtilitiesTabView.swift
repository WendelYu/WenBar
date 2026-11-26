import SwiftUI
import WenBarCore

struct UtilitiesTabView: View {
    @Bindable var clockVM: ClockViewModel
    @Bindable var calendarVM: CalendarViewModel
    @Bindable var settingsStore: SettingsStore

    @State private var diffStartDate: Date = Date()
    @State private var diffEndDate: Date = Date().addingTimeInterval(7 * 86400)
    @State private var diffResult: DateCalculator.DiffResult?
    @State private var customMinutesText: String = "15"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                timerSection
                worldClockSection
                dateDiffSection
            }
            .padding(.vertical, 4)
        }
        .task {
            diffResult = await calendarVM.calculateDateDiff(from: diffStartDate, to: diffEndDate)
        }
        .onChange(of: diffStartDate) { _, _ in
            Task { diffResult = await calendarVM.calculateDateDiff(from: diffStartDate, to: diffEndDate) }
        }
        .onChange(of: diffEndDate) { _, _ in
            Task { diffResult = await calendarVM.calculateDateDiff(from: diffStartDate, to: diffEndDate) }
        }
    }

    private var timerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("倒计时 / 番茄钟", systemImage: "timer")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(clockVM.formattedRemainingTime)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(clockVM.isTimerRunning ? Color.accentColor : Color.primary)
            }

            HStack(spacing: 6) {
                Button("🍅 25m 专注") { clockVM.startPomodoroFocus(minutes: 25) }
                Button("☕ 5m 休息") { clockVM.startPomodoroBreak(minutes: 5) }

                TextField("分钟", text: $customMinutesText)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                Button("开始") {
                    let mins = Int(customMinutesText) ?? 10
                    clockVM.startCountdown(minutes: mins)
                }
            }
            .controlSize(.small)

            HStack(spacing: 8) {
                Button(clockVM.isTimerRunning ? "暂停" : "继续") {
                    clockVM.toggleTimerPause()
                }
                .disabled(!clockVM.isTimerRunning && clockVM.remainingSeconds == 0)

                Button("重置") {
                    clockVM.resetTimer()
                }
                Spacer()
            }
            .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var worldClockSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("世界时钟", systemImage: "globe.asia.australia")
                .font(.subheadline.weight(.semibold))

            ForEach(settingsStore.settings.worldClockCities) { city in
                let info = clockVM.formattedWorldClockTime(for: city)
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(city.name)
                            .font(.caption.weight(.medium))
                        Text("\(info.dayDiff) · \(info.offset)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(info.time)
                        .font(.system(size: 16, weight: .semibold, design: .monospaced))
                }
                .padding(.vertical, 2)
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var dateDiffSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("日期差与工作日计算", systemImage: "calendar.badge.clock")
                .font(.subheadline.weight(.semibold))

            HStack {
                DatePicker("起", selection: $diffStartDate, displayedComponents: .date)
                    .labelsHidden()
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                DatePicker("止", selection: $diffEndDate, displayedComponents: .date)
                    .labelsHidden()
                Spacer()
            }

            if let diff = diffResult {
                HStack(spacing: 12) {
                    Text("共 \(abs(diff.calendarDays)) 天")
                        .font(.caption.weight(.semibold))
                    Text("工作日 \(abs(diff.workingDays)) 天")
                        .font(.caption)
                        .foregroundStyle(Color.accentColor)
                    Text("含周末/调休 \(abs(diff.weekendAndHolidayDays)) 天")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}
