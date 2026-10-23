import SwiftUI
import Shared

struct GroupsListView: View {
    @Environment(GroupStore.self) private var store
    @State private var isCreatingGroup = false

    var body: some View {
        NavigationStack {
            List {
                ExitAlertsSection()
                Section("Groups") {
                    if store.groups.isEmpty {
                        Text("No groups yet. Tap + to create your first tracking group.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.groups) { group in
                        NavigationLink {
                            GroupDetailView(group: group)
                        } label: {
                            VStack(alignment: .leading) {
                                Text(group.name)
                                    .font(.headline)
                                Text(geofenceCountText(store.geofences(in: group).count))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Groups")
            .toolbar {
                Button("New Group", systemImage: "plus") {
                    isCreatingGroup = true
                }
            }
            .sheet(isPresented: $isCreatingGroup) {
                NewGroupView()
            }
        }
    }

    private func geofenceCountText(_ count: Int) -> String {
        count == 1 ? "1 geofence" : "\(count) geofences"
    }
}

struct NewGroupView: View {
    @Environment(GroupStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("Group name", text: $name)
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("New Group")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create", action: create)
                }
            }
        }
    }

    private func create() {
        do {
            try store.createGroup(named: name)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    GroupsListView()
        .environment(GroupStore())
        .environment(GeofenceMonitor())
}
