import XCTest

final class AirPlayHardwareUITests: XCTestCase {
    private let mac = "雪涼的MacBook Neo"
    func testPhysicalAirPlayRoundTrip() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SETU_AIRPLAY_HARDWARE"] == "1", "Opt-in physical AirPlay receiver acceptance")
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-player", "-ui-testing-lyrics-playback", "-ui-testing-airplay-hardware",
                               "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"]
        continueAfterFailure = false
        app.launch()
        let open = app.buttons["打开正在播放：夏夜微风"]
        XCTAssertTrue(open.waitForExistence(timeout: 15)); open.tap()
        let audit = app.staticTexts["airplay.audit"]
        XCTAssertTrue(audit.waitForExistence(timeout: 10))
        try tapVisible("播放", in: app)
        try waitPhase("playing", app: app)
        app.buttons["更多操作"].tap()
        app.buttons["睡眠定时"].tap()
        app.buttons["15 分钟"].tap()
        let baseline = try snapshot(app)
        print("AIRPLAY_STEP playback_started")
        openControlCenter(app)
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let names = spring.buttons.allElementsBoundByIndex.map(\.label)
            .filter { $0.contains("播放") || $0.contains("音频") || $0.contains("输出") || $0.contains("AirPlay") || $0.contains("夏夜") || $0.contains("MacBook") }
        print("AIRPLAY_SYSTEM_AUDIO_BUTTONS " + names.joined(separator: " | "))
        // Allow the single system-level handoff if needed; playback and telemetry remain live.
        var connected = false
        for _ in 0..<180 {
            if let value = try? snapshot(app), (value["route"] as? [String])?.contains("AirPlay") == true {
                connected = true; break
            }
            Thread.sleep(forTimeInterval: 2)
        }
        guard connected else { throw NSError(domain: "AirPlayHardware", code: 1, userInfo: [NSLocalizedDescriptionKey: "No physical AirPlay route observed"]) }
        app.activate()
        let onMac = try snapshot(app)
        XCTAssertTrue(names.contains { $0.contains(mac) }, "System UI identifies the receiving Mac; AVAudioSession may name an aggregate AirPlay port")
        XCTAssertEqual(onMac["track"] as? Int, baseline["track"] as? Int)
        XCTAssertEqual(onMac["queue"] as? [Int], baseline["queue"] as? [Int])
        XCTAssertGreaterThan(try time(onMac), try time(baseline))
        try exercise(app, label: "mac")
        try switchOutput("iPhone", app: app, airPlay: false)
        try exercise(app, label: "local_return")
        try switchOutput(mac, app: app, airPlay: true)
        try exercise(app, label: "mac_second")
        openControlCenter(app)
        let remotePause = spring.buttons.matching(NSPredicate(format: "label == '暂停'")).allElementsBoundByIndex.filter(\.isHittable)
        try XCTUnwrap(remotePause.first).tap()
        app.activate()
        try waitPhase("paused", app: app)
        openControlCenter(app)
        let remotePlay = spring.buttons.matching(NSPredicate(format: "label == '播放'")).allElementsBoundByIndex.filter(\.isHittable)
        try XCTUnwrap(remotePlay.first).tap()
        app.activate()
        try waitPhase("playing", app: app)
        print("AIRPLAY_STEP system_remote_pause_resume_verified")
        print("AIRPLAY_STEP all_round_trip_checks_completed")
    }

    private func exercise(_ app: XCUIApplication, label: String) throws {
        try waitPhase("playing", app: app)
        let before = try snapshot(app)
        try tapVisible("暂停", in: app); try waitPhase("paused", app: app)
        let paused = try snapshot(app); Thread.sleep(forTimeInterval: 2)
        XCTAssertEqual(try time(snapshot(app)), try time(paused), accuracy: 1)
        try tapVisible("播放", in: app); try waitPhase("playing", app: app)
        Thread.sleep(forTimeInterval: 2)
        XCTAssertGreaterThan(try time(snapshot(app)), try time(paused))
        app.buttons["下一首"].tap(); try waitPhase("playing", app: app)
        XCTAssertNotEqual(try snapshot(app)["track"] as? Int, before["track"] as? Int)
        app.buttons["上一首"].tap(); try waitPhase("playing", app: app)
        XCTAssertEqual(try snapshot(app)["track"] as? Int, before["track"] as? Int)
        app.sliders["播放进度"].adjust(toNormalizedSliderPosition: 0.25)
        Thread.sleep(forTimeInterval: 2)
        let after = try snapshot(app)
        XCTAssertGreaterThan(try time(after), 20)
        XCTAssertEqual(after["queue"] as? [Int], before["queue"] as? [Int])
        XCTAssertEqual(after["titleMatches"] as? Bool, true)
        XCTAssertEqual(after["artistMatches"] as? Bool, true)
        XCTAssertEqual(after["avPlayerInstancesObserved"] as? Int, 1)
        XCTAssertEqual(after["miniInstances"] as? Int, 1)
        XCTAssertEqual(after["error"] as? Bool, false)
        XCTAssertEqual(after["sleepTimer"] as? Bool, true)
        let urls = (after["urlRequests"] as? Int) ?? 0
        Thread.sleep(forTimeInterval: 3)
        let steady = try snapshot(app)
        XCTAssertEqual(steady["urlRequests"] as? Int, urls, "No idle URL resolution loop")
        XCTAssertGreaterThan(steady["lyricIndex"] as? Int ?? -1, after["lyricIndex"] as? Int ?? -1)
        XCTAssertEqual(steady["parses"] as? Int, after["parses"] as? Int)
        print("AIRPLAY_STEP \(label)_controls_verified")
    }
    private func switchOutput(_ name: String, app: XCUIApplication, airPlay: Bool) throws {
        let before = try snapshot(app)
        openControlCenter(app)
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        Thread.sleep(forTimeInterval: 1)
        // Observed media-page output button in physical-device recording.
        spring.coordinate(withNormalizedOffset: CGVector(dx: 0.50, dy: 0.862)).tap()
        Thread.sleep(forTimeInterval: 2)
        let choices = spring.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@ AND NOT label CONTAINS '→'", name)).allElementsBoundByIndex.filter(\.isHittable)
        let attachment = XCTAttachment(screenshot: spring.screenshot())
        attachment.name = "System output picker"
        add(attachment)
        let target = try XCTUnwrap(choices.first, "No visible output choice for requested receiver")
        target.tap()
        app.activate()
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            guard let value = try? self.snapshot(app) else { return false }
            return (value["route"] as? [String])?.contains("AirPlay") == airPlay
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 25), .completed)
        let after = try snapshot(app)
        print("AIRPLAY_STEP route_switched_\(airPlay ? "mac" : "iphone")")
        XCTAssertEqual(after["track"] as? Int, before["track"] as? Int)
        XCTAssertEqual(after["queue"] as? [Int], before["queue"] as? [Int])
        XCTAssertGreaterThanOrEqual(try time(after), try time(before) - 1)
    }
    private func openControlCenter(_ app: XCUIApplication) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.005))
            .press(forDuration: 0.1, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.98, dy: 0.25)))
        // The physical-device screenshot shows the media-page tab at this coordinate.
        // Select it explicitly rather than scrolling into the connectivity page.
        let spring = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        spring.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.50)).tap()
    }
    private func tapVisible(_ title: String, in app: XCUIApplication) throws {
        let button = try XCTUnwrap(app.buttons.matching(identifier: title).allElementsBoundByIndex.first(where: \.isHittable))
        button.tap()
    }
    private func waitPhase(_ phase: String, app: XCUIApplication) throws {
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _,_ in
            (try? self.snapshot(app)["phase"] as? String) == phase
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 20), .completed)
    }
    private func snapshot(_ app: XCUIApplication) throws -> [String: Any] {
        let text = try XCTUnwrap(app.staticTexts["airplay.audit"].value as? String)
        print("AIRPLAY_SNAPSHOT " + text)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
    }
    private func time(_ value: [String: Any]) throws -> Double { try XCTUnwrap((value["time"] as? NSNumber)?.doubleValue) }
}
