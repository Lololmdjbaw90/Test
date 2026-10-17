import XCTest

final class HomeInteractionTests: XCTestCase {
    func testHomeSectionsRemainVisibleAfterScrollingAndReturning() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--polish-ui-test"]
        app.launch()
        app.buttons["Home"].tap()
        let composer = app.staticTexts["What are you making today?"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertTrue(composer.isHittable, "Creating a post should be reachable without scrolling")
        let coins = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "coins")).firstMatch
        XCTAssertTrue(coins.waitForExistence(timeout: 3), "Your coins show at the top of Home")
        XCTAssertTrue(composer.isHittable)
        let feed = app.scrollViews["home-feed"]
        XCTAssertTrue(feed.exists)
        // Home is a long page: scroll until the last section shows, then
        // all the way back up.
        for _ in 0..<10 where !app.staticTexts["Your servers"].exists { feed.swipeUp() }
        XCTAssertTrue(app.staticTexts["Your servers"].exists)
        for _ in 0..<12 where !composer.isHittable { feed.swipeDown() }
        XCTAssertTrue(composer.isHittable)
        app.buttons["Editor"].tap()
        app.buttons["Home"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 3))
        XCTAssertTrue(composer.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "home-after-scrolling"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
