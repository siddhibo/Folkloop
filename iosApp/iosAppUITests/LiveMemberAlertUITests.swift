import XCTest

/// Another member joins with the join code and reports an exit; this device shows a live in-app alert.
/// The other member is played by EmulatorClient, which is subject to the same security rules as the app.
final class LiveMemberAlertUITests: XCTestCase {
    @MainActor
    func testOtherMembersExitAppearsAsLiveAlert() async throws {
        let app = XCUIApplication.launchSignedUp(as: "Alice")
        app.createGroup(named: "Family")
        app.staticTexts["Family"].tap()

        XCTAssertTrue(app.staticTexts["Alice (You)"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Owner"].exists)
        let joinCode = app.staticTexts["joinCode"]
        XCTAssertTrue(joinCode.waitForExistence(timeout: 10))
        app.addGeofenceAtMapCentre(named: "Office")

        // Bob joins from "another device" using the code shown on screen.
        let emulator = EmulatorClient()
        let bob = try await emulator.signUp(as: "Bob")
        let groupID = try await emulator.join(code: joinCode.label, as: bob, displayName: "Bob")
        XCTAssertTrue(app.staticTexts["Bob"].waitForExistence(timeout: 10), "Bob should appear as a member")
        XCTAssertTrue(app.staticTexts["Member"].exists)
        attachScreenshot(named: "Members after join")

        // Bob reports leaving Office; Alice's running app should alert.
        let officeID = try await emulator.geofenceID(named: "Office", inGroup: groupID, as: bob)
        try await emulator.reportExit(groupID: groupID, geofenceID: officeID, geofenceName: "Office", memberName: "Bob", as: bob)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Bob left Office (Family)."].waitForExistence(timeout: 10))
        attachScreenshot(named: "Live member alert")
    }

    @MainActor
    func testWrongJoinCodeIsRejected() {
        let app = XCUIApplication.launchSignedUp(as: "Erin")
        app.buttons["Join Group"].tap()
        let codeField = app.textFields["Join code"]
        XCTAssertTrue(codeField.waitForExistence(timeout: 5))
        codeField.tap()
        codeField.typeText("ZZZZ22")
        app.buttons["Join"].tap()
        XCTAssertTrue(app.staticTexts["No group uses that code."].waitForExistence(timeout: 10))
        codeField.tap()
        codeField.typeText("0")
        app.buttons["Join"].tap()
        XCTAssertTrue(app.staticTexts["Join codes are 6 letters and numbers."].waitForExistence(timeout: 5))
    }
}
