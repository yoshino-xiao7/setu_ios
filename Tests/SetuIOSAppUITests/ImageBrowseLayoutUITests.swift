import XCTest

final class ImageBrowseLayoutUITests: XCTestCase {
    private func launch(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-root-images", "-ui-testing-image-layout", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryL"] + extra
        app.launchEnvironment["SETU_IMAGE_LAYOUT_FIXTURE_BASE_URL"] = "http://127.0.0.1:8766"
        app.launch()
        XCTAssertTrue(app.buttons["image.favorite"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "随机图片：星光落在湖面，作者 云岚")).firstMatch.waitForExistence(timeout: 10))
        return app
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testPortraitLandscapeLongImageAndExistingActions() {
        let app = launch()
        let scroll = app.scrollViews["image.detail.scroll"]
        XCTAssertTrue(app.buttons["image.more"].isHittable)
        XCTAssertTrue(app.buttons["image.favorite"].isHittable)
        capture("portrait-top")
        scroll.swipeUp()
        capture("portrait-details")
        let unlock = app.buttons["image.unlock"]
        XCTAssertTrue(unlock.isHittable)
        app.buttons["image.more"].tap()
        XCTAssertTrue(app.buttons["image.share"].exists)
        XCTAssertTrue(app.buttons["image.delete-request"].exists)
        app.buttons["下一张"].tap()
        XCTAssertTrue(app.staticTexts["夏日列车与向日葵"].waitForExistence(timeout: 5))
        capture("landscape")
        // Swipe in the artwork, keeping vertical detail scrolling independent.
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.25))
        start.press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.25)))
        capture("long-image-top")
        for _ in 0..<4 { scroll.swipeUp() }
        XCTAssertTrue(app.staticTexts["沿着山间的小路走到星空尽头，记录旅途中的每一个温柔瞬间"].exists)
        capture("long-image-details")
        XCTAssertTrue(app.buttons["image.favorite"].isHittable)
        unlock.tap()
        XCTAssertTrue(app.buttons["image.unlock.confirm"].waitForExistence(timeout: 4))
        capture("unlock-confirmation")
        app.terminate()
    }

}
