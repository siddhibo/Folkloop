import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import Foundation

enum FirebaseSetup {
    static let cloudProjectID = "folkloop-2effc"

    #if DEBUG
    static let usesEmulator = true
    #else
    static let usesEmulator = false
    #endif

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
            guard let path = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist"),
                  let options = FirebaseOptions(contentsOfFile: path),
                  options.projectID == cloudProjectID
            else {
                fatalError("Release builds need the GoogleService-Info.plist for \(cloudProjectID) in iosApp/iosApp/.")
            }
            FirebaseApp.configure(options: options)
        }

        if ProcessInfo.processInfo.arguments.contains("-signOutOnLaunch") {
            try? Auth.auth().signOut()
        }
    }
}
