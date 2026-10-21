import XCTest

final class PerformanceInteractionTests: XCTestCase {
    func testRecordingPausesDecorativeGIFAndRestoresItAfterwards() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--polish-ui-test", "--check-recording-policy"]
        app.launch()
        let animated = app.otherElements["decoded-gif-animation"].firstMatch
        XCTAssertTrue(animated.waitForExistence(timeout: 5))
        app.buttons["Start recording simulation"].tap()
        expectation(for: NSPredicate { _, _ in !app.otherElements["decoded-gif-animation"].firstMatch.exists }, evaluatedWith: app)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.staticTexts["recording-budget-state"].label, "Recording budget active")
        app.buttons["Stop recording simulation"].tap()
        XCTAssertTrue(app.otherElements["decoded-gif-animation"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["recording-budget-state"].label, "Normal rendering")
    }

    func testProductionMotionPolicyAndHomeScrolling() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--polish-ui-test", "--check-performance-policy"]
        app.launch()
        let policy = app.staticTexts["performance-policy"]
        XCTAssertTrue(policy.waitForExistence(timeout: 5))
        XCTAssertEqual(policy.label, "Performance fixtures passed")
        app.buttons["Home"].tap()
        let feed = app.scrollViews["home-feed"]
        XCTAssertTrue(feed.waitForExistence(timeout: 5))
        feed.swipeUp()
        feed.swipeDown()
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        options.invocationOptions = [.manuallyStop]
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            feed.swipeUp(velocity: .fast)
            stopMeasuring()
            feed.swipeDown(velocity: .fast)
        }
        XCTAssertTrue(app.buttons["home-compose-post"].exists)
    }
}
