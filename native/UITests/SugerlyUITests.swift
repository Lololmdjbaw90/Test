import XCTest

final class SugerlyUITests: XCTestCase {
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--design-preview"]
        app.launch()
        return app
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testOneNavigationBarHidesWhenTyping() {
        let app = launch()
        let dock = app.otherElements["sugerly.navigation"]
        XCTAssertTrue(dock.waitForExistence(timeout: 15))
        XCTAssertEqual(app.tabBars.count, 0)
        XCTAssertEqual(app.buttons.matching(identifier: "Chat").count, 1)
        capture("Community-pink-fonts")
        app.buttons["Chat"].tap()
        let search = app.textFields["Search chats"]
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("hello")
        let hidden = NSPredicate(format: "exists == false")
        expectation(for: hidden, evaluatedWith: dock)
        waitForExpectations(timeout: 5)
        capture("Chat-keyboard-no-dock")
    }
    func testCustomSettingsAndColorSelection() {
        let app = launch()
        XCTAssertTrue(app.buttons["Profile"].waitForExistence(timeout: 15))
        app.buttons["Profile"].tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(app.staticTexts["Your world, your way."].waitForExistence(timeout: 5))
        app.buttons["Accent AC53C4"].tap()
        XCTAssertEqual(app.textFields["D9577F"].value as? String, "AC53C4")
        app.buttons["Accent D9577F"].tap()
        capture("Settings-custom-pink")
    }
}
