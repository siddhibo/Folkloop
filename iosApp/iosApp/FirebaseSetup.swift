import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

/// Connects the app to Firebase.
///
/// With a `GoogleService-Info.plist` in the app, GeoCircle uses that real Firebase project.
/// Without one it uses the local Firebase Emulator Suite (`npm run emulators` in `backend/`) with a "demo-" project,
/// which cannot reach any real Google service. The placeholder values below are not credentials.
enum FirebaseSetup {
    static var usesEmulator: Bool {
        Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") == nil
    }

    static func configure() {
        if usesEmulator {
            let options = FirebaseOptions(googleAppID: "1:000000000000:ios:0000000000000000", gcmSenderID: "000000000000")
            options.projectID = "demo-geocircle"
            options.apiKey = "AIzaDEMO-local-emulator-only-0000000000"
            FirebaseApp.configure(options: options)

            Auth.auth().useEmulator(withHost: "127.0.0.1", port: 9099)
            let settings = Firestore.firestore().settings
            settings.host = "127.0.0.1:8080"
            settings.isSSLEnabled = false
            settings.cacheSettings = MemoryCacheSettings()
            Firestore.firestore().settings = settings
        } else {
            FirebaseApp.configure()
        }

        // UI tests start from a clean session because the emulator forgets accounts when it restarts.
        if ProcessInfo.processInfo.arguments.contains("-signOutOnLaunch") {
            try? Auth.auth().signOut()
        }
    }
}
