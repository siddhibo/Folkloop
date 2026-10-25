import XCTest

final class ActivityDashboardUITests: XCTestCase {
    @MainActor
    func testDashboardTotalsMatchRecordedExits() async throws {
        continueAfterFailure = false
        let app = XCUIApplication.launchSignedUp(as: "Hana")
        app.createGroup(named: "Family")
        app.createGroup(named: "Work")

        app.buttons["Activity"].tap()
        XCTAssertTrue(app.staticTexts["No exits recorded"].waitForExistence(timeout: 10))
        assertTile("todayExitCount", equals: "0 exits", in: app)
        attachScreenshot(named: "Empty activity")
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let emulator = EmulatorClient()
        let bob = try await emulator.signUp(as: "Bob")
        let cara = try await emulator.signUp(as: "Cara")
        let familyID = try await addGeofence("Office", toGroup: "Family", joinedBy: bob, named: "Bob", in: app, using: emulator)
        let workID = try await addGeofence("Desk", toGroup: "Work", joinedBy: cara, named: "Cara", in: app, using: emulator)
        let officeID = try await emulator.geofenceID(named: "Office", inGroup: familyID, as: bob)
        let deskID = try await emulator.geofenceID(named: "Desk", inGroup: workID, as: cara)

        for _ in 0..<2 {
            try await emulator.reportExit(groupID: familyID, geofenceID: officeID, geofenceName: "Office", memberName: "Bob", as: bob)
        }
        try await emulator.reportExit(groupID: workID, geofenceID: deskID, geofenceName: "Desk", memberName: "Cara", as: cara)

        let familyEvents = try await emulator.adminList("groups/\(familyID)/exitEvents")
        let workEvents = try await emulator.adminList("groups/\(workID)/exitEvents")
        XCTAssertEqual(familyEvents.count + workEvents.count, 3)

        app.buttons["Activity"].tap()
        assertTile("todayExitCount", equals: "3 exits", in: app)
        assertTile("periodExitCount", equals: "3 exits", in: app)
        assertTile("memberCount", equals: "2 with exits", in: app)
        XCTAssertTrue(app.staticTexts["Exits by group"].exists)
        attachScreenshot(named: "Activity, all groups")

        let caraRow = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Cara left Desk'")).firstMatch
        for _ in 0..<4 where !caraRow.exists {
            app.swipeUp()
        }
        XCTAssertTrue(caraRow.exists, "The feed should list Cara's exit")
        attachScreenshot(named: "Activity feed")
        for _ in 0..<4 {
            app.swipeDown()
        }

        app.buttons["30 days"].tap()
        assertTile("periodExitCount", equals: "3 exits", in: app)
        XCTAssertTrue(app.staticTexts["Last 30 days"].firstMatch.exists)
        attachScreenshot(named: "Activity, 30 days")

        app.buttons["groupFilter"].tap()
        app.buttons["Family"].tap()
        assertTile("todayExitCount", equals: "2 exits", in: app)
        assertTile("memberCount", equals: "1 with exits", in: app)
        XCTAssertFalse(app.staticTexts["Exits by group"].exists)
        attachScreenshot(named: "Activity, Family only")
    }

    @MainActor
    private func addGeofence(
        _ geofenceName: String,
        toGroup groupName: String,
        joinedBy member: EmulatorClient.User,
        named memberName: String,
        in app: XCUIApplication,
        using emulator: EmulatorClient
    ) async throws -> String {
        app.staticTexts[groupName].tap()
        let joinCode = app.staticTexts["joinCode"]
        XCTAssertTrue(joinCode.waitForExistence(timeout: 10))
        app.addGeofenceAtMapCentre(named: geofenceName)
        let groupID = try await emulator.join(code: joinCode.label, as: member, displayName: memberName)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        return groupID
    }

    @MainActor
    private func assertTile(_ identifier: String, equals value: String, in app: XCUIApplication) {
        let tile = app.descendants(matching: .any)[identifier]
        let matches = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: tile)
        XCTAssertEqual(XCTWaiter().wait(for: [matches], timeout: 10), .completed, "\(identifier) should read \(value)")
    }
}
