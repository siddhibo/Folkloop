import SwiftUI
import Shared

/// Shows whether exit monitoring is running and lets the user grant permissions.
struct ExitAlertsSection: View {
    @Environment(GeofenceMonitor.self) private var monitor
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            switch monitor.authorization {
            case .notDetermined:
                Button("Enable Exit Alerts", systemImage: "location") {
                    monitor.requestPermissions()
                }
            case .denied, .restricted:
                Text("Location access is off, so exits can't be detected.")
                Button("Open Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            default:
                Text(statusText)
            }
            if let lastExit = monitor.lastExitMessage {
                Text(lastExit)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Exit Alerts")
        } footer: {
            Text("Alerts appear on this iPhone only. Other group members are not notified yet.")
        }
    }

    private var statusText: String {
        let limit = Int(GeofenceMonitoring.shared.IOS_REGION_LIMIT)
        var text = "Monitoring \(monitor.monitoredIDs.count) of \(monitor.totalGeofences) geofences."
        if monitor.totalGeofences > limit {
            text += " iOS allows \(limit), so the nearest are chosen."
        }
        if monitor.authorization == .authorizedWhenInUse {
            text += " Alerts need GeoCircle in use; choose Always in Settings for background alerts."
        }
        return text
    }
}
