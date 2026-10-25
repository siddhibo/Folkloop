import SwiftUI

struct ActivityDashboardView: View {
    @Environment(GroupStore.self) private var store
    @State private var activity = ActivityStore()
    @State private var range = ActivityRange.lastSevenDays
    @State private var selectedGroupID: String?

    var body: some View {
        let summary = ActivitySummary(events: visibleEvents, groupNames: groupNames, range: range)
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                filters
                content(for: summary)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Activity")
        .onChange(of: store.groups.map(\.id), initial: true) { _, groupIDs in
            listen(toGroups: Set(groupIDs))
        }
        .onDisappear { activity.stop() }
    }

    private var groupNames: [String: String] {
        Dictionary(store.groups.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
    }

    private var visibleEvents: [ActivityEvent] {
        guard let selectedGroupID else { return activity.events }
        return activity.events.filter { $0.groupID == selectedGroupID }
    }

    private var failedGroupNames: [String] {
        activity.failedGroupIDs.map { groupNames[$0] ?? "a group" }.sorted()
    }

    private func listen(toGroups groupIDs: Set<String>) {
        if let selectedGroupID, !groupIDs.contains(selectedGroupID) {
            self.selectedGroupID = nil
        }
        activity.listen(toGroups: groupIDs, since: ActivityRange.lastThirtyDays.firstDay(endingOn: .now))
    }

    private var filters: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Period", selection: $range) {
                ForEach(ActivityRange.allCases) { range in
                    Text(range.shortTitle).tag(range)
                }
            }
            .pickerStyle(.segmented)

            HStack {
                Text("Group")
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("Group", selection: $selectedGroupID) {
                    Text("All groups").tag(String?.none)
                    ForEach(store.groups) { group in
                        Text(group.name).tag(Optional(group.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("groupFilter")
            }
            .disabled(store.groups.isEmpty)
        }
    }

    @ViewBuilder
    private func content(for summary: ActivitySummary) -> some View {
        if store.groups.isEmpty {
            DashboardCard {
                ContentUnavailableView(
                    "No groups yet",
                    systemImage: "person.3",
                    description: Text("Create or join a group to see its exit activity here.")
                )
            }
        } else if activity.isLoading {
            DashboardCard {
                ProgressView("Loading activity…")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            }
        } else {
            statusNotes
            ActivitySummaryTiles(summary: summary, range: range)
            if summary.periodCount == 0 {
                DashboardCard {
                    ContentUnavailableView(
                        "No exits recorded",
                        systemImage: "chart.line.flattrend.xyaxis",
                        description: Text("Nobody has left a geofence in the \(range.title.lowercased()). Folkloop records exits only, not entries or time spent in a place.")
                    )
                }
            } else {
                DailyExitsCard(dailyCounts: summary.dailyCounts, range: range)
                if selectedGroupID == nil {
                    GroupBreakdownCard(groupCounts: summary.groupCounts, range: range)
                }
                DashboardCard("Most exited geofences", subtitle: "Top \(ActivitySummary.geofenceRankingLimit) · \(range.title)") {
                    RankedExitsChart(items: summary.geofenceCounts, showsGroupName: selectedGroupID == nil)
                }
                ActivityFeedCard(sections: summary.feedSections, groupNames: groupNames)
            }
        }
    }

    @ViewBuilder
    private var statusNotes: some View {
        if activity.isShowingCachedData {
            StatusNote(systemImage: "wifi.slash", text: "Showing activity saved on this device. New exits appear once Folkloop reconnects.")
        }
        if !failedGroupNames.isEmpty {
            StatusNote(systemImage: "exclamationmark.triangle", text: "Couldn't load activity for \(failedGroupNames.formatted(.list(type: .and))). Reopen this screen to try again.")
        }
        if !activity.truncatedGroupIDs.isEmpty {
            StatusNote(systemImage: "info.circle", text: "Only the latest \(ActivityStore.eventLimitPerGroup) exits per group are included.")
        }
    }
}

struct DashboardCard<Content: View>: View {
    private let title: String?
    private let subtitle: String?
    private let content: Content

    init(_ title: String? = nil, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let title {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle {
                        Text(subtitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isHeader)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
    }
}

private struct StatusNote: View {
    let systemImage: String
    let text: String

    var body: some View {
        Label(text, systemImage: systemImage)
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 12, style: .continuous))
    }
}

private struct ActivitySummaryTiles: View {
    let summary: ActivitySummary
    let range: ActivityRange

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12, alignment: .top)], spacing: 12) {
            SummaryTile(title: "Today", value: summary.todayCount, caption: exitCaption(summary.todayCount), identifier: "todayExitCount")
            SummaryTile(title: range.shortTitle, value: summary.periodCount, caption: exitCaption(summary.periodCount), identifier: "periodExitCount")
            SummaryTile(title: "Members", value: summary.memberCount, caption: "with exits", identifier: "memberCount")
        }
    }

    private func exitCaption(_ count: Int) -> String {
        count == 1 ? "exit" : "exits"
    }
}

private struct SummaryTile: View {
    let title: String
    let value: Int
    let caption: String
    let identifier: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Text(value, format: .number)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
            Text(caption)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue("\(value) \(caption)")
        .accessibilityIdentifier(identifier)
    }
}

private struct GroupBreakdownCard: View {
    let groupCounts: [RankedExitCount]
    let range: ActivityRange

    var body: some View {
        DashboardCard("Exits by group", subtitle: range.title) {
            if groupCounts.count > 1 {
                RankedExitsChart(items: groupCounts, showsGroupName: false)
            } else if let onlyGroup = groupCounts.first {
                Text("All \(onlyGroup.count) \(onlyGroup.count == 1 ? "exit" : "exits") came from \(onlyGroup.name).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct ActivityFeedCard: View {
    let sections: [ActivityFeedSection]
    let groupNames: [String: String]

    var body: some View {
        DashboardCard("Recent activity") {
            LazyVStack(alignment: .leading, spacing: 18) {
                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(section.day.rawValue)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .accessibilityAddTraits(.isHeader)
                        ForEach(section.events) { event in
                            ActivityRow(
                                event: event,
                                groupName: groupNames[event.groupID] ?? "Unknown group",
                                showsDate: section.day == .earlier
                            )
                        }
                    }
                }
            }
        }
    }
}

private struct ActivityRow: View {
    let event: ActivityEvent
    let groupName: String
    let showsDate: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "figure.walk.departure")
                .font(.subheadline)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .background(Color.accentColor.opacity(0.12), in: .circle)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(event.memberName) left \(event.geofenceName)")
                    .font(.subheadline.weight(.medium))
                Text("\(groupName) · \(timestamp)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            syncStatus
        }
        .accessibilityElement(children: .combine)
    }

    private var timestamp: String {
        event.occurredAt.formatted(showsDate ? .dateTime.month(.abbreviated).day().hour().minute() : .dateTime.hour().minute())
    }

    @ViewBuilder
    private var syncStatus: some View {
        if event.isWaitingToUpload {
            Label("Waiting to upload", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Image(systemName: "checkmark.icloud")
                .font(.footnote)
                .foregroundStyle(.tertiary)
                .accessibilityLabel("Saved")
        }
    }
}
