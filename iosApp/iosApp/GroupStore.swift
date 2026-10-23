import CoreLocation
import FirebaseFirestore
import Observation
import Shared

/// Keeps the signed-in user's groups in sync with Firestore and shares geofence exits with the group.
///
/// Input rules come from the Kotlin `Validation`, `JoinCodes` and `MemberAlerts` objects, and
/// `backend/firestore.rules` enforces the same limits on the server.
/// Other members' exits arrive through live Firestore listeners, so they only reach this device while
/// GeoCircle is running. They are not remote push notifications.
@MainActor
@Observable
final class GroupStore {
    private(set) var groups: [TrackingGroup] = []
    private(set) var latestAlert: String?
    private var geofencesByGroup: [String: [Geofence]] = [:]
    private var membersByGroup: [String: [GroupMember]] = [:]
    private var joinCodesByGroup: [String: String] = [:]

    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var user: SignedInUser?
    @ObservationIgnored private var groupsListener: ListenerRegistration?
    @ObservationIgnored private var groupListeners: [String: [ListenerRegistration]] = [:]

    var allGeofences: [Geofence] {
        groups.flatMap { geofences(in: $0) }
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

    // MARK: - Listening

    /// Starts listening for the user's groups, or clears everything when nobody is signed in.
    func start(for user: SignedInUser?) {
        stopListening()
        self.user = user
        groups = []
        geofencesByGroup = [:]
        membersByGroup = [:]
        joinCodesByGroup = [:]
        latestAlert = nil
        guard let user else { return }

        // Metadata changes tell us when a group created on this device has reached the server.
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

        let groupIDs = Set(groups.map(\.id))
        for (groupID, listeners) in groupListeners where !groupIDs.contains(groupID) {
            listeners.forEach { $0.remove() }
            groupListeners[groupID] = nil
            geofencesByGroup[groupID] = nil
            membersByGroup[groupID] = nil
        }
        // A group created here appears before the server has saved it. The security rules would reject
        // listeners attached that early (and Firestore never retries a rejected listener), so wait for the server.
        let savedGroupIDs = snapshot.documents.filter { !$0.metadata.hasPendingWrites }.map(\.documentID)
        for groupID in savedGroupIDs where groupListeners[groupID] == nil {
            groupListeners[groupID] = listen(toGroup: groupID)
        }
    }

    private func listen(toGroup groupID: String) -> [ListenerRegistration] {
        let groupRef = db.collection("groups").document(groupID)

        let geofences = groupRef.collection("geofences").addSnapshotListener { [weak self] snapshot, _ in
            guard let snapshot else { return }
            MainActor.assumeIsolated {
                self?.geofencesByGroup[groupID] = snapshot.documents
                    .compactMap { Self.geofence(from: $0, groupID: groupID) }
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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

        // Only exits reported from now on become alerts; the first snapshot is history and is skipped.
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
        show(MemberAlerts.shared.alert(event: event, groupName: groupName))
    }

    private func show(_ alert: ExitAlert) {
        latestAlert = alert.body
        LocalNotifications.post(alert)
    }

    // MARK: - Changes

    func createGroup(named rawName: String) async throws {
        let user = try requireUser()
        if let error = Validation.shared.nameError(name: rawName) {
            throw UserFacingError(message: error)
        }
        let groupRef = db.collection("groups").document()
        let code = JoinCodes.shared.generate()

        // The group, its join code and the owner's membership are created together or not at all.
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

        // The security rules accept the new member only if this document carries the right join code.
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
        let point = Shared.GeoPoint(center)
        if let error = Validation.shared.nameError(name: rawName)
            ?? Validation.shared.coordinateError(point: point)
            ?? Validation.shared.radiusError(radiusMeters: radiusMeters) {
            throw UserFacingError(message: error)
        }
        _ = try await db.collection("groups").document(group.id).collection("geofences").addDocument(data: [
            "name": rawName.trimmingCharacters(in: .whitespacesAndNewlines),
            "latitude": center.latitude,
            "longitude": center.longitude,
            "radiusMeters": radiusMeters,
            "createdBy": user.uid,
        ])
    }

    func deleteGeofence(_ geofence: Geofence) async throws {
        try await db.collection("groups").document(geofence.groupId)
            .collection("geofences").document(geofence.id).delete()
    }

    /// Called when this device leaves a geofence: alerts here and shares the exit with the group.
    func recordExit(from geofence: Geofence) {
        guard let user, let group = groups.first(where: { $0.id == geofence.groupId }) else { return }
        let members = members(in: group)
        let others = MemberAlerts.shared.recipients(members: members, exitingMemberId: user.uid)
        show(GeofenceMonitoring.shared.exitAlert(geofence: geofence, groupName: group.name, otherMemberCount: Int32(others.count)))

        let memberName = members.first { $0.id == user.uid }?.displayName ?? user.displayName
        db.collection("groups").document(group.id).collection("exitEvents").addDocument(data: [
            "memberId": user.uid,
            "memberName": memberName,
            "geofenceId": geofence.id,
            "geofenceName": geofence.name,
            "occurredAt": FieldValue.serverTimestamp(),
        ]) { [weak self] error in
            guard let error else { return }
            MainActor.assumeIsolated {
                self?.latestAlert = "Couldn't share your exit with the group: \(error.localizedDescription)"
            }
        }
    }

    private func requireUser() throws -> SignedInUser {
        guard let user else { throw UserFacingError(message: "Please sign in again.") }
        return user
    }

    // MARK: - Reading documents

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
            geofenceName: geofenceName
        )
    }
}
