import SwiftUI

@main
struct GeoCircleApp: App {
    @State private var store = GroupStore()
    @State private var monitor = GeofenceMonitor()

    var body: some Scene {
        WindowGroup {
            GroupsListView()
                .environment(store)
                .environment(monitor)
                .onChange(of: store.allGeofences, initial: true) { _, geofences in
                    monitor.sync(geofences: geofences, groupNames: store.groupNamesByID)
                }
        }
    }
}
