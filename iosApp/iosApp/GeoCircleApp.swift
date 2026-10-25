import SwiftUI

@main
struct GeoCircleApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var session: SessionStore
    @State private var store: GroupStore
    @State private var monitor: GeofenceMonitor
    @State private var notificationPermission = NotificationPermission()

    init() {
        FirebaseSetup.configure()
        let store = GroupStore()
        let monitor = GeofenceMonitor()
        monitor.onExit = { geofence, occurredAt in store.recordExit(from: geofence, at: occurredAt) }
        monitor.onEntry = { geofence, occurredAt in store.recordEntry(into: geofence, at: occurredAt) }
        _session = State(initialValue: SessionStore())
        _store = State(initialValue: store)
        _monitor = State(initialValue: monitor)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .environment(store)
                .environment(monitor)
                .environment(notificationPermission)
                .environment(appDelegate.push)
                .onChange(of: session.user, initial: true) { _, user in
                    if !session.isRestoringSession {
                        store.start(for: user)
                    }
                    updatePushRegistration()
                }
                .onChange(of: notificationPermission.status) {
                    updatePushRegistration()
                }
                .onChange(of: store.geofencesToMonitor, initial: true) { _, geofences in
                    if let geofences {
                        monitor.sync(geofences: geofences)
                    }
                }
        }
    }

    private func updatePushRegistration() {
        let notificationsAllowed = notificationPermission.status.map { [.authorized, .provisional, .ephemeral].contains($0) } ?? false
        appDelegate.push.update(userID: session.user?.uid, notificationsAllowed: notificationsAllowed)
    }
}

private struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        if session.user == nil {
            SignInView()
        } else {
            GroupsListView()
        }
    }
}
