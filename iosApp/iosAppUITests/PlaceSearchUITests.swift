import XCTest

final class PlaceSearchUITests: XCTestCase {
    @MainActor
    func testSearchingForAPlaceSetsTheGeofenceCentre() async throws {
        continueAfterFailure = false
        let app = XCUIApplication.launchSignedUp(as: "Priya")
        app.createGroup(named: "Delhi Trip")
        app.staticTexts["Delhi Trip"].tap()
        let joinCode = app.staticTexts["joinCode"]
        XCTAssertTrue(joinCode.waitForExistence(timeout: 10))
        let code = joinCode.label

        app.buttons["Add Geofence"].tap()
        XCTAssertTrue(app.staticTexts["Search for a place or tap the map to choose the centre."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Save"].isEnabled, "Nothing is chosen until the user searches or taps the map")

        let searchField = app.searchFields["Search for a place or address"]
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("India Gate")
        let suggestion = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Delhi'")).firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 20), "Apple Maps should suggest a place in Delhi (needs network)")
        attachScreenshot(named: "Search suggestions")
        suggestion.tap()

        let selected = app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Selected: '")).firstMatch
        XCTAssertTrue(selected.waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'Centre 28.'")).firstMatch.exists)
        attachScreenshot(named: "Place selected")

        let nameField = app.textFields["Geofence name"]
        nameField.tap()
        nameField.typeText("India Gate")
        app.buttons["Save"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH '300 m · 28.'")).firstMatch.waitForExistence(timeout: 10))

        let emulator = EmulatorClient()
        let groupID = try await emulator.adminGroupID(forJoinCode: code)
        let geofences = try await emulator.adminList("groups/\(groupID)/geofences")
        let saved = try XCTUnwrap(geofences.first)
        let latitude = try XCTUnwrap(EmulatorClient.number("latitude", in: saved))
        let longitude = try XCTUnwrap(EmulatorClient.number("longitude", in: saved))
        XCTAssertEqual(latitude, 28.6, accuracy: 0.4, "The saved centre should be the chosen Delhi result")
        XCTAssertEqual(longitude, 77.2, accuracy: 0.4)
    }
}
