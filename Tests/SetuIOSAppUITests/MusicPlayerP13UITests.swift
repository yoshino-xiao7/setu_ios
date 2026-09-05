import XCTest

final class MusicPlayerP13UITests: XCTestCase {
    func testAX5ControlsHaveSeparate44PointTargets() { verifyControls(category: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge", name: "AX5") }
    func testStandardControlsHaveSeparate44PointTargets() { verifyControls(category: "UICTContentSizeCategoryL", name: "standard") }

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
