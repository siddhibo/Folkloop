import CoreLocation
import FirebaseFirestore
import Observation
import Shared

@MainActor
@Observable
final class GroupStore {
    private(set) var groups: [TrackingGroup] = []
    private(set) var latestAlert: String?
    private(set) var isLoadingGeofences = true
    private var geofencesByGroup: [String: [Geofence]] = [:]
    private var membersByGroup: [String: [GroupMember]] = [:]
    private var joinCodesByGroup: [String: String] = [:]
    private var ownerIDsByGroup: [String: String] = [:]

    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var user: SignedInUser?
    @ObservationIgnored private var groupsListener: ListenerRegistration?
    @ObservationIgnored private var groupListeners: [String: [ListenerRegistration]] = [:]
    @ObservationIgnored private var hasReceivedGroups = false
    @ObservationIgnored private var loadedGeofenceGroupIDs: Set<String> = []
    @ObservationIgnored private var sharedExitIDs: Set<String> = []

    var allGeofences: [Geofence] {
        groups.flatMap { geofences(in: $0) }
    }

    var geofencesToMonitor: [Geofence]? {
        isLoadingGeofences ? nil : allGeofences
    }

    func geofences(in group: TrackingGroup) -> [Geofence] {
        geofencesByGroup[group.id] ?? []
    }

    func members(in group: TrackingGroup) -> [GroupMember] {
        membersByGroup[group.id] ?? []
    }

    func joinCode(for group: TrackingGroup) -> String? {
        joinCodesByGroup[group.id]
    }

