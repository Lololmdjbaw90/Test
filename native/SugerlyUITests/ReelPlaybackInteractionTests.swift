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
        expectation(for: NSPredicate { value, _ in
            guard let element = value as? XCUIElement, let count = Int(element.label) else { return false }
            return count >= 2
        }, evaluatedWith: app.staticTexts["clip-0-loops"])
        waitForExpectations(timeout: 15)
        let videoTap = app.scrollViews["reel-feed"].coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        videoTap.tap()
        expectation(for: NSPredicate { _, _ in app.staticTexts["clip-0-state"].label == "paused" }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        videoTap.tap()
        expectation(for: NSPredicate { _, _ in app.staticTexts["clip-0-state"].label == "playing" }, evaluatedWith: app)
        waitForExpectations(timeout: 10)
        XCTAssertTrue(app.buttons["Like"].firstMatch.isHittable)
        XCTAssertTrue(app.buttons["Save"].firstMatch.isHittable)
        XCTAssertTrue(app.buttons["Comments"].firstMatch.isHittable)
        XCTAssertFalse(app.staticTexts["Playback test 1"].isHittable, "The next reel must stay below the clipped viewport")
        let share = app.buttons["Share"].firstMatch
        XCTAssertTrue(share.exists)
        XCTAssertLessThan(share.frame.maxY, app.tabBars.firstMatch.frame.minY)
        share.tap()
        XCTAssertTrue(app.staticTexts["Send to"].waitForExistence(timeout: 5))
        // Dismiss using a drag beginning inside the sheet, away from its buttons.
        let sheetTitle = app.staticTexts["Send to"]
        let sheetTop = sheetTitle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
        sheetTop.press(forDuration: 0.05, thenDragTo: sheetTop.withOffset(CGVector(dx: 0, dy: 550)))
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: sheetTitle)
        waitForExpectations(timeout: 5)
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
        XCTAssertGreaterThanOrEqual(Int(app.staticTexts["clip-1-restarts"].label) ?? 0, 1)
        app.buttons["Open single reel"].tap()
        let back = app.buttons["Back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "Back").count, 1)
        XCTAssertLessThan(back.frame.minX, 30)
        if app.statusBars.firstMatch.exists {
            XCTAssertGreaterThanOrEqual(back.frame.minY, app.statusBars.firstMatch.frame.maxY)
        } else {
            XCTAssertGreaterThanOrEqual(back.frame.minY, 24, "Back must clear the system status area")
        }
        back.tap()
        XCTAssertTrue(app.buttons["Open single reel"].waitForExistence(timeout: 5))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "reel-playing-above-tab-bar"; shot.lifetime = .keepAlways; add(shot)
    }
    func testMusicWidgetDragsAndReturnsAfterReels() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--reel-playback-ui-test"]
        app.launch()
        XCTAssertTrue(app.buttons["Open single reel"].waitForExistence(timeout: 15))
        app.tabBars.buttons["Home"].tap()
        app.buttons["Start test music"].tap()
        let state = app.staticTexts["music-state"]
        expectation(for: NSPredicate(format: "label == 'playing'"), evaluatedWith: state)
        waitForExpectations(timeout: 10)
        let handle = app.descendants(matching: .any).matching(identifier: "music-widget-handle").firstMatch
        XCTAssertTrue(handle.exists)
        let oldY = handle.frame.midY
        let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -100)))
        XCTAssertLessThan(handle.frame.midY, oldY - 40)
        let movedY = handle.frame.midY
        app.tabBars.buttons["Reels"].tap()
        expectation(for: NSPredicate(format: "label == 'hidden'"), evaluatedWith: state)
        waitForExpectations(timeout: 5)
        XCTAssertFalse(handle.isHittable)
        app.tabBars.buttons["Home"].tap()
        expectation(for: NSPredicate(format: "label == 'playing'"), evaluatedWith: state)
        waitForExpectations(timeout: 10)
        XCTAssertEqual(handle.frame.midY, movedY, accuracy: 6)
    }

}
