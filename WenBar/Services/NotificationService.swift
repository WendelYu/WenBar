import Foundation
import UserNotifications
import WenBarCore

@MainActor
final class NotificationService {
    static let shared = NotificationService()
    private init() {}

    func requestAuthorizationIfNeeded() async -> Bool {
        guard Bundle.main.bundleIdentifier != nil else { return false }
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    nonisolated func authorizationStatus() async -> UNAuthorizationStatus {
        guard Bundle.main.bundleIdentifier != nil else { return .notDetermined }
        return await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings.authorizationStatus)
            }
        }
    }

    func post(title: String, body: String) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "wenbar.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func syncScheduledReminderAlerts(_ alerts: [ScheduledReminderAlert]) {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let prefix = ScheduledReminderAlert.identifierPrefix
        UNUserNotificationCenter.current().getPendingNotificationRequests { pending in
            let existingIDs = pending
                .map(\.identifier)
                .filter { $0.hasPrefix(prefix) }
            let center = UNUserNotificationCenter.current()
            if !existingIDs.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: existingIDs)
            }

            for alert in alerts {
                let content = UNMutableNotificationContent()
                content.title = alert.title
                content.body = alert.body
                content.sound = .default

                var comps = DateComponents()
                comps.year = alert.fireYear
                comps.month = alert.fireMonth
                comps.day = alert.fireDay
                comps.hour = alert.fireHour
                comps.minute = alert.fireMinute
                comps.second = 0

                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
                let request = UNNotificationRequest(identifier: alert.id, content: content, trigger: trigger)
                center.add(request)
            }
        }
    }
}
