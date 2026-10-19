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

    private var messageInput: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "chat-message-input").firstMatch
    }

    func testSingleChatBackRestoresTabBarAfterTypingAndRepeatedVisits() {
        let open = app.buttons["Open test chat"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            open.tap()
            let message = messageInput
            XCTAssertTrue(message.waitForExistence(timeout: 5))
            XCTAssertEqual(backButtons.count, 1, "A chat must have one Back control")
            message.tap()
            message.typeText("Local draft")
            backButtons.firstMatch.tap()
            XCTAssertTrue(open.waitForExistence(timeout: 3))
            XCTAssertTrue(tabButton("Home").waitForExistence(timeout: 3), "Returning must bring the tab bar back")
        }
        tapTab("Home")
        XCTAssertTrue(app.staticTexts["Home page"].waitForExistence(timeout: 3))
        tapTab("Chat")
        XCTAssertTrue(open.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "phone-tab-bar-after-chat"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Create something"].waitForExistence(timeout: 3))
    }

    func testChatEdgeSwipeKeepsNavigationPathInSync() throws {
        try XCTSkipIf(app.frame.width > 600, "This test covers the iPhone edge gesture; iPad navigation is tested with its Back button.")
        let open = app.buttons["Open test chat"]
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        open.tap()
        XCTAssertTrue(messageInput.waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.4))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.4))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(open.waitForExistence(timeout: 3))
        XCTAssertTrue(tabButton("Chat").waitForExistence(timeout: 3))
        open.tap()
        XCTAssertTrue(messageInput.waitForExistence(timeout: 3))
        XCTAssertEqual(backButtons.count, 1)
    }

    func testSettingsAndItsNestedPageCloseWhenLeavingTheirTab() {
        tapTab("Community")
        app.buttons["Open saved profile"].tap()
        XCTAssertTrue(app.staticTexts["Saved profile page"].waitForExistence(timeout: 3))
        app.buttons["Open settings"].tap()
        XCTAssertTrue(app.buttons["Edit profile"].waitForExistence(timeout: 5))

        // Hidden words is an ordinary destination NavigationLink inside
        // Settings, so its presentation is not recorded in Navigator's path.
        let hiddenWords = app.staticTexts["Hidden words"]
        for _ in 0..<12 where !hiddenWords.isHittable {
            dismissNotificationPermissionIfNeeded()
            app.swipeUp()
        }
        XCTAssertTrue(hiddenWords.isHittable)
        hiddenWords.tap()
        XCTAssertTrue(app.textFields["Add a word or phrase"].waitForExistence(timeout: 3))
        tapTab("Home")
        XCTAssertTrue(app.staticTexts["Home page"].waitForExistence(timeout: 3))
        tapTab("Community")
        XCTAssertTrue(app.staticTexts["Saved profile page"].waitForExistence(timeout: 3),
                      "Leaving Settings must return to the page before it, including its nested pages")
        XCTAssertFalse(app.textFields["Add a word or phrase"].exists)

        // A fresh visit starts at Settings, rather than reopening its child.
        app.buttons["Open settings"].tap()
        XCTAssertTrue(app.buttons["Edit profile"].waitForExistence(timeout: 3))
        tapTab("Home")
        tapTab("Community")
        XCTAssertTrue(app.staticTexts["Saved profile page"].waitForExistence(timeout: 3))
    }

    func testNotificationsCloseOnTabTapAndProgrammaticSwitchWithoutLosingOtherPages() {
        tapTab("Home")
        app.buttons["Open saved profile"].tap()
        XCTAssertTrue(app.staticTexts["Saved profile page"].waitForExistence(timeout: 3))
        tapTab("Fan Art")
        app.buttons["Notifications"].tap()
        XCTAssertTrue(app.staticTexts["Your updates"].waitForExistence(timeout: 3))
        tapTab("Home")
        XCTAssertTrue(app.staticTexts["Saved profile page"].waitForExistence(timeout: 3),
                      "An unrelated tab's ordinary navigation must stay intact")
        tapTab("Fan Art")
        XCTAssertTrue(app.staticTexts["Fan Art page"].waitForExistence(timeout: 3))

        app.buttons["Notifications"].tap()
        let notification = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "Navigation notification")).firstMatch
        XCTAssertTrue(notification.waitForExistence(timeout: 3))
        notification.tap()
        XCTAssertTrue(app.staticTexts["Notification profile page"].waitForExistence(timeout: 3))
        app.buttons["Switch to Home"].tap()
        XCTAssertTrue(app.staticTexts["Saved profile page"].waitForExistence(timeout: 3))
        tapTab("Fan Art")
        XCTAssertTrue(app.staticTexts["Fan Art page"].waitForExistence(timeout: 3),
                      "A programmatic switch must also remove Notifications and the page opened from it")
    }

    private func tabButton(_ label: String) -> XCUIElement {
        let matches = app.buttons.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
        return matches.first(where: { $0.isHittable }) ?? app.buttons[label].firstMatch
    }

    private func tapTab(_ label: String) {
        let button = tabButton(label)
        XCTAssertTrue(button.waitForExistence(timeout: 3))
        button.tap()
    }

    private func dismissNotificationPermissionIfNeeded() {
        let alert = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if alert.exists { alert.buttons.firstMatch.tap() }
    }
}
