import XCTest

final class GeofenceEditingUITests: XCTestCase {
    @MainActor
    func testEditingKeepsIdentityAndCreatorAndRejectsInvalidInput() async throws {
        continueAfterFailure = false
        let app = XCUIApplication.launchSignedUp(as: "Eddie")
        app.createGroup(named: "Studio")
        app.staticTexts["Studio"].tap()
        let joinCode = app.staticTexts["joinCode"]
        XCTAssertTrue(joinCode.waitForExistence(timeout: 10))
        app.addGeofenceAtMapCentre(named: "Office")

        let emulator = EmulatorClient()
        let groupID = try await emulator.adminGroupID(forJoinCode: joinCode.label)
        let original = try await onlyGeofence(inGroup: groupID, using: emulator)

        app.staticTexts["Office"].tap()
        XCTAssertTrue(app.navigationBars["Edit Geofence"].waitForExistence(timeout: 5))
        let nameField = app.textFields["Geofence name"]
        XCTAssertEqual(nameField.value as? String, "Office")
        nameField.tap()
        nameField.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 10))
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts["Name cannot be empty."].waitForExistence(timeout: 5))

        nameField.typeText("HQ")
        app.sliders.firstMatch.adjust(toNormalizedSliderPosition: 1)
        let maximumRadius = app.staticTexts.matching(NSPredicate(format: "label MATCHES 'Radius: 2.?000 m'")).firstMatch
        XCTAssertTrue(maximumRadius.waitForExistence(timeout: 5))
        app.descendants(matching: .any)["geofenceMap"].firstMatch
            .coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
        attachScreenshot(named: "Editing geofence")
        app.buttons["Save"].tap()

        XCTAssertTrue(app.staticTexts["HQ"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label MATCHES '2.?000 m .*'")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Office"].exists)
        attachScreenshot(named: "Edited geofence")

        let edited = try await onlyGeofence(inGroup: groupID, using: emulator)
        XCTAssertEqual(EmulatorClient.documentID(of: edited), EmulatorClient.documentID(of: original))
        XCTAssertEqual(EmulatorClient.string("createdBy", in: edited), EmulatorClient.string("createdBy", in: original))
        XCTAssertEqual(EmulatorClient.string("name", in: edited), "HQ")
        XCTAssertEqual(EmulatorClient.number("radiusMeters", in: edited), 2000)
        XCTAssertNotEqual(EmulatorClient.number("longitude", in: edited), EmulatorClient.number("longitude", in: original))
    }

    @MainActor
    private func onlyGeofence(inGroup groupID: String, using emulator: EmulatorClient) async throws -> [String: Any] {
        let geofences = try await emulator.adminList("groups/\(groupID)/geofences")
        XCTAssertEqual(geofences.count, 1)
        return try XCTUnwrap(geofences.first)
    }
}
