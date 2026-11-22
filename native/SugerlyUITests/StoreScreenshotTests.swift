import XCTest

final class StoreScreenshotTests: XCTestCase {
    func testCaptureStorePages() {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        for page in ["home", "community", "chats", "conversation", "bunny"] {
            let app = XCUIApplication()
            app.launchArguments = ["--store-screenshots", "--store-" + page]
            app.launch()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
            // Let startup layout and bundled bunny assets settle before capture.
            sleep(5)
            let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            shot.name = "store-" + page
            shot.lifetime = .keepAlways
            add(shot)
            app.terminate()
        }
    }
}
