import SwiftUI
import Shared

struct GroupPresenceSection: View {
    let geofences: [Geofence]
    let members: [GroupMember]
    let events: [ActivityEvent]
    let isLoading: Bool
    let isUnavailable: Bool

    var body: some View {
        Section {
            if isUnavailable {
                Text("Presence is unavailable right now.")
                    .foregroundStyle(.secondary)
            } else if !isLoading {
                ForEach(geofences) { geofence in
                    GeofencePresenceRow(geofence: geofence, members: members, presence: presence(at: geofence))
                }
            }
        } header: {
            Text("Presence")
        } footer: {
            Text("Based on recorded arrivals and exits, not live location. Records older than 12 hours are stale, members without records are unknown, and neither counts as outside. Other members can't see when someone pauses sharing.")
        }
    }

    private func presence(at geofence: Geofence) -> [MemberPresence] {
        GroupPresence.shared.forGeofence(
            geofenceId: geofence.id,
            memberIds: members.map(\.id),
            crossings: events.map {
                RecordedCrossing(
                    memberId: $0.memberID,
                    geofenceId: $0.geofenceID,
                    isEntry: $0.isEntry,
                    occurredAtMillis: Int64($0.occurredAt.timeIntervalSince1970 * 1000)
                )
            },
            nowMillis: Int64(Date.now.timeIntervalSince1970 * 1000)
        )
    }
}

private struct GeofencePresenceRow: View {
    let geofence: Geofence
    let members: [GroupMember]
    let presence: [MemberPresence]

    var body: some View {
        DisclosureGroup {
            ForEach(presence, id: \.memberId) { memberPresence in
                HStack {
                    Text(name(of: memberPresence.memberId))
                    Spacer()
                    Text(statusText(for: memberPresence))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                }
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(geofence.name)
                    .font(.headline)
                Text("\(count(.inside)) inside · \(count(.outside)) outside · \(count(.stale) + count(.unknown)) unknown or stale · \(members.count) members")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func count(_ status: PresenceStatus) -> Int {
        presence.filter { $0.status == status }.count
    }

    private func name(of memberID: String) -> String {
        members.first { $0.id == memberID }?.displayName ?? "Former member"
    }

    private func statusText(for memberPresence: MemberPresence) -> String {
        guard let millis = memberPresence.lastRecordedAtMillis?.int64Value else { return "Unknown" }
        let when = MembersSection.whenText(for: Date(timeIntervalSince1970: Double(millis) / 1000))
        let action = memberPresence.lastWasEntry?.boolValue == true ? "arrived" : "left"
        switch memberPresence.status {
        case .inside: return "Inside · arrived \(when)"
        case .outside: return "Outside · left \(when)"
        case .stale: return "Stale · \(action) \(when)"
        default: return "Unknown"
        }
    }
}
