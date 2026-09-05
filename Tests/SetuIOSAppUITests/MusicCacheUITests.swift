import XCTest

final class MusicCacheUITests: XCTestCase {
    func testHomeSearchReturnKeepsCachedContent() {
        let app = launch()
        defer { app.terminate() }
        let history = app.buttons["查看全部播放历史"]
        XCTAssertTrue(history.waitForExistence(timeout: 10))
        // Use the existing search entry; no playback or writes can invalidate history.
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("测试\n")
        XCTAssertTrue(app.navigationBars["搜索音乐"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["歌曲、歌手或专辑"].value as? String, "测试")
        XCTAssertTrue(app.staticTexts["3/3"].waitForExistence(timeout: 5), "先确认正常搜索结果已出现")
        app.navigationBars["搜索音乐"].buttons.firstMatch.tap()
        XCTAssertTrue(history.exists, "返回首页已有内容应立即存在")
        XCTAssertFalse(app.staticTexts["正在加载最近播放"].exists)
        XCTAssertFalse(app.staticTexts["正在加载我的歌单"].exists)
        attach(app, name: "music-home-cached-return")
    }

    func testPlaylistDetailReentryKeepsContent() {
        let app = launch()
        defer { app.terminate() }
        let manage = app.buttons["管理全部歌单"]
        XCTAssertTrue(manage.waitForExistence(timeout: 10))
        if !manage.isHittable { app.swipeUp() }
        // Exercise cache reentry independently of the baseline row's spacer hit region.
        manage.staticTexts["管理全部歌单"].tap()
        XCTAssertTrue(app.navigationBars["我的歌单"].waitForExistence(timeout: 5))
        let playlist = app.buttons["music.playlists.row.7401"]
        XCTAssertTrue(playlist.waitForExistence(timeout: 5))
        playlist.tap()
        XCTAssertTrue(app.staticTexts["播放模式"].waitForExistence(timeout: 5))
        app.navigationBars["歌单详情"].buttons.firstMatch.tap()
        XCTAssertTrue(playlist.waitForExistence(timeout: 5))
        playlist.tap()
        XCTAssertTrue(app.staticTexts["播放模式"].exists)
        XCTAssertFalse(app.staticTexts["正在加载"].exists)
        attach(app, name: "music-playlist-cached-reentry")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
