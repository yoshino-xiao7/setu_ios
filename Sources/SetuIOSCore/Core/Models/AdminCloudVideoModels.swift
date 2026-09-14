import Foundation

public struct AdminCloudVideoItem: Decodable, Identifiable, Hashable, Sendable {
    public let id: Int
    public let title: String
    public let description: String?
    public let tags: String?
    public let durationSeconds: Int?
    public let width: Int?
    public let height: Int?
    public let coverUrl: String?
    public let status: String?
    public let visibility: String?
    public let rating: String?
    public let encodeProgress: Int?
    public let createdAt: String?
    public let updatedAt: String?

    public var isR18: Bool { rating == "r18" }
    public var ratingText: String { isR18 ? "R18" : "全年龄" }
    public var visibilityText: String { visibility == "published" ? "已发布" : "草稿" }
    public var statusText: String {
        switch status {
        case "ready": "已就绪"
        case "encoding": "转码中"
        case "failed": "失败"
        default: "上传中"
        }
    }

    public var durationText: String {
        let total = max(0, durationSeconds ?? 0)
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    public var canPublish: Bool { status == "ready" }
    public var isEncoding: Bool { status == "encoding" || status == "uploading" }
}

public struct CloudVideoUploadSession: Codable, Hashable, Sendable {
    public var id: Int
    public var bunnyVideoId: String
    public var libraryId: Int64
    public var tusEndpoint: String
    public var authorizationSignature: String
    public var authorizationExpire: Int64
    public var title: String
    public var status: String

    public init(
        id: Int,
        bunnyVideoId: String,
        libraryId: Int64,
        tusEndpoint: String,
        authorizationSignature: String,
        authorizationExpire: Int64,
        title: String,
        status: String
    ) {
        self.id = id
        self.bunnyVideoId = bunnyVideoId
        self.libraryId = libraryId
        self.tusEndpoint = tusEndpoint
        self.authorizationSignature = authorizationSignature
        self.authorizationExpire = authorizationExpire
        self.title = title
        self.status = status
    }

    public var expireDate: Date {
        Date(timeIntervalSince1970: TimeInterval(authorizationExpire))
    }

    public func needsRefresh(now: Date, lead: TimeInterval) -> Bool {
        expireDate.timeIntervalSince(now) <= lead
    }
}

public struct AdminCloudVideoUpdate: Encodable, Sendable {
    public var title: String?
    public var description: String?
    public var tags: String?
    public var visibility: String?
    public var rating: String?

    public init(
        title: String? = nil,
        description: String? = nil,
        tags: String? = nil,
        visibility: String? = nil,
        rating: String? = nil
    ) {
        self.title = title
        self.description = description
        self.tags = tags
        self.visibility = visibility
        self.rating = rating
    }
}

public struct CloudVideoUploadDraft: Identifiable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var rating: String
    public var fileName: String
    public var sourceURL: URL
    public var byteCount: Int64

    public init(
        id: String = UUID().uuidString,
        title: String,
        rating: String = "all_ages",
        fileName: String,
        sourceURL: URL,
        byteCount: Int64
    ) {
        self.id = id
        self.title = title
        self.rating = rating
        self.fileName = fileName
        self.sourceURL = sourceURL
        self.byteCount = byteCount
    }
}

public enum CloudVideoUploadPhase: String, Codable, Sendable {
    case preparing
    case queued
    case waitingForWifi
    case uploading
    case syncing
    case failed
}

public struct CloudVideoUploadItem: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var rating: String
    public var fileName: String
    public var fileURL: URL
    public var byteCount: Int64
    public var uploadedBytes: Int64
    public var phase: CloudVideoUploadPhase
    public var attempts: Int
    public var session: CloudVideoUploadSession?
    public var tusUploadURL: String?
    public var lastError: String?

    public init(
        id: String,
        title: String,
        rating: String,
        fileName: String,
        fileURL: URL,
        byteCount: Int64,
        uploadedBytes: Int64 = 0,
        phase: CloudVideoUploadPhase = .queued,
        attempts: Int = 0,
        session: CloudVideoUploadSession? = nil,
        tusUploadURL: String? = nil,
        lastError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.rating = rating
        self.fileName = fileName
        self.fileURL = fileURL
        self.byteCount = byteCount
        self.uploadedBytes = uploadedBytes
        self.phase = phase
        self.attempts = attempts
        self.session = session
        self.tusUploadURL = tusUploadURL
        self.lastError = lastError
    }

    public var fraction: Double {
        guard byteCount > 0 else { return 0 }
        return min(1, Double(uploadedBytes) / Double(byteCount))
    }

    public var percent: Int { Int((fraction * 100).rounded()) }
}

public struct CloudVideoUploadConfiguration: Sendable {
    public var maxAttempts: Int
    public var stallTimeout: TimeInterval
    public var retryPause: TimeInterval
    public var ticketRefreshLead: TimeInterval
    public var chunkSize: Int

    public init(
        maxAttempts: Int = 12,
        stallTimeout: TimeInterval = 180,
        retryPause: TimeInterval = 2,
        ticketRefreshLead: TimeInterval = 600,
        chunkSize: Int = 8 * 1024 * 1024
    ) {
        self.maxAttempts = maxAttempts
        self.stallTimeout = stallTimeout
        self.retryPause = retryPause
        self.ticketRefreshLead = ticketRefreshLead
        self.chunkSize = chunkSize
    }

    public static let tests = CloudVideoUploadConfiguration(
        maxAttempts: 12,
        stallTimeout: 180,
        retryPause: 0,
        ticketRefreshLead: 600,
        chunkSize: 8 * 1024 * 1024
    )
}

public enum CloudVideoUploadPauseReason: String, Sendable, Equatable {
    case none
    case wifi
    case power
    case thermal
    case session
    case user
}

public enum CloudVideoUploadError: Error, Equatable, LocalizedError {
    case stall
    case noSpace
    case notVideo
    case sessionExpired
    case blocked(CloudVideoUploadPauseReason)

    public var errorDescription: String? {
        switch self {
        case .stall: "上传停滞，准备续传"
        case .noSpace: "本机空间不足，无法复制视频"
        case .notVideo: "请选择视频文件"
        case .sessionExpired: "登录已过期，队列已暂停"
        case .blocked(.wifi): "等待 Wi-Fi"
        case .blocked(.power): "低电量，上传已暂停"
        case .blocked(.thermal): "设备过热，上传已暂停"
        case .blocked(.session): "登录已过期，队列已暂停"
        case .blocked(.user): "已暂停"
        case .blocked(.none): "上传已暂停"
        }
    }
}
