import XCTest

final class ChatHistoryInteractionTests: XCTestCase {
    func testBusyChatOpensAndComposerRemainsResponsive() {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["--polish-ui-test", "--design-preview", "--preview-chat-history"]
        app.launch()
        let input = app.descendants(matching: .any).matching(identifier: "chat-message-input").firstMatch
        XCTAssertTrue(input.waitForExistence(timeout: 10))
        input.tap()
        input.typeText("Still responsive")
        XCTAssertTrue(app.staticTexts["History message 399"].exists)
        XCTAssertFalse(app.staticTexts["History message 0"].exists)
        app.swipeDown()
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "busy-chat-responsive"; screenshot.lifetime = .keepAlways; add(screenshot)
    }
}
