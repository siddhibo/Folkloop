import SwiftUI
import Shared

struct GroupsListView: View {
    @Environment(GroupStore.self) private var store
    @Environment(SessionStore.self) private var session
    @Environment(NotificationPermission.self) private var notifications
    @Environment(PushRegistration.self) private var push
    @Environment(\.scenePhase) private var scenePhase
    @State private var isCreatingGroup = false
    @State private var isJoiningGroup = false

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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        Task {
                            await push.unregister()
                            session.signOut()
                        }
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ActivityDashboardView()
                    } label: {
                        Label("Activity", systemImage: "chart.xyaxis.line")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Join Group", systemImage: "person.badge.plus") {
                        isJoiningGroup = true
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("New Group", systemImage: "plus") {
                        isCreatingGroup = true
                    }
                }
            }
            .sheet(isPresented: $isCreatingGroup) {
                NewGroupView()
            }
            .sheet(isPresented: $isJoiningGroup) {
                JoinGroupView()
            }
        }
        .task { await notifications.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await notifications.refresh() }
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
    @State private var isCreating = false

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
                        .disabled(isCreating)
                }
            }
        }
    }

    private func create() {
        isCreating = true
        Task {
            do {
                try await store.createGroup(named: name)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isCreating = false
        }
    }
}

