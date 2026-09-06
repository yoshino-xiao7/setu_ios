import XCTest

final class AiDrawDraftUITests: XCTestCase {
    func testDualCharacterModeIsVisibleInMainCreationFlow() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-ai-draft"]
        app.launch()

        let openButton = app.buttons["ai.draft.open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 8))
        openButton.tap()

        let modePicker = app.descendants(matching: .any)["ai.draw.generationMode"].firstMatch
        XCTAssertTrue(modePicker.waitForExistence(timeout: 8))
        let dualButton = modePicker.buttons["双人物"]
        XCTAssertTrue(dualButton.exists)
        dualButton.tap()
        XCTAssertTrue(app.staticTexts["双人物已开启，请在角色库分别选择主角色和副角色"].waitForExistence(timeout: 3))
    }

    func testDraftRestoresAfterLeavingAndReopeningTheEditor() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-ai-draft"]
        app.launch()

        let openButton = app.buttons["ai.draft.open"]
        XCTAssertTrue(openButton.waitForExistence(timeout: 8))
        openButton.tap()

        let prompt = app.textFields["ai.draw.prompt"]
        XCTAssertTrue(prompt.waitForExistence(timeout: 8))
        prompt.tap()
        prompt.typeText("，紫色雨伞")

        let closeButton = app.buttons["ai.draft.close"]
        XCTAssertTrue(closeButton.exists)
        closeButton.tap()

        XCTAssertTrue(openButton.waitForExistence(timeout: 5))
        openButton.tap()

        let restoredPrompt = app.textFields["ai.draw.prompt"]
        XCTAssertTrue(restoredPrompt.waitForExistence(timeout: 8))
        XCTAssertTrue((restoredPrompt.value as? String)?.contains("紫色雨伞") == true)
    }
}
