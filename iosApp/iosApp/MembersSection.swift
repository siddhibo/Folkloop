import SwiftUI
import Shared

struct MembersSection: View {
    @Environment(GroupStore.self) private var store
    @Environment(SessionStore.self) private var session
    let group: TrackingGroup
    let lastEvents: [String: ActivityEvent]
    let isStatusLoading: Bool
    let isStatusUnavailable: Bool
    let onRemove: (GroupMember) -> Void

    var body: some View {
        Section {
            ForEach(store.members(in: group)) { member in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(member.id == session.user?.uid ? "\(member.displayName) (You)" : member.displayName)
                        if let status = statusText(for: member) {
                            Text(status)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(member.status == .owner ? "Owner" : "Member")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .swipeActions {
                    if store.isOwner(of: group) && member.status != .owner {
                        Button("Remove", systemImage: "person.badge.minus", role: .destructive) {
                            onRemove(member)
                        }
                    }
                }
            }
            if let code = store.joinCode(for: group) {
                HStack {
                    Text("Join code")
                    Spacer()
                    Text(code)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                        .accessibilityIdentifier("joinCode")
                }
                ShareLink(
                    item: "Join my Folkloop group \"\(group.name)\" with the code \(code). Open Folkloop, tap Join Group and enter the code.",
                    subject: Text("Join \(group.name) on Folkloop")
                ) {
                    Label("Invite", systemImage: "square.and.arrow.up")
                }
            }
        } header: {
            Text("Members")
        } footer: {
            Text("Share the join code so others can join. Nobody is added until they enter the code themselves. Members see each other's activity only while Folkloop is open. Each member's last recorded arrival or exit is shown, not their live location.")
        }
    }

    private func statusText(for member: GroupMember) -> String? {
        if isStatusUnavailable {
            return "Last activity unavailable right now"
        }
        if isStatusLoading {
            return nil
        }
        guard let event = lastEvents[member.id] else {
            return "No activity recorded in the last 30 days"
        }
        let kind = event.isEntry ? "arrival" : "exit"
        let uploadNote = event.isWaitingToUpload ? " (waiting to upload)" : ""
        return "Last recorded \(kind): \(event.geofenceName), \(Self.whenText(for: event.occurredAt))\(uploadNote)"
    }

    static func whenText(for date: Date) -> String {
        if Date.now.timeIntervalSince(date) < 24 * 60 * 60 {
            return date.formatted(.relative(presentation: .named))
        }
        return date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
