import CoreLocation
import XCTest

final class PauseSharingUITests: XCTestCase {
    private let insideApplePark = CLLocation(latitude: 37.3349, longitude: -122.0090)
    private let sevenKilometresNorth = CLLocation(latitude: 37.3979, longitude: -122.0090)

    @MainActor
    func testPauseSurvivesRestartWritesNoExitAndResumeRestoresMonitoring() async throws {
        continueAfterFailure = false
        XCUIDevice.shared.location = XCUILocation(location: insideApplePark)
        var app = XCUIApplication.launchSignedUp(as: "Pia")
        allowLocationIfAsked(in: app)
        guard app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Monitoring'")).firstMatch.waitForExistence(timeout: 10) else {
            return XCTFail("Location access should be granted before adding geofences")
        }

        app.createGroup(named: "Errands")
        app.staticTexts["Errands"].tap()
        let joinCode = app.staticTexts["joinCode"]
        XCTAssertTrue(joinCode.waitForExistence(timeout: 10))
        let code = joinCode.label
        app.addGeofenceAtCurrentLocation(named: "Office")
        guard app.staticTexts["Inside"].waitForExistence(timeout: 30) else {
            return XCTFail("Core Location should report the device inside")
        }

        app.navigationBars.buttons.element(boundBy: 0).tap()
        let shareToggle = app.switches["shareExitsToggle"]
        XCTAssertEqual(shareToggle.value as? String, "1")
        shareToggle.switches.firstMatch.tap()
        let pausedNote = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Paused on this device'")).firstMatch
        XCTAssertTrue(pausedNote.waitForExistence(timeout: 5))
        attachScreenshot(named: "Sharing paused")

        app.staticTexts["Errands"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 5))
        XCUIDevice.shared.location = XCUILocation(location: sevenKilometresNorth)

        app.terminate()
        app = XCUIApplication()
        app.launch()
        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 15))
        XCTAssertEqual(app.switches["shareExitsToggle"].value as? String, "0", "Pause should survive a restart")
        XCTAssertTrue(pausedNote.exists)
        app.staticTexts["Errands"].tap()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 10))

        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.switches["shareExitsToggle"].switches.firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Monitoring 1 of 1 geofences."].waitForExistence(timeout: 10), "Resuming should monitor the geofence once")
        app.staticTexts["Errands"].tap()
        XCTAssertTrue(app.staticTexts["Outside"].waitForExistence(timeout: 60), "Monitoring should resume with the current state")
        attachScreenshot(named: "Sharing resumed")

        let emulator = EmulatorClient()
        let groupID = try await emulator.adminGroupID(forJoinCode: code)
        let events = try await emulator.adminList("groups/\(groupID)/exitEvents")
        XCTAssertTrue(events.isEmpty, "No exit should be recorded while sharing was paused")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertFalse(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'You left Office'")).firstMatch.exists)
    }

    @MainActor
    private func allowLocationIfAsked(in app: XCUIApplication) {
        let enableAlerts = app.buttons["Enable Exit Alerts"]
        guard enableAlerts.exists else { return }
        enableAlerts.tap()
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 5) {
                button.tap()
            }
        }
    }
}
