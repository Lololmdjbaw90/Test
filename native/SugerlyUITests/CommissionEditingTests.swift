import XCTest

final class CommissionEditingTests: XCTestCase {
    func testDeletingSamplesAndFocusedPriceRowsKeepsEditorAlive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--polish-ui-test", "--design-preview", "--preview-commission"]
        app.launch()
        let removePhotos = app.buttons.matching(identifier: "Remove sample")
        XCTAssertTrue(removePhotos.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(removePhotos.count, 3)
        removePhotos.element(boundBy: 1).tap()
        XCTAssertEqual(removePhotos.count, 2)
        removePhotos.firstMatch.tap()
        XCTAssertEqual(removePhotos.count, 1)
        removePhotos.firstMatch.tap()
        XCTAssertEqual(removePhotos.count, 0)
        let rows = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'commission-remove-tier-'"))
        for _ in 0..<4 where !rows.firstMatch.isHittable { app.swipeUp() }
        let names = app.textFields.matching(identifier: "Size name (e.g. Headshot)")
        let first = names.firstMatch
        XCTAssertTrue(first.isHittable)
        first.tap()
        first.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 6))
        rows.firstMatch.tap()
        XCTAssertEqual(names.count, 2)
        XCTAssertEqual(names.firstMatch.value as? String, "Colour")
        names.firstMatch.tap()
        names.firstMatch.typeText(" edited")
        XCTAssertTrue((names.firstMatch.value as? String ?? "").contains("edited"))
        rows.firstMatch.tap()
        XCTAssertEqual(names.count, 1)
        XCTAssertEqual(names.firstMatch.value as? String, "Portrait")
        app.swipeUp()
        let addSize = app.buttons["Add a size"]
        XCTAssertTrue(addSize.waitForExistence(timeout: 3))
        for _ in 0..<3 where !addSize.isHittable { app.swipeUp() }
        addSize.tap()
        XCTAssertEqual(names.count, 2)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "commission-after-deletions"; shot.lifetime = .keepAlways; add(shot)
    }
}
