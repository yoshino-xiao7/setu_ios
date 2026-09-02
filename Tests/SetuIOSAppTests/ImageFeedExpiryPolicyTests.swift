import Foundation
import XCTest
@testable import SetuIOSCore

final class ImageFeedExpiryPolicyTests: XCTestCase {
    func testAcceptsInstantWithOrWithoutFractionalSeconds() throws {
        let date = try XCTUnwrap(ImageFeedExpiryPolicy.expirationDate("2026-09-02T04:00:00Z"))
        let fractional = try XCTUnwrap(ImageFeedExpiryPolicy.expirationDate("2026-09-02T04:00:00.123456Z"))
        XCTAssertEqual(fractional.timeIntervalSince(date), 0.123456, accuracy: 0.001)
        XCTAssertFalse(ImageFeedExpiryPolicy.isExpired(date, now: date.addingTimeInterval(-1)))
        XCTAssertTrue(ImageFeedExpiryPolicy.isExpired(date, now: date))
        XCTAssertNil(ImageFeedExpiryPolicy.expirationDate("invalid"))
    }

    func testFreePreviewPrefetchStartsOneMinuteBeforeExpiry() {
        let now = Date(timeIntervalSince1970: 1000)
        XCTAssertEqual(ImageFeedExpiryPolicy.prefetchDelay(for: now.addingTimeInterval(600), now: now), 540)
        XCTAssertEqual(ImageFeedExpiryPolicy.prefetchDelay(for: now.addingTimeInterval(30), now: now), 0)
        XCTAssertEqual(ImageFeedExpiryPolicy.prefetchDelay(for: now.addingTimeInterval(-1), now: now), 0)
        XCTAssertNil(ImageFeedExpiryPolicy.prefetchDelay(for: nil, now: now))
    }

    func testOnlyConfirmedTokenExpiryAllowsFreePreviewRecovery() {
        XCTAssertTrue(ImageFeedExpiryPolicy.shouldReloadPreview(after: APIError.httpStatus(404, code: "IMAGE_FEED_TOKEN_EXPIRED")))
        XCTAssertFalse(ImageFeedExpiryPolicy.shouldReloadPreview(after: APIError.httpStatus(404)))
        XCTAssertFalse(ImageFeedExpiryPolicy.shouldReloadPreview(after: APIError.httpStatus(500, code: "IMAGE_FEED_TOKEN_EXPIRED")))
        XCTAssertFalse(ImageFeedExpiryPolicy.shouldReloadPreview(after: URLError(.timedOut)))
        XCTAssertFalse(ImageFeedExpiryPolicy.shouldReloadPreview(after: APIError.httpStatus(409, code: "IMAGE_FEED_CONSUME_PROCESSING")))
    }
}
