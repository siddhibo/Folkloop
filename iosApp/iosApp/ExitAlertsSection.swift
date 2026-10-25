import SwiftUI
import Shared

struct ExitAlertsSection: View {
    @Environment(GeofenceMonitor.self) private var monitor
    @Environment(GroupStore.self) private var store
    @Environment(NotificationPermission.self) private var notifications
    @Environment(PushRegistration.self) private var push
    @Environment(\.openURL) private var openURL

    var body: some View {
        Section {
            Toggle("Share My Exits", isOn: Binding(
                get: { !monitor.isSharingPaused },
                set: { monitor.setSharingPaused(!$0) }
            ))
            .accessibilityIdentifier("shareExitsToggle")
            if monitor.isSharingPaused {
                Label("Paused on this device. Your geofences aren't being watched and no new exits are shared. Other members aren't told that you paused.", systemImage: "pause.circle")
                    .foregroundStyle(.secondary)
            }
            switch monitor.authorization {
            case .notDetermined:
                Button("Enable Exit Alerts", systemImage: "location") {
                    monitor.requestLocationPermission()
                    Task { await notifications.request() }
                }
            case .denied, .restricted:
                Text("Location access is off, so exits can't be detected.")
                Button("Open Settings", systemImage: "gear") {
                    open(UIApplication.openSettingsURLString)
                }
            default:
                if !monitor.isSharingPaused {
                    Text(statusText)
                }
            }
            notificationStatus
            if let latestAlert = store.latestAlert {
                Text(latestAlert)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Exit Alerts")
        } footer: {
            Text("Your exits are shared with your groups. Other members see them as live in-app alerts only while Folkloop is open on their device. These are not push notifications.")
        }
    }

    @ViewBuilder
    private var notificationStatus: some View {
        if let status = notifications.status {
            switch status {
            case .notDetermined:
                Text("Notifications tell you when group members arrive at or leave a geofence, including when Folkloop is closed once push is set up.")
                    .foregroundStyle(.secondary)
                Button("Allow Notifications", systemImage: "bell") {
                    Task { await notifications.request() }
                }
            case .provisional:
                Text("Notifications arrive quietly in Notification Center.")
                Button("Allow Notification Banners", systemImage: "bell") {
                    Task { await notifications.request() }
                }
            case .denied:
                Text("Notifications are off, so exit alerts only appear inside Folkloop.")
                Button("Notification Settings", systemImage: "bell.slash") {
                    open(UIApplication.openNotificationSettingsURLString)
                }
            case .authorized, .ephemeral:
                Text("Notifications are on.")
            @unknown default:
                Text("Notification status is unavailable.")
            }
        }
        if let pushProblem = push.problem {
            Text(pushProblem)
                .foregroundStyle(.secondary)
        }
        if let requestError = notifications.requestError {
            Text(requestError)
                .foregroundStyle(.red)
        }
    }

    private func open(_ settingsURLString: String) {
        if let url = URL(string: settingsURLString) {
            openURL(url)
        }
    }

    private var statusText: String {
        let limit = Int(GeofenceMonitoring.shared.IOS_REGION_LIMIT)
        var text = "Monitoring \(monitor.monitoredIDs.count) of \(monitor.totalGeofences) geofences."
        if monitor.totalGeofences > limit {
            text += " iOS allows \(limit), so the nearest are chosen."
        }
        if monitor.authorization == .authorizedWhenInUse {
            text += " Alerts need Folkloop in use; choose Always in Settings for background alerts."
        }
        return text
    }
}
