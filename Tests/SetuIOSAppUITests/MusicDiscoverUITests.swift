import XCTest

final class MusicDiscoverUITests: XCTestCase {
    func testHomeDegradedContentPlaybackAndDiscoveryNavigation() {
        let app = launch("home"); defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["音乐"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["刷新暂不可用，正在显示已有内容"].exists)
        let track = app.buttons["播放 发现测试歌曲"].firstMatch
        XCTAssertTrue(track.waitForExistence(timeout: 5)); track.tap()
        XCTAssertTrue(app.buttons["打开正在播放：发现测试歌曲"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["电台"].isEnabled); XCTAssertFalse(app.buttons["我喜欢"].isEnabled)
        app.buttons["排行榜"].tap()
        XCTAssertTrue(app.navigationBars["排行榜"].waitForExistence(timeout: 5))
        let playlist = app.buttons.matching(NSPredicate(format: "label CONTAINS '发现测试榜单'")).firstMatch
        XCTAssertTrue(playlist.waitForExistence(timeout: 5)); playlist.tap()
        XCTAssertTrue(app.navigationBars["歌单详情"].waitForExistence(timeout: 5))
    }

    func testNewReleasesPaginationAreaAlbumNavigationAndPlayback() {
        let app = launch("newReleases"); defer { app.terminate() }
        XCTAssertTrue(app.navigationBars["新发行"].waitForExistence(timeout: 10))
        app.buttons["播放 发现测试歌曲"].firstMatch.tap()
        XCTAssertTrue(app.buttons["打开正在播放：发现测试歌曲"].waitForExistence(timeout: 5))
        app.buttons["加载更多"].tap()
        XCTAssertTrue(app.buttons["播放 分页发现歌曲"].waitForExistence(timeout: 5))
        app.buttons["music.discover.area"].tap(); app.buttons["华语"].tap()
        XCTAssertTrue(app.buttons["加载更多"].waitForExistence(timeout: 5))
        app.buttons["新专辑"].tap()
        let album = app.buttons.matching(NSPredicate(format: "label CONTAINS '发现测试专辑'")).firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 5)); album.tap()
        XCTAssertTrue(app.navigationBars["专辑详情"].waitForExistence(timeout: 5))
    }

    func testDailySharedCopyAndPlayback() {
        let app = launch("dailyRecommend"); defer { app.terminate() }
        XCTAssertTrue(app.staticTexts["非个人定制"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["为你定制"].exists)
        app.buttons["播放 发现测试歌曲"].tap()
        XCTAssertTrue(app.buttons["打开正在播放：发现测试歌曲"].waitForExistence(timeout: 5))
    }

    func testFourPagesEmptyErrorAndUnauthorized() {
        let empties = ["home": "暂无音乐内容", "rankings": "暂无榜单", "newReleases": "暂无歌曲", "dailyRecommend": "暂无歌曲"]
        for page in ["home", "rankings", "newReleases", "dailyRecommend"] {
            for state in ["empty", "error", "unauthorized"] {
                let app = launch(page, extra: ["-ui-testing-discover-\(state)"])
                let label = state == "empty" ? empties[page]! : state == "error" ? "发现服务暂时不可用" : "请先登录"
                XCTAssertTrue(app.staticTexts[label].firstMatch.waitForExistence(timeout: 10), "\(page) \(state)")
                if state == "error" { XCTAssertTrue(app.buttons["重试"].exists) }
                app.terminate()
            }
        }
    }

    func testHomeScrollingPerformance() {
        let app = launch("home"); defer { app.terminate() }
        XCTAssertTrue(app.buttons["排行榜"].waitForExistence(timeout: 10))
        let options = XCTMeasureOptions(); options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric], options: options) {
            app.swipeUp(); app.swipeDown()
        }
    }

    private func launch(_ page: String, extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music", "-ui-testing-music-discover", "-ui-testing-discover-page", page,
            "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"] + extra
        app.launch(); return app
    }
}
