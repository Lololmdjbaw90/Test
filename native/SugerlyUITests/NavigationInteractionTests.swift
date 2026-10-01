import XCTest

final class NavigationInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--shell-ui-test"]
        app.launch()
    }

    private var backButtons: XCUIElementQuery {
        app.navigationBars.buttons.matching(NSPredicate(format: "label == 'Back' OR label == 'Messages'"))
    }

    func testSingleChatBackRestoresDockAfterTypingAndRepeatedVisits() {
        let open = app.buttons["Open test chat"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            open.tap()
            let message = app.textFields["Message"]
            XCTAssertTrue(message.waitForExistence(timeout: 5))
            XCTAssertEqual(backButtons.count, 1, "A chat must have one Back control")
            message.tap()
            message.typeText("Local draft")
            backButtons.firstMatch.tap()
            XCTAssertTrue(open.waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["Home"].isHittable, "Returning must restore the dock")
        }
        app.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["Home page"].waitForExistence(timeout: 3))
        app.buttons["Chat"].tap()
        XCTAssertTrue(open.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "phone-dock-after-chat"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Create something"].waitForExistence(timeout: 3))
    }

    func testChatEdgeSwipeKeepsNavigationPathInSync() {
        let open = app.buttons["Open test chat"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(app.textFields["Message"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.4))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Chat"].isHittable)
        open.tap()
        XCTAssertTrue(app.textFields["Message"].waitForExistence(timeout: 3))
        XCTAssertEqual(backButtons.count, 1)
    }
}
