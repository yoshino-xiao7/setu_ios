import XCTest
import SetuIOSCore
@testable import SetuIOSApp

#if os(iOS) && canImport(ActivityKit)
import ActivityKit

final class AiGenerationLiveActivityCenterTests: XCTestCase {
    @available(iOS 16.1, *)
    @MainActor
    func testLiveActivityRequestsPushTokenForBackgroundUpdates() {
        let pushType = AiGenerationLiveActivityCenter.pushType
        XCTAssertNotNil(pushType)
    }

    func testLiveActivityRegistrationIncludesGenerationTarget() throws {
        let request = MobileLiveActivityTokenRequest(
            deviceId: "device-1",
            activityId: "activity-1",
            activityType: "AI_GENERATION",
            targetId: "82",
            pushToken: "token-1",
            staleAt: nil
        )

        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        )
        XCTAssertEqual(object["targetId"] as? String, "82")
    }
}
#endif
