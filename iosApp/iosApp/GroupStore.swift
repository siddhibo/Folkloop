import CoreLocation
import Observation
import Shared

/// Connects SwiftUI to the Kotlin repository.
/// Validation and storage happen in Kotlin; this class only keeps the screens up to date.
@MainActor
@Observable
final class GroupStore {
    private(set) var groups: [TrackingGroup] = []
    private var geofencesByGroup: [String: [Geofence]] = [:]
    private var membersByGroup: [String: [GroupMember]] = [:]

    @ObservationIgnored private let repository: any GroupRepository

    init(repository: any GroupRepository = InMemoryGroupRepository()) {
        self.repository = repository
        reload()
    }

    func geofences(in group: TrackingGroup) -> [Geofence] {
        geofencesByGroup[group.id] ?? []
    }

    var allGeofences: [Geofence] {
        groups.flatMap { geofences(in: $0) }
    }

    var groupNamesByID: [String: String] {
        Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.name) })
    }

    func members(in group: TrackingGroup) -> [GroupMember] {
        membersByGroup[group.id] ?? []
    }

    /// Throws with a readable message when Kotlin validation fails.
    func createGroup(named name: String) throws {
        _ = try repository.createGroup(name: name)
        reload()
    }

    func addGeofence(to group: TrackingGroup, name: String, center: CLLocationCoordinate2D, radiusMeters: Double) throws {
        _ = try repository.addGeofence(groupId: group.id, name: name, center: GeoPoint(center), radiusMeters: radiusMeters)
        reload()
    }

    func deleteGeofence(_ geofence: Geofence) {
        repository.deleteGeofence(geofenceId: geofence.id)
        reload()
    }

    func addSimulatedMember(to group: TrackingGroup, named displayName: String) throws {
        _ = try repository.addSimulatedMember(groupId: group.id, displayName: displayName)
        reload()
    }

    private func reload() {
        groups = repository.groups()
        geofencesByGroup = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, repository.geofences(groupId: $0.id)) })
        membersByGroup = Dictionary(uniqueKeysWithValues: groups.map { ($0.id, repository.members(groupId: $0.id)) })
    }
}
