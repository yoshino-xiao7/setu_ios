import XCTest
final class ArtworkBrowserUITests: XCTestCase {
    func testOpeningLoadedCardDoesNotReplaceArtworkWithSpinner() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images", "-ui-testing-artwork-continuity"]
        app.launch()
        XCTAssertTrue(app.buttons["本站图库"].waitForExistence(timeout: 15))
        app.buttons["本站图库"].tap()
        let title = app.staticTexts["画集 1"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 8))
        title.tap()
        XCTAssertTrue(app.buttons["关闭作品"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["正在加载作品"].exists,
                       "A loaded card must remain visible while its detail request is pending")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "artwork-opening-continuity"; screenshot.lifetime = .keepAlways; add(screenshot)
    }

    func testSwipePagingLongPressAndCompactDetail() { checkDetail(dark: false) }
    func testDarkSwipePagingLongPressAndCompactDetail() { checkDetail(dark: true) }
    private func checkDetail(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images"] + (dark ? ["Dark"] : [])
        app.launch()
        XCTAssertTrue(app.buttons["本站图库"].waitForExistence(timeout: 15))
        app.buttons["本站图库"].tap()
        XCTAssertTrue(app.staticTexts["画集 1"].firstMatch.waitForExistence(timeout: 8))
        app.staticTexts["画集 1"].firstMatch.tap()
        XCTAssertTrue(app.buttons["关闭作品"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["下一部作品"].exists)
        XCTAssertFalse(app.buttons["上一部作品"].exists)
        XCTAssertTrue(app.buttons["artwork-favorite"].exists)
        app.buttons["artwork-favorite"].tap()
        XCTAssertTrue(app.buttons["取消收藏作品"].waitForExistence(timeout: 5))
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.45))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.68, dy: 0.45)))
        XCTAssertTrue(app.buttons["artwork-image-1-0"].isHittable, "A cancelled swipe must retain the current artwork")
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.45))
        center.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45)))
        XCTAssertTrue(app.buttons["artwork-image-2-0"].waitForExistence(timeout: 8))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.45))
            .press(forDuration: 0.05, thenDragTo: center)
        let image = app.buttons["artwork-image-1-0"]
        XCTAssertTrue(image.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["正在加载作品"].exists)
        image.press(forDuration: 1.2)
        XCTAssertTrue(app.buttons["保存原图"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["保存整部作品（2 张）"].exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.25)).tap()
        app.swipeLeft()
        XCTAssertTrue(app.buttons["artwork-image-2-0"].waitForExistence(timeout: 8))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.7))
            .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = dark ? "artwork-detail-compact-dark" : "artwork-detail-compact-light"
        shot.lifetime = .keepAlways; add(shot)
        app.buttons["关闭作品"].tap()
        XCTAssertTrue(app.buttons["本站图库"].waitForExistence(timeout: 8))
    }

    func testPIDImportSubmitsDirectlyWithoutAnotherForm() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images", "-ui-testing-artwork-admin"]
        app.launch()
        XCTAssertTrue(app.buttons["Pixiv 在线"].waitForExistence(timeout: 15))
        app.buttons["Pixiv 在线"].tap()
        XCTAssertTrue(app.staticTexts["画集 1"].firstMatch.waitForExistence(timeout: 8))
        app.staticTexts["画集 1"].firstMatch.tap()
        XCTAssertTrue(app.buttons["作品操作"].waitForExistence(timeout: 8))
        app.buttons["作品操作"].tap()
        app.buttons["通过 PID 导入本站"].tap()
        XCTAssertTrue(app.staticTexts["已提交 PID 1，可在管理员页面的「图片任务」查看进度和结果。"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["提交 PID"].exists)
        app.buttons["知道了"].tap()
        app.buttons["作品操作"].tap()
        XCTAssertTrue(app.buttons["已提交至管理员图片任务"].exists)
        XCTAssertFalse(app.buttons["已提交至管理员图片任务"].isEnabled)
    }

    func testAdminTaskHistoryShowsVerifiedResultsAndRetry() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-image-tasks", "-ui-testing-artwork-admin"]
        app.launch()
        XCTAssertTrue(app.navigationBars["图片任务"].waitForExistence(timeout: 15))
        app.swipeUp()
        let row = app.buttons["pixiv-task-detail-fixture-import-task"]
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        XCTAssertTrue(app.navigationBars["任务详情"].waitForExistence(timeout: 8))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["已进入图库"].exists)
        XCTAssertTrue(app.buttons["重试 PID 2"].exists)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "artwork-admin-task-results"; shot.lifetime = .keepAlways; add(shot)
    }

    func testCustomImageHostSettingsRejectInvalidInput() {
        checkCustomImageHostSettings(dark: false)
    }
    func testDarkCustomImageHostSettingsRejectInvalidInput() {
        checkCustomImageHostSettings(dark: true)
    }
    private func checkCustomImageHostSettings(dark: Bool) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images"]
        if dark { app.launchArguments.append("Dark") }
        app.launch()
        XCTAssertTrue(app.buttons["图片设置"].waitForExistence(timeout: 15))
        app.buttons["图片设置"].tap()
        app.buttons["图片图床"].tap()
        let custom = app.buttons["自定义图床"]
        if custom.exists { custom.tap() } else { app.staticTexts["自定义图床"].tap() }
        let field = app.textFields["自定义图床域名"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let layout = XCTAttachment(screenshot: app.screenshot())
        layout.name = "images-custom-host-settings"; layout.lifetime = .keepAlways; add(layout)
        field.tap(); field.typeText("http://images.example.org")
        app.buttons["保存"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "请输入 HTTPS 图床域名")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
    }

    func testPixivLoginPageOnPhysicalDevice() throws {
        #if targetEnvironment(simulator)
        throw XCTSkip("Physical-device login transport verification")
        #else
        let app = XCUIApplication()
        app.launch()
        guard app.buttons["图片"].firstMatch.waitForExistence(timeout: 20) else { throw XCTSkip("Requires existing Setu login") }
        app.buttons["图片"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Pixiv 在线"].waitForExistence(timeout: 10))
        app.buttons["Pixiv 在线"].tap()
        guard app.buttons["登录 Pixiv"].waitForExistence(timeout: 10) else { throw XCTSkip("Pixiv may already be bound") }
        app.buttons["登录 Pixiv"].tap()
        let loginForm = app.webViews.textFields.firstMatch
        XCTAssertTrue(loginForm.waitForExistence(timeout: 60), "Real login page must display an input field")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "pixiv-device-login-page"; screenshot.lifetime = .keepAlways; add(screenshot)
        // Do not enter, inspect or submit the user's credentials.
        #endif
    }
    func testDarkHome() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images", "Dark"]
        app.launch()
        XCTAssertTrue(app.buttons["Pixiv 在线"].waitForExistence(timeout: 15))
        app.buttons["Pixiv 在线"].tap()
        XCTAssertTrue(app.staticTexts["为你推荐"].waitForExistence(timeout: 15))
        let image = XCTAttachment(screenshot: app.screenshot()); image.name = "images-home-dark"; image.lifetime = .keepAlways; add(image)
    }
    func testHomeAndGalleryRemainFree() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images"]
        app.launch()
        XCTAssertTrue(app.buttons["Pixiv 在线"].waitForExistence(timeout: 15))
        app.buttons["Pixiv 在线"].tap()
        XCTAssertTrue(app.staticTexts["为你推荐"].waitForExistence(timeout: 15))
        let home = XCTAttachment(screenshot: app.screenshot()); home.name = "images-home"; home.lifetime = .keepAlways; add(home)
        app.buttons["本站图库"].tap()
        XCTAssertTrue(app.staticTexts["画集 1"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["积分不足"].exists)
        app.staticTexts["画集 1"].firstMatch.tap()
        XCTAssertTrue(app.buttons["关闭作品"].waitForExistence(timeout: 8))
        let detail = XCTAttachment(screenshot: app.screenshot()); detail.name = "images-detail"; detail.lifetime = .keepAlways; add(detail)
    }
}
