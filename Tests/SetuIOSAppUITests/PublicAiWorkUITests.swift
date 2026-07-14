import XCTest

final class PublicAiWorkUITests: XCTestCase {
    func testOtherUsersPublicWorkShowsInteractionsWithoutOwnerManagementActions() {
        let app = XCUIApplication()
        app.launchArguments = ["-ui-testing-public-ai-work"]
        app.launch()

        XCTAssertTrue(app.buttons["ai.public.like"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["ai.public.favorite"].exists)
        XCTAssertFalse(app.buttons["申请发布到广场"].exists)
        XCTAssertFalse(app.buttons["提交删除申请"].exists)
    }
}
