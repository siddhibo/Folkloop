import MapKit
import SwiftUI
import Shared

struct GeofenceEditorView: View {
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let group: TrackingGroup
    let geofence: Geofence?

    @State private var name = ""
    @State private var center: CLLocationCoordinate2D?
    @State private var radiusMeters = 300.0
    @State private var errorMessage: String?
    @State private var isSaving = false
    @State private var search = PlaceSearch()
    @State private var isSearching = false
    @State private var selectedPlace: SelectedPlace?
    @State private var locationNote: String?
    @State private var cameraPosition = MapCameraPosition.region(Self.india)

    private static let india = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 22.5, longitude: 79.0),
        latitudinalMeters: 3_300_000,
        longitudinalMeters: 3_300_000
    )

    init(group: TrackingGroup, editing geofence: Geofence? = nil) {
        self.group = group
        self.geofence = geofence
        if let geofence {
            let span = geofence.radiusMeters * 6
            _name = State(initialValue: geofence.name)
            _center = State(initialValue: geofence.center.coordinate)
            _radiusMeters = State(initialValue: geofence.radiusMeters)
            _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
                center: geofence.center.coordinate,
                latitudinalMeters: span,
                longitudinalMeters: span
            )))
        }
    }

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
                        selectedPlace = nil
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
                    if let selectedPlace {
                        Label("Selected: \(selectedPlace.summary)", systemImage: "mappin.and.ellipse")
                    }
                    if let center {
                        Text("Centre \(center.latitude, format: .number.precision(.fractionLength(4))), \(center.longitude, format: .number.precision(.fractionLength(4))). Tap the map to move it.")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Search for a place or tap the map to choose the centre.")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Button("Show Selected Area", systemImage: "scope", action: showSelectedArea)
                            .disabled(center == nil)
                        Spacer()
                        Button("Use My Location", systemImage: "location", action: useCurrentLocation)
                    }
                    .buttonStyle(.borderless)
                    if let locationNote {
                        Text(locationNote)
                            .foregroundStyle(.secondary)
                    }
                    if let searchMessage = search.message {
                        Text(searchMessage)
                            .foregroundStyle(.secondary)
                    }
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
                .frame(maxHeight: 360)
            }
            .searchable(text: $search.query, isPresented: $isSearching, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a place or address")
            .searchSuggestions {
                ForEach(search.suggestions, id: \.self) { suggestion in
                    Button {
                        select(suggestion)
                    } label: {
                        VStack(alignment: .leading) {
                            Text(suggestion.title)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle(geofence == nil ? "New Geofence" : "Edit Geofence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(center == nil || isSaving)
                }
            }
        }
        .interactiveDismissDisabled()
    }

    private func select(_ suggestion: MKLocalSearchCompletion) {
        Task {
            guard let place = await search.place(for: suggestion) else { return }
            isSearching = false
            search.query = ""
            selectedPlace = place
            center = place.coordinate
            locationNote = nil
            showSelectedArea()
        }
    }

    private func useCurrentLocation() {
        guard let location = CLLocationManager().location else {
            locationNote = "Your current location isn't available. Turn on Exit Alerts to allow location access, or search for a place."
            return
        }
        center = location.coordinate
        selectedPlace = SelectedPlace(name: "Your current location", detail: nil, coordinate: location.coordinate)
        locationNote = nil
        showSelectedArea()
    }

    private func showSelectedArea() {
        guard let center else { return }
        let span = max(radiusMeters * 6, 2_000)
        cameraPosition = .region(MKCoordinateRegion(center: center, latitudinalMeters: span, longitudinalMeters: span))
    }

    private func save() {
        guard let center else { return }
        isSaving = true
        Task {
            do {
                if let geofence {
                    try await store.updateGeofence(geofence, name: name, center: center, radiusMeters: radiusMeters)
                } else {
                    try await store.addGeofence(to: group, name: name, center: center, radiusMeters: radiusMeters)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
