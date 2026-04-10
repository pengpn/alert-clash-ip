import Foundation
import UserNotifications

@MainActor
final class NotificationService: NSObject, ObservableObject {
    @Published private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined

    private let center: UNUserNotificationCenter

    init(center: UNUserNotificationCenter = .current()) {
        self.center = center
        super.init()
        center.delegate = self
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorizationIfNeeded() async {
        await refreshAuthorizationStatus()
        guard authorizationStatus == .notDetermined else {
            return
        }

        do {
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Ignore, UI reflects the refreshed status below.
        }
        await refreshAuthorizationStatus()
    }

    func send(kind: NotificationKind, status: MonitorStatus) async {
        guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
            return
        }

        let content = UNMutableNotificationContent()
        switch kind {
        case .alertInitial:
            content.title = "Clash 出口 IP 已变化"
        case .alertEscalated:
            content.title = "Clash 出口 IP 仍然异常"
        case .recovered:
            content.title = "Clash 出口 IP 已恢复正常"
        }
        content.body = status.subheadline
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: nil
        )

        try? await center.add(request)
    }
}

extension NotificationService: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
