import XCTest

final class RandomImageConsumptionUITests: XCTestCase {
    func testFirstHighResolutionOpenRequiresExplicitPointsConfirmation() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-random-image"]
        app.launch()

        let unlockButton = app.buttons["image.unlock"]
        XCTAssertTrue(unlockButton.waitForExistence(timeout: 8))
        let enabled = expectation(
            for: NSPredicate(format: "isEnabled == true"),
            evaluatedWith: unlockButton
        )
        XCTAssertEqual(XCTWaiter.wait(for: [enabled], timeout: 8), .completed)

        unlockButton.tap()

        XCTAssertTrue(app.staticTexts["确认查看高清图？"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["image.unlock.confirm"].exists)
        XCTAssertTrue(app.buttons["取消"].exists)
        XCTAssertTrue(app.staticTexts["低清预览免费。当前余额：86 积分；同一张图片重复查看不会再次扣分。"].exists)
    }
}
