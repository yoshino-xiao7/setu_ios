import SetuIOSCore
import XCTest
@testable import SetuIOSApp

final class UserFacingErrorMapperTests: XCTestCase {
    func testOfflineErrorProvidesRetryWithoutTechnicalDetails() {
        let mapped = UserFacingErrorMapper.map(URLError(.notConnectedToInternet))

        XCTAssertEqual(mapped.title, "网络似乎断开了")
        XCTAssertEqual(mapped.action, .retry)
        XCTAssertNil(mapped.diagnosticCode)
        XCTAssertFalse(mapped.message.contains("NSURLError"))
    }

    func testUnauthorizedErrorProvidesSignInAndKeepsDiagnosticsSeparate() {
        let mapped = UserFacingErrorMapper.map(
            APIError.httpStatus(401, message: "signature invalid", requestID: "request-1", traceID: "trace-2")
        )

        XCTAssertEqual(mapped.title, "登录已过期")
        XCTAssertEqual(mapped.action, .signIn)
        XCTAssertEqual(mapped.diagnosticCode, "request-1 · trace-2")
        XCTAssertFalse(mapped.message.contains("signature"))
        XCTAssertFalse(mapped.message.contains("HTTP"))
    }

    func testConflictErrorAsksUserToRefresh() {
        let mapped = UserFacingErrorMapper.map(APIError.httpStatus(409, message: nil))

        XCTAssertEqual(mapped.title, "内容状态已变化")
        XCTAssertEqual(mapped.action, .refresh)
    }

    func testValidationErrorAsksUserToReviewInput() {
        let mapped = UserFacingErrorMapper.map(APIError.httpStatus(422, message: "invalid payload"))

        XCTAssertEqual(mapped.title, "提交内容需要调整")
        XCTAssertEqual(mapped.action, .reviewInput)
        XCTAssertFalse(mapped.message.contains("payload"))
    }

    func testInsufficientPointsUsesProductLanguageAndNextStep() {
        let mapped = UserFacingErrorMapper.map(
            APIError.httpStatus(400, message: "积分余额不足", requestID: "request-3")
        )

        XCTAssertEqual(mapped.title, "积分不足")
        XCTAssertEqual(mapped.action, .viewPoints)
        XCTAssertTrue(mapped.message.contains("积分获取方式"))
        XCTAssertFalse(mapped.message.contains("HTTP"))
    }

    func testEveryRecoveryActionHasAUserFacingButtonTitle() {
        let expected: [(UserFacingErrorAction, String)] = [
            (.retry, "重试"),
            (.signIn, "重新登录"),
            (.goBack, "返回"),
            (.reviewInput, "检查填写内容"),
            (.refresh, "刷新"),
            (.wait, "稍后再试"),
            (.viewPoints, "查看积分明细"),
        ]

        for (action, title) in expected {
            XCTAssertEqual(action.buttonTitle, title)
        }
    }
}
