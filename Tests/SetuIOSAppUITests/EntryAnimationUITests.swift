import XCTest

final class EntryAnimationUITests: XCTestCase {
    func testGeneralSettingsAndProfileLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music-cache", "-ui-testing-artwork-admin"]
        app.launch()
        defer { app.terminate() }
        let imageSettings = app.buttons["account.image-display"]
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 15))
        for _ in 0..<5 where !imageSettings.isHittable { app.swipeUp() }
        XCTAssertTrue(imageSettings.exists)
        XCTAssertTrue(app.staticTexts["通用设置"].exists)
        attachAccount(app, "general-settings")
        imageSettings.tap()
        XCTAssertTrue(app.switches["settings.images.blur-previews"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let diagnostics = app.buttons["account.diagnostics"]
        for _ in 0..<3 where !diagnostics.isHittable { app.swipeUp() }
        diagnostics.tap()
        XCTAssertTrue(app.navigationBars["故障排查"].waitForExistence(timeout: 5))
        app.buttons["会话与登录状态"].tap()
        XCTAssertTrue(app.buttons["检查会话状态"].waitForExistence(timeout: 5))
        app.navigationBars.buttons.firstMatch.tap()
        let profile = app.buttons["个人资料，头像、昵称和账号信息"]
        for _ in 0..<5 where !profile.isHittable { app.swipeDown() }
        profile.tap()
        XCTAssertTrue(app.textFields["profile.nickname"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["profile.avatar.change"].exists)
        attachAccount(app, "profile-editor")
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["账号信息"].waitForExistence(timeout: 5))
        attachAccount(app, "profile-account-info")
    }

    private func attachAccount(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name; shot.lifetime = .keepAlways; add(shot)
    }

    func testReturningFromAccountRetainsDashboardResources() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player"]
        app.launch()
        defer { app.terminate() }
        let greeting = app.otherElements["dashboard.greeting"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 15))
        XCTAssertTrue(app.images["hub.logo.HomeLogo"].exists)
        XCTAssertEqual(app.buttons.matching(identifier: "我的").count, 1)
        let before = greeting.value as? String
        XCTAssertTrue(before?.contains("loads=1") == true)
        app.buttons["我的"].tap()
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 8))
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(greeting.waitForExistence(timeout: 8))
        XCTAssertEqual(greeting.value as? String, before, "返回首页不能重新加载首页资源")
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "home-account-return"; shot.lifetime = .keepAlways; add(shot)
    }

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
