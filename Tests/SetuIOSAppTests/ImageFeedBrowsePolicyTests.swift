import XCTest
@testable import SetuIOSCore

final class ImageFeedBrowsePolicyTests: XCTestCase {
    func testPidDisplayKeepsPageZeroReadableAndCopyable() {
        let display = ImagePidDisplay(pid: 12123456, page: 0)
        XCTAssertEqual(display.text, "12123456")
        XCTAssertEqual(display.title, "PID 12123456")
        XCTAssertEqual(display.copyText, "12123456")
        XCTAssertEqual(display.fieldLabel, "插画 ID")
        XCTAssertEqual(display.accessibilityLabel, "插画 ID 12123456，轻点复制")
    }

    func testPidDisplayIncludesPageWhenNotZero() {
        let display = ImagePidDisplay(pid: 88_051_451, page: 2)
        XCTAssertEqual(display.text, "88051451_p2")
        XCTAssertEqual(display.copyText, "88051451_p2")
        XCTAssertEqual(display.title, "PID 88051451_p2")
    }

    func testFeedImageHeightUsesAspectRatioAndStaysPeekable() {
        let height = ImageFeedBrowsePolicy.imageHeight(
            containerWidth: 360,
            pixelWidth: 1081,
            pixelHeight: 1500,
            maxHeight: 520
        )
        XCTAssertEqual(height, 360 * (1500.0 / 1081.0), accuracy: 0.5)
    }

    func testFeedImageHeightClampsVeryTallImages() {
        let height = ImageFeedBrowsePolicy.imageHeight(
            containerWidth: 360,
            pixelWidth: 800,
            pixelHeight: 4000,
            maxHeight: 520
        )
        XCTAssertEqual(height, 520)
    }

    func testMissingPixelSizeFallsBackToPortraitFeedHeight() {
        let height = ImageFeedBrowsePolicy.imageHeight(
            containerWidth: 300,
            pixelWidth: 0,
            pixelHeight: 0,
            maxHeight: 800
        )
        XCTAssertEqual(height, 400)
    }

    func testNextIndexSkipsExpiredCardsAndStopsAtEnd() {
        XCTAssertEqual(ImageFeedBrowsePolicy.nextIndex(after: 0, expired: [false, false, false]), 1)
        XCTAssertEqual(ImageFeedBrowsePolicy.nextIndex(after: 0, expired: [false, true, false]), 2)
        XCTAssertNil(ImageFeedBrowsePolicy.nextIndex(after: 2, expired: [false, false, false]))
        XCTAssertNil(ImageFeedBrowsePolicy.nextIndex(after: 0, expired: []))
    }
}
