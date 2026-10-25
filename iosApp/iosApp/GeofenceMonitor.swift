import CoreLocation
import Observation
import Shared
import UserNotifications

@MainActor
@Observable
final class GeofenceMonitor: NSObject {
    private static let sharingPausedKey = "sharingPaused"
    private static let regionStatesKey = "regionStates"
    private static let pendingCrossingLimit = 20
    private static let identifierSeparator: Character = "#"

    private struct PendingCrossing: Equatable {
        let geofenceID: String
        let isEntry: Bool
        let date: Date
    }

    private(set) var authorization: CLAuthorizationStatus
    private(set) var monitoredIDs: Set<String> = []
    private(set) var totalGeofences = 0
    private(set) var isSharingPaused: Bool
    private var states: [String: RegionState] = [:]

    @ObservationIgnored var onExit: ((Geofence, Date) -> Void)?
    @ObservationIgnored var onEntry: ((Geofence, Date) -> Void)?

    @ObservationIgnored private let locationManager = CLLocationManager()
    @ObservationIgnored private let defaults = UserDefaults.standard
    @ObservationIgnored private var monitorTask: Task<CLMonitor, Never>?
    @ObservationIgnored private var syncTask: Task<Void, Never>?
    @ObservationIgnored private var geofences: [Geofence] = []
    @ObservationIgnored private var pendingCrossings: [PendingCrossing] = []
    @ObservationIgnored private var activeIdentifiers: [String: String] = [:]

    override init() {
        authorization = locationManager.authorizationStatus
        isSharingPaused = UserDefaults.standard.bool(forKey: Self.sharingPausedKey)
        super.init()
        states = savedStates()
        locationManager.delegate = self
        UNUserNotificationCenter.current().delegate = self
        openMonitorIfAuthorized()
    }

    var isAuthorized: Bool {
        authorization == .authorizedAlways || authorization == .authorizedWhenInUse
    }

    private func openMonitorIfAuthorized() {
        guard isAuthorized, monitorTask == nil else { return }
        let task = Task { await CLMonitor("GeoCircleGeofences") }
        monitorTask = task
        Task { await listenForEvents(from: task.value) }
    }

    func requestLocationPermission() {
        locationManager.requestAlwaysAuthorization()
    }

    func sync(geofences: [Geofence]) {
        self.geofences = geofences
        totalGeofences = geofences.count
        deliverPendingCrossings()
        scheduleSync()
    }

    func setSharingPaused(_ paused: Bool) {
        guard paused != isSharingPaused else { return }
        isSharingPaused = paused
        defaults.set(paused, forKey: Self.sharingPausedKey)
        pendingCrossings.removeAll()
        scheduleSync()
    }

    func stateText(for geofence: Geofence) -> String {
        if isSharingPaused { return "Paused" }
        guard monitoredIDs.contains(geofence.id) else { return "Not monitored" }
        switch states[geofence.id] {
        case RegionState.inside: return "Inside"
        case RegionState.outside: return "Outside"
        default: return "Checking…"
        }
    }

    private func scheduleSync() {
        let previous = syncTask
        syncTask = Task {
            await previous?.value
            await applySync()
        }
    }

