import MapKit
import SwiftUI
import Shared

struct GeofenceEditorView: View {
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let group: TrackingGroup

    @State private var name = ""
    @State private var center: CLLocationCoordinate2D?
    @State private var radiusMeters = 300.0
    @State private var errorMessage: String?

    // Starts near Apple Park until the app uses the device location in a later milestone.
    @State private var cameraPosition = MapCameraPosition.region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.3349, longitude: -122.0090),
            latitudinalMeters: 4_000,
            longitudinalMeters: 4_000
        )
    )

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                MapReader { proxy in
                    Map(position: $cameraPosition) {
                        if let center {
                            MapCircle(center: center, radius: radiusMeters)
                                .foregroundStyle(.blue.opacity(0.2))
                                .stroke(.blue, lineWidth: 2)
                            Marker("Centre", coordinate: center)
                        }
                    }
                    .onTapGesture { screenPoint in
                        center = proxy.convert(screenPoint, from: .local)
                    }
                    .accessibilityIdentifier("geofenceMap")
                }

                Form {
                    TextField("Geofence name", text: $name)
                    VStack(alignment: .leading) {
                        Text("Radius: \(Int(radiusMeters)) m")
                        Slider(
                            value: $radiusMeters,
                            in: Validation.shared.MIN_RADIUS_METERS...Validation.shared.MAX_RADIUS_METERS,
                            step: 50
                        )
                    }
                    if center == nil {
                        Text("Tap the map to choose the centre.")
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxHeight: 280)
            }
            .navigationTitle("New Geofence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(center == nil)
                }
            }
        }
        // Stops a map drag from accidentally closing the sheet.
        .interactiveDismissDisabled()
    }

    private func save() {
        guard let center else { return }
        do {
            try store.addGeofence(to: group, name: name, center: center, radiusMeters: radiusMeters)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
