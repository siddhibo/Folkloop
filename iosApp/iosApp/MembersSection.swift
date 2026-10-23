import SwiftUI
import Shared

/// Lists a group's members and the code others use to join.
struct MembersSection: View {
    @Environment(GroupStore.self) private var store
    @Environment(SessionStore.self) private var session
    let group: TrackingGroup

    var body: some View {
        Section {
            ForEach(store.members(in: group)) { member in
                HStack {
                    Text(member.id == session.user?.uid ? "\(member.displayName) (You)" : member.displayName)
                    Spacer()
                    Text(member.status == .owner ? "Owner" : "Member")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
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
            }
        } header: {
            Text("Members")
        } footer: {
            Text("Share the join code so others can join. Members see each other's exits only while GeoCircle is open.")
        }
    }
}
