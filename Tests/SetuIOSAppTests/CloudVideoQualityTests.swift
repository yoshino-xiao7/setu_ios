import CoreGraphics
import XCTest
@testable import SetuIOSCore

final class CloudVideoQualityTests: XCTestCase {
    func testDefaultsStoredPreferenceTo720p() {
        let defaults = UserDefaults(suiteName: "cloud-video-quality-\(UUID().uuidString)")!
        XCTAssertEqual(CloudVideoQuality.maxHeight(defaults: defaults), 720)

        CloudVideoQuality.saveMaxHeight(1080, defaults: defaults)
        XCTAssertEqual(CloudVideoQuality.maxHeight(defaults: defaults), 1080)
    }

    func testCapsAt720pWhenTheLadderIncludesIt() {
        XCTAssertEqual(CloudVideoQuality.capHeight(requested: 720, available: [240, 360, 480, 720, 1080]), 720)
    }

    func testUsesHighestRungAtOrBelow720pWhen720pIsMissing() {
        XCTAssertEqual(CloudVideoQuality.capHeight(requested: 720, available: [240, 480, 1080]), 480)
    }

    func testStaysOnLowestAvailableRungWhenEveryRungIsAboveTheCap() {
        XCTAssertEqual(CloudVideoQuality.capHeight(requested: 720, available: [1080, 1440]), 1080)
        XCTAssertEqual(CloudVideoQuality.capHeight(requested: 240, available: [240, 720]), 240)
    }

    func testListsLadderHeightsOrStandardRungsUpToTheSource() {
        XCTAssertEqual(CloudVideoQuality.optionHeights(available: [1080, 720, 720, 480]), [480, 720, 1080])
        XCTAssertEqual(CloudVideoQuality.optionHeights(available: [], sourceHeight: 1080), [240, 360, 480, 720, 1080])
        XCTAssertEqual(CloudVideoQuality.optionHeights(available: [], sourceHeight: 480), [240, 360, 480])
        XCTAssertEqual(CloudVideoQuality.optionHeights(available: [], sourceHeight: 0), [240, 360, 480, 720, 1080])
    }

    func testLabels720pAsTheDefaultOption() {
        XCTAssertEqual(CloudVideoQuality.label(for: 720), "720p（默认）")
        XCTAssertEqual(CloudVideoQuality.label(for: 1080), "1080p")
    }

    func testMaximumResolutionUses16By9AtTheCappedHeight() {
        XCTAssertEqual(CloudVideoQuality.maximumResolution(forMaxHeight: 720), CGSize(width: 1280, height: 720))
        XCTAssertEqual(CloudVideoQuality.maximumResolution(forMaxHeight: 1080), CGSize(width: 1920, height: 1080))
    }
}
