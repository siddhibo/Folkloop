import XCTest

final class GroupsAndGeofencesUITests: XCTestCase {
    @MainActor
    func testCreateGroupAndSaveGeofence() {
        let app = XCUIApplication.launchSignedUp(as: "Alice")

        app.buttons["New Group"].tap()
        app.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Name cannot be empty."].waitForExistence(timeout: 3))

        let groupName = app.textFields["Group name"]
        groupName.tap()
        groupName.typeText("Family")
        app.buttons["Create"].tap()

        let groupRow = app.staticTexts["Family"]
        XCTAssertTrue(groupRow.waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["0 geofences"].exists)
        groupRow.tap()

        app.buttons["Add Geofence"].tap()
        let saveButton = app.buttons["Save"]
        XCTAssertTrue(saveButton.waitForExistence(timeout: 3))
        XCTAssertFalse(saveButton.isEnabled, "Save needs a centre first")

        let geofenceName = app.textFields["Geofence name"]
        geofenceName.tap()
        geofenceName.typeText("Home")

        app.descendants(matching: .any)["geofenceMap"].firstMatch.tap()
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: saveButton)
        wait(for: [enabled], timeout: 3)
        attachScreenshot(named: "Geofence editor")
        saveButton.tap()

        let savedRow = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '300 m'")).firstMatch
        XCTAssertTrue(savedRow.waitForExistence(timeout: 10))
        attachScreenshot(named: "Group detail")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["1 geofence"].waitForExistence(timeout: 3))
        attachScreenshot(named: "Groups list")
    }
}
