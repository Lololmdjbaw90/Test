import XCTest
import UIKit

final class HomeInteractionTests: XCTestCase {
    func testColorfulHomeSidebarInLandscape() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("Wide iPad layout") }
        let app = XCUIApplication()
        app.launchArguments = ["--polish-ui-test"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        app.buttons["Home"].tap()
        let inspiration = app.staticTexts["A little inspiration"].firstMatch
        expectation(for: NSPredicate { _, _ in
            let bounds = app.windows.firstMatch.frame
            return bounds.width > bounds.height && inspiration.isHittable
        }, evaluatedWith: app)
        waitForExpectations(timeout: 15)
        XCTAssertTrue(inspiration.exists)
        XCTAssertTrue(app.buttons["home-compose-post"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "colorful-home-landscape"
        shot.lifetime = .keepAlways
        add(shot)
    }

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
        XCTAssertTrue(composer.isHittable, "Creating a post must stay reachable")
        let coins = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "coins")).firstMatch
        XCTAssertTrue(coins.waitForExistence(timeout: 3), "Your coins show at the top of Home")
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
