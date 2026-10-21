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
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "compact-" + page
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
