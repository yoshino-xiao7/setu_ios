import XCTest

final class MusicCacheSettingsUITests: XCTestCase {
    func testCacheSettingsFromAccountKeepsMiniPlayerAvailable() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music-cache", "-ui-testing-root-player", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch(); defer { app.terminate() }
        let link = app.buttons["account.music-cache"]
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 15))
        for _ in 0..<3 where !link.isHittable { app.swipeUp() }
        XCTAssertTrue(link.exists)
        link.tap()
        let capacity = app.buttons["music.cache.capacity"]
        XCTAssertTrue(capacity.waitForExistence(timeout: 5))
        capacity.tap(); app.buttons["2GB"].firstMatch.tap()
        let network = app.buttons["music.cache.network"]
        network.tap(); app.buttons["所有网络"].firstMatch.tap()
        let bar = app.otherElements["music.mini-player"].firstMatch
        XCTAssertTrue(bar.isHittable)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "music-cache-settings-normal-font"; attachment.lifetime = .keepAlways; add(attachment)
        app.buttons["music.cache.clear"].tap()
        XCTAssertTrue(app.buttons["清空缓存"].waitForExistence(timeout: 5))
    }
}
