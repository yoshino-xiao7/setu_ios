import XCTest

final class MusicLibraryUITests: XCTestCase {
    func testLikedPaginationAndPlaybackIntent() {
        let app = launch(); defer { app.terminate() }
        XCTAssertTrue(app.buttons["播放 发现测试歌曲"].waitForExistence(timeout: 10))
        app.buttons["加载更多"].tap()
        XCTAssertTrue(app.buttons["播放 第二页测试歌曲"].waitForExistence(timeout: 5))
        app.buttons["播放 发现测试歌曲"].tap()
        XCTAssertTrue(app.buttons["打开正在播放：发现测试歌曲"].waitForExistence(timeout: 5))
        attach(app, "p15-liked-pagination-playback")
    }
    func testUnlikeFailureRollbackAndFeedback() {
        let app = launch(extra: ["-ui-testing-library-write-failure", "-ui-testing-library-single"]); defer { app.terminate() }
        let heart = app.buttons["取消喜欢 发现测试歌曲"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10)); heart.tap()
        XCTAssertTrue(app.staticTexts["用户库测试错误"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(heart.waitForExistence(timeout: 5))
        attach(app, "p15-liked-failure-rollback")
    }
    func testUnlikeSuccessAndSavedList() {
        let app = launch(extra: ["-ui-testing-library-single"]); defer { app.terminate() }
        let heart = app.buttons["取消喜欢 发现测试歌曲"]
        XCTAssertTrue(heart.waitForExistence(timeout: 10)); heart.tap()
        XCTAssertTrue(app.staticTexts["暂无喜欢的歌曲"].waitForExistence(timeout: 5))
        app.buttons["收藏歌单"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["收藏歌单"].waitForExistence(timeout: 5))
        app.buttons["取消收藏"].tap()
        XCTAssertTrue(app.staticTexts["暂无收藏歌单"].waitForExistence(timeout: 5))
        attach(app, "p15-liked-saved-empty-after-remove")
    }
    func testEmptyErrorUnauthorized() {
        for (arg, label) in [("empty", "暂无喜欢的歌曲"), ("error", "用户库测试错误"), ("unauthorized", "请先登录")] {
            let app = launch(extra: ["-ui-testing-library-\(arg)"] + (arg == "unauthorized" ? ["-ui-testing-root-401"] : []))
            if arg == "unauthorized" {
                // Account reset must restart the page task and leave a usable sign-in state.
                XCTAssertTrue(app.staticTexts["请先登录"].firstMatch.waitForExistence(timeout: 10))
                XCTAssertTrue(app.buttons["重新登录"].exists)
            } else {
                XCTAssertTrue(app.staticTexts[label].firstMatch.waitForExistence(timeout: 10))
            }
            attach(app, "p15-liked-\(arg)"); app.terminate()
        }
    }
    func testFalseFlagsHideLibraryEntries() {
        let app = XCUIApplication(); app.launchArguments = ["-ui-testing-root-music", "-ui-testing-music-discover"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["音乐"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["我喜欢"].exists); XCTAssertFalse(app.buttons["收藏歌单"].exists)
    }
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music", "-ui-testing-music-discover", "-ui-testing-music-library",
            "-ui-testing-discover-page", "likedTracks"] + extra
        app.launch(); return app
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let a = XCTAttachment(screenshot: app.screenshot()); a.name = name; a.lifetime = .keepAlways; add(a)
    }
}
