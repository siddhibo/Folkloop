import CoreLocation
import Observation
import Shared
import UserNotifications

/// Watches saved geofences with Core Location and reports when this device leaves one.
///
/// iOS decides when region events arrive; delivery is not guaranteed or instant, especially in the background.
/// Monitoring follows the signed-in user's geofences, so it stops after signing out.
@MainActor
@Observable
final class GeofenceMonitor: NSObject {
    private(set) var authorization: CLAuthorizationStatus
    private(set) var monitoredIDs: Set<String> = []
    private(set) var totalGeofences = 0
    private var states: [String: RegionState] = [:]

    /// Called on the main actor when this device leaves a monitored geofence.
    @ObservationIgnored var onExit: ((Geofence) -> Void)?

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let monitorTask: Task<CLMonitor, Never>
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var geofences: [Geofence] = []

    override init() {
        authorization = locationManager.authorizationStatus
        // CLMonitor remembers its conditions by name across launches.
        monitorTask = Task { await CLMonitor("GeoCircleGeofences") }
        super.init()
        locationManager.delegate = self
        UNUserNotificationCenter.current().delegate = self
        Task { await listenForEvents() }
    }

    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    /// Asks for location access (iOS offers "While Using" first, "Always" later) and for permission to show alerts.
    func requestPermissions() {
        locationManager.requestAlwaysAuthorization()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Call whenever the saved geofences change.
    func sync(geofences: [Geofence]) {
        self.geofences = geofences
        totalGeofences = geofences.count
        scheduleSync()
    }

    func stateText(for geofence: Geofence) -> String {
        guard monitoredIDs.contains(geofence.id) else { return "Not monitored" }
        switch states[geofence.id] {
        case RegionState.inside: return "Inside"
        case RegionState.outside: return "Outside"
        default: return "Checking…"
        }
    }

    // Runs syncs one after another so adds and removes never overlap.
    private func scheduleSync() {
        let previous = syncTask
        syncTask = Task {
            await previous?.value
            await applySync()
        }
    }

    private func applySync() async {
        let monitor = await monitorTask.value
        let wanted = isAuthorized
            ? GeofenceMonitoring.shared.selectForMonitoring(
                geofences: geofences,
                currentLocation: locationManager.location.map { GeoPoint($0.coordinate) },
                limit: GeofenceMonitoring.shared.IOS_REGION_LIMIT
            )
            : []
        let wantedIDs = Set(wanted.map(\.id))

        for id in await monitor.identifiers where !wantedIDs.contains(id) {
            await monitor.remove(id)
            states[id] = nil
        }
        let existingIDs = Set(await monitor.identifiers)
        for geofence in wanted where !existingIDs.contains(geofence.id) {
            let condition = CLMonitor.CircularGeographicCondition(
                center: geofence.center.coordinate,
                radius: geofence.radiusMeters
            )
            await monitor.add(condition, identifier: geofence.id)
            states[geofence.id] = .unknown
        }
        monitoredIDs = wantedIDs
    }

    private func listenForEvents() async {
        let monitor = await monitorTask.value
        do {
            for try await event in await monitor.events {
                handle(identifier: event.identifier, state: event.state)
            }
        } catch {
            // The event stream only ends if Core Location stops monitoring; nothing to recover here.
        }
    }

    private func handle(identifier: String, state: CLMonitor.Event.State) {
        let newState: RegionState = switch state {
        case .satisfied: .inside
        case .unsatisfied: .outside
        default: .unknown
        }
        let previous = states[identifier] ?? .unknown
        states[identifier] = newState

        guard GeofenceMonitoring.shared.isExit(previous: previous, current: newState),
              let geofence = geofences.first(where: { $0.id == identifier })
        else { return }
        onExit?(geofence)
    }
}

extension GeofenceMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        // The manager was created on the main thread, so its callbacks arrive there too.
        MainActor.assumeIsolated {
            authorization = status
            scheduleSync()
        }
    }
}

extension GeofenceMonitor: UNUserNotificationCenterDelegate {
    // Show the banner even while GeoCircle is open.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }
}
