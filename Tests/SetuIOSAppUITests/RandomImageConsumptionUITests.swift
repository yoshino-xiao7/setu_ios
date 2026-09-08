import XCTest

final class RandomImageConsumptionUITests: XCTestCase {
    func testOriginalImageOpensWithoutPointsConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-random-image"]
        app.launch()
        let original = app.buttons["image.unlock"]
        XCTAssertTrue(original.waitForExistence(timeout: 8))
        let enabled = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: original)
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)
        original.tap()
        XCTAssertFalse(app.staticTexts["确认查看高清图？"].exists)
        XCTAssertFalse(app.staticTexts["积分不足"].exists)
    }
}
