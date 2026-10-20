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
        let dragStart = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.82))
        let dragEnd = feed.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.08))
        dragStart.press(forDuration: 0.05, thenDragTo: dragEnd)
        let second = app.staticTexts["clip-1-state"]
        expectation(for: playing, evaluatedWith: second)
        waitForExpectations(timeout: 15)
        app.tabBars.buttons["Home"].tap()
        expectation(for: NSPredicate(format: "label == 'paused'"), evaluatedWith: second)
        waitForExpectations(timeout: 5)
        app.tabBars.buttons["Reels"].tap()
        expectation(for: playing, evaluatedWith: second)
        waitForExpectations(timeout: 15)
        app.buttons["Open single reel"].tap()
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Back").count, 1)
        XCTAssertLessThan(back.frame.minX, 30)
        XCTAssertGreaterThanOrEqual(back.frame.minY, app.statusBars.firstMatch.frame.maxY)
        back.tap()
        XCTAssertTrue(app.buttons["Open single reel"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "reel-playing-above-tab-bar"; shot.lifetime = .keepAlways; add(shot)
    }
}
