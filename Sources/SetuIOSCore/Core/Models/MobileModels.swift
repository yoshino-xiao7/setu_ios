import Foundation

public struct MobileCapabilities: Decodable, Sendable {
    public let refreshSignatureSupported: Bool
    public let apnsDeviceRegistrationSupported: Bool
    public let liveActivityPushTokenSupported: Bool
    public let liveActivityBroadcastChannelSupported: Bool
    public let galleryDirectUploadSupported: Bool
    public let galleryMultipartUploadSupported: Bool
    public let galleryUploadRecoverySupported: Bool
    public let imageFeedPreloadSupported: Bool
    public let musicPlaybackMode: String
    public let musicRangeRequestPolicy: String

    private enum CodingKeys: String, CodingKey {
        case refreshSignatureSupported
        case apnsDeviceRegistrationSupported
        case liveActivityPushTokenSupported
        case liveActivityBroadcastChannelSupported
        case galleryDirectUploadSupported
        case galleryMultipartUploadSupported
        case galleryUploadRecoverySupported
        case imageFeedPreloadSupported
        case musicPlaybackMode
        case musicRangeRequestPolicy
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        refreshSignatureSupported = try container.decode(Bool.self, forKey: .refreshSignatureSupported)
        apnsDeviceRegistrationSupported = try container.decode(Bool.self, forKey: .apnsDeviceRegistrationSupported)
        liveActivityPushTokenSupported = try container.decode(Bool.self, forKey: .liveActivityPushTokenSupported)
        liveActivityBroadcastChannelSupported = try container.decode(Bool.self, forKey: .liveActivityBroadcastChannelSupported)
        galleryDirectUploadSupported = try container.decode(Bool.self, forKey: .galleryDirectUploadSupported)
        galleryMultipartUploadSupported = try container.decode(Bool.self, forKey: .galleryMultipartUploadSupported)
        galleryUploadRecoverySupported = try container.decode(Bool.self, forKey: .galleryUploadRecoverySupported)
        imageFeedPreloadSupported = try container.decodeIfPresent(Bool.self, forKey: .imageFeedPreloadSupported) ?? false
        musicPlaybackMode = try container.decode(String.self, forKey: .musicPlaybackMode)
        musicRangeRequestPolicy = try container.decode(String.self, forKey: .musicRangeRequestPolicy)
    }
}

public struct MobileDeviceRegistrationRequest: Encodable, Sendable {
    public let deviceId: String
    public let apnsToken: String
    public let apnsEnvironment: String
    public let appVersion: String?
    public let osVersion: String?
    public let model: String?

    public init(
        deviceId: String,
        apnsToken: String,
        apnsEnvironment: String,
        appVersion: String?,
        osVersion: String?,
        model: String?
    ) {
        self.deviceId = deviceId
        self.apnsToken = apnsToken
        self.apnsEnvironment = apnsEnvironment
        self.appVersion = appVersion
        self.osVersion = osVersion
        self.model = model
    }
}

public struct MobileDeviceRegistrationResponse: Decodable, Sendable {
    public let deviceId: String
    public let platform: String
    public let apnsEnvironment: String
    public let enabled: Bool
    public let lastSeenAt: String?
}

public struct MobileLiveActivityTokenRequest: Encodable, Sendable {
    public let deviceId: String
    public let activityId: String
    public let activityType: String
    public let targetId: String?
    public let pushToken: String
    public let staleAt: String?

    public init(
        deviceId: String,
        activityId: String,
        activityType: String,
        targetId: String? = nil,
        pushToken: String,
        staleAt: String?
    ) {
        self.deviceId = deviceId
        self.activityId = activityId
        self.activityType = activityType
        self.targetId = targetId
        self.pushToken = pushToken
        self.staleAt = staleAt
    }
}

public struct MobileLiveActivityTokenResponse: Decodable, Sendable {
    public let activityId: String
    public let activityType: String
    public let deviceId: String
    public let staleAt: String?
    public let endedAt: String?
}
