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

    func testBunnyThreeLayerLimitAndMobileAdjustments() {
        app.buttons["Open bunny"].tap()
        let outfit = app.buttons["Outfit"].firstMatch
        XCTAssertTrue(outfit.waitForExistence(timeout: 5))
        for _ in 0..<4 where !outfit.isHittable { app.scrollViews.firstMatch.swipeUp() }
        outfit.tap()
        let none = app.buttons["None"].firstMatch
        for _ in 0..<4 where !none.isHittable { app.scrollViews.firstMatch.swipeUp() }
        none.tap()
        for name in ["T-shirt", "Hoodie", "Ruffles", "Sailor"] {
            let item = app.buttons[name].firstMatch
            for _ in 0..<3 where !item.isHittable { app.scrollViews.firstMatch.swipeUp() }
            item.tap()
        }
        let arrange = app.buttons["Arrange layers (3/3)"].firstMatch
        for _ in 0..<8 where !arrange.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(arrange.isHittable)
        arrange.tap()
        let rotation = app.sliders["Rotation"]
        XCTAssertTrue(rotation.waitForExistence(timeout: 3))
        for _ in 0..<4 where !rotation.isHittable { app.scrollViews.firstMatch.swipeUp() }
        rotation.adjust(toNormalizedSliderPosition: 0.65)
        app.sliders["Left / right"].adjust(toNormalizedSliderPosition: 0.6)
        capture("bunny-mobile-layer-editor")
        app.buttons["Done"].tap()
        XCTAssertTrue(arrange.waitForExistence(timeout: 3))
    }

    func testMimiPlusRepeatedPlanChangesUpdateCost() {
        app.buttons["Open MimiPlus"].tap()
        let month = app.buttons["mimiplus-plan-month"]
        let season = app.buttons["mimiplus-plan-season"]
        XCTAssertTrue(month.waitForExistence(timeout: 5))
        let purchase = app.buttons["mimiplus-purchase"]
        for _ in 0..<5 where season.frame.maxY >= purchase.frame.minY - 20 {
            app.scrollViews.firstMatch.swipeUp()
        }
        for _ in 0..<6 {
            season.tap()
            XCTAssertEqual(app.buttons["mimiplus-purchase"].label.filter(\.isNumber), "2000")
            XCTAssertTrue(season.isSelected)
            month.tap()
            XCTAssertEqual(app.buttons["mimiplus-purchase"].label.filter(\.isNumber), "800")
            XCTAssertTrue(month.isSelected)
        }
        capture("mimiplus-after-switching")
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Open MimiPlus"].waitForExistence(timeout: 3))
    }
}
