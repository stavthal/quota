import Foundation
import QuotaCore
import UserNotifications

@MainActor
final class NotificationService {
    func requestAuthorizationIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func deliver(events: [AlertEvent], preferences: QuotaPreferences) async {
        guard preferences.notificationsEnabled, !events.isEmpty else { return }
        await requestAuthorizationIfNeeded()

        for event in events {
            let content = UNMutableNotificationContent()
            content.title = "Quota · \(event.providerID.rawValue.capitalized)"
            content.body =
                "\(label(for: event.windowKind)) at \(Int(event.utilization * 100))% (\(event.severity.rawValue))"
            if preferences.soundEnabled {
                content.sound = .default
            }

            let request = UNNotificationRequest(
                identifier: "\(event.providerID.rawValue)-\(event.windowKind.rawValue)-\(event.severity.rawValue)-\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            try? await UNUserNotificationCenter.current().add(request)
        }
    }

    private func label(for kind: UsageWindowKind) -> String {
        switch kind {
        case .fiveHour: "5-hour window"
        case .weekly: "Weekly window"
        case .monthly: "Monthly window"
        case .custom: "Usage window"
        }
    }
}
