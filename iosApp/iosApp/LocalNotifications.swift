import Foundation
import Shared
import UserNotifications

/// Shows an alert on this device only. Nothing here reaches other devices.
enum LocalNotifications {
    static func post(_ alert: ExitAlert) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }
}
