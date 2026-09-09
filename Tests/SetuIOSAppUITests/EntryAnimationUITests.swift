import XCTest

final class EntryAnimationUITests: XCTestCase {
    func testPasswordLoginWelcomeReachesDashboard() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-welcome-fixture"]
        app.launch()
        defer { app.terminate() }
        let email = app.buttons["auth.welcome.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 8))
        email.tap()
        let emailField = app.textFields["auth.login.email"]
        emailField.tap(); emailField.typeText("preview@example.com")
        let password = app.secureTextFields["auth.login.password"]
        password.tap(); password.typeText("fixture-password")
        let captcha = app.textFields["auth.login.captcha"]
        captcha.tap(); captcha.typeText("1234")
        app.buttons["完成"].firstMatch.tap()
        app.buttons["登录"].firstMatch.tap()
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["首页"].wait(for: \.isHittable, toEqual: true, timeout: 8))
        XCTAssertFalse(app.otherElements["app.brandSplash"].exists)
        XCTAssertFalse(app.buttons["auth.welcome.email"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "login-welcome-home"; shot.lifetime = .keepAlways; add(shot)
    }

    func testSignedInWelcomeDoesNotReplayOnForeground() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.tabBars.buttons["首页"].wait(for: \.isHittable, toEqual: true, timeout: 8))
        XCTAssertFalse(app.otherElements["app.brandSplash"].exists)
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertFalse(app.otherElements["app.brandSplash"].exists)
        XCTAssertTrue(app.tabBars.buttons["首页"].wait(for: \.isHittable, toEqual: true, timeout: 5))
    }
}
