import XCTest

final class MusicSearchUITests: XCTestCase {
    func testFirstPageIsLazyAndScrollingLoadsNextPage() {
        let app = launch()
        defer { app.terminate() }
        openSearch(app, keyword: "分页")
        XCTAssertTrue(app.staticTexts["10/100"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["搜索历史"].exists)
        XCTAssertFalse(app.buttons["播放 分页 歌曲 11"].exists, "首屏不得自动加载第二页")
        let firstRow = app.buttons["播放 分页 歌曲 1"]
        XCTAssertTrue(firstRow.exists)
        // Real rows should be independently accessible in List, not one giant card cell.
        XCTAssertGreaterThan(app.cells.count, 3)
        for _ in 0..<4 {
            if app.buttons["播放 分页 歌曲 11"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["播放 分页 歌曲 11"].waitForExistence(timeout: 5))
        for _ in 0..<30 {
            if app.buttons["播放 分页 歌曲 100"].exists { break }
            app.swipeUp()
        }
        XCTAssertTrue(app.buttons["播放 分页 歌曲 100"].waitForExistence(timeout: 5), "连续滚动应能加载完整 100 首结果")
        attach(app, name: "music-search-lazy-pagination")
    }

    func testPopPushRestoresQueryResultsAndSegment() {
        let app = launch()
        defer { app.terminate() }
        openSearch(app, keyword: "恢复")
        XCTAssertTrue(app.staticTexts["10/100"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["专辑"].tap()
        XCTAssertTrue(app.staticTexts["分页专辑"].waitForExistence(timeout: 5))
        app.navigationBars["搜索音乐"].buttons.firstMatch.tap()
        let homeSearch = app.searchFields.firstMatch
        XCTAssertTrue(homeSearch.waitForExistence(timeout: 5))
        homeSearch.tap()
        homeSearch.typeText("恢复\n")
        XCTAssertTrue(app.navigationBars["搜索音乐"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["歌曲、歌手或专辑"].value as? String, "恢复")
        XCTAssertTrue(app.segmentedControls.buttons["专辑"].isSelected)
        XCTAssertTrue(app.staticTexts["分页专辑"].exists)
        XCTAssertFalse(app.staticTexts["正在搜索"].exists)
        attach(app, name: "music-search-restored-session")
    }

    func testInputDebouncesWithoutSubmitAndSegmentsStayLocal() {
        let app = launch()
        defer { app.terminate() }
        openSearch(app, keyword: "初始")
        XCTAssertTrue(app.staticTexts["10/100"].waitForExistence(timeout: 5))
        let field = app.textFields["歌曲、歌手或专辑"]
        field.tap()
        let text = field.value as? String ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: text.count) + "周杰伦")
        XCTAssertTrue(app.buttons["播放 周杰伦 歌曲 1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["搜索历史"].exists)
        // Dismiss keyboard using Search; session must deduplicate the submission.
        field.typeText("\n")
        app.segmentedControls.buttons["歌手"].tap()
        XCTAssertTrue(app.staticTexts["10 首相关歌曲"].waitForExistence(timeout: 5))
        app.segmentedControls.buttons["歌曲"].tap()
        XCTAssertTrue(app.buttons["播放 周杰伦 歌曲 1"].exists)
        XCTAssertTrue(app.staticTexts["10/100"].exists)
        app.tabBars.buttons["首页"].tap()
        app.tabBars.buttons["音乐"].tap()
        XCTAssertTrue(app.navigationBars["搜索音乐"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["歌曲、歌手或专辑"].value as? String, "周杰伦")
        XCTAssertTrue(app.buttons["播放 周杰伦 歌曲 1"].exists)
        attach(app, name: "music-search-debounced-input")
    }

    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-music", "-ui-testing-music-search-pages", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        app.launch()
        return app
    }

    private func openSearch(_ app: XCUIApplication, keyword: String) {
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText(keyword + "\n")
        XCTAssertTrue(app.navigationBars["搜索音乐"].waitForExistence(timeout: 5))
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
}
