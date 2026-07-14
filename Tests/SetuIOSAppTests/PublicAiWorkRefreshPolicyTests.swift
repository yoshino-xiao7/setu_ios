import SetuIOSCore
import XCTest
@testable import SetuIOSApp

final class PublicAiWorkRefreshPolicyTests: XCTestCase {
    func testFreshSquareSnapshotIsNotMisreportedAsUnavailableWhenDetailRouteReturns404() {
        let decision = PublicAiWorkRefreshPolicy.resolve(
            APIError.httpStatus(404, message: nil),
            hasVerifiedServerCopy: false
        )

        XCTAssertEqual(decision, .keepSnapshot)
    }

    func testPreviouslyVerifiedWorkBecomesUnavailableAfterConfirmed404() {
        let decision = PublicAiWorkRefreshPolicy.resolve(
            APIError.httpStatus(404, message: "Public generation work not found"),
            hasVerifiedServerCopy: true
        )

        XCTAssertEqual(decision, .markUnavailable)
    }

    func testTransientFailureKeepsCurrentSnapshot() {
        let decision = PublicAiWorkRefreshPolicy.resolve(
            APIError.httpStatus(503, message: "Service unavailable"),
            hasVerifiedServerCopy: true
        )

        XCTAssertEqual(decision, .keepSnapshot)
    }
}
