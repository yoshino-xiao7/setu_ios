import XCTest

final class MusicDetailUITests: XCTestCase {
    func testArtistAlbumNavigationAndTypedPlaybackEntry() {
        let app = launch("artist")
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["歌手详情"].waitForExistence(timeout: 10))
        let play = app.buttons["播放 详情测试歌曲"].firstMatch
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.buttons["打开正在播放：详情测试歌曲"].waitForExistence(timeout: 5))
        let album = app.buttons["详情测试专辑"].firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 5)); album.tap()
        XCTAssertTrue(app.navigationBars["专辑详情"].waitForExistence(timeout: 5))
        attach(app, "p11-artist-album-playback")
    }

    func testPlaylistPaginationRetainsMissingProjection() {
        let app = launch("playlist")
        defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["歌单详情"].waitForExistence(timeout: 10))
        let more = app.buttons["加载更多"]
        for _ in 0..<3 where !more.isHittable { app.swipeUp() }
        XCTAssertTrue(more.waitForExistence(timeout: 5)); more.tap()
        let missing = app.staticTexts["第 51 首歌曲信息暂不可用"]
        for _ in 0..<3 where !missing.isHittable { app.swipeUp() }
        XCTAssertTrue(missing.waitForExistence(timeout: 5))
        XCTAssertFalse(more.exists)
        attach(app, "p11-playlist-null-membership")
    }

    func testThreePagesEmptyAndErrorStates() {
        for page in ["artist", "album", "playlist"] {
            for state in ["empty", "error"] {
                let app = launch(page, extra: ["-ui-testing-detail-\(state)"])
                let label = state == "empty" ? "暂无歌曲" : "详情服务暂时不可用"
                XCTAssertTrue(app.staticTexts[label].firstMatch.waitForExistence(timeout: 10), "\(page) \(state)")
                if state == "error" { XCTAssertTrue(app.buttons["重试"].exists) }
                attach(app, "p11-\(page)-\(state)")
                app.terminate()
            }
        }
    }
    private func launch(_ page: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music", "-ui-testing-music-details", "-ui-testing-detail-page", page,
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"] + extra
        app.launch(); return app
    }
    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
