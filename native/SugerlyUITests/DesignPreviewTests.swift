import XCTest

final class DesignPreviewTests: XCTestCase {
    func testCaptureCompactPages() {
        continueAfterFailure = false
        for page in ["home", "community", "chats"] {
            let app = XCUIApplication()
            app.launchArguments = ["--polish-ui-test", "--design-preview", "--preview-" + page]
            app.launch()
            let expected = page == "chats" ? "Luna" : page == "community" ? "What’s happening?" : "Good"
            let ready = app.staticTexts.matching(NSPredicate(format: "label CONTAINS[c] %@", expected)).firstMatch
            XCTAssertTrue(ready.waitForExistence(timeout: 15))
            XCTAssertEqual(app.buttons.matching(identifier: "Menu").count, 1)
            XCTAssertEqual(app.buttons.matching(identifier: "Notifications").count, 1)
            XCTAssertTrue(app.buttons["Menu"].isHittable)
            XCTAssertTrue(app.buttons["Notifications"].isHittable)
            XCTAssertTrue(app.buttons[page == "chats" ? "New message" : "Create"].isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "compact-" + page
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
    func testAppearanceOptionsAndProfilePresets() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--polish-ui-test", "--design-preview", "--preview-appearance"]
        app.launch()
        let options = app.staticTexts["Top bar"]
        for _ in 0..<5 where !options.isHittable { app.swipeUp() }
        XCTAssertTrue(options.isHittable)
        app.buttons["Tinted"].tap()
        XCTAssertTrue(app.buttons["Tinted"].isSelected)
        let dreamy = app.buttons["Dreamy"]
        for _ in 0..<3 where !dreamy.isHittable { app.swipeUp() }
        dreamy.tap()
        XCTAssertTrue(dreamy.isSelected)
        let wallpaper = app.sliders["Wallpaper colour strength"]
        XCTAssertTrue(wallpaper.exists)
        wallpaper.adjust(toNormalizedSliderPosition: 0.5)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "appearance-options"; shot.lifetime = .keepAlways; add(shot)
        app.terminate()
        app.launchArguments = ["--polish-ui-test", "--design-preview", "--preview-profile"]
        app.launch()
        let lavender = app.buttons["Lavender profile theme"]
        for _ in 0..<7 where !lavender.isHittable { app.swipeUp() }
        XCTAssertTrue(lavender.isHittable)
        lavender.tap()
        XCTAssertTrue(lavender.isSelected)
        let mint = app.buttons["Mint soda profile theme"]
        for _ in 0..<2 where !mint.isHittable { app.swipeUp() }
        mint.tap()
        XCTAssertTrue(mint.isSelected)
        XCTAssertFalse(lavender.isSelected)
        let profile = XCTAttachment(screenshot: app.screenshot())
        profile.name = "profile-theme-presets"; profile.lifetime = .keepAlways; add(profile)
    }

}