    func start(for user: SignedInUser?) {
        stopListening()
        self.user = user
        groups = []
        geofencesByGroup = [:]
        membersByGroup = [:]
        joinCodesByGroup = [:]
        ownerIDsByGroup = [:]
        latestAlert = nil
        hasReceivedGroups = false
        loadedGeofenceGroupIDs = []
        isLoadingGeofences = user != nil
        guard let user else { return }

        groupsListener = db.collection("groups")
            .whereField("memberIds", arrayContains: user.uid)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, _ in
                guard let snapshot else { return }
                MainActor.assumeIsolated { self?.updateGroups(from: snapshot) }
            }
    }

    private func stopListening() {
        groupsListener?.remove()
        groupsListener = nil
        groupListeners.values.flatMap { $0 }.forEach { $0.remove() }
        groupListeners = [:]
    }

    private func updateGroups(from snapshot: QuerySnapshot) {
        groups = snapshot.documents
            .map { TrackingGroup(id: $0.documentID, name: $0["name"] as? String ?? "") }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        joinCodesByGroup = Dictionary(uniqueKeysWithValues: snapshot.documents.map {
            ($0.documentID, $0["joinCode"] as? String ?? "")
        })
        ownerIDsByGroup = Dictionary(uniqueKeysWithValues: snapshot.documents.map {
            ($0.documentID, $0["ownerId"] as? String ?? "")
        })

        let groupIDs = Set(groups.map(\.id))
        for (groupID, listeners) in groupListeners where !groupIDs.contains(groupID) {
            listeners.forEach { $0.remove() }
            groupListeners[groupID] = nil
            geofencesByGroup[groupID] = nil
            membersByGroup[groupID] = nil
            loadedGeofenceGroupIDs.remove(groupID)
        }
        let savedGroupIDs = snapshot.documents.filter { !$0.metadata.hasPendingWrites }.map(\.documentID)
        for groupID in savedGroupIDs where groupListeners[groupID] == nil {
            groupListeners[groupID] = listen(toGroup: groupID)
        }
        if Self.isConfirmed(snapshot) {
            hasReceivedGroups = true
        }
        refreshGeofenceLoading()
    }

    private func refreshGeofenceLoading() {
        isLoadingGeofences = user != nil
            && (!hasReceivedGroups || !groupListeners.keys.allSatisfy(loadedGeofenceGroupIDs.contains))
    }

    private static func isConfirmed(_ snapshot: QuerySnapshot) -> Bool {
        !(snapshot.metadata.isFromCache && snapshot.isEmpty)
    }

    private func listen(toGroup groupID: String) -> [ListenerRegistration] {
        let groupRef = db.collection("groups").document(groupID)

        let geofences = groupRef.collection("geofences").addSnapshotListener { [weak self] snapshot, _ in
            guard let snapshot else { return }
            MainActor.assumeIsolated {
                guard let self else { return }
                self.geofencesByGroup[groupID] = snapshot.documents
                    .compactMap { Self.geofence(from: $0, groupID: groupID) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                if Self.isConfirmed(snapshot) {
                    self.loadedGeofenceGroupIDs.insert(groupID)
                }
                self.refreshGeofenceLoading()
            }
        }

        let members = groupRef.collection("members").addSnapshotListener { [weak self] snapshot, _ in
            guard let snapshot else { return }
            MainActor.assumeIsolated {
                self?.membersByGroup[groupID] = snapshot.documents
                    .compactMap { Self.member(from: $0, groupID: groupID) }
                    .sorted { ($0.status == .owner ? 0 : 1, $0.displayName) < ($1.status == .owner ? 0 : 1, $1.displayName) }
            }
        }

        var isFirstSnapshot = true
        let exits = groupRef.collection("exitEvents")
            .whereField("occurredAt", isGreaterThan: Timestamp(date: Date().addingTimeInterval(-60)))
            .addSnapshotListener { [weak self] snapshot, _ in
                guard let snapshot else { return }
                MainActor.assumeIsolated {
                    defer { isFirstSnapshot = false }
                    guard !isFirstSnapshot else { return }
                    for change in snapshot.documentChanges where change.type == .added {
                        self?.handleExitEvent(change.document, groupID: groupID)
                    }
                }
            }

        return [geofences, members, exits]
    }

    private func handleExitEvent(_ document: QueryDocumentSnapshot, groupID: String) {
        guard let user,
              let event = Self.exitEvent(from: document, groupID: groupID),
              MemberAlerts.shared.shouldAlert(currentUserId: user.uid, event: event)
        else { return }
        let groupName = groups.first { $0.id == groupID }?.name ?? "your group"
        show(MemberAlerts.shared.alert(event: event, groupName: groupName), id: event.id)
    }

    private func show(_ alert: ExitAlert, id: String) {
        latestAlert = alert.body
        LocalNotifications.post(alert, id: id)
    }

    func createGroup(named rawName: String) async throws {
        let user = try requireUser()
        if let error = Validation.shared.nameError(name: rawName) {
            throw UserFacingError(message: error)
        }
        let groupRef = db.collection("groups").document()
        let code = JoinCodes.shared.generate()

        let batch = db.batch()
        batch.setData([
            "name": rawName.trimmingCharacters(in: .whitespacesAndNewlines),
            "ownerId": user.uid,
            "joinCode": code,
            "memberIds": [user.uid],
            "createdAt": FieldValue.serverTimestamp(),
        ], forDocument: groupRef)
        batch.setData(["groupId": groupRef.documentID], forDocument: db.collection("joinCodes").document(code))
        batch.setData([
            "displayName": user.displayName,
            "status": "OWNER",
            "joinedAt": FieldValue.serverTimestamp(),
        ], forDocument: groupRef.collection("members").document(user.uid))
        try await batch.commit()
    }

    func joinGroup(code rawCode: String) async throws {
        let user = try requireUser()
        let code = JoinCodes.shared.normalize(input: rawCode)
        if let error = JoinCodes.shared.formatError(code: code) {
            throw UserFacingError(message: error)
        }
        let lookup = try await db.collection("joinCodes").document(code).getDocument()
        guard let groupID = lookup.data()?["groupId"] as? String else {
            throw UserFacingError(message: "No group uses that code.")
        }
        guard !groups.contains(where: { $0.id == groupID }) else {
            throw UserFacingError(message: "You're already in this group.")
        }

        let groupRef = db.collection("groups").document(groupID)
        let batch = db.batch()
        batch.setData([
            "displayName": user.displayName,
            "status": "MEMBER",
            "joinCode": code,
            "joinedAt": FieldValue.serverTimestamp(),
        ], forDocument: groupRef.collection("members").document(user.uid))
        batch.updateData(["memberIds": FieldValue.arrayUnion([user.uid])], forDocument: groupRef)
        try await batch.commit()
    }

    func addGeofence(to group: TrackingGroup, name rawName: String, center: CLLocationCoordinate2D, radiusMeters: Double) async throws {
        let user = try requireUser()
        try Self.validateGeofence(name: rawName, center: center, radiusMeters: radiusMeters)
        _ = try await db.collection("groups").document(group.id).collection("geofences").addDocument(data: [
            "name": rawName.trimmingCharacters(in: .whitespacesAndNewlines),
            "latitude": center.latitude,
            "longitude": center.longitude,
            "radiusMeters": radiusMeters,
            "createdBy": user.uid,
        ])
    }

    func updateGeofence(_ geofence: Geofence, name rawName: String, center: CLLocationCoordinate2D, radiusMeters: Double) async throws {
        _ = try requireUser()
        try Self.validateGeofence(name: rawName, center: center, radiusMeters: radiusMeters)
        do {
            try await geofenceRef(for: geofence).updateData([
                "name": rawName.trimmingCharacters(in: .whitespacesAndNewlines),
                "latitude": center.latitude,
                "longitude": center.longitude,
                "radiusMeters": radiusMeters,
            ])
        } catch where Self.isPermissionDenied(error) {
            throw UserFacingError(message: "Only the person who added this geofence or the group owner can edit it.")
        }
    }

    func deleteGeofence(_ geofence: Geofence) async throws {
        do {
            try await geofenceRef(for: geofence).delete()
        } catch where Self.isPermissionDenied(error) {
            throw UserFacingError(message: "Only the person who added this geofence or the group owner can delete it.")
        }
    }

    private func geofenceRef(for geofence: Geofence) -> DocumentReference {
        db.collection("groups").document(geofence.groupId).collection("geofences").document(geofence.id)
    }

    private static func validateGeofence(name rawName: String, center: CLLocationCoordinate2D, radiusMeters: Double) throws {
        if let error = Validation.shared.nameError(name: rawName)
            ?? Validation.shared.coordinateError(point: Shared.GeoPoint(center))
            ?? Validation.shared.radiusError(radiusMeters: radiusMeters) {
            throw UserFacingError(message: error)
        }
    }

    private static func isPermissionDenied(_ error: Error) -> Bool {
        let error = error as NSError
        return error.domain == FirestoreErrorDomain && error.code == FirestoreErrorCode.permissionDenied.rawValue
    }

    func recordExit(from geofence: Geofence, at occurredAt: Date) {
        guard let user, let group = groups.first(where: { $0.id == geofence.groupId }) else { return }
        let eventID = Self.eventID(memberID: user.uid, geofence: geofence, isEntry: false, occurredAt: occurredAt)
        guard sharedExitIDs.insert(eventID).inserted else { return }
        let members = members(in: group)
        let others = MemberAlerts.shared.recipients(members: members, exitingMemberId: user.uid)
        let eventRef = db.collection("groups").document(group.id).collection("exitEvents").document(eventID)
        let sharedAlert = GeofenceMonitoring.shared.exitAlert(geofence: geofence, groupName: group.name, otherMemberCount: Int32(others.count))
        let title = sharedAlert.title
        let sharedBody = sharedAlert.body
        let leftPlace = "You left \(geofence.name) (\(group.name))."
        show(ExitAlert(title: title, body: "\(leftPlace) Sharing your exit…"), id: eventID)

        let memberName = members.first { $0.id == user.uid }?.displayName ?? user.displayName
        eventRef.setData([
            "memberId": user.uid,
            "memberName": memberName,
            "geofenceId": geofence.id,
            "geofenceName": geofence.name,
            "occurredAt": FieldValue.serverTimestamp(),
            "type": "EXIT",
        ]) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let error else {
                    self.show(ExitAlert(title: title, body: sharedBody), id: eventID)
                    return
                }
                Task {
                    if await Self.wasSavedEarlier(eventRef, after: error) {
                        self.show(ExitAlert(title: title, body: sharedBody), id: eventID)
                    } else {
                        self.sharedExitIDs.remove(eventID)
                        LocalNotifications.post(ExitAlert(title: title, body: "\(leftPlace) Couldn't share it with the group."), id: eventID)
                        self.latestAlert = "Couldn't share your exit with the group: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    func recordEntry(into geofence: Geofence, at occurredAt: Date) {
        guard let user, let group = groups.first(where: { $0.id == geofence.groupId }) else { return }
        let eventID = Self.eventID(memberID: user.uid, geofence: geofence, isEntry: true, occurredAt: occurredAt)
        guard sharedExitIDs.insert(eventID).inserted else { return }
        let eventRef = db.collection("groups").document(group.id).collection("exitEvents").document(eventID)
        let memberName = members(in: group).first { $0.id == user.uid }?.displayName ?? user.displayName
        let geofenceName = geofence.name
        eventRef.setData([
            "memberId": user.uid,
            "memberName": memberName,
            "geofenceId": geofence.id,
            "geofenceName": geofence.name,
            "occurredAt": FieldValue.serverTimestamp(),
            "type": "ENTRY",
        ]) { [weak self] error in
            MainActor.assumeIsolated {
                guard let self, let error else { return }
                Task {
                    guard !(await Self.wasSavedEarlier(eventRef, after: error)) else { return }
                    self.sharedExitIDs.remove(eventID)
                    self.latestAlert = "Couldn't share your arrival at \(geofenceName): \(error.localizedDescription)"
                }
            }
        }
    }

    private static func eventID(memberID: String, geofence: Geofence, isEntry: Bool, occurredAt: Date) -> String {
        MemberAlerts.shared.eventId(
            memberId: memberID,
            geofenceId: geofence.id,
            isEntry: isEntry,
            occurredAtMillis: Int64((occurredAt.timeIntervalSince1970 * 1000).rounded())
        )
    }

    func leave(_ group: TrackingGroup) async throws {
        let user = try requireUser()
        try await removeMember(withID: user.uid, from: group)
    }

    func remove(_ member: GroupMember, from group: TrackingGroup) async throws {
        try await removeMember(withID: member.id, from: group)
    }

    func isOwner(of group: TrackingGroup) -> Bool {
        user != nil && ownerIDsByGroup[group.id] == user?.uid
    }

    private func removeMember(withID memberID: String, from group: TrackingGroup) async throws {
        let groupRef = db.collection("groups").document(group.id)
        let batch = db.batch()
        batch.updateData(["memberIds": FieldValue.arrayRemove([memberID])], forDocument: groupRef)
        batch.deleteDocument(groupRef.collection("members").document(memberID))
        do {
            try await batch.commit()
        } catch where Self.isPermissionDenied(error) {
            throw UserFacingError(message: "Only the group owner can remove members, and the owner can't leave the group.")
        }
    }

    private static func wasSavedEarlier(_ eventRef: DocumentReference, after error: Error) async -> Bool {
        guard isPermissionDenied(error) else { return false }
        return (try? await eventRef.getDocument(source: .server))?.exists ?? false
    }

    private func requireUser() throws -> SignedInUser {
        guard let user else { throw UserFacingError(message: "Please sign in again.") }
        return user
    }

    private static func geofence(from document: QueryDocumentSnapshot, groupID: String) -> Geofence? {
        guard let name = document["name"] as? String,
              let latitude = document["latitude"] as? Double,
              let longitude = document["longitude"] as? Double,
              let radius = document["radiusMeters"] as? Double
        else { return nil }
        return Geofence(
            id: document.documentID,
            groupId: groupID,
            name: name,
            center: Shared.GeoPoint(latitude: latitude, longitude: longitude),
            radiusMeters: radius
        )
    }

    private static func member(from document: QueryDocumentSnapshot, groupID: String) -> GroupMember? {
        guard let name = document["displayName"] as? String else { return nil }
        let status = document["status"] as? String == "OWNER" ? MembershipStatus.owner : MembershipStatus.member
        return GroupMember(id: document.documentID, groupId: groupID, displayName: name, status: status)
    }

    private static func exitEvent(from document: QueryDocumentSnapshot, groupID: String) -> ExitEvent? {
        guard let memberID = document["memberId"] as? String,
              let memberName = document["memberName"] as? String,
              let geofenceID = document["geofenceId"] as? String,
              let geofenceName = document["geofenceName"] as? String
        else { return nil }
        return ExitEvent(
            id: document.documentID,
            groupId: groupID,
            memberId: memberID,
            memberName: memberName,
            geofenceId: geofenceID,
            geofenceName: geofenceName,
            isEntry: document["type"] as? String == "ENTRY"
        )
    }
}
