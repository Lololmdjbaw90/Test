import XCTest

final class ReelPlaybackInteractionTests: XCTestCase {
    func testVideosAdvanceSwipeLoopAndResumeAboveTabBar() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reel-playback-ui-test"]
        app.launch()
        let first = app.staticTexts["clip-0-state"]
        let playing = NSPredicate(format: "label == 'playing'")
        expectation(for: playing, evaluatedWith: first)
        waitForExpectations(timeout: 20)
        let share = app.buttons["Share"].firstMatch
        XCTAssertTrue(share.exists)
        XCTAssertLessThan(share.frame.maxY, app.tabBars.firstMatch.frame.minY)
        let feed = app.scrollViews["reel-feed"]
        XCTAssertTrue(feed.exists)
        feed.swipeUp(velocity: .fast)
        let second = app.staticTexts["clip-1-state"]
        expectation(for: playing, evaluatedWith: second)
        waitForExpectations(timeout: 15)
        app.tabBars.buttons["Home"].tap()
        expectation(for: NSPredicate(format: "label == 'paused'"), evaluatedWith: second)
        waitForExpectations(timeout: 5)
        app.tabBars.buttons["Reels"].tap()
        expectation(for: playing, evaluatedWith: second)
        waitForExpectations(timeout: 15)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "reel-playing-above-tab-bar"; shot.lifetime = .keepAlways; add(shot)
    }
}
