import Foundation
import Combine
import WenBarCore

enum TimerMode: String, CaseIterable, Identifiable {
    case countdown = "倒计时"
    case pomodoro = "番茄钟"

    var id: String { rawValue }
}

@MainActor
@Observable
final class ClockViewModel {
    var currentDate: Date = Date()
    var menuBarTitle: String = ""

    // Countdown / Pomodoro state
    var timerMode: TimerMode = .pomodoro
    var isTimerRunning: Bool = false
    var isPomodoroBreak: Bool = false
    var remainingSeconds: Int = 25 * 60
    var configuredCountdownMinutes: Int = 10

    private var timer: Timer?
    private let settingsStore: SettingsStore
    var nextHolidayProvider: (() -> NextHolidayCountdown?)?

    init(settingsStore: SettingsStore, nextHolidayProvider: (() -> NextHolidayCountdown?)? = nil) {
        self.settingsStore = settingsStore
        self.nextHolidayProvider = nextHolidayProvider
        updateDisplay()
        scheduleNextTick()
    }

    func refreshScheduling() {
        updateDisplay()
        scheduleNextTick()
    }

    func startPomodoroFocus(minutes: Int = 25) {
        timerMode = .pomodoro
        isPomodoroBreak = false
        remainingSeconds = max(1, minutes) * 60
        isTimerRunning = true
        refreshScheduling()
    }

    func startPomodoroBreak(minutes: Int = 5) {
        timerMode = .pomodoro
        isPomodoroBreak = true
        remainingSeconds = max(1, minutes) * 60
        isTimerRunning = true
        refreshScheduling()
    }

    func startCountdown(minutes: Int) {
        timerMode = .countdown
        configuredCountdownMinutes = max(1, minutes)
        remainingSeconds = configuredCountdownMinutes * 60
        isTimerRunning = true
        refreshScheduling()
    }

    func toggleTimerPause() {
        isTimerRunning.toggle()
        refreshScheduling()
    }

    func resetTimer() {
        isTimerRunning = false
        if timerMode == .pomodoro {
            remainingSeconds = (isPomodoroBreak ? 5 : 25) * 60
        } else {
            remainingSeconds = configuredCountdownMinutes * 60
        }
        refreshScheduling()
    }

    var formattedRemainingTime: String {
        let mins = remainingSeconds / 60
        let secs = remainingSeconds % 60
        return String(format: "%02d:%02d", mins, secs)
    }

    func formattedWorldClockTime(for city: WorldClockCity) -> (time: String, dayDiff: String, offset: String) {
        guard let tz = TimeZone(identifier: city.timeZoneIdentifier) else {
            return ("--:--", "", "")
        }

        let df = DateFormatter()
        df.timeZone = tz
        df.locale = Locale(identifier: "zh_CN")
        df.dateFormat = "HH:mm"
        let timeStr = df.string(from: currentDate)

        var localCal = Calendar(identifier: .gregorian)
        localCal.timeZone = .current
        var targetCal = Calendar(identifier: .gregorian)
        targetCal.timeZone = tz

        let localDay = localCal.dateComponents([.year, .month, .day], from: currentDate)
        let targetDay = targetCal.dateComponents([.year, .month, .day], from: currentDate)

        let dayDiffText: String
        if let d1 = localCal.date(from: localDay), let d2 = localCal.date(from: targetDay) {
            let days = localCal.dateComponents([.day], from: d1, to: d2).day ?? 0
            if days > 0 { dayDiffText = "明天" }
            else if days < 0 { dayDiffText = "昨天" }
            else { dayDiffText = "今天" }
        } else {
            dayDiffText = ""
        }

        let deltaSeconds = tz.secondsFromGMT(for: currentDate) - TimeZone.current.secondsFromGMT(for: currentDate)
        let deltaHours = Double(deltaSeconds) / 3600.0
        let offsetText: String
        if deltaSeconds == 0 {
            offsetText = "本地"
        } else if deltaHours == floor(deltaHours) {
            let h = Int(deltaHours)
            offsetText = h > 0 ? "+\(h)h" : "\(h)h"
        } else {
            offsetText = String(format: "%+.1fh", deltaHours)
        }

        return (timeStr, dayDiffText, offsetText)
    }

    private func scheduleNextTick() {
        timer?.invalidate()
        timer = nil

        let needsSecondTicks = isTimerRunning || ClockFormatEngine.requiresPerSecondUpdates(
            template: settingsStore.settings.clockFormatTemplate
        )

        if needsSecondTicks {
            let newTimer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.handleTick()
                }
            }
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        } else {
            // Align to the next minute boundary to keep idle CPU near zero
            let now = Date()
            let secs = Calendar.current.component(.second, from: now)
            let delay = Double(max(1, 60 - secs))
            let newTimer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
                Task { @MainActor in
                    self?.handleTick()
                    self?.scheduleNextTick()
                }
            }
            RunLoop.main.add(newTimer, forMode: .common)
            timer = newTimer
        }
    }

    private func handleTick() {
        currentDate = Date()

        if isTimerRunning {
            if remainingSeconds > 0 {
                remainingSeconds -= 1
            }
            if remainingSeconds == 0 {
                isTimerRunning = false
                let title = timerMode == .pomodoro
                    ? (isPomodoroBreak ? "休息结束" : "番茄钟专注完成")
                    : "倒计时结束"
                let body = timerMode == .pomodoro
                    ? (isPomodoroBreak ? "准备开始下一轮专注吧！" : "休息 5 分钟放松一下眼睛。")
                    : "设定的 \(configuredCountdownMinutes) 分钟倒计时已到达。"
                NotificationService.shared.post(title: title, body: body)
                scheduleNextTick()
            }
        }

        updateDisplay()
    }

    private func updateDisplay() {
        let settings = settingsStore.settings
        guard settings.enableClockCalendar else {
            menuBarTitle = "WenBar"
            return
        }

        let locale = effectiveLocale()
        var title = ClockFormatEngine.format(
            date: currentDate,
            template: settings.clockFormatTemplate,
            locale: locale,
            nextHoliday: nextHolidayProvider?()
        )

        if isTimerRunning && settings.showCountdownInMenuBar {
            let icon = timerMode == .pomodoro ? (isPomodoroBreak ? "☕" : "🍅") : "⏱"
            title += " \(icon) \(formattedRemainingTime)"
        }

        menuBarTitle = title
    }

    private func effectiveLocale() -> Locale {
        switch settingsStore.settings.language {
        case .system: return .current
        case .zhHans: return Locale(identifier: "zh_CN")
        case .en: return Locale(identifier: "en_US")
        }
    }
}
