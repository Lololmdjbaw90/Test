import XCTest

final class HomeInteractionTests: XCTestCase {
    func testHomeSectionsRemainVisibleAfterScrollingAndReturning() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--polish-ui-test"]
        app.launch()
        app.buttons["Home"].tap()
        let composer = app.buttons["home-compose-post"]
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        let feed = app.scrollViews["home-feed"]
        for _ in 0..<3 where !composer.isHittable { feed.swipeUp() }
        XCTAssertTrue(composer.isHittable, "The post composer must remain reachable")
        let coins = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "coins")).firstMatch
        XCTAssertTrue(coins.exists, "Your coins show in the Home header")
        XCTAssertTrue(composer.isHittable)
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
