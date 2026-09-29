import XCTest

final class EditorInteractionTests: XCTestCase {
    private var app: XCUIApplication!
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--polish-ui-test"]
        app.launch()
    }

    private func screenshot(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testTextTimingCanBeSelectedAndChanged() {
        XCTAssertTrue(app.staticTexts["Fonts loaded"].waitForExistence(timeout: 10))
        let track = app.buttons["overlay-track-00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(track.waitForExistence(timeout: 5))
        track.tap()
        XCTAssertTrue(app.buttons["Timing"].waitForExistence(timeout: 3))
        app.buttons["Timing"].tap()
        let start = app.sliders["Appears"]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        start.adjust(toNormalizedSliderPosition: 0.5)
        screenshot("text-timing")
        app.buttons["Done"].tap()
        let value = app.staticTexts["timing-value"].label.split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(value.count, 2)
        XCTAssertGreaterThan(value[0], 1.5)
        XCTAssertLessThan(value[0], value[1])
        screenshot("timeline")
    }

    func testTextTrackDragKeepsItsDuration() {
        let track = app.buttons["overlay-track-00000000-0000-0000-0000-000000000001"]
        XCTAssertTrue(track.waitForExistence(timeout: 10))
        let from = track.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.1, thenDragTo: from.withOffset(CGVector(dx: 45, dy: 0)))
        let value = app.staticTexts["timing-value"].label.split(separator: ",").compactMap { Double($0) }
        XCTAssertEqual(value.count, 2)
        XCTAssertGreaterThan(value[0], 1.2)
        XCTAssertEqual(value[1] - value[0], 6, accuracy: 0.1)
    }

    func testTextPreviewAndKeyboardControls() {
        app.buttons["Text"].tap()
        let field = app.textFields.firstMatch.exists ? app.textFields.firstMatch : app.textViews.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText("A little pink moment")
        XCTAssertTrue(app.buttons["Hide keyboard"].waitForExistence(timeout: 3))
        screenshot("text-keyboard")
        app.buttons["Hide keyboard"].tap()
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Text track: A little pink moment"].waitForExistence(timeout: 3))
    }

    func testFanartButtonsDoNotOpenTheWrongPage() {
        app.buttons["Fanart"].tap()
        app.buttons["Like artwork"].tap()
        XCTAssertEqual(app.staticTexts["art-action"].label, "Liked artwork")
        app.buttons["Luna"].tap()
        XCTAssertEqual(app.staticTexts["art-action"].label, "Opened artist")
        app.buttons["Open Pink sketch"].tap()
        XCTAssertEqual(app.staticTexts["art-action"].label, "Opened artwork")
        screenshot("fanart-card")
    }
}
