import Charts
import SwiftUI

struct DailyExitsCard: View {
    let dailyCounts: [DailyExitCount]
    let range: ActivityRange
    @State private var selectedDate: Date?

    var body: some View {
        DashboardCard("Exits per day", subtitle: range.title) {
            Chart {
                ForEach(dailyCounts) { day in
                    AreaMark(x: .value("Day", day.day, unit: .day), y: .value("Exits", day.count))
                        .foregroundStyle(Color.accentColor.opacity(0.12))
                        .accessibilityHidden(true)
                    LineMark(x: .value("Day", day.day, unit: .day), y: .value("Exits", day.count))
                        .foregroundStyle(Color.accentColor)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .accessibilityLabel(day.day.formatted(.dateTime.weekday(.wide).month().day()))
                        .accessibilityValue(exitText(day.count))
                    if range == .lastSevenDays {
                        PointMark(x: .value("Day", day.day, unit: .day), y: .value("Exits", day.count))
                            .foregroundStyle(Color.accentColor)
                            .symbolSize(36)
                            .accessibilityHidden(true)
                    }
                }
                if let selectedDay {
                    RuleMark(x: .value("Day", selectedDay.day, unit: .day))
                        .foregroundStyle(Color.secondary.opacity(0.35))
                        .lineStyle(StrokeStyle(lineWidth: 1))
                        .annotation(position: .top, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            SelectedDayCallout(day: selectedDay)
                        }
                        .accessibilityHidden(true)
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartGesture { proxy in
                SpatialTapGesture().onEnded { tap in
                    proxy.selectXValue(at: tap.location.x)
                }
            }
            .chartYScale(domain: 0...yUpperBound)
            .chartYAxis {
                AxisMarks(position: .leading, values: Array(stride(from: 0, through: yUpperBound, by: yStep))) {
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5))
                    AxisValueLabel()
                }
            }
            .chartXAxis {
                AxisMarks(values: xAxisDays) {
                    AxisValueLabel(format: xAxisFormat)
                }
            }
            .frame(height: 190)
        }
    }

    private var selectedDay: DailyExitCount? {
        guard let selectedDate else { return nil }
        return dailyCounts.first { Calendar.current.isDate($0.day, inSameDayAs: selectedDate) }
    }

    private var maxCount: Int {
        dailyCounts.map(\.count).max() ?? 0
    }

    private var yStep: Int {
        max(1, Int((Double(maxCount) / 3).rounded(.up)))
    }

    private var yUpperBound: Int {
        max(yStep, Int((Double(maxCount) / Double(yStep)).rounded(.up)) * yStep)
    }

    private var xAxisDays: [Date] {
        let labelledIndices = range == .lastSevenDays
            ? Array(dailyCounts.indices)
            : Array(stride(from: 2, to: dailyCounts.count, by: 7))
        return labelledIndices.map { dailyCounts[$0].day }
    }

    private var xAxisFormat: Date.FormatStyle {
        range == .lastSevenDays ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day()
    }
}

private struct SelectedDayCallout: View {
    let day: DailyExitCount

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(day.day, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(exitText(day.count))
                .font(.subheadline.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(.tertiarySystemGroupedBackground), in: .rect(cornerRadius: 8, style: .continuous))
    }
}

struct RankedExitsChart: View {
    let items: [RankedExitCount]
    let showsGroupName: Bool

    var body: some View {
        Chart(items) { item in
            BarMark(x: .value("Exits", item.count), y: .value("Name", item.id), height: .fixed(14))
                .foregroundStyle(Color.accentColor)
                .cornerRadius(4)
                .annotation(position: .trailing, alignment: .leading, spacing: 6) {
                    Text(item.count, format: .number)
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel(item.label(showingGroup: showsGroupName))
                .accessibilityValue(exitText(item.count))
        }
        .chartXScale(domain: 0...(Double(maxCount) * 1.2))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisValueLabel {
                    if let id = value.as(String.self) {
                        Text(label(for: id))
                            .font(.footnote)
                            .lineLimit(1)
                    }
                }
            }
        }
        .frame(height: CGFloat(items.count) * 36 + 8)
    }

    private var maxCount: Int {
        items.map(\.count).max() ?? 1
    }

    private func label(for id: String) -> String {
        items.first { $0.id == id }?.label(showingGroup: showsGroupName) ?? ""
    }
}

private func exitText(_ count: Int) -> String {
    count == 1 ? "1 exit" : "\(count) exits"
}
