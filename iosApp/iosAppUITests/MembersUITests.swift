import XCTest

/// Checks that a group lists its owner and accepts locally simulated members.
final class MembersUITests: XCTestCase {
    @MainActor
    func testAddSimulatedMember() {
        let app = XCUIApplication()
        app.launch()

        app.buttons["New Group"].tap()
        let groupName = app.textFields["Group name"]
        groupName.tap()
        groupName.typeText("Friends")
        app.buttons["Create"].tap()

        let groupRow = app.staticTexts["Friends"]
        XCTAssertTrue(groupRow.waitForExistence(timeout: 3))
        groupRow.tap()

        // The creator is listed as owner, and the screen says members are only simulated.
        XCTAssertTrue(app.staticTexts["You"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Owner"].exists)
        XCTAssertTrue(app.staticTexts["Simulated members exist only on this device. No invitation is sent."].exists)

        // An empty name is rejected by the Kotlin validation.
        app.buttons["Add Simulated Member"].tap()
        let addButton = app.buttons["Add"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 3))
        addButton.tap()
        XCTAssertTrue(app.staticTexts["Name cannot be empty."].waitForExistence(timeout: 3))

        let memberName = app.textFields["Member name"]
        memberName.tap()
        memberName.typeText("Alex")
        addButton.tap()

        XCTAssertTrue(app.staticTexts["Alex"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.staticTexts["Simulated"].exists)
        attachScreenshot(app, named: "Members")

        // The same name in different capitals is rejected.
        app.buttons["Add Simulated Member"].tap()
        memberName.tap()
        memberName.typeText("alex")
        addButton.tap()
        XCTAssertTrue(app.staticTexts["alex is already in this group."].waitForExistence(timeout: 3))
        attachScreenshot(app, named: "Duplicate member")
        app.buttons["Cancel"].tap()
    }

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
