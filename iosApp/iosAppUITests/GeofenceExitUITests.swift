import CoreLocation
import XCTest

/// Moves the simulated device out of a saved geofence and checks that the exit is detected and alerted.
final class GeofenceExitUITests: XCTestCase {
    private let insideApplePark = CLLocation(latitude: 37.3349, longitude: -122.0090)
    private let sevenKilometresNorth = CLLocation(latitude: 37.3979, longitude: -122.0090)

    @MainActor
    func testLeavingGeofenceShowsExitAlert() async throws {
        XCUIApplication().resetAuthorizationStatus(for: .location)
        XCUIDevice.shared.location = XCUILocation(location: insideApplePark)
        let app = XCUIApplication.launchSignedUp(as: "Dana")

        app.buttons["Enable Exit Alerts"].tap()
        allowSystemAlerts()
        let monitoringStatus = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Monitoring 0 of 0'")).firstMatch
        XCTAssertTrue(monitoringStatus.waitForExistence(timeout: 5))

        // Save a geofence around the current simulated location (the editor map opens centred on Apple Park).
        app.createGroup(named: "Commute")
        app.staticTexts["Commute"].tap()
        app.addGeofenceAtMapCentre(named: "Office")

        XCTAssertTrue(app.staticTexts["Inside"].waitForExistence(timeout: 30), "Core Location should report the device inside")
        attachScreenshot(named: "Inside geofence")

        XCUIDevice.shared.location = XCUILocation(location: sevenKilometresNorth)
        XCTAssertTrue(app.staticTexts["Outside"].waitForExistence(timeout: 60), "Core Location should report the exit")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Left Office'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "A local notification banner should appear")
        attachScreenshot(named: "Exit notification")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["You left Office (Commute). No other members are in this group yet."].waitForExistence(timeout: 5))
        // The person who left never gets the member alert about themselves.
        XCTAssertFalse(app.staticTexts["Dana left Office (Commute)."].exists)
        attachScreenshot(named: "Exit Alerts status")

        // The exit was written to Firestore through the security rules.
        let event = try await waitForExitEvent(inGroupNamed: "Commute")
        XCTAssertEqual(EmulatorClient.string("memberName", in: event), "Dana")
        XCTAssertEqual(EmulatorClient.string("geofenceName", in: event), "Office")
    }

    @MainActor
    private func waitForExitEvent(inGroupNamed groupName: String) async throws -> [String: Any] {
        let emulator = EmulatorClient()
        for _ in 0..<20 {
            let groups = try await emulator.adminList("groups")
            // Several test runs may create a "Commute" group; check the newest ones too.
            for group in groups where EmulatorClient.string("name", in: group) == groupName {
                let groupID = String((group["name"] as! String).split(separator: "/").last!)
                if let event = try await emulator.adminList("groups/\(groupID)/exitEvents").first(where: {
                    EmulatorClient.string("memberName", in: $0) == "Dana"
                }) {
                    return event
                }
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw EmulatorClient.RequestError(description: "No exit event was written for \(groupName)")
    }

    /// Taps through the location and notification permission prompts, in whichever order they appear.
    @MainActor
    private func allowSystemAlerts() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for _ in 0..<2 {
            for label in ["Allow While Using App", "Allow"] {
                let button = springboard.buttons[label]
                if button.waitForExistence(timeout: 3) {
                    button.tap()
                    break
                }
            }
        }
    }
}
