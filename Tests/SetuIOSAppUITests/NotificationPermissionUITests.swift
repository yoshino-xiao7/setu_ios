import XCTest

final class NotificationPermissionUITests: XCTestCase {
    func testPermissionPrePromptAndDeniedRecoveryEntry() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-notification-permission"]
        app.launch()

        XCTAssertTrue(app.otherElements["notifications.permission.prompt"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["系统通知"].exists)
        XCTAssertTrue(app.staticTexts["用于作品生成完成、投稿结果和账号安全提醒"].exists)
        XCTAssertTrue(app.staticTexts["尚未设置"].exists)
        XCTAssertTrue(app.buttons["开启通知"].exists)

        app.buttons["notifications.permission.simulate-denied"].tap()

        XCTAssertTrue(app.staticTexts["已关闭"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["前往系统设置"].exists)
    }
}
