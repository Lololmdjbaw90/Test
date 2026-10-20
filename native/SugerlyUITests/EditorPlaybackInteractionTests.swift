import XCTest

final class EditorPlaybackInteractionTests: XCTestCase {
    func testLandscapePreviewLoopsAndExportsPortrait() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--editor-loop-ui-test"]
        app.launch()
        expectation(for: NSPredicate(format: "label == 'looping'"), evaluatedWith: app.staticTexts["editor-loop-state"])
        waitForExpectations(timeout: 25)
        app.buttons["Export portrait"].tap()
        expectation(for: NSPredicate(format: "label == '1080x1920 passed'"), evaluatedWith: app.staticTexts["editor-export-result"])
        waitForExpectations(timeout: 40)
    }
}
