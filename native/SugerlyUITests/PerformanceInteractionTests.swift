import XCTest

final class PerformanceInteractionTests: XCTestCase {
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
