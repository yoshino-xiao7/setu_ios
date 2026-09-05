import XCTest

final class RadioFMUITests: XCTestCase {
    func testEntryHiddenWithProductionDefaultsAndFMFixtureControls() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music", "-ui-testing-music-discover", "-ui-testing-discover-page", "home"]
        app.launch()
        XCTAssertTrue(app.buttons["排行榜"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["电台"].exists)
        app.terminate()
        app.launchArguments += ["-ui-testing-radio-fm"]
        app.launch()
        XCTAssertTrue(app.buttons["电台"].waitForExistence(timeout: 10))
        app.buttons["电台"].tap()
        XCTAssertTrue(app.navigationBars["私人 FM"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["FM 测试歌曲 0"].firstMatch.waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["不再播放"].firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "P14 FM standard"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["不再播放"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["FM 测试歌曲 1"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["FM 测试歌曲 0"].exists)
        app.terminate()
    }

    func testFMAccessibilityLayout() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music", "-ui-testing-music-discover", "-ui-testing-radio-fm",
            "-ui-testing-discover-page", "radioFM", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXXXL"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["私人 FM"].waitForExistence(timeout: 10))
        let block = app.buttons["不再播放"].firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 10))
        XCTAssertGreaterThanOrEqual(block.frame.height, 44)
        XCTAssertGreaterThanOrEqual(block.frame.width, 44)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "P14 FM AX5"; attachment.lifetime = .keepAlways; add(attachment)
    }
}
