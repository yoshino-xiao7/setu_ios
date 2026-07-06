import XCTest
@testable import SetuIOSCore

final class AuthSignerTests: XCTestCase {
    func testHmacMatchesExpectedSHA256Hex() {
        let signature = AuthSigner.hmac(
            message: "1710000000000:9a0b1c2d3e4f5061:GET:/user/info",
            secret: "test-secret"
        )

        XCTAssertEqual(signature, "7b89fd077e741dd5b51d4ccfc5d0244e7f4bd549b625347ed324234befd1ca4b")
    }
}
