import XCTest

final class MusicArchitectureUITests: XCTestCase {
    func testSinglePlayerIdentityAcrossTabsPushPopQueueAndNowPlaying() {
        let app = launch(["-ui-testing-root-player"])
        defer { app.terminate() }
        let bar = app.otherElements["music.mini-player"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 10))
        let identity = bar.value as? String
        XCTAssertTrue(identity?.hasPrefix("instances=1;") == true)
        for tab in ["首页", "AI 绘画", "图片", "音乐", "更多"] {
            app.tabBars.buttons[tab].tap()
            XCTAssertEqual(bar.value as? String, identity, "Same live instance on \(tab)")
            XCTAssertLessThanOrEqual(bar.frame.maxY, app.tabBars.firstMatch.frame.minY + 1)
        }
        app.tabBars.buttons["音乐"].tap()
        let search = app.searchFields.firstMatch
        search.tap()
        // The global bar follows the stack's keyboard safe area.
        XCTAssertTrue(bar.isHittable)
        search.typeText("测试\n")
        XCTAssertTrue(app.navigationBars["搜索音乐"].waitForExistence(timeout: 5))
        XCTAssertEqual(bar.value as? String, identity)
        app.navigationBars["搜索音乐"].buttons.firstMatch.tap()
        XCTAssertEqual(bar.value as? String, identity)
        app.buttons["查看当前播放列表"].tap()
        XCTAssertTrue(app.buttons["关闭当前播放"].waitForExistence(timeout: 5))
        app.buttons["关闭当前播放"].tap()
        XCTAssertTrue(app.buttons["关闭当前播放"].waitForNonExistence(timeout: 5))
        app.buttons["打开正在播放：夏夜微风"].tap()
        XCTAssertTrue(app.buttons["更多操作"].waitForExistence(timeout: 5), "Player state: \(String(describing: bar.value))")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "phase5-single-player-now-playing"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        // Dismiss the existing presentation, then change tracks through the ordinary search path.
        app.buttons["收起播放页"].tap()
        XCTAssertTrue(bar.waitForExistence(timeout: 5))
        search.tap(); search.typeText("测试\n")
        XCTAssertTrue(app.buttons["播放 沿着星光回家"].waitForExistence(timeout: 5))
        app.buttons["播放 沿着星光回家"].tap()
        XCTAssertTrue(app.buttons["打开正在播放：沿着星光回家"].waitForExistence(timeout: 5))
        XCTAssertEqual(bar.value as? String, identity, "Changing the current song cannot recreate the bar")
    }

    func testMVParentAndChildShareOneDetailRequest() {
        let app = launch(["-ui-testing-root-music", "-ui-testing-music-mv"])
        defer { app.terminate() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("MV\n")
        let mv = app.buttons["播放《夏夜微风》的 MV"]
        XCTAssertTrue(mv.waitForExistence(timeout: 5))
        mv.tap()
        XCTAssertTrue(app.staticTexts["预览 MV"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["720P"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.descendants(matching: .any)["music.mv"].firstMatch.value as? String, "details=1")
        app.buttons["720P"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["music.mv"].firstMatch.value as? String, "details=1")
        XCTAssertTrue(app.buttons["重新获取播放地址"].waitForExistence(timeout: 5))
        app.buttons["重新获取播放地址"].tap()
        XCTAssertEqual(app.descendants(matching: .any)["music.mv"].firstMatch.value as? String, "details=1")
    }

    func testSongPlaylistSheetUsesExistingStoreAndPreservesSummary() {
        let app = launch(["-ui-testing-root-music"])
        defer { app.terminate() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap(); search.typeText("测试\n")
        let add = app.buttons["将《夏夜微风》加入歌单"]
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        add.tap()
        XCTAssertTrue(app.navigationBars["加入歌单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["夏夜微风"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '我的专注时刻'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["正在加载歌单"].exists)
        app.buttons["关闭"].tap()
        XCTAssertTrue(add.waitForExistence(timeout: 5))
    }

    func testLyricsStayParsedAcrossBrowsingAndCoverSwitches() {
        let app = launch(["-ui-testing-root-player", "-ui-testing-lyrics-playback"])
        defer { app.terminate() }
        let open = app.buttons["打开正在播放：夏夜微风"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.buttons["收起播放页"].waitForExistence(timeout: 5))
        app.buttons["歌曲封面，点击查看歌词"].tap()
        let lyrics = app.descendants(matching: .any)["music.lyrics"].firstMatch
        XCTAssertTrue(lyrics.waitForExistence(timeout: 5))
        XCTAssertEqual(lyrics.value as? String, "parses=1")
        lyrics.swipeUp()
        XCTAssertTrue(app.buttons["从当前选中歌词播放"].waitForExistence(timeout: 5))
        app.buttons["从当前选中歌词播放"].tap()
        XCTAssertEqual(lyrics.value as? String, "parses=1")
        lyrics.tap()
        app.buttons["歌曲封面，点击查看歌词"].tap()
        XCTAssertTrue(lyrics.waitForExistence(timeout: 5))
        XCTAssertEqual(lyrics.value as? String, "parses=1")
        app.buttons["下一首"].tap()
        let nextParse = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "parses=2"), object: lyrics)
        XCTAssertEqual(XCTWaiter.wait(for: [nextParse], timeout: 5), .completed)
    }

    func testPlaybackAndBulkPlaylistSheetsKeepTheirExistingSummaries() {
        let app = launch(["-ui-testing-root-player"])
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["打开正在播放：夏夜微风"].waitForExistence(timeout: 10))
        app.buttons["打开正在播放：夏夜微风"].tap()
        app.buttons["更多操作"].tap()
        app.buttons["收藏到歌单"].tap()
        XCTAssertTrue(app.navigationBars["收藏到歌单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["夏夜微风"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '我的专注时刻'")).firstMatch.waitForExistence(timeout: 5))
        app.buttons["取消"].tap()
        app.buttons["收起播放页"].tap()
        app.tabBars.buttons["音乐"].tap()
        let manage = app.buttons["管理全部歌单"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5))
        if !manage.isHittable { app.swipeUp() }
        // Exercise sheet behavior independently of the baseline row's spacer hit region.
        manage.staticTexts["管理全部歌单"].tap()
        app.buttons["music.playlists.row.7401"].tap()
        let multi = app.buttons["多选"]
        XCTAssertTrue(multi.waitForExistence(timeout: 5))
        if !multi.isHittable { app.swipeUp() }
        multi.tap()
        app.buttons["选择 夏夜微风"].tap()
        app.buttons["加入歌单"].tap()
        XCTAssertTrue(app.navigationBars["加入其它歌单"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["已选 1 首歌曲"].exists)
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS '夜晚散步'")).firstMatch.exists)
        XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label CONTAINS '我的专注时刻'")).firstMatch.exists)
    }

    private func launch(_ arguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = arguments + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }
}
