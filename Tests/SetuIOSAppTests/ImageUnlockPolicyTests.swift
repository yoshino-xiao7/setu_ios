import XCTest
@testable import SetuIOSApp

final class ImageUnlockPolicyTests: XCTestCase {
    func testPreviewSettlingNeverConsumesPoints() {
        XCTAssertFalse(ImageUnlockPolicy.shouldConsume(trigger: .previewSettled, isAlreadyUnlocked: false))
    }

    func testExplicitHighResolutionRequestConsumesOnlyOnce() {
        XCTAssertTrue(ImageUnlockPolicy.shouldConsume(trigger: .userRequestedHighResolution, isAlreadyUnlocked: false))
        XCTAssertFalse(ImageUnlockPolicy.shouldConsume(trigger: .userRequestedHighResolution, isAlreadyUnlocked: true))
    }
}
