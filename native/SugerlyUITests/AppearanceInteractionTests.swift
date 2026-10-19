import XCTest

final class AppearanceInteractionTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--appearance-ui-test"]
        app.launch()
    }

    private func capture(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    func testTitlesFitAndFollowThemeAfterSearch() {
        XCTAssertTrue(app.buttons["Mint"].waitForExistence(timeout: 10))
        capture("outlined-titles-rose")
        app.buttons["Search"].tap()
        XCTAssertTrue(app.textFields["Search"].waitForExistence(timeout: 3))
        app.buttons["Cancel"].tap()
        app.buttons["Mint"].tap()
        capture("outlined-titles-mint")
        app.buttons["Dark mode"].tap()
        capture("outlined-titles-mint-dark")
        XCTAssertTrue(app.buttons["Open MimiPlus"].isHittable)
    }

    func testMimiPlusRepeatedPlanChangesUpdateCost() {
        app.buttons["Open MimiPlus"].tap()
        let month = app.buttons["mimiplus-plan-month"]
        let season = app.buttons["mimiplus-plan-season"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        if !month.isHittable { app.scrollViews.firstMatch.swipeUp() }
        for _ in 0..<6 {
            season.tap()
            XCTAssertTrue(app.buttons["You need 2000 more coins"].waitForExistence(timeout: 2))
            XCTAssertTrue(season.isSelected)
            month.tap()
            XCTAssertTrue(app.buttons["You need 800 more coins"].waitForExistence(timeout: 2))
            XCTAssertTrue(month.isSelected)
        }
        capture("mimiplus-after-switching")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Open MimiPlus"].waitForExistence(timeout: 3))
    }
}
