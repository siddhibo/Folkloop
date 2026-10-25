import XCTest

final class PresenceAndMembershipUITests: XCTestCase {
    @MainActor
    func testEntryShowsPresenceAndOwnerCanRemoveMember() async throws {
        continueAfterFailure = false
        let app = XCUIApplication.launchSignedUp(as: "Olga")
        app.createGroup(named: "Book Club")
        app.staticTexts["Book Club"].tap()
        let joinCode = app.staticTexts["joinCode"]
        XCTAssertTrue(joinCode.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["Invite"].exists)
        XCTAssertFalse(app.buttons["Leave Group"].exists, "The owner can't leave their own group")
        let code = joinCode.label
        app.addGeofenceAtMapCentre(named: "Library")

        let emulator = EmulatorClient()
        let bob = try await emulator.signUp(as: "Bob")
        let groupID = try await emulator.join(code: code, as: bob, displayName: "Bob")
        XCTAssertTrue(app.staticTexts["Bob"].waitForExistence(timeout: 10))
        let libraryID = try await emulator.geofenceID(named: "Library", inGroup: groupID, as: bob)
        try await emulator.reportExit(groupID: groupID, geofenceID: libraryID, geofenceName: "Library", memberName: "Bob", as: bob, isEntry: true)

        let bobStatus = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Last recorded arrival: Library'")).firstMatch
        XCTAssertTrue(bobStatus.waitForExistence(timeout: 15), "Bob's recorded arrival should be shown")
        app.swipeUp()
        let presence = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '1 inside · 0 outside · 1 unknown or stale · 2 members'")).firstMatch
        XCTAssertTrue(presence.waitForExistence(timeout: 10), "Bob's recorded arrival should count him inside, and Olga should be unknown, not outside")
        attachScreenshot(named: "Presence after arrival")

        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.staticTexts["Bob arrived at Library (Book Club)."].waitForExistence(timeout: 10), "Other members get an arrival alert")
        app.staticTexts["Book Club"].tap()

        let bobRow = app.staticTexts["Bob"]
        XCTAssertTrue(bobRow.waitForExistence(timeout: 10))
        app.cells.containing(.staticText, identifier: "Bob").firstMatch.swipeLeft()
        app.buttons["Remove"].tap()
        app.buttons["Remove from Group"].tap()
        XCTAssertTrue(bobRow.waitForNonExistence(timeout: 10), "Bob should disappear from the member list")
        attachScreenshot(named: "After removing Bob")

        let group = try await emulator.adminDocument("groups/\(groupID)")
        let memberIDs = ((group["fields"] as? [String: Any])?["memberIds"] as? [String: Any])?["arrayValue"] as? [String: Any]
        let values = (memberIDs?["values"] as? [[String: Any]] ?? []).compactMap { $0["stringValue"] as? String }
        XCTAssertFalse(values.contains(bob.uid))
        XCTAssertEqual(values.count, 1)
        let bobMember = try? await emulator.adminDocument("groups/\(groupID)/members/\(bob.uid)")
        XCTAssertNil(bobMember, "Bob's member document should be deleted")
    }
}
