import SwiftUI

@main
struct GeoCircleApp: App {
    @State private var session: SessionStore
    @State private var store: GroupStore
    @State private var monitor: GeofenceMonitor

    init() {
        // Firebase must be configured before any store touches Auth or Firestore.
        FirebaseSetup.configure()
        let store = GroupStore()
        let monitor = GeofenceMonitor()
        monitor.onExit = { geofence in store.recordExit(from: geofence) }
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
                .onChange(of: session.user, initial: true) { _, user in
                    store.start(for: user)
                }
                .onChange(of: store.allGeofences, initial: true) { _, geofences in
                    monitor.sync(geofences: geofences)
                }
        }
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
