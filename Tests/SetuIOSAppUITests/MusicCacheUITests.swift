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

    func testManagePlaylistsEntireRowIsTappable() {
        verifyManagePlaylistsHitRegions(contentSize: "UICTContentSizeCategoryL")
    }

    func testManagePlaylistsEntireRowIsTappableAtAX5() {
        verifyManagePlaylistsHitRegions(contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge")
    }

    private func verifyManagePlaylistsHitRegions(contentSize: String) {
        continueAfterFailure = false
        let app = launch(contentSize: contentSize)
        defer { app.terminate() }
        let manage = app.buttons["管理全部歌单"]
        XCTAssertTrue(app.navigationBars["音乐"].waitForExistence(timeout: 10))
        // Exercise physical hit testing, not an accessibility activation of the Button.
        for region in ["text", "center", "spacer", "right", "center-after-return"] {
            for _ in 0..<10 {
                if manage.isHittable,
                   manage.frame.minY >= app.navigationBars.firstMatch.frame.maxY,
                   manage.frame.maxY <= app.tabBars.firstMatch.frame.minY { break }
                app.swipeUp()
            }
            XCTAssertTrue(manage.isHittable, "Visible management row: \(region), \(contentSize)")
            XCTAssertLessThanOrEqual(manage.frame.maxY, app.tabBars.firstMatch.frame.minY)
            if region == "text" {
                let text = manage.staticTexts["管理全部歌单"]
                XCTAssertTrue(text.exists)
                attach(app, name: "music-manage-row-\(contentSize)")
                text.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            } else if region == "spacer" {
                // At AX5 the text can cover the row center; also hit the actual gap.
                let text = manage.staticTexts["管理全部歌单"]
                let chevron = manage.images["chevron.right"]
                XCTAssertTrue(chevron.exists)
                let gapStart = text.frame.maxX, gapEnd = chevron.frame.minX
                XCTAssertGreaterThan(gapEnd, gapStart)
                let x = ((gapStart + gapEnd) / 2 - manage.frame.minX) / manage.frame.width
                manage.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
            } else {
                let x: CGFloat = region == "right" ? 0.95 : 0.5
                manage.coordinate(withNormalizedOffset: CGVector(dx: x, dy: 0.5)).tap()
            }
            XCTAssertTrue(app.navigationBars["我的歌单"].waitForExistence(timeout: 5),
                          "Tap \(region) must open playlists at \(contentSize)")
            app.navigationBars["我的歌单"].buttons.firstMatch.tap()
            XCTAssertTrue(app.navigationBars["音乐"].waitForExistence(timeout: 5))
        }
    }

    private func launch(contentSize: String = "UICTContentSizeCategoryL") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music", "-UIPreferredContentSizeCategoryName", contentSize]
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
