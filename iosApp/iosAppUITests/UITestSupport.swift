import XCTest

// These UI tests need the Firebase Emulator Suite running (see README.md).

extension XCUIApplication {
    /// Launches the app signed out and creates a fresh emulator account.
    @MainActor
    static func launchSignedUp(as displayName: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-signOutOnLaunch"]
        app.launch()

        let nameField = app.textFields["Display name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 10))
        nameField.tap()
        nameField.typeText(displayName)
        let emailField = app.textFields["Email"]
        emailField.tap()
        emailField.typeText(EmulatorClient.uniqueEmail(for: displayName))
        let passwordField = app.secureTextFields["Password"]
        passwordField.tap()
        passwordField.typeText(EmulatorClient.testPassword)
        app.buttons["Continue"].tap()

        XCTAssertTrue(app.navigationBars["Groups"].waitForExistence(timeout: 15), "Sign-up should open the groups screen")
        // iOS offers to save the new password in a system sheet that covers the app.
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 5) {
            notNow.tap()
        }
        // The toolbar exists before the sign-in screen finishes animating away; wait until it can be tapped.
        let newGroup = app.buttons["New Group"]
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: newGroup)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 10), .completed, "Groups toolbar should become tappable")
        return app
    }

    @MainActor
    func createGroup(named name: String) {
        buttons["New Group"].tap()
        let nameField = textFields["Group name"]
        nameField.tap()
        nameField.typeText(name)
        buttons["Create"].tap()
        XCTAssertTrue(staticTexts[name].waitForExistence(timeout: 10))
    }

    /// Adds a geofence centred where the editor map opens (Apple Park) with the default 300 m radius.
    @MainActor
    func addGeofenceAtMapCentre(named name: String) {
        buttons["Add Geofence"].tap()
        let nameField = textFields["Geofence name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        descendants(matching: .any)["geofenceMap"].firstMatch.tap()
        let saveButton = buttons["Save"]
        let enabled = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isEnabled == true"), object: saveButton)
        XCTAssertEqual(XCTWaiter().wait(for: [enabled], timeout: 5), .completed)
        saveButton.tap()
        XCTAssertTrue(staticTexts.matching(NSPredicate(format: "label BEGINSWITH '300 m'")).firstMatch.waitForExistence(timeout: 10))
    }
}

extension XCTestCase {
    @MainActor
    func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
