import Foundation

public struct MobileAppClient: Sendable {
    private let apiClient: APIClient

    public init(apiClient: APIClient) {
        self.apiClient = apiClient
    }

    public func capabilities() async throws -> MobileCapabilities {
        try await apiClient.get("/mobile/capabilities")
    }

    public func registerApnsDevice(_ request: MobileDeviceRegistrationRequest) async throws -> MobileDeviceRegistrationResponse {
        try await apiClient.post("/mobile/devices/apns", body: request)
    }

    public func disableDevice(deviceId: String) async throws {
        let encodedDeviceId = deviceId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? deviceId
        let _: EmptyResponse = try await apiClient.requestWithoutBody(
            "/mobile/devices/\(encodedDeviceId)",
            method: "DELETE",
            signed: true
        )
    }

    public func registerLiveActivity(_ request: MobileLiveActivityTokenRequest) async throws -> MobileLiveActivityTokenResponse {
        try await apiClient.post("/mobile/live-activities", body: request)
    }

    public func endLiveActivity(activityId: String) async throws -> MobileLiveActivityTokenResponse {
        let encodedActivityId = activityId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? activityId
        return try await apiClient.post("/mobile/live-activities/\(encodedActivityId)/end", signed: true)
    }
}
