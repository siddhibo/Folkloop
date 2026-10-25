import MapKit
import SwiftUI
import Shared

struct GroupDetailView: View {
    @Environment(GroupStore.self) private var store
    @Environment(GeofenceMonitor.self) private var monitor
    @Environment(\.dismiss) private var dismiss
    @State private var isAddingGeofence = false
    @State private var editingGeofence: Geofence?
    @State private var errorTitle = ""
    @State private var errorMessage: String?
    @State private var isConfirmingLeave = false
    @State private var memberToRemove: GroupMember?
    @State private var activity = ActivityStore()
    let group: TrackingGroup

    var body: some View {
        let geofences = store.geofences(in: group)

        List {
            if !geofences.isEmpty {
                Section {
                    GeofencesMap(geofences: geofences)
                        .id(geofences.map(\.id))
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                }
            }
            Section("Geofences") {
                if geofences.isEmpty {
                    Text("No geofences yet. Tap + to add an area for this group.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(geofences) { geofence in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(geofence.name)
                                    .font(.headline)
                                Text("\(Int(geofence.radiusMeters)) m · \(coordinateText(geofence.center))")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(monitor.stateText(for: geofence))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture { editingGeofence = geofence }
                        .swipeActions(edge: .leading) {
                            Button("Edit", systemImage: "pencil") { editingGeofence = geofence }
                                .tint(.accentColor)
                        }
                    }
                    .onDelete { offsets in
                        delete(offsets.map { geofences[$0] })
                    }
                }
            }
            MembersSection(
                group: group,
                lastEvents: lastEventByMember,
                isStatusLoading: activity.isLoading,
                isStatusUnavailable: !activity.failedGroupIDs.isEmpty,
                onRemove: { memberToRemove = $0 }
            )
            if !geofences.isEmpty {
                GroupPresenceSection(
                    geofences: geofences,
                    members: store.members(in: group),
                    events: activity.events,
                    isLoading: activity.isLoading,
                    isUnavailable: !activity.failedGroupIDs.isEmpty
                )
            }
        }
        .onAppear {
            activity.listen(toGroups: [group.id], since: ActivityRange.lastThirtyDays.firstDay(endingOn: .now))
        }
        .onDisappear { activity.stop() }
        .alert(errorTitle, isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog("Leave \(group.name)?", isPresented: $isConfirmingLeave, titleVisibility: .visible) {
            Button("Leave Group", role: .destructive, action: leave)
        } message: {
            Text("You'll stop sharing your arrivals and exits with this group and lose access to its activity.")
        }
        .confirmationDialog(
            "Remove \(memberToRemove?.displayName ?? "member")?",
            isPresented: Binding(get: { memberToRemove != nil }, set: { if !$0 { memberToRemove = nil } }),
            titleVisibility: .visible,
            presenting: memberToRemove
        ) { member in
            Button("Remove from Group", role: .destructive) { remove(member) }
        } message: { _ in
            Text("They'll lose access to this group's geofences and activity.")
        }
        .navigationTitle(group.name)
        .toolbar {
            if !store.isOwner(of: group) {
                Button("Leave Group", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    isConfirmingLeave = true
                }
            }
            Button("Add Geofence", systemImage: "plus") {
                isAddingGeofence = true
            }
        }
        .sheet(isPresented: $isAddingGeofence) {
            GeofenceEditorView(group: group)
        }
        .sheet(item: $editingGeofence) { geofence in
            GeofenceEditorView(group: group, editing: geofence)
        }
    }

    private var lastEventByMember: [String: ActivityEvent] {
        Dictionary(grouping: activity.events, by: \.memberID)
            .compactMapValues { events in events.max { $0.occurredAt < $1.occurredAt } }
    }

    private func delete(_ geofences: [Geofence]) {
        Task {
            for geofence in geofences {
                do {
                    try await store.deleteGeofence(geofence)
                } catch {
                    show("Couldn't Delete Geofence", error)
                }
            }
        }
    }

    private func leave() {
        Task {
            do {
                try await store.leave(group)
                dismiss()
            } catch {
                show("Couldn't Leave Group", error)
            }
        }
    }

    private func remove(_ member: GroupMember) {
        Task {
            do {
                try await store.remove(member, from: group)
            } catch {
                show("Couldn't Remove Member", error)
            }
        }
    }

    private func show(_ title: String, _ error: Error) {
        errorTitle = title
        errorMessage = error.localizedDescription
    }

    private func coordinateText(_ point: GeoPoint) -> String {
        String(format: "%.4f, %.4f", point.latitude, point.longitude)
    }
}

private struct GeofencesMap: View {
    let geofences: [Geofence]

    var body: some View {
        Map(initialPosition: .automatic) {
            ForEach(geofences) { geofence in
                MapCircle(center: geofence.center.coordinate, radius: geofence.radiusMeters)
                    .foregroundStyle(.blue.opacity(0.2))
                    .stroke(.blue, lineWidth: 2)
                Marker(geofence.name, coordinate: geofence.center.coordinate)
            }
        }
    }
}
