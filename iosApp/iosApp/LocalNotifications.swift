import Foundation
import OSLog
import Shared
import UserNotifications

enum LocalNotifications {
    private static let logger = Logger(subsystem: "com.geocircle.app", category: "LocalNotifications")

    static func post(_ alert: ExitAlert, id: String) {
        let content = UNMutableNotificationContent()
        content.title = alert.title
        content.body = alert.body
        content.sound = .default
        let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                logger.error("Couldn't schedule notification \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
