import XCTest

final class MusicPlayerP13UITests: XCTestCase {
    func testAX5ControlsHaveSeparate44PointTargets() { verifyControls(category: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge", name: "AX5") }
    func testStandardControlsHaveSeparate44PointTargets() { verifyControls(category: "UICTContentSizeCategoryL", name: "standard") }

    @MainActor
    func testVoiceOverReadsPlayerControlsAndSongRowOnDevice() throws {
        guard #available(iOS 27.0, *) else { throw XCTSkip("Requires the public iOS 27 VoiceOver service") }
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player"]
        app.launch()
        defer { app.terminate() }
        let open = app.buttons["打开正在播放：夏夜微风"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        let service = XCUIDevice.shared.voiceOverService
        let wasEnabled = service.isEnabled
        defer { if wasEnabled { try? service.enable() } else { try? service.disable() } }
        try service.enable()
        var remaining: Set<String> = ["上一首", "播放", "下一首", "更多操作"]
        for _ in 0..<50 {
            let speech = try service.moveForward().utterance
            remaining = remaining.filter { !speech.contains($0) }
            if remaining.isEmpty { break }
        }
        XCTAssertTrue(remaining.isEmpty, "Missing spoken fixture controls: \(remaining.sorted())")
        print("P13_VOICEOVER player_controls_spoken")
        try service.disable()
        app.buttons["收起播放页"].tap()
        app.tabBars.buttons["音乐"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap(); search.typeText("测试\n")
        XCTAssertTrue(app.buttons["播放 夏夜微风"].waitForExistence(timeout: 5))
        try service.enable()
        var rowSpoken = false
        for _ in 0..<60 {
            let speech = try service.moveForward().utterance
            if speech.contains("夏夜微风") && speech.contains("播放") { rowSpoken = true; break }
        }
        XCTAssertTrue(rowSpoken, "VoiceOver must actually speak the fixture song row")
        print("P13_VOICEOVER song_row_spoken")
    }

    func testPhysicalAppearanceSwitchKeepsPlayerControls() throws {
        let device = XCUIDevice.shared

        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player", "-ui-testing-airplay-hardware", "-ui-testing-system-appearance"]
        app.launch()
        defer { app.terminate() }
        let open = app.buttons["打开正在播放：夏夜微风"]
        XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
        let audit = app.staticTexts["airplay.audit"]
        XCTAssertTrue(audit.waitForExistence(timeout: 5))
        func observedAppearance() -> String? {
            guard let value = audit.value as? String,
                  let data = value.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            return json["appearance"] as? String
        }
        let original = try XCTUnwrap(observedAppearance())
        defer { device.appearance = original == "dark" ? .dark : .light }
        for (appearance, name) in [(XCUIDevice.Appearance.light, "light"), (.dark, "dark"), (.light, "light-return")] {
            device.appearance = appearance
            XCTAssertEqual(device.appearance, appearance)
            let changed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                observedAppearance() == (appearance == .dark ? "dark" : "light")
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [changed], timeout: 5), .completed)
            XCTAssertTrue(app.buttons["更多操作"].isHittable)
            XCTAssertTrue(app.buttons["下一首"].isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "p13-system-appearance-\(name)"; shot.lifetime = .keepAlways; add(shot)
        }
        print("P13_APPEARANCE light_dark_light_completed")
    }

    func testPhysicalWordScrollPresentedMetrics() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SETU_P13_RENDER_METRICS"] == "1", "Opt-in physical rendered-frame metrics")
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-p13-word-scroll"]
        if ProcessInfo.processInfo.environment["SETU_P13_FIXED_LINE"] == "1" { app.launchArguments.append("-ui-testing-p13-fixed-line") }
        if ProcessInfo.processInfo.environment["SETU_P13_STATIC_WORD"] == "1" { app.launchArguments.append("-ui-testing-p13-static-word") }
        if ProcessInfo.processInfo.environment["SETU_P13_LINE_CONTROL"] == "1" { app.launchArguments.append("-ui-testing-p13-line-control") }
        app.launch()
        defer { app.terminate() }
        let scroll = app.scrollViews.firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 10))
        let options = XCTMeasureOptions()
        options.iterationCount = Int(ProcessInfo.processInfo.environment["SETU_P13_METRIC_ITERATIONS"] ?? "3") ?? 3
        var metrics: [any XCTMetric] = [XCTOSSignpostMetric.scrollingAndDecelerationMetric]
        if ProcessInfo.processInfo.environment["SETU_P13_CPU_TRACE"] == "1" { metrics.append(XCTCPUMetric(application: app)) }
        measure(metrics: metrics, options: options) {
            scroll.swipeUp(velocity: .slow)
            scroll.swipeDown(velocity: .slow)
        }
    }

