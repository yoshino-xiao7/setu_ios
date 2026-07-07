import XCTest
@testable import SetuIOSCore

final class AuthSignerTests: XCTestCase {
    func testHmacMatchesExpectedSHA256Hex() {
        let signature = AuthSigner.hmac(
            message: "1710000000000:9a0b1c2d3e4f5061:GET:/user/info",
            secret: "test-secret"
        )

        XCTAssertEqual(signature, "745cf2253c6dfc956d200fc6b9c33f3bcc4159aa2411a7455f379d319fa56077")
    }
}
