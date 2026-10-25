import XCTest

extension XCUIApplication {
    @MainActor
    static func launchSignedUp(as displayName: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-signOutOnLaunch", "-sharingPaused", "NO"]
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
        dismissSavePasswordPrompt(in: app)
        let newGroup = app.buttons["New Group"]
        let hittable = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: newGroup)
        XCTAssertEqual(XCTWaiter().wait(for: [hittable], timeout: 10), .completed, "Groups toolbar should become tappable")
        return app
    }

    @MainActor
    private static func dismissSavePasswordPrompt(in app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        guard notNow.waitForExistence(timeout: 10) else { return }
        for _ in 0..<3 {
            notNow.tap()
            if notNow.waitForNonExistence(timeout: 3) { return }
        }
        XCTFail("The Save Password prompt did not close after 3 taps on Not Now")
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

    @MainActor
    func addGeofenceAtMapCentre(named name: String) {
        addGeofence(named: name) {
            descendants(matching: .any)["geofenceMap"].firstMatch.tap()
        }
    }

    @MainActor
    func addGeofenceAtCurrentLocation(named name: String) {
        addGeofence(named: name) {
            buttons["Use My Location"].tap()
            XCTAssertTrue(staticTexts["Selected: Your current location"].waitForExistence(timeout: 5))
        }
    }

    @MainActor
    private func addGeofence(named name: String, choosingCentre chooseCentre: () -> Void) {
        buttons["Add Geofence"].tap()
        let nameField = textFields["Geofence name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        nameField.tap()
        nameField.typeText(name)
        chooseCentre()
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
