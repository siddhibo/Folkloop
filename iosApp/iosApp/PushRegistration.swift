import FirebaseFirestore
import FirebaseMessaging
import Observation
import UIKit

@MainActor
@Observable
final class PushRegistration: NSObject {
    private static let deviceIDKey = "pushDeviceID"

    private(set) var problem: String?

    @ObservationIgnored private var userID: String?
    @ObservationIgnored private var isEnabled = false

    var isAvailable: Bool { !FirebaseSetup.usesEmulator }

    func update(userID: String?, notificationsAllowed: Bool) {
        guard isAvailable else { return }
        self.userID = userID
        isEnabled = userID != nil && notificationsAllowed
        guard isEnabled else { return }
        Messaging.messaging().delegate = self
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        guard isAvailable else { return }
        problem = nil
        Messaging.messaging().apnsToken = deviceToken
    }

    func didFailToRegister(_ error: Error) {
        guard isAvailable else { return }
        problem = "Push notifications aren't available on this device: \(error.localizedDescription)"
    }

    func unregister() async {
        guard isAvailable, let userID else { return }
        try? await deviceDocument(for: userID).delete()
        try? await Messaging.messaging().unregister()
    }

    private func save(_ token: String) {
        guard isEnabled, let userID else { return }
        deviceDocument(for: userID).setData([
            "token": token,
            "platform": "ios",
            "updatedAt": FieldValue.serverTimestamp(),
        ]) { [weak self] error in
            guard let error else { return }
            MainActor.assumeIsolated {
                self?.problem = "Couldn't register this device for push notifications: \(error.localizedDescription)"
            }
        }
    }

    private func deviceDocument(for userID: String) -> DocumentReference {
        Firestore.firestore().collection("users").document(userID).collection("devices").document(Self.deviceID)
    }

    private static var deviceID: String {
        if let existing = UserDefaults.standard.string(forKey: deviceIDKey) {
            return existing
        }
        let created = UUID().uuidString
        UserDefaults.standard.set(created, forKey: deviceIDKey)
        return created
    }
}

extension PushRegistration: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        Task { @MainActor in
            self.save(fcmToken)
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    let push = PushRegistration()

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        push.didRegister(deviceToken: deviceToken)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        push.didFailToRegister(error)
    }
}
