import Observation
import UserNotifications

@MainActor
@Observable
final class NotificationPermission {
    private(set) var status: UNAuthorizationStatus?
    private(set) var requestError: String?

    func refresh() async {
        let currentStatus = await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
        status = currentStatus
        if [.authorized, .provisional, .ephemeral].contains(currentStatus) {
            requestError = nil
        }
    }

    func request() async {
        do {
            _ = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
            requestError = nil
        } catch {
            requestError = "Couldn't turn on notifications: \(error.localizedDescription)"
        }
        await refresh()
    }
}
