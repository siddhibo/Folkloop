import CoreLocation
import XCTest

/// Moves the simulated device out of a saved geofence and checks that the exit is detected and alerted.
final class GeofenceExitUITests: XCTestCase {
    private let insideApplePark = CLLocation(latitude: 37.3349, longitude: -122.0090)
    private let sevenKilometresNorth = CLLocation(latitude: 37.3979, longitude: -122.0090)

    @MainActor
    func testLeavingGeofenceShowsExitAlert() {
        let app = XCUIApplication()
        app.resetAuthorizationStatus(for: .location)
        XCUIDevice.shared.location = XCUILocation(location: insideApplePark)
        app.launch()

        app.buttons["Enable Exit Alerts"].tap()
        allowSystemAlerts()
        let monitoringStatus = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Monitoring 0 of 0'")).firstMatch
        XCTAssertTrue(monitoringStatus.waitForExistence(timeout: 5))

        // Save a geofence around the current simulated location (the editor map opens centred on Apple Park).
        app.buttons["New Group"].tap()
        let groupName = app.textFields["Group name"]
        groupName.tap()
        groupName.typeText("Commute")
        app.buttons["Create"].tap()
        app.staticTexts["Commute"].tap()

        app.buttons["Add Geofence"].tap()
        let geofenceName = app.textFields["Geofence name"]
        XCTAssertTrue(geofenceName.waitForExistence(timeout: 3))
        geofenceName.tap()
        geofenceName.typeText("Office")
        app.descendants(matching: .any)["geofenceMap"].firstMatch.tap()
        let saveButton = app.buttons["Save"]
        wait(for: [expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: saveButton)], timeout: 3)
        saveButton.tap()

        XCTAssertTrue(app.staticTexts["Inside"].waitForExistence(timeout: 30), "Core Location should report the device inside")
        attachScreenshot(app, named: "Inside geofence")

        XCUIDevice.shared.location = XCUILocation(location: sevenKilometresNorth)
        XCTAssertTrue(app.staticTexts["Outside"].waitForExistence(timeout: 60), "Core Location should report the exit")

        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let banner = springboard.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS 'Left Office'")).firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 10), "A local notification banner should appear")
        attachScreenshot(app, named: "Exit notification")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["You left Office (Commute). Only this device was alerted."].waitForExistence(timeout: 5))
        attachScreenshot(app, named: "Exit Alerts status")
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

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
