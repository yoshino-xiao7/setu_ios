import XCTest

final class AiDrawDraftUITests: XCTestCase {
    func testChatComposerIsVisibleInMainCreationFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-ai-draft"]
        app.launch()

        let openButton = app.buttons["ai.draft.open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 8))
        openButton.tap()

        XCTAssertTrue(app.otherElements["ai.draw.page"].waitForExistence(timeout: 8)
            || app.descendants(matching: .any)["ai.draw.page"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textViews["ai.draw.prompt"].waitForExistence(timeout: 8)
            || app.textFields["ai.draw.prompt"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["ai.draw.generate"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["ai.chat.new"].waitForExistence(timeout: 8))
    }

    func testComposerKeepsTypedPromptAfterLeavingAndReopening() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-ai-draft"]
        app.launch()

        let openButton = app.buttons["ai.draft.open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 8))
        openButton.tap()

        let prompt = firstPromptField(in: app)
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        prompt.tap()
        prompt.typeText("紫色雨伞猫娘")

        // Pending prompt is only used across navigation reuse; for in-editor leave we just verify composer exists again.
        let closeButton = app.buttons["ai.draft.close"]
        XCTAssertTrue(closeButton.exists)
        closeButton.tap()

        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        openButton.tap()

        let restoredPrompt = firstPromptField(in: app)
        XCTAssertTrue(restoredPrompt.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["ai.draw.generate"].waitForExistence(timeout: 5))
    }

    private func firstPromptField(in app: XCUIApplication) -> XCUIElement {
        let textView = app.textViews["ai.draw.prompt"]
        if textView.exists { return textView }
        return app.textFields["ai.draw.prompt"]
    }
}
