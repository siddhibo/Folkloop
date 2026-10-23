import SwiftUI
import Shared

/// Lists a group's members. Added members are local placeholders until the backend milestone.
struct MembersSection: View {
    @Environment(GroupStore.self) private var store
    let group: TrackingGroup
    let onAddMember: () -> Void

    var body: some View {
        Section {
            ForEach(store.members(in: group)) { member in
                HStack {
                    Text(member.displayName)
                    Spacer()
                    Text(statusText(member.status))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Button("Add Simulated Member", systemImage: "person.badge.plus", action: onAddMember)
        } header: {
            Text("Members")
        } footer: {
            Text("Simulated members exist only on this device. No invitation is sent.")
        }
    }

    private func statusText(_ status: MembershipStatus) -> String {
        status == .owner ? "Owner" : "Simulated"
    }
}

struct NewMemberView: View {
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var displayName = ""
    @State private var errorMessage: String?
    let group: TrackingGroup

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Member name", text: $displayName)
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("This adds a local placeholder for testing. Nobody is contacted.")
                }
            }
            .navigationTitle("Simulated Member")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add", action: add)
                }
            }
        }
    }

    private func add() {
        do {
            try store.addSimulatedMember(to: group, named: displayName)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
