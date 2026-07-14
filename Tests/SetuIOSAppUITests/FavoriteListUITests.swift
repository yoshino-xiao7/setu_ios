import XCTest

final class FavoriteListUITests: XCTestCase {
    func testFavoriteImageOpensNativePreviewFromTheGrid() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-favorites"]
        app.launch()

        let firstFavorite = app.buttons["favorite.item.901"]
        XCTAssertTrue(firstFavorite.waitForExistence(timeout: 8))
        firstFavorite.tap()

        XCTAssertTrue(app.navigationBars["图片预览"].waitForExistence(timeout: 5))
        let title = app.staticTexts["image.preview.title"]
        XCTAssertTrue(title.exists)
        XCTAssertEqual(title.label, "晚霞落在海面")
        XCTAssertTrue(app.staticTexts["青木"].exists)
        XCTAssertTrue(app.buttons["image.preview.close"].exists)
    }
}