    private func verifyControls(category: String, name: String) {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player", "-UIPreferredContentSizeCategoryName", category]
        app.launch()
        defer { app.terminate() }
        let open = app.buttons["打开正在播放：夏夜微风"]
        XCTAssertTrue(open.waitForExistence(timeout: 10))
        open.tap()
        XCTAssertTrue(app.buttons["更多操作"].waitForExistence(timeout: 5))
        let visiblePlayButtons = app.buttons.matching(identifier: "播放").allElementsBoundByIndex.filter(\.isHittable)
        XCTAssertEqual(visiblePlayButtons.count, 1, "Only the presented player is interactive")
        guard let play = visiblePlayButtons.first else { return }
        let controls = [app.buttons.matching(NSPredicate(format: "label BEGINSWITH '播放模式：'")).firstMatch,
                        app.buttons["上一首"], play, app.buttons["下一首"], app.buttons["播放列表"]]
        for control in controls {
            XCTAssertTrue(control.exists)
            XCTAssertGreaterThanOrEqual(control.frame.width, 44)
            XCTAssertGreaterThanOrEqual(control.frame.height, 44)
            XCTAssertTrue(app.frame.contains(control.frame))
        }
        for index in 0..<(controls.count - 1) {
            XCTAssertLessThanOrEqual(controls[index].frame.maxX, controls[index + 1].frame.minX)
        }
        XCTAssertFalse(app.descendants(matching: .any)["music.airplay"].exists, "Real cutover stays off")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "p13-controls-\(name)"; screenshot.lifetime = .keepAlways; add(screenshot)
        app.buttons["更多操作"].tap()
        XCTAssertTrue(app.navigationBars["更多操作"].waitForExistence(timeout: 5))
        if !app.buttons["睡眠定时"].exists { app.swipeUp() }
        XCTAssertTrue(app.buttons["睡眠定时"].exists)
        if !app.buttons["收藏到歌单"].isHittable { app.swipeDown() }
        app.buttons["收藏到歌单"].tap()
        XCTAssertTrue(app.navigationBars["收藏到歌单"].waitForExistence(timeout: 5))
    }
}

final class P13PageAX5AuditUITests: XCTestCase {
    func testLegacyHome() throws { try audit("legacyHome") }
    func testDiscoveryHome() throws { try audit("home") }
    func testDaily() throws { try audit("dailyRecommend") }
    func testReleases() throws { try audit("newReleases") }
    func testRankings() throws { try audit("rankings") }
    func testPlaylist() throws { try audit("playlist") }
    func testAlbum() throws { try audit("album") }
    func testArtist() throws { try audit("artist") }
    func testHistory() throws { try audit("history") }
    func testPlaylists() throws { try audit("playlists") }
    func testSearch() throws { try audit("search") }
    func testPlayer() throws { try audit("player") }
    func testLyrics() throws { try audit("lyrics") }
    func testQueue() throws { try audit("queue") }
    func testLegacyPlaylistDetail() throws { try audit("legacyPlaylistDetail") }
    func testReleaseAlbums() throws { try audit("releaseAlbums") }
    func testSearchAlbums() throws { try audit("searchAlbums") }
    func testSearchArtists() throws { try audit("searchArtists") }
    func testCreatePlaylist() throws { try audit("createPlaylist") }

    func testAddPlaylistModal() throws { try audit("addPlaylist") }
    func testMVModal() throws { try audit("mvModal") }
    func testRecommendedPlaylistModal() throws { try audit("recommendedModal") }
    func testMoreMenu() throws { try audit("moreMenu") }
    func testSleepMenu() throws { try audit("sleepMenu") }
    func testQualityMenu() throws { try audit("qualityMenu") }

