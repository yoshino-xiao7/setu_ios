import XCTest

/// Uses normal logged-in App, actual FM page, and development-only argument-domain flags.
final class PlaybackContract3LiveUITests: XCTestCase {
    private func launchRadio() throws -> XCUIApplication {
        guard ProcessInfo.processInfo.environment["SETU_PLAYBACK3_LIVE"] == "1" else {
            throw XCTSkip("Explicit real development acceptance only")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-development-playback3-radio", "-SETU_API_BASE_URL", "https://api.yukiryou.icu",
                               "-SETU_MUSIC_RADIO_FM_ENABLED", "YES", "-SETU_MUSIC_USES_V2_PLAYBACK", "YES"]
        app.launch()
        XCTAssertTrue(app.navigationBars["私人 FM"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.buttons["暂停"].firstMatch.waitForExistence(timeout: 45))
        return app
    }
    func testRealFMPageAndControls() throws {
        let app = try launchRadio()
        defer { app.terminate() }
        XCTAssertTrue(app.buttons["不再播放"].firstMatch.exists)
        let current = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '打开正在播放：'")).firstMatch
        XCTAssertTrue(current.waitForExistence(timeout: 10)); current.tap()
        XCTAssertFalse(app.buttons["上一首"].firstMatch.isEnabled)
        XCTAssertFalse(app.buttons["播放模式：顺序播放"].firstMatch.isEnabled)
        print("P14_REAL_UI_PASS normalAuth=true actualFMPage=true")
    }
    func testRealFMReadyForManualLockscreen() throws {
        let app = try launchRadio()
        XCTAssertTrue(app.buttons["不再播放"].firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Real FM ready for manual lockscreen check"
        attachment.lifetime = .keepAlways
        add(attachment)
        print("P14_MANUAL_LOCKSCREEN_READY actualFMPage=true playbackControl=pause")
        // Keep the verified real page available while the user checks the physical lock screen.
        Thread.sleep(forTimeInterval: 300)
    }
    func testM13NormalAppForInstruments() throws {
        let app = try launchRadio()
        defer { app.terminate() }
        print("M13_NORMAL_APP_READY attach Instruments; test timing is not performance evidence")
        for _ in 0..<190 {
            Thread.sleep(forTimeInterval: 10)
            XCTAssertEqual(app.state, .runningForeground)
            XCTAssertTrue(app.buttons["暂停"].firstMatch.exists)
        }
        print("M13_NORMAL_APP_FINISHED Instruments evidence requires independent analysis")
    }
}
