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
            let label = page == "conversation" ? "Can’t wait to see it! 🎨" : page == "chats" ? "Luna" : page == "bunny" ? "Save" : page == "community" ? "Sketchbook check-in 🌷" : "Mimi"
            XCTAssertTrue(app.staticTexts[label].firstMatch.waitForExistence(timeout: 20) || app.buttons[label].firstMatch.exists, "Missing demo content on \(page)")
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