    private func audit(_ page: String) throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        var args = ["-ui-testing-root-music"]
        if ["home", "dailyRecommend", "newReleases", "rankings", "releaseAlbums"].contains(page) {
            args += ["-ui-testing-music-discover", "-ui-testing-discover-page", page == "releaseAlbums" ? "newReleases" : page]
        } else if ["playlist", "album", "artist"].contains(page) {
            args += ["-ui-testing-music-details", "-ui-testing-detail-page", page]
        } else if ["player", "lyrics", "queue", "moreMenu", "sleepMenu", "qualityMenu"].contains(page) {
            args = ["-ui-testing-root-player"]
        } else if page.hasPrefix("search") {
            args += ["-ui-testing-music-search-pages"]
        } else { args = ["-ui-testing-root-music"] }
        if page == "mvModal" { args += ["-ui-testing-music-mv"] }
        app.launchArguments = args + ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"]
        app.launch(); defer { app.terminate() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
        if page == "history" || page == "playlists" || page == "legacyPlaylistDetail" || page == "createPlaylist" {
            let button = app.buttons[page == "history" ? "查看全部播放历史" : "管理全部歌单"].firstMatch
            for _ in 0..<6 where !button.isHittable { app.swipeUp() }
            XCTAssertTrue(button.isHittable)
            if page == "history" { button.tap() } else { button.staticTexts["管理全部歌单"].tap() }
            XCTAssertTrue(app.navigationBars[page == "history" ? "播放历史" : "我的歌单"].waitForExistence(timeout: 10))
            if page == "createPlaylist" {
                let create = app.buttons["创建歌单"]
                XCTAssertTrue(create.waitForExistence(timeout: 10)); create.tap()
                XCTAssertTrue(app.navigationBars["新建歌单"].waitForExistence(timeout: 10))
            }
            if page == "legacyPlaylistDetail" {
                let row = app.buttons["music.playlists.row.7401"]
                for _ in 0..<6 where !row.isHittable { app.swipeUp() }
                XCTAssertTrue(row.isHittable); row.tap()
                XCTAssertTrue(app.navigationBars["歌单详情"].waitForExistence(timeout: 10))
            }
        } else if page.hasPrefix("search") {
            let field = app.textFields["搜索歌曲、歌手或专辑"].firstMatch
            for _ in 0..<3 where !field.exists { app.swipeDown() }
            let initial = XCTAttachment(screenshot: app.screenshot()); initial.name = "p13-search-entry-AX5"; initial.lifetime = .keepAlways; add(initial)
            XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("测试\n")
            XCTAssertTrue(app.navigationBars["搜索音乐"].waitForExistence(timeout: 10))
            if page != "search" { app.segmentedControls.buttons[page == "searchAlbums" ? "专辑" : "歌手"].tap() }
        } else if page == "releaseAlbums" {
            XCTAssertTrue(app.buttons["新专辑"].waitForExistence(timeout: 10)); app.buttons["新专辑"].tap()
        } else if page == "queue" {
            let queue = app.buttons["查看当前播放列表"]
            XCTAssertTrue(queue.waitForExistence(timeout: 10)); queue.tap()
        } else if page == "player" || page == "lyrics" {
            let open = app.buttons["打开正在播放：夏夜微风"]
            XCTAssertTrue(open.waitForExistence(timeout: 10)); open.tap()
            if page == "lyrics" { app.buttons["歌曲封面，点击查看歌词"].tap() }
        }
        if page == "addPlaylist" || page == "mvModal" {
            let field = app.textFields["搜索歌曲、歌手或专辑"].firstMatch
            XCTAssertTrue(field.waitForExistence(timeout: 10)); field.tap(); field.typeText("测试\n")
            XCTAssertTrue(app.navigationBars["搜索音乐"].waitForExistence(timeout: 10))
            let target = app.buttons[page == "addPlaylist" ? "将《夏夜微风》加入歌单" : "播放《夏夜微风》的 MV"]
            for _ in 0..<6 where !target.isHittable { app.swipeUp() }
            XCTAssertTrue(target.isHittable); target.tap()
            if page == "addPlaylist" { XCTAssertTrue(app.navigationBars["加入歌单"].waitForExistence(timeout: 10)) }
            else { XCTAssertTrue(app.staticTexts["预览 MV"].waitForExistence(timeout: 10)) }
        } else if page == "recommendedModal" {
            let target = app.buttons.matching(NSPredicate(format: "label CONTAINS '粉色云层下的通勤歌单'")).firstMatch
            for _ in 0..<10 where !target.isHittable { app.swipeUp() }
            XCTAssertTrue(target.isHittable); target.tap()
            XCTAssertTrue(app.navigationBars["粉色云层下的通勤歌单"].waitForExistence(timeout: 10))
        } else if ["moreMenu", "sleepMenu", "qualityMenu"].contains(page) {
            app.buttons["打开正在播放：夏夜微风"].tap()
            if page == "qualityMenu" { app.buttons["music.quality"].tap() }
            else {
                app.buttons["更多操作"].tap()
                if page == "sleepMenu" { app.buttons["睡眠定时"].tap() }
            }
        }
        for viewport in 0..<3 {
            print("P13_AX5_AUDIT_BEGIN page=\(page) viewport=\(viewport)")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "p13-AX5-\(page)-\(viewport)"; shot.lifetime = .keepAlways; add(shot)
            // The fixture explicitly pins AX5. A font-switching audit cannot change it;
            // audit actual AX5 clipping/elements without treating that harness limit as a pass.
            try app.performAccessibilityAudit(for: [.textClipped, .elementDetection])
            print("P13_AX5_AUDIT_PASS page=\(page) viewport=\(viewport)")
            if page == "player" || page.hasSuffix("Menu") { break }
            app.swipeUp()
        }
    }
}