    private func applySync() async {
        guard let monitor = await monitorTask?.value else {
            monitoredIDs = []
            return
        }
        let wanted = isAuthorized && !isSharingPaused
            ? GeofenceMonitoring.shared.selectForMonitoring(
                geofences: geofences,
                currentLocation: locationManager.location.map { GeoPoint($0.coordinate) },
                limit: GeofenceMonitoring.shared.IOS_REGION_LIMIT
            )
            : []
        let wantedByID = Dictionary(wanted.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        for identifier in await monitor.identifiers {
            let geofenceID = Self.geofenceID(from: identifier)
            if let geofence = wantedByID[geofenceID],
               (activeIdentifiers[geofenceID] ?? identifier) == identifier,
               await isRegistered(identifier, matching: geofence, in: monitor) {
                activeIdentifiers[geofenceID] = identifier
                continue
            }
            if activeIdentifiers[geofenceID] == identifier {
                activeIdentifiers[geofenceID] = nil
            }
            await monitor.remove(identifier)
        }
        for geofence in wanted where activeIdentifiers[geofence.id] == nil {
            let identifier = Self.newIdentifier(for: geofence)
            activeIdentifiers[geofence.id] = identifier
            setState(.unknown, for: geofence.id)
            let condition = CLMonitor.CircularGeographicCondition(
                center: geofence.center.coordinate,
                radius: geofence.radiusMeters
            )
            await monitor.add(condition, identifier: identifier)
        }
        for geofenceID in Array(activeIdentifiers.keys) where wantedByID[geofenceID] == nil {
            activeIdentifiers[geofenceID] = nil
        }
        for geofenceID in Array(states.keys) where activeIdentifiers[geofenceID] == nil {
            setState(nil, for: geofenceID)
        }
        monitoredIDs = Set(activeIdentifiers.keys)
    }

    private func isRegistered(_ identifier: String, matching geofence: Geofence, in monitor: CLMonitor) async -> Bool {
        guard let registered = await monitor.record(for: identifier)?.condition as? CLMonitor.CircularGeographicCondition else {
            return false
        }
        return GeofenceMonitoring.shared.isSameRegion(
            center: GeoPoint(registered.center),
            radiusMeters: registered.radius,
            otherCenter: geofence.center,
            otherRadiusMeters: geofence.radiusMeters
        )
    }

    private static func newIdentifier(for geofence: Geofence) -> String {
        "\(geofence.id)\(identifierSeparator)\(UUID().uuidString)"
    }

    private static func geofenceID(from identifier: String) -> String {
        String(identifier.split(separator: identifierSeparator, maxSplits: 1).first ?? Substring(identifier))
    }

    private func listenForEvents(from monitor: CLMonitor) async {
        for identifier in await monitor.identifiers {
            let geofenceID = Self.geofenceID(from: identifier)
            if activeIdentifiers[geofenceID] == nil {
                activeIdentifiers[geofenceID] = identifier
            }
        }
        do {
            for try await event in await monitor.events {
                handle(identifier: event.identifier, state: event.state, date: event.date)
            }
        } catch {
        }
    }

    private func handle(identifier: String, state: CLMonitor.Event.State, date: Date) {
        let geofenceID = Self.geofenceID(from: identifier)
        guard !isSharingPaused, activeIdentifiers[geofenceID] == identifier else { return }
        let newState: RegionState = switch state {
        case .satisfied: .inside
        case .unsatisfied: .outside
        default: .unknown
        }
        let previous = states[geofenceID] ?? .unknown
        setState(newState, for: geofenceID)

        let crossing: PendingCrossing
        if GeofenceMonitoring.shared.isExit(previous: previous, current: newState) {
            crossing = PendingCrossing(geofenceID: geofenceID, isEntry: false, date: date)
        } else if GeofenceMonitoring.shared.isEntry(previous: previous, current: newState) {
            crossing = PendingCrossing(geofenceID: geofenceID, isEntry: true, date: date)
        } else {
            return
        }
        if let geofence = geofences.first(where: { $0.id == geofenceID }) {
            report(crossing, at: geofence)
        } else {
            holdUntilGeofencesLoad(crossing)
        }
    }

    private func report(_ crossing: PendingCrossing, at geofence: Geofence) {
        if crossing.isEntry {
            onEntry?(geofence, crossing.date)
        } else {
            onExit?(geofence, crossing.date)
        }
    }

    private func holdUntilGeofencesLoad(_ crossing: PendingCrossing) {
        guard !pendingCrossings.contains(crossing) else { return }
        pendingCrossings.append(crossing)
        if pendingCrossings.count > Self.pendingCrossingLimit {
            pendingCrossings.removeFirst()
        }
    }

    private func deliverPendingCrossings() {
        let crossings = pendingCrossings
        pendingCrossings.removeAll()
        for crossing in crossings {
            if let geofence = geofences.first(where: { $0.id == crossing.geofenceID }) {
                report(crossing, at: geofence)
            }
        }
    }

    private func setState(_ state: RegionState?, for identifier: String) {
        states[identifier] = state
        defaults.set(states.mapValues(\.name), forKey: Self.regionStatesKey)
    }

    private func savedStates() -> [String: RegionState] {
        let names = defaults.dictionary(forKey: Self.regionStatesKey) as? [String: String] ?? [:]
        let knownStates = [RegionState.inside, RegionState.outside, RegionState.unknown]
        return names.compactMapValues { name in knownStates.first { $0.name == name } }
    }
}

extension GeofenceMonitor: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        MainActor.assumeIsolated {
            authorization = status
            openMonitorIfAuthorized()
            scheduleSync()
        }
    }
}

extension GeofenceMonitor: UNUserNotificationCenterDelegate {
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        notification.request.trigger is UNPushNotificationTrigger ? [] : [.banner, .list, .sound]
    }
}
