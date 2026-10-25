import Foundation

struct ActivityEvent: Identifiable, Equatable {
    let id: String
    let groupID: String
    let memberID: String
    let memberName: String
    let geofenceID: String
    let geofenceName: String
    let occurredAt: Date
    let isWaitingToUpload: Bool
    let isEntry: Bool
}

enum ActivityRange: Int, CaseIterable, Identifiable {
    case lastSevenDays = 7
    case lastThirtyDays = 30

    var id: Int { rawValue }
    var shortTitle: String { "\(rawValue) days" }
    var title: String { "Last \(rawValue) days" }

    func firstDay(endingOn date: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: date)
        return calendar.date(byAdding: .day, value: 1 - rawValue, to: today) ?? today
    }
}

struct DailyExitCount: Identifiable {
    let day: Date
    let count: Int
    var id: Date { day }
}

struct RankedExitCount: Identifiable {
    let id: String
    let name: String
    let groupName: String?
    let count: Int

    func label(showingGroup: Bool) -> String {
        guard showingGroup, let groupName else { return name }
        return "\(name) · \(groupName)"
    }
}

enum ActivityDay: String {
    case today = "Today"
    case yesterday = "Yesterday"
    case earlier = "Earlier"
}

struct ActivityFeedSection: Identifiable {
    let day: ActivityDay
    let events: [ActivityEvent]
    var id: ActivityDay { day }
}

struct ActivitySummary {
    let todayCount: Int
    let periodCount: Int
    let memberCount: Int
    let dailyCounts: [DailyExitCount]
    let groupCounts: [RankedExitCount]
    let geofenceCounts: [RankedExitCount]
    let feedSections: [ActivityFeedSection]

    static let geofenceRankingLimit = 5

    init(events: [ActivityEvent], groupNames: [String: String], range: ActivityRange, now: Date = .now, calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        let periodStart = range.firstDay(endingOn: now, calendar: calendar)
        let periodEvents = events
            .filter { !$0.isEntry && $0.occurredAt >= periodStart }
            .sorted { $0.occurredAt > $1.occurredAt }
        let eventsByDay = Dictionary(grouping: periodEvents) { min(calendar.startOfDay(for: $0.occurredAt), today) }

        todayCount = eventsByDay[today]?.count ?? 0
        periodCount = periodEvents.count
        memberCount = Set(periodEvents.map(\.memberID)).count
        dailyCounts = (0..<range.rawValue).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: periodStart) else { return nil }
            let day = calendar.startOfDay(for: date)
            return DailyExitCount(day: day, count: eventsByDay[day]?.count ?? 0)
        }
        groupCounts = Dictionary(grouping: periodEvents, by: \.groupID)
            .map { groupID, groupEvents in
                RankedExitCount(id: groupID, name: groupNames[groupID] ?? "Unknown group", groupName: nil, count: groupEvents.count)
            }
            .sorted(by: Self.mostExitsFirst)
        geofenceCounts = Array(
            Dictionary(grouping: periodEvents) { "\($0.groupID)/\($0.geofenceID)" }
                .compactMap { key, geofenceEvents in
                    geofenceEvents.first.map { latest in
                        RankedExitCount(
                            id: key,
                            name: latest.geofenceName,
                            groupName: groupNames[latest.groupID] ?? "Unknown group",
                            count: geofenceEvents.count
                        )
                    }
                }
                .sorted(by: Self.mostExitsFirst)
                .prefix(Self.geofenceRankingLimit)
        )
        feedSections = [
            ActivityFeedSection(day: .today, events: periodEvents.filter { $0.occurredAt >= today }),
            ActivityFeedSection(day: .yesterday, events: periodEvents.filter { $0.occurredAt >= yesterday && $0.occurredAt < today }),
            ActivityFeedSection(day: .earlier, events: periodEvents.filter { $0.occurredAt < yesterday }),
        ]
        .filter { !$0.events.isEmpty }
    }

    private static func mostExitsFirst(_ first: RankedExitCount, _ second: RankedExitCount) -> Bool {
        if first.count != second.count {
            return first.count > second.count
        }
        return first.name.localizedCaseInsensitiveCompare(second.name) == .orderedAscending
    }
}
