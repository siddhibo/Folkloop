import MapKit
import SwiftUI
import Shared

struct GroupDetailView: View {
    @Environment(GroupStore.self) private var store
    @Environment(GeofenceMonitor.self) private var monitor
    @State private var isAddingGeofence = false
    let group: TrackingGroup

    var body: some View {
        let geofences = store.geofences(in: group)

        List {
            if !geofences.isEmpty {
                Section {
                    GeofencesMap(geofences: geofences)
                        // Rebuild the map when geofences change so it re-fits all circles.
                        .id(geofences.map(\.id))
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section("Geofences") {
                if geofences.isEmpty {
                    Text("No geofences yet. Tap + to add an area for this group.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(geofences) { geofence in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(geofence.name)
                                    .font(.headline)
                                Text("\(Int(geofence.radiusMeters)) m · \(coordinateText(geofence.center))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(monitor.stateText(for: geofence))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { offsets in
                        let removed = offsets.map { geofences[$0] }
                        Task {
                            for geofence in removed {
                                try? await store.deleteGeofence(geofence)
                            }
                        }
                    }
                }
            }
            MembersSection(group: group)
        }
        .navigationTitle(group.name)
        .toolbar {
            Button("Add Geofence", systemImage: "plus") {
                isAddingGeofence = true
            }
        }
        // Sheets must live outside the List; one attached to a Section never opens.
        .sheet(isPresented: $isAddingGeofence) {
            GeofenceEditorView(group: group)
        }
    }

    private func coordinateText(_ point: GeoPoint) -> String {
        String(format: "%.4f, %.4f", point.latitude, point.longitude)
    }
}

/// Read-only map showing every geofence in a group.
private struct GeofencesMap: View {
    let geofences: [Geofence]

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(geofences) { geofence in
                MapCircle(center: geofence.center.coordinate, radius: geofence.radiusMeters)
                    .foregroundStyle(.blue.opacity(0.2))
                    .stroke(.blue, lineWidth: 2)
                Marker(geofence.name, coordinate: geofence.center.coordinate)
            }
        }
    }
}
