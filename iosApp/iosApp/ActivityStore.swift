import FirebaseFirestore
import Observation

@MainActor
@Observable
final class ActivityStore {
    static let eventLimitPerGroup = 500

    private(set) var events: [ActivityEvent] = []
    private(set) var isLoading = false
    private(set) var failedGroupIDs: Set<String> = []
    private(set) var truncatedGroupIDs: Set<String> = []
    private(set) var cachedGroupIDs: Set<String> = []

    @ObservationIgnored private let db = Firestore.firestore()
    @ObservationIgnored private var listeners: [String: ListenerRegistration] = [:]
    @ObservationIgnored private var eventsByGroup: [String: [ActivityEvent]] = [:]
    @ObservationIgnored private var loadedGroupIDs: Set<String> = []

    var isShowingCachedData: Bool { !cachedGroupIDs.isEmpty }

    func listen(toGroups groupIDs: Set<String>, since start: Date) {
        for groupID in Array(listeners.keys) where !groupIDs.contains(groupID) {
            listeners.removeValue(forKey: groupID)?.remove()
            forget(groupID)
        }
        for groupID in groupIDs where listeners[groupID] == nil {
            listeners[groupID] = listener(forGroup: groupID, since: start)
        }
        publish()
    }

    func stop() {
        listeners.values.forEach { $0.remove() }
        listeners = [:]
        Array(eventsByGroup.keys).forEach(forget)
        publish()
    }

    private func listener(forGroup groupID: String, since start: Date) -> ListenerRegistration {
        db.collection("groups").document(groupID).collection("exitEvents")
            .whereField("occurredAt", isGreaterThanOrEqualTo: Timestamp(date: start))
            .order(by: "occurredAt", descending: true)
            .limit(to: Self.eventLimitPerGroup)
            .addSnapshotListener(includeMetadataChanges: true) { [weak self] snapshot, _ in
                MainActor.assumeIsolated {
                    self?.apply(snapshot, toGroup: groupID)
                }
            }
    }

    private func apply(_ snapshot: QuerySnapshot?, toGroup groupID: String) {
        guard listeners[groupID] != nil else { return }
        loadedGroupIDs.insert(groupID)
        if let snapshot {
            eventsByGroup[groupID] = snapshot.documents.compactMap { Self.event(from: $0, groupID: groupID) }
            failedGroupIDs.remove(groupID)
            update(&cachedGroupIDs, groupID, isIncluded: snapshot.metadata.isFromCache)
            update(&truncatedGroupIDs, groupID, isIncluded: snapshot.count >= Self.eventLimitPerGroup)
        } else {
            failedGroupIDs.insert(groupID)
        }
        publish()
    }

    private func forget(_ groupID: String) {
        eventsByGroup[groupID] = nil
        loadedGroupIDs.remove(groupID)
        failedGroupIDs.remove(groupID)
        truncatedGroupIDs.remove(groupID)
        cachedGroupIDs.remove(groupID)
    }

    private func publish() {
        events = eventsByGroup.values.flatMap { $0 }
        isLoading = !listeners.keys.allSatisfy(loadedGroupIDs.contains)
    }

    private func update(_ groupIDs: inout Set<String>, _ groupID: String, isIncluded: Bool) {
        if isIncluded {
            groupIDs.insert(groupID)
        } else {
            groupIDs.remove(groupID)
        }
    }

    private static func event(from document: QueryDocumentSnapshot, groupID: String) -> ActivityEvent? {
        let data = document.data(with: .estimate)
        guard let memberID = data["memberId"] as? String,
              let memberName = data["memberName"] as? String,
              let geofenceID = data["geofenceId"] as? String,
              let geofenceName = data["geofenceName"] as? String,
              let occurredAt = (data["occurredAt"] as? Timestamp)?.dateValue()
        else { return nil }
        return ActivityEvent(
            id: document.documentID,
            groupID: groupID,
            memberID: memberID,
            memberName: memberName,
            geofenceID: geofenceID,
            geofenceName: geofenceName,
            occurredAt: occurredAt,
            isWaitingToUpload: document.metadata.hasPendingWrites,
            isEntry: data["type"] as? String == "ENTRY"
        )
    }
}
