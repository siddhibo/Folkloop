import XCTest

/// Walks through the milestone flow: create a group, then save a geofence picked on the map.
final class GroupsAndGeofencesUITests: XCTestCase {
    @MainActor
    func testCreateGroupAndSaveGeofence() {
        let app = XCUIApplication()
        app.launch()

        // Create a group. An empty name must be rejected by the Kotlin validation.
        app.buttons["New Group"].tap()
        app.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Name cannot be empty."].waitForExistence(timeout: 3))

        let groupName = app.textFields["Group name"]
        groupName.tap()
        groupName.typeText("Family")
        app.buttons["Create"].tap()

        let groupRow = app.staticTexts["Family"]
        XCTAssertTrue(groupRow.waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["0 geofences"].exists)
        groupRow.tap()

        // Add a geofence: name it, tap the map to set the centre, then save.
        app.buttons["Add Geofence"].tap()
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertFalse(saveButton.isEnabled, "Save needs a centre first")

        let geofenceName = app.textFields["Geofence name"]
        geofenceName.tap()
        geofenceName.typeText("Home")

        app.descendants(matching: .any)["geofenceMap"].firstMatch.tap()
        // SwiftUI updates the button a moment after the tap, so wait for it.
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: saveButton)
        wait(for: [enabled], timeout: 3)
        attachScreenshot(app, named: "Geofence editor")
        saveButton.tap()

        // The saved row shows the default 300 m radius followed by its coordinates.
        let savedRow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '300 m'")).firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 3))
        attachScreenshot(app, named: "Group detail")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["1 geofence"].waitForExistence(timeout: 3))
        attachScreenshot(app, named: "Groups list")
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
