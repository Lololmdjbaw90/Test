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
        let activity = app.buttons["home-activity-toggle"]
        XCTAssertTrue(activity.isHittable)
        activity.tap()
        XCTAssertTrue(app.staticTexts["LEVEL"].waitForExistence(timeout: 3))
        activity.tap()
        XCTAssertFalse(app.staticTexts["LEVEL"].exists)
        XCTAssertTrue(composer.isHittable)
        let feed = app.scrollViews["home-feed"]
        XCTAssertTrue(feed.exists)
        for _ in 0..<5 { feed.swipeUp() }
        XCTAssertTrue(app.staticTexts["Your servers"].exists)
        for _ in 0..<6 { feed.swipeDown() }
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
