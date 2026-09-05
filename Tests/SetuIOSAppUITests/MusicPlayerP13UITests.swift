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
                        app.buttons["上一首"], play, app.buttons["下一首"], app.buttons["更多操作"]]
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
        XCTAssertTrue(app.buttons["睡眠定时"].waitForExistence(timeout: 5))
    }
}
