import XCTest

final class WelcomeFlowUITests: XCTestCase {
    func testSplashDoesNotReplayWhenReturningFromBackground() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-welcome-fixture"]
        app.launch()
        XCTAssertTrue(app.buttons["auth.welcome.email"].waitForExistence(timeout: 8))
        XCUIDevice.shared.press(.home)
        app.activate()
        XCTAssertTrue(app.buttons["auth.welcome.email"].isHittable)
        XCTAssertFalse(app.otherElements["app.brandSplash"].exists)
    }

    func testReducedMotionLaunchReachesWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-welcome-fixture", "-ui-testing-reduce-motion"]
        app.launch()
        XCTAssertTrue(app.buttons["auth.welcome.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["auth.welcome.email"].isHittable)
        XCTAssertFalse(app.otherElements["app.brandSplash"].exists)
    }

    func testSignedInSplashReachesAppWithoutShowingLogin() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images"]
        app.launch()
        XCTAssertTrue(app.buttons["图片设置"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["图片设置"].wait(for: \.isHittable, toEqual: true, timeout: 8))
        XCTAssertFalse(app.buttons["auth.welcome.email"].exists)
        XCTAssertFalse(app.otherElements["app.brandSplash"].exists)
    }

    func testSignedOutLaunchLeadsWithValueAndNativeAuthenticationChoices() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-session"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["auth.welcome.title"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.descendants(matching: .any)["auth.welcome.title"].label, "亦可 YK")
        XCTAssertEqual(app.staticTexts["auth.welcome.subtitle"].label, "图片、AI 创作与音乐")
        XCTAssertTrue(app.buttons["auth.welcome.apple"].isHittable)
        XCTAssertTrue(app.buttons["auth.welcome.email"].isHittable)
        XCTAssertTrue(app.buttons["auth.welcome.register"].isHittable)
        XCTAssertTrue(app.buttons["auth.welcome.passkey"].isHittable)
        XCTAssertFalse(app.buttons["auth.welcome.preview"].exists)
        XCTAssertTrue(app.buttons["auth.welcome.privacy"].exists)
        XCTAssertTrue(app.buttons["auth.welcome.terms"].exists)
        XCTAssertFalse(app.staticTexts["亦可 API"].exists)

        let accessibilityOrder = app.descendants(matching: .any)
            .allElementsBoundByAccessibilityElement
            .map(\.identifier)
        assertAppearsBefore("auth.welcome.title", "auth.welcome.subtitle", in: accessibilityOrder)
        assertAppearsBefore("auth.welcome.subtitle", "auth.welcome.email", in: accessibilityOrder)
        assertAppearsBefore("auth.welcome.email", "auth.welcome.apple", in: accessibilityOrder)
        assertAppearsBefore("auth.welcome.apple", "auth.welcome.register", in: accessibilityOrder)
    }

    func testEmailLoginAndReturnRemainReachable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-session"]
        app.launch()
        let emailEntry = app.buttons["auth.welcome.email"]
        XCTAssertTrue(emailEntry.waitForExistence(timeout: 8))
        emailEntry.tap()
        XCTAssertTrue(app.textFields["auth.login.email"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.secureTextFields["auth.login.password"].exists)
        app.buttons["返回"].firstMatch.tap()
        XCTAssertTrue(emailEntry.waitForExistence(timeout: 5))
    }

    func testLegalPagesCanReturnToWelcome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-session"]
        app.launch()
        for identifier in ["auth.welcome.privacy", "auth.welcome.terms"] {
            let entry = app.buttons[identifier]
            XCTAssertTrue(entry.waitForExistence(timeout: 8))
            entry.tap()
            let back = app.navigationBars.buttons.firstMatch
            XCTAssertTrue(back.waitForExistence(timeout: 5))
            XCTAssertTrue(back.isHittable)
            back.tap()
            XCTAssertTrue(app.buttons["auth.welcome.email"].waitForExistence(timeout: 5))
        }
    }

    func testRegistrationFormRemainsReachableWithKeyboardAndAccessibilityText() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-ui-testing-reset-session",
            "-UIPreferredContentSizeCategoryName",
            "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
        ]
        app.launch()

        let registerEntry = app.buttons["auth.welcome.register"]
        XCTAssertTrue(registerEntry.waitForExistence(timeout: 8))
        scrollUntilHittable(registerEntry, in: app)
        registerEntry.tap()

        let email = app.textFields["auth.register.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 5))
        email.tap()
        email.typeText("preview@example.com")

        let password = app.secureTextFields["auth.register.password"]
        if !password.isHittable { app.swipeUp() }
        XCTAssertTrue(password.exists)
        password.tap()
        password.typeText("preview-password")

        let confirmation = app.secureTextFields["auth.register.confirmation"]
        if !confirmation.isHittable { app.swipeUp() }
        XCTAssertTrue(confirmation.exists)
        confirmation.tap()
        confirmation.typeText("preview-password")

        let dismissKeyboard = app.buttons["完成"].firstMatch
        XCTAssertTrue(dismissKeyboard.waitForExistence(timeout: 3))
        dismissKeyboard.tap()

        let captcha = app.textFields["auth.register.captcha"]
        scrollUntilHittable(captcha, in: app)
        let submit = app.buttons["注册"]
        scrollUntilVisible(submit, in: app)
        let returnToLogin = app.buttons["已有账号？返回登录"]
        scrollUntilHittable(returnToLogin, in: app)
        try app.performAccessibilityAudit(for: [
            .hitRegion,
            .sufficientElementDescription,
            .trait,
        ])
    }

    func testWelcomeScreenPassesSystemAccessibilityAudit() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-reset-session"]
        app.launch()

        XCTAssertTrue(app.descendants(matching: .any)["auth.welcome.title"].waitForExistence(timeout: 8))
        try app.performAccessibilityAudit(for: [
            .hitRegion,
            .sufficientElementDescription,
            .textClipped,
            .trait,
        ])
    }

    private func scrollUntilHittable(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<maximumSwipes {
            if element.exists, element.isHittable {
                break
            }
            app.swipeUp()
        }

        XCTAssertTrue(element.exists, "滚动后仍未找到 \(element)", file: file, line: line)
        XCTAssertTrue(element.isHittable, "滚动后元素仍不可见或不可交互：\(element)", file: file, line: line)
    }

    private func scrollUntilVisible(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maximumSwipes: Int = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<maximumSwipes {
            if element.exists, element.frame.intersects(app.frame) {
                break
            }
            app.swipeUp()
        }

        XCTAssertTrue(element.exists, "滚动后仍未找到 \(element)", file: file, line: line)
        XCTAssertTrue(element.frame.intersects(app.frame), "滚动后元素仍不在可见区域：\(element)", file: file, line: line)
    }

    private func assertAppearsBefore(
        _ first: String,
        _ second: String,
        in identifiers: [String],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let firstIndex = identifiers.firstIndex(of: first),
              let secondIndex = identifiers.firstIndex(of: second) else {
            XCTFail("无障碍顺序中缺少 \(first) 或 \(second)", file: file, line: line)
            return
        }
        XCTAssertLessThan(firstIndex, secondIndex, file: file, line: line)
    }
}
