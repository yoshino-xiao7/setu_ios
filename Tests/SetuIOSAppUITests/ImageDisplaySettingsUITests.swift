import XCTest

final class ImageDisplaySettingsUITests: XCTestCase {
    func testBlurSettingKeepsDetailsClearAndPersists() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images", "-ui-testing-image-blur"]
        app.launch()
        defer { app.terminate() }
        openSettings(app)
        let toggle = app.switches["settings.images.blur-previews"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        set(toggle, enabled: true)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "image-display-settings"; shot.lifetime = .keepAlways; add(shot)
        app.tabBars.buttons["图片"].tap()
        app.buttons["本站图库"].tap()
        let restricted = app.buttons["artwork-thumbnail-1"]
        XCTAssertTrue(restricted.waitForExistence(timeout: 8))
        XCTAssertTrue((restricted.value as? String ?? "").contains("图片已模糊"))
        let ordinary = app.buttons["artwork-thumbnail-2"]
        XCTAssertFalse((ordinary.value as? String ?? "").contains("图片已模糊"))
        let gridShot = XCTAttachment(screenshot: app.screenshot())
        gridShot.name = "blurred-restricted-thumbnail"; gridShot.lifetime = .keepAlways; add(gridShot)
        restricted.tap()
        let detail = app.buttons["artwork-image-1-0"]
        XCTAssertTrue(detail.waitForExistence(timeout: 8))
        XCTAssertFalse((detail.value as? String ?? "").contains("图片已模糊"))
        app.buttons["关闭作品"].tap()
        app.tabBars.buttons["首页"].tap()
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        set(toggle, enabled: false)
        app.tabBars.buttons["图片"].tap()
        XCTAssertFalse((restricted.value as? String ?? "").contains("图片已模糊"))
        app.terminate()
        app.launch()
        openSettings(app)
        XCTAssertEqual(toggle.value as? String, "0", "设置应在重启后保留")
        set(toggle, enabled: true) // Restore the default for subsequent tests.
    }

    private func set(_ toggle: XCUIElement, enabled: Bool) {
        let value = enabled ? "1" : "0"
        if toggle.value as? String != value {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", value), object: toggle)], timeout: 5), .completed)
    }

    private func openSettings(_ app: XCUIApplication) {
        XCTAssertTrue(app.tabBars.buttons["首页"].waitForExistence(timeout: 15))
        app.tabBars.buttons["首页"].tap()
        app.buttons["我的"].tap()
        let row = app.buttons["account.image-display"]
        XCTAssertTrue(app.navigationBars["我的"].waitForExistence(timeout: 5))
        for _ in 0..<5 where !row.isHittable { app.swipeUp() }
        XCTAssertTrue(row.exists)
        row.tap()
    }
}
