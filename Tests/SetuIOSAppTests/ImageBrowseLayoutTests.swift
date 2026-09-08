import XCTest
@testable import SetuIOSApp

final class ImageBrowseLayoutTests: XCTestCase {
    func testVerticalReadingDoesNotAdvanceTheImage() {
        XCTAssertNil(ImageBrowseLayout.swipeDirection(translation: CGSize(width: 80, height: -400)))
        XCTAssertNil(ImageBrowseLayout.swipeDirection(translation: CGSize(width: 40, height: 0)))
        XCTAssertEqual(ImageBrowseLayout.swipeDirection(translation: CGSize(width: -180, height: 10)), -1)
        XCTAssertEqual(ImageBrowseLayout.swipeDirection(translation: CGSize(width: 180, height: 10)), 1)
    }

    func testImageUsesItsOriginalAspectRatioWithoutScreenHeightCap() {
        XCTAssertEqual(ImageBrowseLayout.imageHeight(containerWidth: 390, pixelWidth: 1200, pixelHeight: 1600), 520)
        XCTAssertEqual(ImageBrowseLayout.imageHeight(containerWidth: 390, pixelWidth: 1600, pixelHeight: 1200), 292.5)
        XCTAssertEqual(ImageBrowseLayout.imageHeight(containerWidth: 375, pixelWidth: 1000, pixelHeight: 5000), 1875)
    }

    func testMissingDimensionsUseSquareAndInvalidContainerIsSafe() {
        XCTAssertEqual(ImageBrowseLayout.imageHeight(containerWidth: 430, pixelWidth: 0, pixelHeight: 1200), 430)
        XCTAssertEqual(ImageBrowseLayout.imageHeight(containerWidth: 430, pixelWidth: 1200, pixelHeight: -1), 430)
        XCTAssertEqual(ImageBrowseLayout.imageHeight(containerWidth: .infinity, pixelWidth: 1, pixelHeight: 1), 0)
    }
}
