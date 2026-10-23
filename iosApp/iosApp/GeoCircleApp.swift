import SwiftUI

@main
struct GeoCircleApp: App {
    @State private var store = GroupStore()

    var body: some Scene {
        WindowGroup {
            GroupsListView()
                .environment(store)
        }
    }
}
