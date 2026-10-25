import XCTest

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
        let code = joinCode.label
        app.addGeofenceAtMapCentre(named: "Office")

        let emulator = EmulatorClient()
        let bob = try await emulator.signUp(as: "Bob")
        let groupID = try await emulator.join(code: code, as: bob, displayName: "Bob")
        XCTAssertTrue(app.staticTexts["Bob"].waitForExistence(timeout: 10), "Bob should appear as a member")
        XCTAssertTrue(app.staticTexts["Member"].exists)
        attachScreenshot(named: "Members after join")

        let officeID = try await emulator.geofenceID(named: "Office", inGroup: groupID, as: bob)
        try await emulator.reportExit(groupID: groupID, geofenceID: officeID, geofenceName: "Office", memberName: "Bob", as: bob)

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Bob left Office (Family)."].waitForExistence(timeout: 10))
        attachScreenshot(named: "Live member alert")

        app.staticTexts["Family"].tap()
        let bobStatus = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last recorded exit: Office'")).firstMatch
        XCTAssertTrue(bobStatus.waitForExistence(timeout: 10), "Bob's last recorded exit should be shown")
        XCTAssertTrue(app.staticTexts["No activity recorded in the last 30 days"].exists, "Alice has no recorded activity")
        attachScreenshot(named: "Member status")
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
